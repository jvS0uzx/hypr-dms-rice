// Package deploys lê o último run do workflow de deploy de cada repositório
// pelo gh CLI.
//
// Push em main dispara deploy em produção nas VPS e não existe staging: este
// coletor é o único retorno entre o push e "funcionou".
package deploys

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/snapshot"
)

const (
	// O gh tem rate limit e são 11 repositórios. Com o tique de 15s do daemon
	// isso seriam 44 chamadas por minuto à toa — o cache corta para ~7.
	// 11 chamadas ao gh custam ~3s. Fora de deploy em andamento, o estado
	// muda em escala de horas; com run rodando, o widget acompanha passo a
	// passo e o intervalo cai para o mínimo útil.
	cacheTTL    = 180 * time.Second
	cacheTTLHot = 15 * time.Second
	perRepoWait = 12 * time.Second
	parallel    = 4
	workflow    = "deploy.yml"
)

type Collector struct {
	ReposPath string

	mu       sync.Mutex
	cached   *snapshot.Deploys
	cachedAt time.Time

	// Estado anterior por repositório, para notificar só na transição. Avisar
	// a cada coleta enquanto um deploy segue quebrado vira ruído ignorado.
	prev  map[string]string
	first bool
}

func New(home string) *Collector {
	return &Collector{
		ReposPath: filepath.Join(home, ".config", "ricestat", "repos.txt"),
		prev:      map[string]string{},
		first:     true,
	}
}

func (c *Collector) Name() string { return "deploys" }

func (c *Collector) Collect(ctx context.Context, s *snapshot.Snapshot) error {
	c.mu.Lock()
	ttl := cacheTTL
	if c.cached != nil && c.cached.Running > 0 {
		ttl = cacheTTLHot
	}
	if c.cached != nil && time.Since(c.cachedAt) < ttl {
		s.Deploys = c.cached
		c.mu.Unlock()
		return nil
	}
	c.mu.Unlock()

	repos, err := readRepos(c.ReposPath)
	if err != nil {
		return err
	}
	if len(repos) == 0 {
		// Nada configurado não é falha: o painel fica sem deploys, sem alarme.
		s.Deploys = &snapshot.Deploys{}
		return nil
	}

	d := &snapshot.Deploys{Repos: make([]snapshot.DeployRepo, len(repos))}

	sem := make(chan struct{}, parallel)
	var wg sync.WaitGroup
	for i, repo := range repos {
		wg.Add(1)
		go func(i int, repo string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			d.Repos[i] = lastRun(ctx, repo)
		}(i, repo)
	}
	wg.Wait()

	for _, r := range d.Repos {
		switch r.State {
		case snapshot.DeployFailure:
			d.Failing++
		case snapshot.DeployRunning:
			d.Running++
		case snapshot.DeploySuccess:
			d.OK++
		default:
			d.Unknown++
		}
	}

	// Falha primeiro, depois em execução: a ordem da lista é a ordem em que
	// alguém precisa olhar.
	// Detalhe ao vivo só para quem está rodando: um `gh run view` por run
	// ativo, não por repositório.
	var liveWG sync.WaitGroup
	for i := range d.Repos {
		if d.Repos[i].State != snapshot.DeployRunning {
			continue
		}
		liveWG.Add(1)
		go func(r *snapshot.DeployRepo) {
			defer liveWG.Done()
			fillLive(ctx, r)
		}(&d.Repos[i])
	}
	liveWG.Wait()

	c.notify(d)

	sort.SliceStable(d.Repos, func(i, j int) bool {
		return statePriority(d.Repos[i].State) < statePriority(d.Repos[j].State)
	})

	c.mu.Lock()
	c.cached, c.cachedAt = d, time.Now()
	c.mu.Unlock()

	s.Deploys = d
	return nil
}

func statePriority(s string) int {
	switch s {
	case snapshot.DeployFailure:
		return 0
	case snapshot.DeployRunning:
		return 1
	case snapshot.DeployUnknown:
		return 2
	default:
		return 3
	}
}

type ghRun struct {
	DatabaseID   int64     `json:"databaseId"`
	Status       string    `json:"status"`
	Conclusion   string    `json:"conclusion"`
	HeadBranch   string    `json:"headBranch"`
	DisplayTitle string    `json:"displayTitle"`
	CreatedAt    time.Time `json:"createdAt"`
	URL          string    `json:"url"`
}

func lastRun(ctx context.Context, repo string) snapshot.DeployRepo {
	out := snapshot.DeployRepo{Repo: repo, Name: shortName(repo), State: snapshot.DeployUnknown}

	ctx, cancel := context.WithTimeout(ctx, perRepoWait)
	defer cancel()

	cmd := exec.CommandContext(ctx, "gh", "run", "list",
		"--repo", repo,
		"--workflow", workflow,
		"--limit", "1",
		"--json", "databaseId,status,conclusion,headBranch,displayTitle,createdAt,url")

	b, err := cmd.Output()
	if err != nil {
		out.Error = ghError(err)
		return out
	}

	var runs []ghRun
	if err := json.Unmarshal(b, &runs); err != nil {
		out.Error = "resposta inválida do gh"
		return out
	}
	if len(runs) == 0 {
		out.Error = "sem execuções"
		return out
	}

	r := runs[0]
	out.RunID = r.DatabaseID
	out.Branch = r.HeadBranch
	out.Title = r.DisplayTitle
	out.URL = r.URL
	out.At = r.CreatedAt

	switch {
	case r.Status != "completed":
		out.State = snapshot.DeployRunning
	case r.Conclusion == "success":
		out.State = snapshot.DeploySuccess
	case r.Conclusion == "cancelled" || r.Conclusion == "skipped":
		out.State = snapshot.DeployUnknown
	default:
		out.State = snapshot.DeployFailure
	}
	return out
}

func ghError(err error) string {
	var ee *exec.ExitError
	if ok := asExitError(err, &ee); ok && len(ee.Stderr) > 0 {
		line := strings.TrimSpace(strings.SplitN(string(ee.Stderr), "\n", 2)[0])
		if line != "" {
			return line
		}
	}
	return err.Error()
}

func asExitError(err error, target **exec.ExitError) bool {
	if ee, ok := err.(*exec.ExitError); ok {
		*target = ee
		return true
	}
	return false
}

func shortName(repo string) string {
	if i := strings.LastIndex(repo, "/"); i >= 0 {
		return repo[i+1:]
	}
	return repo
}

// readRepos lê um "owner/repo" por linha. Linha vazia e comentário são
// ignorados, para o arquivo poder explicar a si mesmo.
func readRepos(path string) ([]string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("crie %s com um owner/repo por linha", path)
		}
		return nil, err
	}
	var repos []string
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		repos = append(repos, line)
	}
	return repos, nil
}
