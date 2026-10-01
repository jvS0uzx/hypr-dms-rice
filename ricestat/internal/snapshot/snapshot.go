// Package snapshot define o contrato entre o coletor e os plugins QML do DMS.
// Qualquer mudança de campo aqui quebra widget — versione com Version.
package snapshot

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

const Version = 1

type Snapshot struct {
	Version int       `json:"version"`
	TS      time.Time `json:"ts"`

	Tailnet *Tailnet `json:"tailnet,omitempty"`
	Quota   *Quota   `json:"quota,omitempty"`
	Hosts   *Hosts   `json:"hosts,omitempty"`
	Repos   *Repos   `json:"repos,omitempty"`
	Focus   *Focus   `json:"focus,omitempty"`
	Agents  *Agents  `json:"agents,omitempty"`
	Docker  *Docker  `json:"docker,omitempty"`
	Deploys *Deploys `json:"deploys,omitempty"`
	Fleet   *Fleet   `json:"fleet,omitempty"`

	Services *Services `json:"services,omitempty"`
	Inbox    *Inbox    `json:"inbox,omitempty"`

	// Erros por bloco. Fonte indisponível apaga só o widget dela, e o widget
	// mostra o motivo — zero silencioso é pior que um traço.
	Errors map[string]string `json:"errors"`
}

type Tailnet struct {
	Online  int           `json:"online"`
	Offline int           `json:"offline"`
	Self    string        `json:"self"`
	Nodes   []TailnetNode `json:"nodes"`
}

type TailnetNode struct {
	Name     string `json:"name"`
	IP       string `json:"ip"`
	OS       string `json:"os"`
	Online   bool   `json:"online"`
	Self     bool   `json:"self"`
	LastSeen string `json:"last_seen,omitempty"`
	// Dias até a chave do nó expirar; -1 quando a expiração está desligada.
	// Chave vencida tira a máquina da tailnet — e o cluster inteiro fala por ela.
	KeyDays int `json:"key_days"`
}

// Quota descreve a janela de cobrança de 5 horas em curso.
type Quota struct {
	Active          bool      `json:"active"`
	BlockStart      time.Time `json:"block_start"`
	BlockEnd        time.Time `json:"block_end"`
	BlockMinutes    int       `json:"block_minutes"`
	MinutesElapsed  int       `json:"minutes_elapsed"`
	MinutesLeft     int       `json:"minutes_left"`
	BlockTokens     int64     `json:"block_tokens"`
	BlockRequests   int       `json:"block_requests"`
	BlockIn         int64     `json:"block_in"`
	BlockOut        int64     `json:"block_out"`
	BlockCacheRead  int64     `json:"block_cache_read"`
	BlockCacheWrite int64     `json:"block_cache_write"`

	// Janela de 7 dias, rolante. O Claude também limita por semana, mas a
	// âncora não aparece em lugar nenhum do log — então é "últimos 7 dias",
	// não "reseta em".
	WeekTokens      int64        `json:"week_tokens"`
	WeekRequests    int          `json:"week_requests"`
	LastActivity    time.Time    `json:"last_activity,omitempty"`
	IdleSec         int          `json:"idle_sec"`
	BurnPerMin      float64      `json:"burn_per_min"`
	Projected       int64        `json:"projected"`
	PeakBlockTokens int64        `json:"peak_block_tokens"`
	ByModel         []QuotaModel `json:"by_model"`
	Recent          []QuotaBlock `json:"recent"`
	Hourly          []QuotaHour  `json:"hourly"`
	LimitHits       []QuotaHit   `json:"limit_hits"`
}

type QuotaModel struct {
	Model  string `json:"model"`
	Tokens int64  `json:"tokens"`
}

type QuotaBlock struct {
	Start  time.Time `json:"start"`
	Tokens int64     `json:"tokens"`
}

// QuotaHour é uma hora cheia de consumo — o retroativo que o widget abre ao
// clicar. Horas sem atividade entram com zero para o eixo não pular.
type QuotaHour struct {
	Start    time.Time `json:"start"`
	Tokens   int64     `json:"tokens"`
	Out      int64     `json:"out"`
	Requests int       `json:"requests"`
}

type QuotaHit struct {
	At       time.Time `json:"at"`
	Kind     string    `json:"kind"`
	ResetsAt time.Time `json:"resets_at"`
}

type Agents struct {
	TodayUSD    float64       `json:"today_usd"`
	WeekUSD     float64       `json:"week_usd"`
	MonthUSD    float64       `json:"month_usd"`
	TotalUSD    float64       `json:"total_usd"`
	ActiveCount int           `json:"active_count"`
	Active      []ActiveAgent `json:"active"`
	ByProject   []ProjectCost `json:"by_project"`
	ByModel     []ModelCost   `json:"by_model"`
	Daily       []DailyCost   `json:"daily"`
	Sessions    int           `json:"sessions"`
}

type ActiveAgent struct {
	Project   string    `json:"project"`
	SessionID string    `json:"session_id"`
	Since     time.Time `json:"since"`
	CostUSD   float64   `json:"cost_usd"`
	LastSeen  time.Time `json:"last_seen"`
}

type ProjectCost struct {
	Project  string  `json:"project"`
	Slug     string  `json:"slug"`
	CostUSD  float64 `json:"cost_usd"`
	Sessions int     `json:"sessions"`
}

type ModelCost struct {
	Model        string  `json:"model"`
	CostUSD      float64 `json:"cost_usd"`
	InputTokens  int64   `json:"input_tokens"`
	OutputTokens int64   `json:"output_tokens"`
	CacheRead    int64   `json:"cache_read_tokens"`
}

type DailyCost struct {
	Date    string  `json:"date"`
	CostUSD float64 `json:"cost_usd"`
}

type Focus struct {
	Current  string       `json:"current"`
	Window   string       `json:"window"`
	TodaySec int          `json:"today_sec"`
	WeekSec  int          `json:"week_sec"`
	Today    []FocusEntry `json:"today"`
	Week     []FocusEntry `json:"week"`
}

type FocusEntry struct {
	Project string `json:"project"`
	Seconds int    `json:"seconds"`
}

type Repos struct {
	Total      int    `json:"total"`
	DirtyCount int    `json:"dirty_count"`
	AheadCount int    `json:"ahead_count"`
	Pending    []Repo `json:"pending"`
}

type Repo struct {
	Name      string `json:"name"`
	Path      string `json:"path"`
	Branch    string `json:"branch,omitempty"`
	Dirty     int    `json:"dirty"`
	Untracked int    `json:"untracked"`
	Ahead     int    `json:"ahead"`
	Behind    int    `json:"behind"`
	Error     string `json:"error,omitempty"`
}

type Hosts struct {
	Up            int    `json:"up"`
	Down          int    `json:"down"`
	Databases     int    `json:"databases"`
	DatabasesDown int    `json:"databases_down"`
	Hosts         []Host `json:"hosts"`
}

type Host struct {
	Alias          string     `json:"alias"`
	Role           string     `json:"role"`
	Remote         bool       `json:"remote"`
	Up             bool       `json:"up"`
	Error          string     `json:"error,omitempty"`
	LatencyMS      int        `json:"latency_ms"`
	Bytes          int        `json:"bytes"` // tamanho da resposta, para conferir o custo em tráfego
	Load1          float64    `json:"load1"`
	Load5          float64    `json:"load5"`
	LoadPct        float64    `json:"load_pct"`
	CPUs           int        `json:"cpus"`
	MemUsedMB      int        `json:"mem_used_mb"`
	MemTotalMB     int        `json:"mem_total_mb"`
	DiskPct        int        `json:"disk_pct"`
	UptimeSec      int64      `json:"uptime_sec"`
	ContainersUp   int        `json:"containers_up"`
	ContainersDown int        `json:"containers_down"`
	Databases      []Database `json:"databases,omitempty"`

	// Tendência do disco por regressão linear das amostras horárias. Só é
	// calculada com pelo menos 24h de dados; antes disso fica em zero e
	// DiskFullDays em -1, para o widget não prever com três pontos.
	DiskTrendPctDay float64 `json:"disk_trend_pct_day"`
	DiskFullDays    int     `json:"disk_full_days"`
}

type Database struct {
	Name        string `json:"name"`
	Engine      string `json:"engine"`
	Up          bool   `json:"up"`
	Health      string `json:"health"` // h saudável, u doente, - sem healthcheck
	Connections int    `json:"connections"`
	SizeBytes   int64  `json:"size_bytes"`
}

// Stubs — ver rice-widgets-monitoramento.md no vault.
type Docker struct {
	Up        int      `json:"up"`
	Down      int      `json:"down"`
	Unhealthy int      `json:"unhealthy"`
	Names     []string `json:"names"`
}

// Estados de deploy. String e não enum numérico porque o consumidor é QML.
const (
	DeploySuccess = "success"
	DeployFailure = "failure"
	DeployRunning = "running"
	DeployUnknown = "unknown"
)

type Deploys struct {
	OK      int          `json:"ok"`
	Failing int          `json:"failing"`
	Running int          `json:"running"`
	Unknown int          `json:"unknown"`
	Repos   []DeployRepo `json:"repos"`
}

type DeployRepo struct {
	Repo   string    `json:"repo"`
	Name   string    `json:"name"`
	State  string    `json:"state"`
	Branch string    `json:"branch,omitempty"`
	Title  string    `json:"title,omitempty"`
	URL    string    `json:"url,omitempty"`
	At     time.Time `json:"at,omitempty"`
	Error  string    `json:"error,omitempty"`

	// Preenchidos só enquanto o run está em andamento — é o que transforma o
	// widget de "resultado final" em acompanhamento ao vivo.
	RunID       int64       `json:"run_id,omitempty"`
	ElapsedSec  int         `json:"elapsed_sec,omitempty"`
	Jobs        []DeployJob `json:"jobs,omitempty"`
	StepsTotal  int         `json:"steps_total,omitempty"`
	StepsDone   int         `json:"steps_done,omitempty"`
	CurrentStep string      `json:"current_step,omitempty"`
}

type DeployJob struct {
	Name        string    `json:"name"`
	State       string    `json:"state"`
	StartedAt   time.Time `json:"started_at,omitempty"`
	ElapsedSec  int       `json:"elapsed_sec,omitempty"`
	StepsTotal  int       `json:"steps_total"`
	StepsDone   int       `json:"steps_done"`
	CurrentStep string    `json:"current_step,omitempty"`
}

type Fleet struct {
	Hosts []FleetHost `json:"hosts"`
}

type FleetHost struct {
	Name string  `json:"name"`
	Role string  `json:"role"`
	Up   bool    `json:"up"`
	CPU  float64 `json:"cpu"`
	Mem  float64 `json:"mem"`
}

// Services é a visão de fora: o domínio responde para quem usa? Máquina no ar
// não quer dizer aplicação no ar.
type Services struct {
	CheckedAt time.Time     `json:"checked_at"`
	OK        int           `json:"ok"`
	Failing   int           `json:"failing"`
	Items     []ServiceItem `json:"items"`
}

type ServiceItem struct {
	Name       string `json:"name"`
	URL        string `json:"url"`
	Status     int    `json:"status"` // 0 quando não houve resposta HTTP
	OK         bool   `json:"ok"`
	LatencyMS  int    `json:"latency_ms"`
	CertDays   int    `json:"cert_days"` // -1 quando o handshake não aconteceu
	CertIssuer string `json:"cert_issuer,omitempty"`
	Error      string `json:"error,omitempty"`
	// Quantas das últimas RecentN checagens falharam. É o que denuncia erro
	// intermitente: um nó bom e outro ruim atrás do balanceador dão "ok" e
	// "500" alternados, e a checagem isolada acerta ou erra por sorte.
	RecentFail int `json:"recent_fail"`
	RecentN    int `json:"recent_n"`
}

// WriteAtomic grava via tmp+rename. Leitura concorrente do QML nunca pega
// arquivo pela metade — o FileView do Quickshell relê a cada mudança de inode.
func WriteAtomic(path string, s *Snapshot) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".ricestat-*.json")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())

	enc := json.NewEncoder(tmp)
	enc.SetIndent("", "  ")
	if err := enc.Encode(s); err != nil {
		tmp.Close()
		return fmt.Errorf("encode: %w", err)
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Chmod(tmp.Name(), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), path)
}

// Inbox é a idade da última coleta do Telegram. A Bot API descarta update com
// mais de 24 horas, então passar disso é perder mensagem sem aviso.
type Inbox struct {
	LastRun  time.Time `json:"last_run"`
	AgeHours int       `json:"age_hours"`
}
