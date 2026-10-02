package focus

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func novo() *Collector {
	return &Collector{state: store{Days: map[string]map[string]int{}}}
}

// Alt+Tab rápido entre editor e terminal: cada trecho recebe a duração real,
// não o intervalo do tique.
func TestFecharCreditaDuracaoExata(t *testing.T) {
	c := novo()
	t0 := time.Date(2026, 10, 2, 9, 0, 0, 0, time.Local)
	trechos := []struct {
		projeto string
		dur     time.Duration
	}{
		{"editor", 3 * time.Second},
		{"terminal", 4 * time.Second},
		{"editor", 2 * time.Second},
		{"terminal", 11 * time.Second},
	}

	agora := t0
	c.desde = agora
	for _, tr := range trechos {
		c.projeto = tr.projeto
		agora = agora.Add(tr.dur)
		c.fechar(agora)
	}

	dia := c.state.Days["2026-10-02"]
	if dia["editor"] != 5 || dia["terminal"] != 15 {
		t.Fatalf("editor=%d terminal=%d, quero 5 e 15", dia["editor"], dia["terminal"])
	}
}

// Trecho sem tique no meio por mais que maxGap é máquina suspensa.
func TestFecharDescartaSuspensao(t *testing.T) {
	c := novo()
	t0 := time.Date(2026, 10, 2, 9, 0, 0, 0, time.Local)
	c.projeto, c.desde = "editor", t0
	c.fechar(t0.Add(40 * time.Minute))

	if n := c.state.Days["2026-10-02"]["editor"]; n != 0 {
		t.Fatalf("creditou %ds de suspensão", n)
	}
	if !c.desde.Equal(t0.Add(40 * time.Minute)) {
		t.Fatal("trecho seguinte não recomeça no fechamento")
	}
}

func TestFecharSemJanelaNaoCredita(t *testing.T) {
	c := novo()
	t0 := time.Date(2026, 10, 2, 9, 0, 0, 0, time.Local)
	c.desde = t0
	c.fechar(t0.Add(10 * time.Second))
	if len(c.state.Days) != 0 {
		t.Fatalf("creditou sem projeto: %v", c.state.Days)
	}
}

// O hypridle avisa só quando o timeout vence: os tiques dos minutos parados já
// tinham creditado a janela aberta e precisam ser devolvidos.
func TestInatividadeDevolveRetroativo(t *testing.T) {
	c := novo()
	c.IdlePath = filepath.Join(t.TempDir(), "ricestat-idle")
	t0 := time.Date(2026, 10, 2, 9, 0, 0, 0, time.Local)
	c.projeto, c.desde = "editor", t0

	// 10 min de tiques: 2 min trabalhando, 8 min longe do teclado.
	agora := t0
	for i := 0; i < 40; i++ {
		agora = agora.Add(15 * time.Second)
		c.encerrar(agora)
	}
	if n := c.state.Days["2026-10-02"]["editor"]; n != 600 {
		t.Fatalf("antes do aviso: %ds, quero 600", n)
	}

	// hypridle vence e marca o início real da inatividade.
	parou := t0.Add(2 * time.Minute)
	os.WriteFile(c.IdlePath, []byte(itoa(int(parou.Unix()))), 0o644)
	for i := 0; i < 4; i++ {
		agora = agora.Add(15 * time.Second)
		c.encerrar(agora)
	}
	if n := c.state.Days["2026-10-02"]["editor"]; n != 120 {
		t.Fatalf("com inatividade: %ds, quero 120", n)
	}

	// Voltou: hypridle apaga o arquivo e a contagem segue normal.
	os.Remove(c.IdlePath)
	agora = agora.Add(15 * time.Second)
	c.encerrar(agora)
	if n := c.state.Days["2026-10-02"]["editor"]; n != 135 {
		t.Fatalf("depois de voltar: %ds, quero 135", n)
	}
}
