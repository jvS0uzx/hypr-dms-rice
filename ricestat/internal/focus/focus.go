// Package focus acumula quanto tempo cada projeto ficou em foco.
//
// Nada sai da máquina: a fonte é a janela ativa do Hyprland e o diretório de
// trabalho do processo dela. O resultado fica num arquivo local.
//
// Cronometragem por evento: o socket2 do Hyprland avisa cada troca de janela
// (activewindowv2) e o trecho que terminou recebe a duração exata. Por
// amostragem, a cada tique, uma janela focada por 3s entre dois tiques sumia ou
// levava os 15s inteiros. Na média isso se compensa e o total do dia saía
// quase certo, mas cada trecho curto vinha errado — e evento custa menos que
// um hyprctl a cada 15s.
//
// O tique (15s) não pergunta nada ao Hyprland: só fecha o trecho em aberto e
// relê o diretório do processo já conhecido, para pegar `cd` para outro
// projeto dentro do mesmo terminal — isso não gera evento. A janela ativa só é
// consultada na troca, ou a cada tique enquanto o socket2 estiver fora.
//
// Não conta como foco: tela bloqueada (hyprlock), máquina suspensa e
// inatividade — o hypridle grava em $XDG_RUNTIME_DIR/ricestat-idle o instante
// em que o teclado e o mouse pararam, e o tempo creditado depois dele é
// devolvido.
package focus

import (
	"bufio"
	"context"
	"encoding/json"
	"io"
	"net"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/coderoots"
	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/snapshot"
)

const (
	maxGap     = 90 * time.Second // trecho maior que isto sem tique no meio é máquina suspensa, não trabalho
	historyDay = 14
	// Até onde o desconto de inatividade alcança. Cobre o timeout do hypridle
	// com folga; trecho mais antigo que isso não é mais revisto.
	janelaRecente = 15 * time.Minute
)

type Collector struct {
	StatePath string
	Roots     []string
	IdlePath  string

	// O tique e o ouvinte do socket2 mexem no mesmo trecho em aberto.
	mu        sync.Mutex
	state     store
	loaded    bool
	ouvindo   bool
	conectado bool

	pid     int
	projeto string
	janela  string
	desde   time.Time

	recentes    []trecho
	ociosoVisto time.Time
}

// trecho já creditado, guardado para o desconto de inatividade retroativo.
type trecho struct {
	projeto     string
	inicio, fim time.Time
}

type store struct {
	// data -> projeto -> segundos
	Days map[string]map[string]int `json:"days"`
}

func New(home string) *Collector {
	return &Collector{
		StatePath: filepath.Join(home, ".local", "share", "ricestat", "focus.json"),
		IdlePath:  filepath.Join(os.Getenv("XDG_RUNTIME_DIR"), "ricestat-idle"),
		Roots:     coderoots.Load(home),
		state:     store{Days: map[string]map[string]int{}},
	}
}

func (c *Collector) Name() string { return "focus" }

func (c *Collector) Collect(ctx context.Context, s *snapshot.Snapshot) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if !c.loaded {
		c.load()
		c.loaded = true
	}
	if !c.ouvindo {
		c.ouvindo = true
		go c.ouvir(ctx)
	}

	agora := time.Now()
	c.encerrar(agora)
	if !c.conectado {
		c.pid, c.janela = c.janelaAtiva()
	}
	c.projeto = c.resolver()
	c.save()

	s.Focus = c.build(agora, c.projeto, c.janela)
	return nil
}

// trocar é a troca de janela vinda do socket2.
func (c *Collector) trocar(agora time.Time) {
	c.encerrar(agora)
	c.pid, c.janela = c.janelaAtiva()
	c.projeto = c.resolver()
}

// encerrar fecha o trecho em aberto, creditando só o tempo que foi foco.
func (c *Collector) encerrar(agora time.Time) {
	switch ocioso := c.ociosoDesde(); {
	case telaBloqueada():
		c.desde = agora
	case !ocioso.IsZero():
		if ocioso != c.ociosoVisto {
			c.devolver(ocioso)
			c.ociosoVisto = ocioso
		}
		c.desde = agora
	default:
		c.fechar(agora)
	}
}

// fechar credita ao projeto em foco o tempo desde o início do trecho.
func (c *Collector) fechar(agora time.Time) {
	gap := agora.Sub(c.desde)
	if !c.desde.IsZero() && gap > 0 && gap <= maxGap && c.projeto != "" {
		c.somar(agora, c.projeto, int(gap.Round(time.Second).Seconds()))
		c.recentes = append(c.recentes, trecho{c.projeto, c.desde, agora})
	}
	c.desde = agora

	corte := agora.Add(-janelaRecente)
	i := 0
	for i < len(c.recentes) && c.recentes[i].fim.Before(corte) {
		i++
	}
	c.recentes = c.recentes[i:]
}

// devolver tira o que foi creditado depois do início da inatividade. O
// hypridle só avisa quando o timeout vence, e até lá os tiques já tinham dado
// esses minutos à janela que ficou aberta.
func (c *Collector) devolver(inicio time.Time) {
	for _, t := range c.recentes {
		if !t.fim.After(inicio) {
			continue
		}
		de := t.inicio
		if inicio.After(de) {
			de = inicio
		}
		c.somar(t.fim, t.projeto, -int(t.fim.Sub(de).Round(time.Second).Seconds()))
	}
	c.recentes = nil
}

// O trecho que cruza a meia-noite vai inteiro para o dia em que fechou; o
// tique limita isso a 15s.
func (c *Collector) somar(quando time.Time, projeto string, seg int) {
	dia := quando.Format("2006-01-02")
	if c.state.Days[dia] == nil {
		c.state.Days[dia] = map[string]int{}
	}
	c.state.Days[dia][projeto] += seg
	if c.state.Days[dia][projeto] <= 0 {
		delete(c.state.Days[dia], projeto)
	}
}

// ociosoDesde lê o instante em que a inatividade começou, gravado pelo
// hypridle. Zero quando a pessoa está mexendo na máquina.
func (c *Collector) ociosoDesde() time.Time {
	b, err := os.ReadFile(c.IdlePath)
	if err != nil {
		return time.Time{}
	}
	n := atoi(strings.TrimSpace(string(b)))
	if n == 0 {
		return time.Time{}
	}
	return time.Unix(int64(n), 0)
}

// ouvir segue o socket2 enquanto o ricestat roda. Cai junto com o Hyprland
// (logout, novo login) e volta a se conectar à instância nova.
func (c *Collector) ouvir(ctx context.Context) {
	for ctx.Err() == nil {
		conn, err := net.Dial("unix", filepath.Join(hyprDir(), ".socket2.sock"))
		if err != nil {
			select {
			case <-ctx.Done():
				return
			case <-time.After(5 * time.Second):
			}
			continue
		}
		parar := context.AfterFunc(ctx, func() { conn.Close() })

		c.mu.Lock()
		c.conectado = true
		c.trocar(time.Now())
		c.mu.Unlock()

		sc := bufio.NewScanner(conn)
		for sc.Scan() {
			if strings.HasPrefix(sc.Text(), "activewindowv2>>") {
				c.mu.Lock()
				c.trocar(time.Now())
				c.mu.Unlock()
			}
		}

		c.mu.Lock()
		c.conectado = false
		c.mu.Unlock()
		parar()
		conn.Close()
	}
}

type hyprWindow struct {
	Class string `json:"class"`
	Title string `json:"title"`
	PID   int    `json:"pid"`
}

// janelaAtiva pergunta ao Hyprland qual janela tem o foco.
func (c *Collector) janelaAtiva() (int, string) {
	out, err := hyprPedir("j/activewindow")
	if err != nil {
		return 0, ""
	}
	var w hyprWindow
	if json.Unmarshal(out, &w) != nil || w.PID == 0 {
		return 0, ""
	}
	if w.Class == "" {
		return w.PID, "desconhecido"
	}
	return w.PID, w.Class
}

// resolver devolve o projeto da janela em foco. O diretório de trabalho do
// processo é a pista mais confiável — título de janela muda de formato a cada
// aplicativo.
func (c *Collector) resolver() string {
	if c.pid == 0 {
		return ""
	}
	if p := c.projetoDoPID(c.pid); p != "" {
		return p
	}
	// Sem cwd sob um repositório: o próprio aplicativo vira a categoria, para
	// navegador e comunicação não sumirem da conta do dia.
	return c.janela
}

// hyprPedir fala direto com o socket de comandos — o mesmo que o hyprctl usa,
// sem abrir um processo a cada troca de janela.
func hyprPedir(cmd string) ([]byte, error) {
	conn, err := net.DialTimeout("unix", filepath.Join(hyprDir(), ".socket.sock"), 2*time.Second)
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(2 * time.Second))
	if _, err := conn.Write([]byte(cmd)); err != nil {
		return nil, err
	}
	return io.ReadAll(conn)
}

// hyprDir acha a pasta da instância do Hyprland. A unit systemd herda a
// assinatura do primeiro login e ela fica velha no login seguinte; nesse caso
// vale a instância com o socket mais recente.
func hyprDir() string {
	base := filepath.Join(os.Getenv("XDG_RUNTIME_DIR"), "hypr")
	if sig := os.Getenv("HYPRLAND_INSTANCE_SIGNATURE"); sig != "" {
		if _, err := os.Stat(filepath.Join(base, sig, ".socket2.sock")); err == nil {
			return filepath.Join(base, sig)
		}
	}
	socks, _ := filepath.Glob(filepath.Join(base, "*", ".socket2.sock"))
	var dir string
	var maisNovo time.Time
	for _, s := range socks {
		if fi, err := os.Stat(s); err == nil && fi.ModTime().After(maisNovo) {
			dir, maisNovo = filepath.Dir(s), fi.ModTime()
		}
	}
	return dir
}

// telaBloqueada procura o hyprlock entre os processos. O Hyprland não manda
// evento de bloqueio, e a janela ativa continua a mesma com a tela travada.
func telaBloqueada() bool {
	procs, _ := os.ReadDir("/proc")
	for _, p := range procs {
		if atoi(p.Name()) == 0 {
			continue
		}
		if b, err := os.ReadFile(filepath.Join("/proc", p.Name(), "comm")); err == nil && strings.TrimSpace(string(b)) == "hyprlock" {
			return true
		}
	}
	return false
}

func (c *Collector) projetoDoPID(pid int) string {
	for _, p := range candidatos(pid) {
		cwd, err := os.Readlink(filepath.Join("/proc", itoa(p), "cwd"))
		if err != nil {
			continue
		}
		if nome := c.projetoDoCaminho(cwd); nome != "" {
			return nome
		}
	}
	return ""
}

// candidatos devolve o processo e seus filhos diretos: num terminal, quem sabe
// o diretório é o shell, não o emulador.
func candidatos(pid int) []int {
	out := []int{pid}
	b, err := os.ReadFile(filepath.Join("/proc", itoa(pid), "task", itoa(pid), "children"))
	if err != nil {
		return out
	}
	for _, f := range strings.Fields(string(b)) {
		if n := atoi(f); n > 0 {
			out = append(out, n)
			// netos cobrem shell dentro de multiplexador
			if bb, err := os.ReadFile(filepath.Join("/proc", f, "task", f, "children")); err == nil {
				for _, g := range strings.Fields(string(bb)) {
					if m := atoi(g); m > 0 {
						out = append(out, m)
					}
				}
			}
		}
	}
	return out
}

func (c *Collector) projetoDoCaminho(cwd string) string {
	for _, root := range c.Roots {
		if !strings.HasPrefix(cwd, root) {
			continue
		}
		resto := strings.TrimPrefix(strings.TrimPrefix(cwd, root), "/")
		if resto == "" {
			return filepath.Base(root)
		}
		partes := strings.Split(resto, "/")
		// Codes/<categoria>/<projeto>: o projeto é o segundo nível.
		if filepath.Base(root) == "Codes" && len(partes) >= 2 {
			return partes[1]
		}
		return partes[0]
	}
	return ""
}

func (c *Collector) build(agora time.Time, projeto, janela string) *snapshot.Focus {
	f := &snapshot.Focus{Current: projeto, Window: janela}
	dia := agora.Format("2006-01-02")

	for nome, seg := range c.state.Days[dia] {
		f.TodaySec += seg
		f.Today = append(f.Today, snapshot.FocusEntry{Project: nome, Seconds: seg})
	}
	sort.Slice(f.Today, func(i, j int) bool { return f.Today[i].Seconds > f.Today[j].Seconds })

	semana := map[string]int{}
	corte := agora.AddDate(0, 0, -7).Format("2006-01-02")
	for d, m := range c.state.Days {
		if d < corte {
			continue
		}
		for nome, seg := range m {
			semana[nome] += seg
			f.WeekSec += seg
		}
	}
	for nome, seg := range semana {
		f.Week = append(f.Week, snapshot.FocusEntry{Project: nome, Seconds: seg})
	}
	sort.Slice(f.Week, func(i, j int) bool { return f.Week[i].Seconds > f.Week[j].Seconds })
	if len(f.Week) > 8 {
		f.Week = f.Week[:8]
	}
	return f
}

func (c *Collector) load() {
	b, err := os.ReadFile(c.StatePath)
	if err != nil {
		return
	}
	var st store
	if json.Unmarshal(b, &st) == nil && st.Days != nil {
		c.state = st
	}
	// Poda: o arquivo é histórico de foco, não arquivo morto.
	corte := time.Now().AddDate(0, 0, -historyDay).Format("2006-01-02")
	for d := range c.state.Days {
		if d < corte {
			delete(c.state.Days, d)
		}
	}
}

func (c *Collector) save() {
	if os.MkdirAll(filepath.Dir(c.StatePath), 0o755) != nil {
		return
	}
	b, err := json.Marshal(c.state)
	if err != nil {
		return
	}
	tmp := c.StatePath + ".tmp"
	if os.WriteFile(tmp, b, 0o644) == nil {
		os.Rename(tmp, c.StatePath)
	}
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var b [20]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	return string(b[i:])
}

func atoi(s string) int {
	n := 0
	for _, c := range s {
		if c < '0' || c > '9' {
			return 0
		}
		n = n*10 + int(c-'0')
	}
	return n
}
