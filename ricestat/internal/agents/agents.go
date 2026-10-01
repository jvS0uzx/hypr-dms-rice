// Package agents agrega o custo e as sessões dos agents CLI a partir dos logs
// de sessão do Claude Code.
//
// Cada sessão grava uma linha `cost-state` com o custo JÁ CALCULADO — não é
// preciso multiplicar token por preço de tabela. São ~700 MB de log no total,
// então o coletor mantém um índice por (mtime, size) e só relê arquivo que
// mudou, e mesmo assim só a cauda: o `cost-state` fica perto do fim.
package agents

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/snapshot"
)

const (
	// O cost-state é reescrito perto do fim; o cwd aparece nas primeiras
	// entradas. Duas janelas pequenas evitam ler 700 MB de log.
	tailBytes    = 1 << 20
	headBytes    = 64 << 10
	activeWindow = 15 * time.Minute
	dailyDays    = 14
)

type Collector struct {
	Root      string // ~/.claude/projects
	IndexPath string // ~/.cache/ricestat/agents-index.json
	index     map[string]entry
}

type entry struct {
	ModTime int64      `json:"mtime"`
	Size    int64      `json:"size"`
	CWD     string     `json:"cwd"`
	State   *costState `json:"state"`
}

type costState struct {
	SessionID    string                `json:"sessionId"`
	TotalCostUSD float64               `json:"totalCostUSD"`
	StartTime    int64                 `json:"startTime"` // epoch ms
	ModelUsage   map[string]modelUsage `json:"modelUsage"`
}

type modelUsage struct {
	InputTokens          int64   `json:"inputTokens"`
	OutputTokens         int64   `json:"outputTokens"`
	CacheReadInputTokens int64   `json:"cacheReadInputTokens"`
	CostUSD              float64 `json:"costUSD"`
}

func New(home string) *Collector {
	return &Collector{
		Root:      filepath.Join(home, ".claude", "projects"),
		IndexPath: filepath.Join(home, ".cache", "ricestat", "agents-index.json"),
		index:     map[string]entry{},
	}
}

func (c *Collector) Name() string { return "agents" }

func (c *Collector) Collect(ctx context.Context, s *snapshot.Snapshot) error {
	c.loadIndex()

	claudeRunning := processRunning(ctx, "claude")
	now := time.Now()
	agg := newAggregator(now)
	seen := map[string]bool{}

	err := filepath.WalkDir(c.Root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil // diretório ilegível não derruba a coleta inteira
		}
		if d.IsDir() || !strings.HasSuffix(path, ".jsonl") {
			return nil
		}
		info, err := d.Info()
		if err != nil {
			return nil
		}
		seen[path] = true

		cached, ok := c.index[path]
		if !ok || cached.ModTime != info.ModTime().UnixNano() || cached.Size != info.Size() {
			cached = entry{
				ModTime: info.ModTime().UnixNano(),
				Size:    info.Size(),
				CWD:     readCWD(path),
				State:   readCostState(path),
			}
			c.index[path] = cached
		}

		// Sessão ativa é detectada mesmo sem cost-state: a linha de custo só
		// é gravada de tempos em tempos, e a sessão em curso é justamente a
		// que ainda não gravou.
		active := claudeRunning && now.Sub(info.ModTime()) < activeWindow
		if cached.State == nil && !active {
			return nil
		}

		name := projectName(cached.CWD, filepath.Base(filepath.Dir(path)))
		agg.add(name, filepath.Base(filepath.Dir(path)), cached.State, info.ModTime(), active)
		return nil
	})
	if err != nil {
		return fmt.Errorf("varredura de %s: %w", c.Root, err)
	}

	for path := range c.index {
		if !seen[path] {
			delete(c.index, path)
		}
	}
	c.saveIndex()

	s.Agents = agg.result()
	return nil
}

// readCostState lê a cauda do arquivo e devolve o último cost-state válido.
func readCostState(path string) *costState {
	f, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer f.Close()

	info, err := f.Stat()
	if err != nil {
		return nil
	}
	offset := int64(0)
	if info.Size() > tailBytes {
		offset = info.Size() - tailBytes
	}
	if _, err := f.Seek(offset, 0); err != nil {
		return nil
	}
	buf := make([]byte, info.Size()-offset)
	n, _ := f.Read(buf)
	buf = buf[:n]

	lines := bytes.Split(buf, []byte("\n"))
	if offset > 0 && len(lines) > 0 {
		lines = lines[1:] // a primeira veio cortada no meio
	}

	var last *costState
	for _, line := range lines {
		if !bytes.Contains(line, []byte("cost-state")) {
			continue
		}
		var probe struct {
			Type string `json:"type"`
		}
		if json.Unmarshal(line, &probe) != nil || probe.Type != "cost-state" {
			continue
		}
		var st costState
		if json.Unmarshal(line, &st) != nil {
			continue
		}
		last = &st
	}
	return last
}

func processRunning(ctx context.Context, name string) bool {
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	return exec.CommandContext(ctx, "pgrep", "-x", name).Run() == nil
}

func (c *Collector) loadIndex() {
	b, err := os.ReadFile(c.IndexPath)
	if err != nil {
		return
	}
	idx := map[string]entry{}
	if json.Unmarshal(b, &idx) == nil {
		c.index = idx
	}
}

func (c *Collector) saveIndex() {
	if err := os.MkdirAll(filepath.Dir(c.IndexPath), 0o755); err != nil {
		return
	}
	b, err := json.Marshal(c.index)
	if err != nil {
		return
	}
	tmp := c.IndexPath + ".tmp"
	if os.WriteFile(tmp, b, 0o644) == nil {
		os.Rename(tmp, c.IndexPath)
	}
}

// readCWD pega o diretório de trabalho da sessão nas primeiras entradas do log.
// O nome do diretório de projeto é o caminho com "/" virando "-", o que é
// ambíguo quando o próprio caminho tem hífen: "my-app" e "my_app"
// geram o mesmo slug. O cwd resolve isso sem adivinhação.
func readCWD(path string) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()

	buf := make([]byte, headBytes)
	n, _ := f.Read(buf)
	for _, line := range bytes.Split(buf[:n], []byte("\n")) {
		if !bytes.Contains(line, []byte(`"cwd"`)) {
			continue
		}
		var probe struct {
			CWD string `json:"cwd"`
		}
		if json.Unmarshal(line, &probe) == nil && probe.CWD != "" {
			return probe.CWD
		}
	}
	return ""
}

// homeName é o nome da pasta pessoal ("ana" em /home/ana): sessão aberta ali
// não é projeto e aparece como "~".
var homeName = func() string {
	h, _ := os.UserHomeDir()
	return filepath.Base(h)
}()

// projectName usa o cwd quando existe e cai para o slug quando não.
func projectName(cwd, slug string) string {
	if cwd != "" {
		if base := filepath.Base(cwd); base != "" && base != "." && base != "/" {
			if base == homeName {
				return "~"
			}
			return base
		}
	}
	parts := strings.Split(strings.TrimPrefix(slug, "-"), "-")
	if len(parts) == 0 {
		return slug
	}
	last := parts[len(parts)-1]
	if last == "" || last == homeName || last == "home" {
		return "~"
	}
	return last
}
