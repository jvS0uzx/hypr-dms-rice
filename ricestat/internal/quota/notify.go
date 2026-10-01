package quota

import (
	"bufio"
	"encoding/json"
	"fmt"
	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/notify"
	"os"
	"time"

	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/snapshot"
)

// Percentuais da janela de 5 horas que avisam. 80% dá tempo de decidir se
// vale começar algo grande; 95% é a última chance antes de travar.
var pctSteps = []float64{80, 95}

// alertState guarda o que já foi avisado, para avisar uma vez por janela.
type alertState struct {
	seeded     bool
	window     time.Time // fim da janela dos avisos de percentual
	warnedStep float64
	lastLimit  time.Time // recusa mais recente já avisada
}

// officialPct lê o percentual oficial da janela gravado pelo registrador da
// status line (BI-Dev). Sem leitura recente (10 min), não há percentual: o
// aviso de percentual simplesmente não dispara.
func officialPct(path string, now time.Time) (pct float64, resets time.Time, ok bool) {
	f, err := os.Open(path)
	if err != nil {
		return 0, time.Time{}, false
	}
	defer f.Close()
	var last struct {
		At     time.Time `json:"at"`
		Pct    *float64  `json:"five_hour_pct"`
		Resets *int64    `json:"five_hour_resets"`
	}
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		json.Unmarshal(sc.Bytes(), &last)
	}
	if last.Pct == nil || last.Resets == nil || now.Sub(last.At) > 10*time.Minute {
		return 0, time.Time{}, false
	}
	return *last.Pct, time.Unix(*last.Resets, 0), true
}

// notify avisa só na mudança: passou de um degrau de percentual nesta janela,
// ou apareceu recusa por limite nova. A primeira coleta semeia sem avisar.
func (c *Collector) notify(q *snapshot.Quota, now time.Time) {
	st := &c.alerts
	var newest snapshot.QuotaHit
	for _, h := range q.LimitHits {
		if h.At.After(newest.At) {
			newest = h
		}
	}
	pct, resets, hasPct := officialPct(c.RateLog, now)

	if !st.seeded {
		st.seeded = true
		st.lastLimit = newest.At
		if hasPct {
			st.window = resets
			for _, s := range pctSteps {
				if pct >= s {
					st.warnedStep = s
				}
			}
		}
		return
	}

	if newest.At.After(st.lastLimit) {
		st.lastLimit = newest.At
		send("critical", "block", "Cota do Claude esgotada",
			"libera às "+newest.ResetsAt.Local().Format("15:04"))
	}

	if !hasPct {
		return
	}
	if !resets.Equal(st.window) {
		st.window, st.warnedStep = resets, 0
	}
	for _, s := range pctSteps {
		if pct >= s && st.warnedStep < s {
			st.warnedStep = s
			urg := "normal"
			if s >= 95 {
				urg = "critical"
			}
			send(urg, "token", fmt.Sprintf("Cota do Claude em %.0f%% da janela", pct),
				"renova às "+resets.Local().Format("15:04"))
		}
	}
}

func send(urgency, icon, title, body string) {
	// O logo do Claude identifica de qual IA é o aviso; o ícone do estado
	// (bloqueio, uso) não aparece, então só entra se o logo não existir.
	home, _ := os.UserHomeDir()
	if logo := home + "/.config/DankMaterialShell/plugins/AgentMeter/icons/claude.svg"; fileExists(logo) {
		icon = logo
	}
	notify.Send("Claude", urgency, icon, title, body)
}

func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}
