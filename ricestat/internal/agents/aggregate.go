package agents

import (
	"sort"
	"time"

	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/snapshot"
)

type aggregator struct {
	now        time.Time
	todayStart time.Time
	weekStart  time.Time
	monthStart time.Time

	a        snapshot.Agents
	projects map[string]*snapshot.ProjectCost
	models   map[string]*snapshot.ModelCost
	daily    map[string]float64
}

func newAggregator(now time.Time) *aggregator {
	y, m, d := now.Date()
	loc := now.Location()
	todayStart := time.Date(y, m, d, 0, 0, 0, 0, loc)

	// Semana começa na segunda — é como o trabalho é contado aqui.
	offset := (int(now.Weekday()) + 6) % 7

	return &aggregator{
		now:        now,
		todayStart: todayStart,
		weekStart:  todayStart.AddDate(0, 0, -offset),
		monthStart: time.Date(y, m, 1, 0, 0, 0, 0, loc),
		projects:   map[string]*snapshot.ProjectCost{},
		models:     map[string]*snapshot.ModelCost{},
		daily:      map[string]float64{},
	}
}

// add contabiliza uma sessão. O bucket de data usa startTime: é quando a sessão
// começou. Sessão que atravessa a meia-noite conta no dia em que nasceu.
//
// st pode ser nil: sessão em curso que ainda não gravou linha de custo. Ela
// entra na lista de ativas sem somar dinheiro nenhum.
func (ag *aggregator) add(name, slug string, st *costState, modTime time.Time, active bool) {
	if st == nil {
		if active {
			ag.a.Active = append(ag.a.Active, snapshot.ActiveAgent{
				Project:  name,
				LastSeen: modTime,
			})
		}
		return
	}

	ag.a.Sessions++
	ag.a.TotalUSD += st.TotalCostUSD

	start := time.UnixMilli(st.StartTime)
	if st.StartTime == 0 {
		start = modTime
	}

	if !start.Before(ag.todayStart) {
		ag.a.TodayUSD += st.TotalCostUSD
	}
	if !start.Before(ag.weekStart) {
		ag.a.WeekUSD += st.TotalCostUSD
	}
	if !start.Before(ag.monthStart) {
		ag.a.MonthUSD += st.TotalCostUSD
	}
	if ag.now.Sub(start) < dailyDays*24*time.Hour {
		ag.daily[start.Format("2006-01-02")] += st.TotalCostUSD
	}

	p, ok := ag.projects[name]
	if !ok {
		p = &snapshot.ProjectCost{Project: name, Slug: slug}
		ag.projects[name] = p
	}
	p.CostUSD += st.TotalCostUSD
	p.Sessions++

	for name, u := range st.ModelUsage {
		m, ok := ag.models[name]
		if !ok {
			m = &snapshot.ModelCost{Model: name}
			ag.models[name] = m
		}
		m.CostUSD += u.CostUSD
		m.InputTokens += u.InputTokens
		m.OutputTokens += u.OutputTokens
		m.CacheRead += u.CacheReadInputTokens
	}

	if active {
		ag.a.Active = append(ag.a.Active, snapshot.ActiveAgent{
			Project:   name,
			SessionID: st.SessionID,
			Since:     start,
			CostUSD:   st.TotalCostUSD,
			LastSeen:  modTime,
		})
	}
}

func (ag *aggregator) result() *snapshot.Agents {
	for _, p := range ag.projects {
		ag.a.ByProject = append(ag.a.ByProject, *p)
	}
	sort.Slice(ag.a.ByProject, func(i, j int) bool {
		return ag.a.ByProject[i].CostUSD > ag.a.ByProject[j].CostUSD
	})

	for _, m := range ag.models {
		ag.a.ByModel = append(ag.a.ByModel, *m)
	}
	sort.Slice(ag.a.ByModel, func(i, j int) bool {
		return ag.a.ByModel[i].CostUSD > ag.a.ByModel[j].CostUSD
	})

	// Série contínua: dia sem sessão precisa aparecer como zero, senão o
	// gráfico do widget comprime o eixo e mente sobre o ritmo.
	for i := dailyDays - 1; i >= 0; i-- {
		d := ag.now.AddDate(0, 0, -i).Format("2006-01-02")
		ag.a.Daily = append(ag.a.Daily, snapshot.DailyCost{Date: d, CostUSD: ag.daily[d]})
	}

	sort.Slice(ag.a.Active, func(i, j int) bool {
		return ag.a.Active[i].LastSeen.After(ag.a.Active[j].LastSeen)
	})
	ag.a.ActiveCount = len(ag.a.Active)

	return &ag.a
}
