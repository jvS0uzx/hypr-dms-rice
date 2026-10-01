package services

import (
	"crypto/x509"
	"crypto/x509/pkix"
	"testing"
	"time"
)

func TestCertInfo(t *testing.T) {
	now := time.Date(2026, 9, 30, 12, 0, 0, 0, time.UTC)
	c := &x509.Certificate{
		NotAfter: now.Add(20*24*time.Hour + 5*time.Hour),
		Issuer:   pkix.Name{CommonName: "R11", Organization: []string{"Let's Encrypt"}},
	}
	days, issuer := certInfo(c, now)
	if days != 20 || issuer != "Let's Encrypt" {
		t.Fatalf("veio %d %q", days, issuer)
	}
	c.NotAfter = now.Add(-2 * time.Hour)
	if days, _ := certInfo(c, now); days != -1 {
		t.Fatalf("vencido há horas deve dar -1, veio %d", days)
	}
	c.Issuer = pkix.Name{CommonName: "nginx-selfsigned"}
	if _, issuer := certInfo(c, now); issuer != "nginx-selfsigned" {
		t.Fatalf("sem organização usa o CN, veio %q", issuer)
	}
}
