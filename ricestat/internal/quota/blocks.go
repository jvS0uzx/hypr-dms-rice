package quota

import (
	"sort"
	"time"

	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/snapshot"
)

// build agrupa os baldes em janelas de 5 horas.
//
// Uma janela abre no início da hora da primeira atividade e morre 5 horas
// depois, ou antes disso se houver 5 horas de silêncio — é assim que o limite
// se comporta na prática.
func build(index map[string]fileAgg, now time.Time) *snapshot.Quota {
	keys, merged := sortedBuckets(index)

	type blk struct {
		start, lastActivity       time.Time
		tokens, in, out, crd, cwr int64
		requests                  int
		byModel                   map[string]int64
	}

	var blocks []blk
	var cur *blk

	for _, k := range keys {
		t := time.Unix(k, 0)
		b := merged[k]

		if cur == nil ||
			!t.Before(cur.start.Add(blockHours*time.Hour)) ||
			t.Sub(cur.lastActivity) >= blockHours*time.Hour {
			blocks = append(blocks, blk{start: t.Truncate(time.Hour), byModel: map[string]int64{}})
			cur = &blocks[len(blocks)-1]
		}

		cur.tokens += b.Tokens
		cur.in += b.In
		cur.out += b.Out
		cur.crd += b.CacheRd
		cur.cwr += b.CacheWr
		cur.requests += b.Requests
		cur.lastActivity = t
		for m, v := range b.ByModel {
			cur.byModel[m] += v
		}
	}

	q := &snapshot.Quota{BlockMinutes: blockHours * 60}

	// Janela de 7 dias, rolante a partir de agora. O pico semanal serve de
	// referência pelo mesmo motivo do pico de bloco: sem teto declarado pela
	// conta, comparar com a própria marca é o único número honesto.
	weekCut := now.AddDate(0, 0, -7)
	var last time.Time
	for _, k := range keys {
		t := time.Unix(k, 0)
		if t.After(last) {
			last = t
		}
		if t.Before(weekCut) {
			continue
		}
		q.WeekTokens += merged[k].Tokens
		q.WeekRequests += merged[k].Requests
	}
	if !last.IsZero() {
		q.LastActivity = last
		q.IdleSec = int(now.Sub(last).Seconds())
	}

	// Pico entre janelas encerradas: sem saber o teto real da conta, a maior
	// janela já registrada é a única referência honesta de "cheio".
	for i := range blocks {
		end := blocks[i].start.Add(blockHours * time.Hour)
		if end.After(now) {
			continue
		}
		if blocks[i].tokens > q.PeakBlockTokens {
			q.PeakBlockTokens = blocks[i].tokens
		}
	}

	if n := len(blocks); n > 0 {
		last := blocks[n-1]
		end := last.start.Add(blockHours * time.Hour)
		if end.After(now) {
			elapsed := now.Sub(last.start).Minutes()
			if elapsed < 1 {
				elapsed = 1
			}
			q.Active = true
			q.BlockStart = last.start
			q.BlockEnd = end
			q.BlockTokens = last.tokens
			q.BlockRequests = last.requests
			q.BlockIn = last.in
			q.BlockOut = last.out
			q.BlockCacheRead = last.crd
			q.BlockCacheWrite = last.cwr
			q.MinutesElapsed = int(elapsed)
			q.MinutesLeft = int(end.Sub(now).Minutes())
			q.BurnPerMin = float64(last.tokens) / elapsed
			q.Projected = int64(q.BurnPerMin * float64(q.BlockMinutes))

			for m, v := range last.byModel {
				q.ByModel = append(q.ByModel, snapshot.QuotaModel{Model: m, Tokens: v})
			}
			sort.Slice(q.ByModel, func(i, j int) bool { return q.ByModel[i].Tokens > q.ByModel[j].Tokens })
		} else {
			q.BlockEnd = end
			q.MinutesLeft = 0
		}
	}

	// Histórico curto para o gráfico: as últimas 12 janelas com atividade.
	from := len(blocks) - 12
	if from < 0 {
		from = 0
	}
	for _, b := range blocks[from:] {
		q.Recent = append(q.Recent, snapshot.QuotaBlock{
			Start:  b.start,
			Tokens: b.tokens,
		})
	}

	// Retroativo por hora das últimas 48 horas, com as horas vazias incluídas.
	const hours = 48
	first := now.Truncate(time.Hour).Add(-(hours - 1) * time.Hour)
	q.Hourly = make([]snapshot.QuotaHour, hours)
	for i := range q.Hourly {
		q.Hourly[i].Start = first.Add(time.Duration(i) * time.Hour)
	}
	for _, k := range keys {
		i := int(time.Unix(k, 0).Sub(first) / time.Hour)
		if i < 0 || i >= hours {
			continue
		}
		b := merged[k]
		q.Hourly[i].Tokens += b.Tokens
		q.Hourly[i].Out += b.Out
		q.Hourly[i].Requests += b.Requests
	}

	weekAgo := now.AddDate(0, 0, -7).Unix()
	var hits []snapshot.QuotaHit
	for _, a := range index {
		for _, h := range a.Limits {
			if h.At >= weekAgo {
				hits = append(hits, snapshot.QuotaHit{
					At:       time.Unix(h.At, 0),
					Kind:     h.Kind,
					ResetsAt: time.Unix(h.ResetsAt, 0),
				})
			}
		}
	}
	sort.Slice(hits, func(i, j int) bool { return hits[i].At.After(hits[j].At) })
	// O mesmo bloqueio aparece repetido em cada tentativa; conta uma vez por
	// horário de reset, senão "5 recusas" vira "21".
	seenReset := map[int64]bool{}
	for _, h := range hits {
		r := h.ResetsAt.Unix()
		if seenReset[r] {
			continue
		}
		seenReset[r] = true
		q.LimitHits = append(q.LimitHits, h)
	}

	return q
}
