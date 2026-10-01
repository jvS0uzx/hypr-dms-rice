package hosts

import (
	"testing"
	"time"
)

func TestTrendRising(t *testing.T) {
	base := time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC).Unix()
	var ss []diskSample
	// 1 p.p. por dia durante 10 dias, amostra a cada hora: 40% → 50%.
	for h := 0; h <= 240; h++ {
		ss = append(ss, diskSample{At: base + int64(h)*3600, Pct: 40 + h/24})
	}
	slope, days := trend(ss, 50)
	if slope < 0.95 || slope > 1.05 {
		t.Fatalf("inclinação %v, esperado ~1", slope)
	}
	if days < 48 || days > 52 {
		t.Fatalf("dias até encher %d, esperado ~50", days)
	}
}

func TestTrendNeedsADay(t *testing.T) {
	base := time.Now().Unix()
	ss := []diskSample{{base, 10}, {base + 3600, 50}}
	if _, days := trend(ss, 50); days != -1 {
		t.Fatalf("com 1h de dado não pode prever, veio %d", days)
	}
}

func TestTrendFlat(t *testing.T) {
	base := time.Now().Unix()
	var ss []diskSample
	for h := 0; h < 72; h++ {
		ss = append(ss, diskSample{At: base + int64(h)*3600, Pct: 30})
	}
	if _, days := trend(ss, 30); days != -1 {
		t.Fatalf("disco estável deve dar -1, veio %d", days)
	}
}

func TestRecordHourly(t *testing.T) {
	h := &diskHistory{Hosts: map[string][]diskSample{}}
	now := time.Now()
	if !h.record("a", 10, now) || h.record("a", 11, now.Add(10*time.Minute)) {
		t.Fatal("deve gravar a primeira e ignorar a segunda dentro da mesma hora")
	}
	h.record("a", 12, now.Add(31*24*time.Hour))
	if n := len(h.Hosts["a"]); n != 1 {
		t.Fatalf("amostra de 31 dias atrás deveria ter sido podada, sobraram %d", n)
	}
}
