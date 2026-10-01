// Package coderoots diz onde ficam os repositórios de código do usuário. Os
// coletores de repositórios e de foco procuram projetos dentro dessas pastas.
package coderoots

import (
	"os"
	"path/filepath"
	"strings"
)

// Load lê ~/.config/ricestat/code-roots.txt (uma pasta por linha, ~ expandido).
// Sem o arquivo, devolve os lugares usuais; pasta que não existe é ignorada por
// quem percorre.
func Load(home string) []string {
	if roots := read(filepath.Join(home, ".config", "ricestat", "code-roots.txt"), home); len(roots) > 0 {
		return roots
	}
	var out []string
	for _, d := range []string{"code", "projects", "src", "dev", "dotfiles"} {
		out = append(out, filepath.Join(home, d))
	}
	return out
}

func read(path, home string) []string {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var out []string
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if line == "~" || strings.HasPrefix(line, "~/") {
			line = filepath.Join(home, strings.TrimPrefix(line, "~"))
		}
		out = append(out, line)
	}
	return out
}
