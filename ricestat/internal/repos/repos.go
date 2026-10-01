// Package repos varre os repositórios git locais e reporta o que está
// pendente.
//
// O que se perde num dia com 34 repositórios espalhados: trabalho não
// commitado esquecido numa pasta, branch atrás do origin, commit local que
// nunca subiu. Nada disso aparece até alguém abrir a pasta e lembrar.
package repos

import (
	"bufio"
	"bytes"
	"context"
	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/coderoots"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/snapshot"
)

const (
	pollTTL  = 45 * time.Second
	gitWait  = 8 * time.Second
	parallel = 6
	maxDepth = 4
)

type Collector struct {
	Roots    []string
	mu       sync.Mutex
	cached   *snapshot.Repos
	cachedAt time.Time
}

// New procura repositórios nas pastas de ~/.config/ricestat/code-roots.txt.
func New(home string) *Collector {
	return &Collector{Roots: coderoots.Load(home)}
}

func (c *Collector) Name() string { return "repos" }

func (c *Collector) Collect(ctx context.Context, s *snapshot.Snapshot) error {
	c.mu.Lock()
	if c.cached != nil && time.Since(c.cachedAt) < pollTTL {
		s.Repos = c.cached
		c.mu.Unlock()
		return nil
	}
	c.mu.Unlock()

	paths := c.find()
	out := &snapshot.Repos{Total: len(paths)}
	list := make([]snapshot.Repo, len(paths))

	sem := make(chan struct{}, parallel)
	var wg sync.WaitGroup
	for i, p := range paths {
		wg.Add(1)
		go func(i int, p string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			list[i] = inspect(ctx, p)
		}(i, p)
	}
	wg.Wait()

	for _, r := range list {
		if r.Name == "" {
			continue
		}
		if r.Dirty > 0 || r.Ahead > 0 || r.Behind > 0 {
			out.Pending = append(out.Pending, r)
		}
		if r.Dirty > 0 {
			out.DirtyCount++
		}
		if r.Ahead > 0 {
			out.AheadCount++
		}
	}

	// Sujo primeiro, e dentro disso o mais sujo na frente: é onde há mais
	// chance de alguém ter esquecido alguma coisa.
	sort.Slice(out.Pending, func(i, j int) bool {
		a, b := out.Pending[i], out.Pending[j]
		if (a.Dirty > 0) != (b.Dirty > 0) {
			return a.Dirty > 0
		}
		if a.Dirty != b.Dirty {
			return a.Dirty > b.Dirty
		}
		return a.Ahead > b.Ahead
	})

	c.mu.Lock()
	c.cached, c.cachedAt = out, time.Now()
	c.mu.Unlock()

	s.Repos = out
	return nil
}

// find localiza os .git sem descer em node_modules e afins, que numa árvore de
// projeto web dominam o tempo de varredura.
func (c *Collector) find() []string {
	var out []string
	pular := map[string]bool{
		"node_modules": true, ".venv": true, "venv": true, "target": true,
		"dist": true, "build": true, ".next": true, "vendor": true, ".cache": true,
	}

	for _, root := range c.Roots {
		base := strings.Count(root, string(os.PathSeparator))
		filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
			if err != nil || !d.IsDir() {
				return nil
			}
			if d.Name() == ".git" {
				out = append(out, filepath.Dir(path))
				return filepath.SkipDir
			}
			if pular[d.Name()] || strings.Count(path, string(os.PathSeparator))-base > maxDepth {
				return filepath.SkipDir
			}
			return nil
		})
	}
	return out
}

func inspect(ctx context.Context, path string) snapshot.Repo {
	r := snapshot.Repo{Name: filepath.Base(path), Path: path}

	ctx, cancel := context.WithTimeout(ctx, gitWait)
	defer cancel()

	// --porcelain=v2 --branch numa chamada só: status, branch e a divergência
	// com o upstream vêm juntos, sem três processos por repositório.
	cmd := exec.CommandContext(ctx, "git", "-C", path,
		"status", "--porcelain=v2", "--branch", "--untracked-files=normal")
	var buf bytes.Buffer
	cmd.Stdout = &buf
	if err := cmd.Run(); err != nil {
		r.Error = "git status falhou"
		return r
	}

	sc := bufio.NewScanner(&buf)
	sc.Buffer(make([]byte, 0, 64<<10), 4<<20)
	for sc.Scan() {
		line := sc.Text()
		switch {
		case strings.HasPrefix(line, "# branch.head "):
			r.Branch = strings.TrimPrefix(line, "# branch.head ")
		case strings.HasPrefix(line, "# branch.ab "):
			a, b := parseAB(strings.TrimPrefix(line, "# branch.ab "))
			r.Ahead, r.Behind = a, b
		case strings.HasPrefix(line, "# "):
			// demais cabeçalhos não interessam
		default:
			r.Dirty++
			if strings.HasPrefix(line, "? ") {
				r.Untracked++
			}
		}
	}
	return r
}

// parseAB lê "+2 -3" do cabeçalho branch.ab.
func parseAB(s string) (ahead, behind int) {
	for _, f := range strings.Fields(s) {
		if len(f) < 2 {
			continue
		}
		n, err := strconv.Atoi(f[1:])
		if err != nil {
			continue
		}
		if f[0] == '+' {
			ahead = n
		} else if f[0] == '-' {
			behind = n
		}
	}
	return
}
