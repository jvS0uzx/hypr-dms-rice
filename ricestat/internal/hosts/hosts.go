// Package hosts coleta uso de máquina e estado de banco, localmente e nas VPS
// por SSH.
//
// Cuidado com tráfego é requisito, não detalhe:
//   - uma única execução por host por coleta, com o probe inteiro mandado pela
//     entrada padrão — não uma sequência de comandos;
//   - resposta medida em ~180 bytes, texto delimitado por "|", sem JSON;
//   - ControlMaster com ControlPersist: o handshake acontece uma vez a cada 5
//     minutos, não a cada coleta (o handshake é o que pesa, não a resposta);
//   - intervalo próprio, bem maior que o tique do daemon.
//
// O probe é somente leitura: lê /proc, df, docker ps e faz uma consulta de
// contagem por banco. Não escreve nada em lugar nenhum.
package hosts

import (
	"bytes"
	"context"
	_ "embed"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/snapshot"
)

//go:embed probe.sh
var probe string

const (
	pollTTL     = 60 * time.Second
	sshTimeout  = 15 * time.Second
	parallel    = 3
	persistSecs = "300"
)

type Collector struct {
	ConfPath   string
	ControlDir string

	mu       sync.Mutex
	cached   *snapshot.Hosts
	cachedAt time.Time

	history *diskHistory
	prev    map[string]hostState // nil até a primeira coleta
}

func New(home string) *Collector {
	return &Collector{
		ConfPath:   filepath.Join(home, ".config", "ricestat", "hosts.txt"),
		ControlDir: filepath.Join(home, ".cache", "ricestat", "ssh"),
		history:    loadHistory(filepath.Join(home, ".cache", "ricestat", "disk_history.json")),
	}
}

func (c *Collector) Name() string { return "hosts" }

type target struct {
	Alias string
	Role  string
	Dest  string // vazio = máquina local
}

func (c *Collector) Collect(ctx context.Context, s *snapshot.Snapshot) error {
	c.mu.Lock()
	if c.cached != nil && time.Since(c.cachedAt) < pollTTL {
		s.Hosts = c.cached
		c.mu.Unlock()
		return nil
	}
	c.mu.Unlock()

	targets, err := readTargets(c.ConfPath)
	if err != nil {
		return err
	}
	if len(targets) == 0 {
		return fmt.Errorf("nenhum host habilitado em %s", c.ConfPath)
	}

	os.MkdirAll(c.ControlDir, 0o700)

	out := &snapshot.Hosts{Hosts: make([]snapshot.Host, len(targets))}
	sem := make(chan struct{}, parallel)
	var wg sync.WaitGroup

	for i, t := range targets {
		wg.Add(1)
		go func(i int, t target) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			out.Hosts[i] = c.probeOne(ctx, t)
		}(i, t)
	}
	wg.Wait()

	for _, h := range out.Hosts {
		if h.Up {
			out.Up++
		} else {
			out.Down++
		}
		for _, d := range h.Databases {
			out.Databases++
			if !d.Up {
				out.DatabasesDown++
			}
		}
	}

	applyTrend(c.history, out, time.Now())
	c.notify(out)

	c.mu.Lock()
	c.cached, c.cachedAt = out, time.Now()
	c.mu.Unlock()

	s.Hosts = out
	return nil
}

func (c *Collector) probeOne(ctx context.Context, t target) snapshot.Host {
	h := snapshot.Host{Alias: t.Alias, Role: t.Role, Remote: t.Dest != ""}

	ctx, cancel := context.WithTimeout(ctx, sshTimeout)
	defer cancel()

	var cmd *exec.Cmd
	if t.Dest == "" {
		cmd = exec.CommandContext(ctx, "sh", "-s")
	} else {
		cmd = exec.CommandContext(ctx, "ssh",
			"-o", "BatchMode=yes",
			"-o", "ConnectTimeout=6",
			"-o", "ControlMaster=auto",
			"-o", "ControlPath="+filepath.Join(c.ControlDir, "cm-%r@%h-%p"),
			"-o", "ControlPersist="+persistSecs,
			t.Dest, "sh -s")
	}
	cmd.Stdin = strings.NewReader(probe)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	start := time.Now()
	if err := cmd.Run(); err != nil {
		h.Error = firstLine(stderr.String())
		if h.Error == "" {
			h.Error = err.Error()
		}
		return h
	}
	h.LatencyMS = int(time.Since(start).Milliseconds())
	h.Bytes = stdout.Len()
	h.Up = true
	parse(stdout.String(), &h)
	return h
}

func parse(out string, h *snapshot.Host) {
	for _, line := range strings.Split(strings.TrimSpace(out), "\n") {
		f := strings.Split(line, "|")
		switch {
		case f[0] == "H" && len(f) >= 9:
			h.Load1 = atof(f[1])
			h.Load5 = atof(f[2])
			mem := strings.Split(f[3], ",")
			if len(mem) == 2 {
				h.MemUsedMB, h.MemTotalMB = atoi(mem[0]), atoi(mem[1])
			}
			h.DiskPct = atoi(f[4])
			h.UptimeSec = int64(atoi(f[5]))
			h.CPUs = atoi(f[6])
			h.ContainersUp = atoi(f[7])
			h.ContainersDown = atoi(f[8])
		case f[0] == "D" && len(f) >= 5:
			db := snapshot.Database{Name: f[1], Engine: f[2], Health: f[4]}
			v := strings.Split(f[3], ",")
			if len(v) == 2 && v[0] != "-" && v[0] != "?" {
				db.Connections = atoi(v[0])
				db.SizeBytes = int64(atoi(v[1]))
				db.Up = true
			}
			// MinIO e afins não respondem consulta; presença no docker ps já
			// diz que está de pé.
			if f[3] == "-,-" && f[2] != "" {
				db.Up = true
			}
			if f[4] == "u" {
				db.Up = false
			}
			h.Databases = append(h.Databases, db)
		}
	}
	if h.CPUs > 0 {
		h.LoadPct = h.Load1 / float64(h.CPUs) * 100
	}
}

func readTargets(path string) ([]target, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("crie %s (veja o modelo em dotfiles/seeds/hosts.txt)", path)
		}
		return nil, err
	}
	var ts []target
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		f := strings.Fields(line)
		if len(f) < 2 {
			continue
		}
		t := target{Alias: f[0], Role: f[1]}
		if len(f) >= 3 && f[2] != "local" {
			t.Dest = f[2]
		}
		ts = append(ts, t)
	}
	return ts, nil
}

func atoi(s string) int     { v, _ := strconv.Atoi(strings.TrimSpace(s)); return v }
func atof(s string) float64 { v, _ := strconv.ParseFloat(strings.TrimSpace(s), 64); return v }

func firstLine(s string) string {
	s = strings.TrimSpace(s)
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		return s[:i]
	}
	return s
}
