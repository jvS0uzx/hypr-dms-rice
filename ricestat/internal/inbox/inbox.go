// Package inbox lê quando o inbox do Telegram foi coletado pela última vez.
package inbox

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/snapshot"
)

type Collector struct{ state string }

// O estado é gravado pela skill /inbox; o coletor só lê.
func New(home string) *Collector {
	return &Collector{state: filepath.Join(home, ".claude", "state", "telegram_inbox.json")}
}

func (c *Collector) Name() string { return "inbox" }

func (c *Collector) Collect(_ context.Context, s *snapshot.Snapshot) error {
	b, err := os.ReadFile(c.state)
	if os.IsNotExist(err) {
		return nil // máquina sem o inbox do Telegram: nada a mostrar, não é erro
	}
	if err != nil {
		return fmt.Errorf("estado do inbox: %w", err)
	}
	var st struct {
		LastRun time.Time `json:"last_run"`
	}
	if err := json.Unmarshal(b, &st); err != nil {
		return fmt.Errorf("json invalido: %w", err)
	}
	s.Inbox = &snapshot.Inbox{LastRun: st.LastRun, AgeHours: int(time.Since(st.LastRun).Hours())}
	return nil
}
