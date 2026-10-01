package deploys

import (
	"fmt"
	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/notify"

	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/snapshot"
)

// notify dispara notificação de desktop apenas quando o estado de um
// repositório MUDA. A primeira coleta depois do boot só semeia o mapa: sem
// isso, todo início de sessão despejaria uma notificação por repositório
// quebrado, e o alerta perderia o sentido no terceiro dia.
func (c *Collector) notify(d *snapshot.Deploys) {
	if c.first {
		for _, r := range d.Repos {
			c.prev[r.Repo] = r.State
		}
		c.first = false
		return
	}

	for _, r := range d.Repos {
		old, seen := c.prev[r.Repo]
		c.prev[r.Repo] = r.State
		if !seen || old == r.State {
			continue
		}

		switch {
		case r.State == snapshot.DeployRunning:
			send("normal", "rocket_launch",
				"Deploy iniciado — "+r.Name,
				truncate(r.Title, 70))

		case old == snapshot.DeployRunning && r.State == snapshot.DeploySuccess:
			body := truncate(r.Title, 70)
			if r.ElapsedSec > 0 {
				body = fmt.Sprintf("%s\nem %s", body, human(r.ElapsedSec))
			}
			send("normal", "check_circle", "Deploy concluído — "+r.Name, body)

		case r.State == snapshot.DeployFailure:
			send("critical", "cancel", "Deploy FALHOU — "+r.Name, truncate(r.Title, 70))
		}
	}
}

func send(urgency, icon, title, body string) {
	notify.Send("Deploy Radar", urgency, icon, title, body)
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n-1] + "…"
}

func human(sec int) string {
	if sec < 60 {
		return fmt.Sprintf("%ds", sec)
	}
	return fmt.Sprintf("%dmin%02ds", sec/60, sec%60)
}
