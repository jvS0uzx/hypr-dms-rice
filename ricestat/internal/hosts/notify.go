package hosts

import (
	"fmt"
	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/notify"

	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/snapshot"
)

// Espelham os padrões do plugin Fleet (warnCpu, warnMem, warnDisk). Se o
// limiar mudar só no widget, a notificação continua disparando no antigo —
// aceitável, porque aqui só interessa o cruzamento, não a cor.
const (
	warnCPU  = 85
	warnMem  = 85
	warnDisk = 60
)

type hostState struct {
	up             bool
	cpu, mem, disk bool // acima do limiar
}

func stateOf(h snapshot.Host) hostState {
	mem := 0.0
	if h.MemTotalMB > 0 {
		mem = float64(h.MemUsedMB) / float64(h.MemTotalMB) * 100
	}
	return hostState{
		up:   h.Up,
		cpu:  h.Up && h.LoadPct >= warnCPU,
		mem:  h.Up && mem >= warnMem,
		disk: h.Up && h.DiskPct >= warnDisk,
	}
}

// notify avisa só na TRANSIÇÃO. A primeira coleta semeia o mapa: sem isso,
// todo login despejaria um aviso por disco que já estava acima do limiar.
func (c *Collector) notify(out *snapshot.Hosts) {
	if c.prev == nil {
		c.prev = map[string]hostState{}
		for _, h := range out.Hosts {
			c.prev[h.Alias] = stateOf(h)
		}
		return
	}

	for _, h := range out.Hosts {
		now := stateOf(h)
		old, seen := c.prev[h.Alias]
		c.prev[h.Alias] = now
		if !seen {
			continue
		}

		switch {
		case old.up && !now.up:
			send("critical", "cancel", h.Alias+" fora do ar", h.Error)
			continue
		case !old.up && now.up:
			send("normal", "check_circle", h.Alias+" voltou", "")
			continue
		}

		if !old.cpu && now.cpu {
			send("normal", "memory", fmt.Sprintf("%s — CPU em %.0f%%", h.Alias, h.LoadPct),
				fmt.Sprintf("load %.2f em %d núcleos", h.Load1, h.CPUs))
		}
		if !old.mem && now.mem {
			send("normal", "memory_alt", fmt.Sprintf("%s — memória em %.0f%%", h.Alias,
				float64(h.MemUsedMB)/float64(h.MemTotalMB)*100), "")
		}
		if !old.disk && now.disk {
			body := ""
			if h.DiskFullDays > 0 {
				body = fmt.Sprintf("no ritmo atual enche em %d dias", h.DiskFullDays)
			}
			send("normal", "hard_drive", fmt.Sprintf("%s — disco em %d%%", h.Alias, h.DiskPct), body)
		}
	}
}

func send(urgency, icon, title, body string) {
	notify.Send("Frota", urgency, icon, title, body)
}
