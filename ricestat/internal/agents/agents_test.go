package agents

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// O parse lê só a cauda do arquivo. Este teste garante que uma linha longa
// antes do cost-state não empurre a linha de custo para fora da janela.
func TestReadCostStateFromTail(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "session.jsonl")

	var b strings.Builder
	b.WriteString(`{"type":"user","cwd":"/home/ana/code/my_app"}` + "\n")
	for i := 0; i < 200; i++ {
		b.WriteString(fmt.Sprintf(`{"type":"attachment","blob":%q}`, strings.Repeat("x", 4096)) + "\n")
	}
	b.WriteString(`{"type": "cost-state", "sessionId": "abc", "totalCostUSD": 1.5, "startTime": 1788010105548, "modelUsage": {"claude-opus-5[1m]": {"outputTokens": 10, "costUSD": 1.5}}}` + "\n")
	b.WriteString(`{"type":"assistant"}` + "\n")

	if err := os.WriteFile(path, []byte(b.String()), 0o644); err != nil {
		t.Fatal(err)
	}

	st := readCostState(path)
	if st == nil {
		t.Fatal("cost-state não encontrado na cauda")
	}
	if st.TotalCostUSD != 1.5 {
		t.Errorf("custo = %v, queria 1.5", st.TotalCostUSD)
	}
	if got := st.ModelUsage["claude-opus-5[1m]"].CostUSD; got != 1.5 {
		t.Errorf("custo por modelo = %v, queria 1.5", got)
	}

	if cwd := readCWD(path); cwd != "/home/ana/code/my_app" {
		t.Errorf("cwd = %q", cwd)
	}
}

// Quando há mais de um cost-state, vale o último: é o estado final da sessão.
func TestReadCostStateUsesLast(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "s.jsonl")
	body := `{"type": "cost-state", "totalCostUSD": 1}` + "\n" +
		`{"type": "cost-state", "totalCostUSD": 9}` + "\n"
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	st := readCostState(path)
	if st == nil || st.TotalCostUSD != 9 {
		t.Fatalf("queria 9, veio %+v", st)
	}
}

// O slug do diretório é ambíguo: "my_app" e "my-app" colidem. O cwd desempata,
// e sem cwd o slug ainda precisa devolver algo utilizável.
func TestProjectName(t *testing.T) {
	old := homeName
	homeName = "ana" // o teste não depende de quem roda
	defer func() { homeName = old }()

	cases := []struct{ cwd, slug, want string }{
		{"/home/ana/code/my_app", "-home-ana-code-my-app", "my_app"},
		{"/home/ana/notes", "-home-ana-notes", "notes"},
		{"/home/ana", "-home-ana", "~"},
		{"", "-home-ana-code-web-Shop", "Shop"},
		{"", "-home-ana", "~"},
	}
	for _, c := range cases {
		if got := projectName(c.cwd, c.slug); got != c.want {
			t.Errorf("projectName(%q, %q) = %q, queria %q", c.cwd, c.slug, got, c.want)
		}
	}
}
