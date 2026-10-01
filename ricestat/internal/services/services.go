// Package services checa os domínios de produção por fora, como o usuário vê:
// GET HTTPS na raiz, status, latência e dias até o certificado vencer.
//
// Somente leitura: um GET por domínio a cada minuto. Nada é enviado além do
// que um navegador mandaria ao abrir a página.
package services

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/snapshot"
)

const (
	pollTTL    = 60 * time.Second
	reqTimeout = 8 * time.Second
	historyN   = 30
)

type Collector struct {
	ConfPath string

	mu       sync.Mutex
	cached   *snapshot.Services
	cachedAt time.Time
	history  map[string][]bool // por domínio, true = falhou; mais recente no fim
	client   *http.Client

	down       map[string]bool   // estado anterior, para avisar só na mudança
	certWarned map[string]string // domínio → dia do último aviso de certificado
}

func New(home string) *Collector {
	return &Collector{
		ConfPath: filepath.Join(home, ".config", "ricestat", "services.txt"),
		history:  map[string][]bool{},
		client: &http.Client{
			Timeout: reqTimeout,
			// Redirect para outro host não é a aplicação respondendo — é outra
			// aplicação. Dentro do mesmo host (http→https, / → /login/) segue.
			CheckRedirect: func(req *http.Request, via []*http.Request) error {
				if len(via) >= 5 {
					return errors.New("redirecionamentos demais")
				}
				if req.URL.Hostname() != via[0].URL.Hostname() {
					return http.ErrUseLastResponse
				}
				return nil
			},
		},
	}
}

func (c *Collector) Name() string { return "services" }

func (c *Collector) Collect(ctx context.Context, s *snapshot.Snapshot) error {
	c.mu.Lock()
	if c.cached != nil && time.Since(c.cachedAt) < pollTTL {
		s.Services = c.cached
		c.mu.Unlock()
		return nil
	}
	c.mu.Unlock()

	names, err := readList(c.ConfPath)
	if err != nil {
		return err
	}

	out := &snapshot.Services{CheckedAt: time.Now(), Items: make([]snapshot.ServiceItem, len(names))}
	var wg sync.WaitGroup
	for i, n := range names {
		wg.Add(1)
		go func(i int, n string) {
			defer wg.Done()
			out.Items[i] = c.check(ctx, n)
		}(i, n)
	}
	wg.Wait()

	c.mu.Lock()
	for i := range out.Items {
		it := &out.Items[i]
		h := append(c.history[it.Name], !it.OK)
		if len(h) > historyN {
			h = h[len(h)-historyN:]
		}
		c.history[it.Name] = h
		it.RecentN = len(h)
		for _, failed := range h {
			if failed {
				it.RecentFail++
			}
		}
		if it.OK {
			out.OK++
		} else {
			out.Failing++
		}
	}
	c.notify(out)
	c.cached, c.cachedAt = out, time.Now()
	c.mu.Unlock()

	s.Services = out
	return nil
}

func (c *Collector) check(ctx context.Context, name string) snapshot.ServiceItem {
	url := "https://" + name + "/"
	it := snapshot.ServiceItem{Name: name, URL: url, CertDays: -1}

	ctx, cancel := context.WithTimeout(ctx, reqTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		it.Error = err.Error()
		return it
	}
	req.Header.Set("User-Agent", "ricestat/1 (monitoramento interno)")

	t0 := time.Now()
	resp, err := c.client.Do(req)
	it.LatencyMS = int(time.Since(t0).Milliseconds())
	if err != nil {
		it.Error = shortErr(err)
		return it
	}
	defer resp.Body.Close()

	it.Status = resp.StatusCode
	// 2xx e 3xx contam como no ar: redirect para login é a aplicação
	// respondendo. 4xx também seria, mas na raiz de um domínio de produção um
	// 404 quase sempre é roteamento quebrado, então conta como falha.
	it.OK = resp.StatusCode < 400
	if !it.OK {
		it.Error = resp.Status
	}
	if resp.TLS != nil && len(resp.TLS.PeerCertificates) > 0 {
		it.CertDays, it.CertIssuer = certInfo(resp.TLS.PeerCertificates[0], time.Now())
	}
	return it
}

// certInfo devolve dias inteiros até o vencimento (negativo se já venceu) e
// o nome curto do emissor.
func certInfo(cert *x509.Certificate, now time.Time) (int, string) {
	days := int(cert.NotAfter.Sub(now).Hours() / 24)
	if cert.NotAfter.Before(now) && days == 0 {
		days = -1
	}
	issuer := cert.Issuer.CommonName
	if len(cert.Issuer.Organization) > 0 {
		issuer = cert.Issuer.Organization[0]
	}
	return days, issuer
}

func shortErr(err error) string {
	var cv *tls.CertificateVerificationError
	if errors.As(err, &cv) {
		return "certificado inválido"
	}
	if errors.Is(err, context.DeadlineExceeded) || strings.Contains(err.Error(), "Client.Timeout") {
		return "sem resposta em 8s"
	}
	msg := err.Error()
	if i := strings.LastIndex(msg, ": "); i >= 0 {
		msg = msg[i+2:]
	}
	return msg
}

func readList(path string) ([]string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("crie %s (veja o modelo em dotfiles/seeds/services.txt)", path)
		}
		return nil, err
	}
	var out []string
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		out = append(out, strings.Fields(line)[0])
	}
	return out, nil
}
