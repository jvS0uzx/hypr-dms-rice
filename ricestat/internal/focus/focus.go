// Package focus acumula quanto tempo cada projeto ficou em foco.
//
// Nada sai da máquina: a fonte é a janela ativa do Hyprland e o diretório de
// trabalho do processo dela. O resultado fica num arquivo local.
//
// Amostragem, não cronometragem: cada coleta credita o intervalo inteiro ao
// projeto que estava em foco naquele instante. Com tique de 15s o erro por
// troca de janela é de no máximo 15s, o que para "onde foi o meu dia" é
// preciso de sobra — e custa uma chamada ao compositor em vez de um daemon
// ouvindo eventos.
package focus

import (
	"context"
	"encoding/json"
	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/coderoots"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/snapshot"
)

const (
	maxGap     = 90 * time.Second // intervalo maior que isto é máquina suspensa, não trabalho
	historyDay = 14
)

type Collector struct {
	StatePath string
	Roots     []string

	state    store
	lastSeen time.Time
	loaded   bool
}

type store struct {
	// data -> projeto -> segundos
	Days map[string]map[string]int `json:"days"`
}

func New(home string) *Collector {
	return &Collector{
		StatePath: filepath.Join(home, ".local", "share", "ricestat", "focus.json"),
		Roots:     coderoots.Load(home),
		state:     store{Days: map[string]map[string]int{}},
	}
}

func (c *Collector) Name() string { return "focus" }

func (c *Collector) Collect(ctx context.Context, s *snapshot.Snapshot) error {
	if !c.loaded {
		c.load()
		c.loaded = true
	}

	agora := time.Now()
	projeto, janela := c.ativo(ctx)

	if !c.lastSeen.IsZero() {
		gap := agora.Sub(c.lastSeen)
		if gap > 0 && gap <= maxGap && projeto != "" {
			dia := agora.Format("2006-01-02")
			if c.state.Days[dia] == nil {
				c.state.Days[dia] = map[string]int{}
			}
			c.state.Days[dia][projeto] += int(gap.Seconds())
			c.save()
		}
	}
	c.lastSeen = agora

	s.Focus = c.build(agora, projeto, janela)
	return nil
}

type hyprWindow struct {
	Class string `json:"class"`
	Title string `json:"title"`
	PID   int    `json:"pid"`
}

// ativo devolve o projeto em foco e o rótulo da janela. O diretório de
// trabalho do processo é a pista mais confiável — título de janela muda de
// formato a cada aplicativo.
func (c *Collector) ativo(ctx context.Context) (string, string) {
	ctx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()

	out, err := exec.CommandContext(ctx, "hyprctl", "activewindow", "-j").Output()
	if err != nil {
		return "", ""
	}
	var w hyprWindow
	if json.Unmarshal(out, &w) != nil || w.PID == 0 {
		return "", ""
	}

	janela := w.Class
	if janela == "" {
		janela = "desconhecido"
	}

	if p := c.projetoDoPID(w.PID); p != "" {
		return p, janela
	}
	// Sem cwd sob um repositório: o próprio aplicativo vira a categoria, para
	// navegador e comunicação não sumirem da conta do dia.
	return janela, janela
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
