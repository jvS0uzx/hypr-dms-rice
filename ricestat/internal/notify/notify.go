// Package notify manda notificações de desktop pelo notify-send.
//
// Título e corpo carregam texto que não é nosso — título de commit, mensagem
// de erro de servidor — e o servidor de notificações interpreta marcação
// (<b>, <a href>, <img>). Sem escapar, um commit com "<a href=...>" vira link
// clicável num alerta que o usuário confia.
package notify

import (
	"os/exec"
	"strings"
)

var markup = strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;")

// Send nunca devolve erro: falha ao notificar não pode derrubar a coleta.
func Send(app, urgency, icon, title, body string) {
	_ = exec.Command("notify-send", "-u", urgency, "-a", app, "-i", icon,
		markup.Replace(title), markup.Replace(body)).Run()
}
