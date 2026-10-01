// ricestat consolida as fontes de monitoramento num único snapshot JSON que os
// plugins QML do DankMaterialShell leem. Ver rice-widgets-monitoramento.md.
package main

import (
	"context"
	"flag"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/agents"
	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/collect"
	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/deploys"
	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/focus"
	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/hosts"
	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/inbox"
	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/quota"
	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/repos"
	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/services"
	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/snapshot"
	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/tailnet"
)

func main() {
	var (
		interval = flag.Duration("interval", 15*time.Second, "intervalo entre coletas")
		out      = flag.String("out", defaultOut(), "caminho do snapshot JSON")
		once     = flag.Bool("once", false, "coleta uma vez, imprime e sai")
	)
	flag.Parse()

	home, err := os.UserHomeDir()
	if err != nil {
		log.Fatalf("home: %v", err)
	}

	collectors := []collect.Collector{
		tailnet.New(),
		agents.New(home),
		quota.New(home),
		hosts.New(home),
		repos.New(home),
		focus.New(home),
		deploys.New(home),
		services.New(home),
		inbox.New(home),
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	if *once {
		s := runOnce(ctx, collectors, true)
		if err := snapshot.WriteAtomic(*out, s); err != nil {
			log.Fatalf("escrita: %v", err)
		}
		log.Printf("snapshot em %s", *out)
		return
	}

	ticker := time.NewTicker(*interval)
	defer ticker.Stop()

	for {
		s := runOnce(ctx, collectors, false)
		if err := snapshot.WriteAtomic(*out, s); err != nil {
			log.Printf("escrita falhou: %v", err)
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

// runOnce roda todos os coletores em sequência. Um coletor que falha vira uma
// entrada em Errors e não impede os outros de publicar o dado deles.
func runOnce(ctx context.Context, cs []collect.Collector, verbose bool) *snapshot.Snapshot {
	s := &snapshot.Snapshot{
		Version: snapshot.Version,
		TS:      time.Now(),
		Errors:  map[string]string{},
	}
	for _, c := range cs {
		t0 := time.Now()
		if err := c.Collect(ctx, s); err != nil {
			s.Errors[c.Name()] = err.Error()
		}
		if verbose {
			log.Printf("%-10s %v", c.Name(), time.Since(t0).Round(time.Millisecond))
		}
	}
	return s
}

func defaultOut() string {
	if dir := os.Getenv("XDG_RUNTIME_DIR"); dir != "" {
		return filepath.Join(dir, "ricestat.json")
	}
	return "/tmp/ricestat.json"
}
