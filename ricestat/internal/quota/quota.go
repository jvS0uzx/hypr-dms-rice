// Package quota reconstrói as janelas de cobrança de 5 horas do Claude Code a
// partir dos logs de sessão.
//
// O que importa numa sessão de trabalho não é o total gasto no mês — é quanto
// da janela atual já foi, a que ritmo, e quando ela reseta. Os logs registram
// `quotaLimits` só quando o limite já foi recusado; a janela em curso precisa
// ser reconstruída dos carimbos de tempo de cada resposta.
//
// Deliberadamente em tokens, não em dólares: o limite de 5h é de uso, e cravar
// tabela de preço no coletor envelheceria mal.
package quota

import (
	"bufio"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/snapshot"
)

const (
	blockHours  = 5
	bucketSize  = 5 * time.Minute
	historyDays = 8
	maxLineSize = 8 << 20
)

// indexVersion sobe sempre que a forma do balde muda. Sem isto, um campo novo
// lê zero para sempre: o índice antigo continua válido pelo par (mtime, size)
// e nunca é reprocessado.
const indexVersion = 2

type indexFile struct {
	Version int                `json:"v"`
	Files   map[string]fileAgg `json:"files"`
}

type Collector struct {
	Root      string
	IndexPath string
	RateLog   string // percentual oficial da janela, gravado pela status line
	index     map[string]fileAgg
	alerts    alertState
}

type fileAgg struct {
	ModTime int64            `json:"mtime"`
	Size    int64            `json:"size"`
	Offset  int64            `json:"off"`     // até onde já foi lido
	Buckets map[int64]bucket `json:"buckets"` // chave: início do balde em epoch segundos
	Limits  []limitHit       `json:"limits"`
}

type bucket struct {
	Tokens   int64            `json:"t"`
	In       int64            `json:"i"`
	Out      int64            `json:"o"`
	CacheRd  int64            `json:"cr"`
	CacheWr  int64            `json:"cw"`
	Requests int              `json:"r"`
	ByModel  map[string]int64 `json:"m"`
}

type limitHit struct {
	At       int64  `json:"at"`
	Kind     string `json:"kind"`
	ResetsAt int64  `json:"resets"`
}

func New(home string) *Collector {
	return &Collector{
		Root:      filepath.Join(home, ".claude", "projects"),
		IndexPath: filepath.Join(home, ".cache", "ricestat", "quota-index.json"),
		RateLog:   rateLogPath(home),
		index:     map[string]fileAgg{},
	}
}

// rateLogPath é onde o registrador da status line grava o percentual oficial
// da janela: o do próprio rice (scripts/claude-statusline.sh) e, se não
// houver, o do BI-Dev, que faz o mesmo para outro fim.
func rateLogPath(home string) string {
	own := filepath.Join(home, ".local", "share", "ricestat", "ratelimits.jsonl")
	for _, p := range []string{own, filepath.Join(home, ".local", "share", "bi-dev", "ratelimits.jsonl")} {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return own
}

func (c *Collector) Name() string { return "quota" }

func (c *Collector) Collect(ctx context.Context, s *snapshot.Snapshot) error {
	c.load()

	cutoff := time.Now().AddDate(0, 0, -historyDays)
	seen := map[string]bool{}

	filepath.WalkDir(c.Root, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() || !strings.HasSuffix(path, ".jsonl") {
			return nil
		}
		info, err := d.Info()
		if err != nil {
			return nil
		}
		// Arquivo parado há mais de 8 dias não entra em nenhuma janela viva.
		// É o corte que faz 700 MB de log caber num tique.
		if info.ModTime().Before(cutoff) {
			return nil
		}
		seen[path] = true

		prev, known := c.index[path]
		if known && prev.ModTime == info.ModTime().UnixNano() && prev.Size == info.Size() {
			return nil
		}

		// O log é append-only: na segunda passada basta ler o que cresceu.
		// Sem isto, a sessão em curso — que muda a cada resposta — fazia o
		// arquivo inteiro ser reparseado a cada tique.
		agg := prev
		if !known || info.Size() < prev.Offset {
			agg = fileAgg{Buckets: map[int64]bucket{}}
		}
		if agg.Buckets == nil {
			agg.Buckets = map[int64]bucket{}
		}
		agg.Offset = parseFrom(path, agg.Offset, cutoff, &agg)
		agg.ModTime = info.ModTime().UnixNano()
		agg.Size = info.Size()
		c.index[path] = agg
		return nil
	})

	for p := range c.index {
		if !seen[p] {
			delete(c.index, p)
		}
	}
	c.save()

	now := time.Now()
	s.Quota = build(c.index, now)
	c.notify(s.Quota, now)
	return nil
}

type logLine struct {
	Type      string    `json:"type"`
	Timestamp time.Time `json:"timestamp"`
	Message   *struct {
		Model string `json:"model"`
		Usage *struct {
			InputTokens              int64 `json:"input_tokens"`
			OutputTokens             int64 `json:"output_tokens"`
			CacheReadInputTokens     int64 `json:"cache_read_input_tokens"`
			CacheCreationInputTokens int64 `json:"cache_creation_input_tokens"`
		} `json:"usage"`
	} `json:"message"`
	QuotaLimits *struct {
		Status        string `json:"status"`
		ResetsAt      int64  `json:"resetsAt"`
		RateLimitType string `json:"rateLimitType"`
	} `json:"quotaLimits"`
}

// parseFrom lê a partir de offset e acumula em agg. Devolve o novo offset —
// a posição do último fim de linha completo, para nunca partir uma linha ao
// meio quando o arquivo ainda está sendo escrito.
func parseFrom(path string, offset int64, cutoff time.Time, agg *fileAgg) int64 {
	f, err := os.Open(path)
	if err != nil {
		return offset
	}
	defer f.Close()

	if offset > 0 {
		if _, err := f.Seek(offset, 0); err != nil {
			return offset
		}
	}

	consumed := offset
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 64<<10), maxLineSize)

	for sc.Scan() {
		line := sc.Bytes()
		consumed += int64(len(line)) + 1
		// Filtro barato antes do parse: a esmagadora maioria das linhas é
		// anexo ou evento de sessão e não tem uso de token nenhum.
		if !hasAny(line, `"type":"assistant"`, `"quotaLimits"`) {
			continue
		}
		var l logLine
		if json.Unmarshal(line, &l) != nil || l.Timestamp.Before(cutoff) {
			continue
		}

		if l.QuotaLimits != nil && l.QuotaLimits.Status == "rejected" {
			agg.Limits = append(agg.Limits, limitHit{
				At:       l.Timestamp.Unix(),
				Kind:     l.QuotaLimits.RateLimitType,
				ResetsAt: l.QuotaLimits.ResetsAt,
			})
		}

		if l.Type != "assistant" || l.Message == nil || l.Message.Usage == nil {
			continue
		}
		u := l.Message.Usage
		total := u.InputTokens + u.OutputTokens + u.CacheReadInputTokens + u.CacheCreationInputTokens
		if total == 0 {
			continue
		}

		key := l.Timestamp.Truncate(bucketSize).Unix()
		b, ok := agg.Buckets[key]
		if !ok {
			b = bucket{ByModel: map[string]int64{}}
		}
		b.Tokens += total
		b.In += u.InputTokens
		b.Out += u.OutputTokens
		b.CacheRd += u.CacheReadInputTokens
		b.CacheWr += u.CacheCreationInputTokens
		b.Requests++
		b.ByModel[l.Message.Model] += total
		agg.Buckets[key] = b
	}
	if err := sc.Err(); err != nil {
		return offset // linha gigante ou leitura truncada: tenta de novo no próximo tique
	}
	return consumed
}

func hasAny(line []byte, needles ...string) bool {
	s := string(line)
	for _, n := range needles {
		if strings.Contains(s, n) {
			return true
		}
	}
	return false
}

func (c *Collector) load() {
	b, err := os.ReadFile(c.IndexPath)
	if err != nil {
		return
	}
	var f indexFile
	if json.Unmarshal(b, &f) != nil || f.Version != indexVersion || f.Files == nil {
		return // versão velha: recomeça do zero
	}
	c.index = f.Files
}

func (c *Collector) save() {
	if os.MkdirAll(filepath.Dir(c.IndexPath), 0o755) != nil {
		return
	}
	b, err := json.Marshal(indexFile{Version: indexVersion, Files: c.index})
	if err != nil {
		return
	}
	tmp := c.IndexPath + ".tmp"
	if os.WriteFile(tmp, b, 0o644) == nil {
		os.Rename(tmp, c.IndexPath)
	}
}

// sortedBuckets funde os baldes de todos os arquivos numa série única ordenada.
func sortedBuckets(index map[string]fileAgg) ([]int64, map[int64]bucket) {
	merged := map[int64]bucket{}
	for _, a := range index {
		for k, v := range a.Buckets {
			m, ok := merged[k]
			if !ok {
				m = bucket{ByModel: map[string]int64{}}
			}
			m.Tokens += v.Tokens
			m.In += v.In
			m.Out += v.Out
			m.CacheRd += v.CacheRd
			m.CacheWr += v.CacheWr
			m.Requests += v.Requests
			for model, t := range v.ByModel {
				m.ByModel[model] += t
			}
			merged[k] = m
		}
	}
	keys := make([]int64, 0, len(merged))
	for k := range merged {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool { return keys[i] < keys[j] })
	return keys, merged
}
