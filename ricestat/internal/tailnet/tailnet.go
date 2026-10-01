// Package tailnet lê o estado da tailnet via CLI do Tailscale.
package tailnet

import (
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"sort"
	"time"

	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/snapshot"
)

type Collector struct{}

func New() *Collector { return &Collector{} }

func (c *Collector) Name() string { return "tailnet" }

// Recorte do `tailscale status --json`. Só os campos usados: o formato completo
// é grande e muda entre versões.
type statusJSON struct {
	Self struct {
		HostName     string    `json:"HostName"`
		TailscaleIPs []string  `json:"TailscaleIPs"`
		OS           string    `json:"OS"`
		Online       bool      `json:"Online"`
		KeyExpiry    time.Time `json:"KeyExpiry"`
	} `json:"Self"`
	Peer map[string]struct {
		HostName     string    `json:"HostName"`
		TailscaleIPs []string  `json:"TailscaleIPs"`
		OS           string    `json:"OS"`
		Online       bool      `json:"Online"`
		LastSeen     time.Time `json:"LastSeen"`
		KeyExpiry    time.Time `json:"KeyExpiry"`
	} `json:"Peer"`
}

func (c *Collector) Collect(ctx context.Context, s *snapshot.Snapshot) error {
	ctx, cancel := context.WithTimeout(ctx, 8*time.Second)
	defer cancel()

	out, err := exec.CommandContext(ctx, "tailscale", "status", "--json").Output()
	if err != nil {
		return fmt.Errorf("tailscale status: %w", err)
	}

	var st statusJSON
	if err := json.Unmarshal(out, &st); err != nil {
		return fmt.Errorf("json invalido: %w", err)
	}

	t := &snapshot.Tailnet{Self: st.Self.HostName}
	t.Nodes = append(t.Nodes, snapshot.TailnetNode{
		Name:    st.Self.HostName,
		IP:      firstIP(st.Self.TailscaleIPs),
		OS:      st.Self.OS,
		Online:  true, // a própria máquina responde por definição
		Self:    true,
		KeyDays: keyDays(st.Self.KeyExpiry),
	})

	for _, p := range st.Peer {
		n := snapshot.TailnetNode{
			Name:    p.HostName,
			IP:      firstIP(p.TailscaleIPs),
			OS:      p.OS,
			Online:  p.Online,
			KeyDays: keyDays(p.KeyExpiry),
		}
		if !p.Online && !p.LastSeen.IsZero() {
			n.LastSeen = p.LastSeen.Format(time.RFC3339)
		}
		t.Nodes = append(t.Nodes, n)
	}

	sort.Slice(t.Nodes, func(i, j int) bool {
		if t.Nodes[i].Online != t.Nodes[j].Online {
			return t.Nodes[i].Online
		}
		return t.Nodes[i].Name < t.Nodes[j].Name
	})

	for _, n := range t.Nodes {
		if n.Online {
			t.Online++
		} else {
			t.Offline++
		}
	}

	s.Tailnet = t
	return nil
}

func firstIP(ips []string) string {
	if len(ips) == 0 {
		return ""
	}
	return ips[0]
}

func keyDays(exp time.Time) int {
	if exp.IsZero() {
		return -1
	}
	d := int(time.Until(exp).Hours() / 24)
	if d < 0 {
		return 0
	}
	return d
}
