package hosts

import (
	"encoding/json"
	"math"
	"os"
	"path/filepath"
	"time"

	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/snapshot"
)

// Uma amostra por hora basta: disco cresce em dias, não em minutos, e o
// arquivo fica em ~720 pontos por host em vez de 43 mil.
const (
	sampleEvery = time.Hour
	keepFor     = 30 * 24 * time.Hour
	minSpan     = 24 * time.Hour
)

type diskSample struct {
	At  int64 `json:"at"`
	Pct int   `json:"pct"`
}

type diskHistory struct {
	path  string
	Hosts map[string][]diskSample `json:"hosts"`
}

func loadHistory(path string) *diskHistory {
	h := &diskHistory{path: path, Hosts: map[string][]diskSample{}}
	if b, err := os.ReadFile(path); err == nil {
		_ = json.Unmarshal(b, h)
		if h.Hosts == nil {
			h.Hosts = map[string][]diskSample{}
		}
	}
	return h
}

// record guarda a amostra se a última tiver mais de uma hora, poda o que
// passou de 30 dias e devolve se houve mudança para gravar.
func (h *diskHistory) record(alias string, pct int, now time.Time) bool {
	ss := h.Hosts[alias]
	if n := len(ss); n > 0 && now.Sub(time.Unix(ss[n-1].At, 0)) < sampleEvery {
		return false
	}
	ss = append(ss, diskSample{At: now.Unix(), Pct: pct})
	cut := now.Add(-keepFor).Unix()
	i := 0
	for i < len(ss) && ss[i].At < cut {
		i++
	}
	h.Hosts[alias] = ss[i:]
	return true
}

func (h *diskHistory) save() {
	b, err := json.Marshal(h)
	if err != nil {
		return
	}
	os.MkdirAll(filepath.Dir(h.path), 0o755)
	tmp := h.path + ".tmp"
	if os.WriteFile(tmp, b, 0o644) == nil {
		os.Rename(tmp, h.path)
	}
}

// trend devolve a inclinação em pontos percentuais por dia e os dias até
// 100%. -1 em dias quando não há dado suficiente ou o disco não está subindo.
func trend(ss []diskSample, current int) (float64, int) {
	if len(ss) < 2 || time.Unix(ss[len(ss)-1].At, 0).Sub(time.Unix(ss[0].At, 0)) < minSpan {
		return 0, -1
	}
	// Mínimos quadrados com x em dias a partir da primeira amostra.
	x0 := float64(ss[0].At)
	var sx, sy, sxx, sxy float64
	n := float64(len(ss))
	for _, s := range ss {
		x := (float64(s.At) - x0) / 86400
		y := float64(s.Pct)
		sx += x
		sy += y
		sxx += x * x
		sxy += x * y
	}
	den := n*sxx - sx*sx
	if den == 0 {
		return 0, -1
	}
	slope := (n*sxy - sx*sy) / den
	slope = math.Round(slope*100) / 100
	// Abaixo de 0,05 p.p./dia é ruído de log rotacionando: "enche em 900
	// dias" não é informação.
	if slope < 0.05 {
		return slope, -1
	}
	return slope, int(float64(100-current) / slope)
}

func applyTrend(h *diskHistory, out *snapshot.Hosts, now time.Time) {
	changed := false
	for i := range out.Hosts {
		host := &out.Hosts[i]
		host.DiskFullDays = -1
		if !host.Up {
			continue
		}
		if h.record(host.Alias, host.DiskPct, now) {
			changed = true
		}
		host.DiskTrendPctDay, host.DiskFullDays = trend(h.Hosts[host.Alias], host.DiskPct)
	}
	if changed {
		h.save()
	}
}
