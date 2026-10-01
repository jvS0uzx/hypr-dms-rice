// Package collect define o contrato dos coletores.
package collect

import (
	"context"

	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/snapshot"
)

// Collector preenche a sua fatia do snapshot. Erro devolvido vira entrada em
// Snapshot.Errors com a chave Name() — nunca derruba o tick inteiro.
type Collector interface {
	Name() string
	Collect(ctx context.Context, s *snapshot.Snapshot) error
}
