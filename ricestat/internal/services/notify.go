package services

import (
	"fmt"
	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/notify"
	"time"

	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/snapshot"
)

// Um site só é dado como fora depois de duas checagens seguidas falhando (2
// minutos): uma falha isolada é oscilação de rede e viraria alarme falso.
const downAfter = 2

// Certificado com menos dias que isto avisa uma vez por dia.
const certWarnDays = 15

// notify avisa só na mudança de estado. A primeira coleta semeia o estado sem
// avisar: sem isso, todo login despejaria um aviso por site já quebrado.
// Chamado com c.mu travado.
func (c *Collector) notify(out *snapshot.Services) {
	seed := c.down == nil
	if seed {
		c.down = map[string]bool{}
		c.certWarned = map[string]string{}
	}
	today := time.Now().Format("2006-01-02")

	for _, it := range out.Items {
		h := c.history[it.Name]
		isDown := len(h) >= downAfter
		for _, failed := range h[max(0, len(h)-downAfter):] {
			isDown = isDown && failed
		}
		was := c.down[it.Name]
		c.down[it.Name] = isDown

		if !seed {
			switch {
			case isDown && !was:
				why := it.Error
				if why == "" && it.Status > 0 {
					why = fmt.Sprintf("respondeu HTTP %d", it.Status)
				}
				send("critical", "public_off", it.Name+" fora do ar", why)
			case !isDown && was && it.OK:
				send("normal", "public", it.Name+" voltou", fmt.Sprintf("respondeu em %d ms", it.LatencyMS))
			}
		}

		if it.CertDays >= 0 && it.CertDays < certWarnDays && c.certWarned[it.Name] != today {
			c.certWarned[it.Name] = today
			if !seed {
				send("normal", "lock_clock", fmt.Sprintf("Certificado de %s vence em %d dias", it.Name, it.CertDays),
					"conferir a renovação do certbot no load balancer")
			}
		}
	}
}

func send(urgency, icon, title, body string) {
	notify.Send("Sites", urgency, icon, title, body)
}
