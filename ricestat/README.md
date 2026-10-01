# ricestat

Coletor único do rice. Consolida as fontes de monitoramento num snapshot JSON
(`$XDG_RUNTIME_DIR/ricestat.json`) que os plugins QML do DankMaterialShell leem,
e manda notificação de desktop quando algo muda de estado.

```
tailscale  ─┐
~/.claude  ─┤
gh (API)   ─┼─▶ ricestat ─▶ $XDG_RUNTIME_DIR/ricestat.json ─▶ plugins QML
ssh hosts  ─┤    (tick 15s)            │
https      ─┘                          └─▶ notify-send (só na mudança de estado)
```

Os plugins **não coletam nada**. Vários widgets puxando dado por conta própria
estourariam o rate limit do `gh`, abririam várias conexões SSH e tentariam
parsear centenas de MB de JSONL dentro do QML.

## Uso

```bash
go build -o ~/.local/bin/ricestat ./cmd/ricestat
ricestat --once            # coleta uma vez e imprime o caminho do snapshot
ricestat --interval 15s    # modo daemon (é o que a unit systemd usa)
systemctl --user status ricestat
```

## Coletores

| Nome | Fonte | Configuração |
|---|---|---|
| `tailnet` | `tailscale status --json` (nós, expiração de chave) | — |
| `agents` | `~/.claude/projects/**/*.jsonl` | — |
| `quota` | janelas de 5 h do Claude Code, a partir dos mesmos logs | status line, opcional (abaixo) |
| `hosts` | probe SSH somente leitura: carga, memória, disco, contêineres, bancos | `~/.config/ricestat/hosts.txt` |
| `deploys` | `gh run list` do `deploy.yml` de cada repositório | `~/.config/ricestat/repos.txt` |
| `services` | GET HTTPS na raiz: status, latência, validade do certificado | `~/.config/ricestat/services.txt` |
| `repos` | repositórios git locais sujos, à frente ou atrás do `origin` | `~/.config/ricestat/code-roots.txt` |
| `focus` | janela ativa do Hyprland → projeto pelo diretório do processo | — |

Coletor que falha vira uma entrada em `errors` no snapshot e **não** derruba os
outros. O widget mostra o motivo — zero silencioso é pior que um traço. Sem
servidores, repositórios ou sites configurados, os coletores correspondentes
ficam vazios em vez de mostrar erro.

## Alertas

Notificação só na **mudança** de estado; a primeira coleta depois de subir só
registra o estado atual, senão todo login despejaria avisos antigos.

- deploy iniciado, concluído, falhou;
- servidor caiu, voltou, CPU/memória/disco acima do limiar;
- site fora do ar (duas checagens seguidas), voltou, certificado vencendo;
- cota do Claude em 80% e 95% da janela, e quando a conta trava.

Título e corpo passam por `internal/notify`, que escapa marcação: título de
commit e mensagem de erro de servidor são texto de terceiros.

## Percentual oficial da cota do Claude

O Claude Code entrega o percentual de uso da janela de 5 h e da semanal apenas
para o script de status line. `statusline/claude-statusline.sh` se encaixa na
frente da sua status line, anota o valor quando muda e repassa a entrada:

```json
"statusLine": {
  "type": "command",
  "command": "bash ~/dotfiles/ricestat/statusline/claude-statusline.sh <sua status line atual>"
}
```

Sem isso, o painel funciona com a reconstrução das janelas pelos logs e só o
aviso de 80%/95% fica desligado.

## Segurança

- O probe SSH é **somente leitura** (`/proc`, `df`, `docker ps`, contagem por
  banco). Usa ControlMaster com sockets em `~/.cache/ricestat/ssh` (0700).
- Nenhuma credencial fica no snapshot ou no repositório. Os logs do Claude são
  lidos localmente; só agregados saem do coletor, e só para o snapshot local.
- O snapshot fica em `$XDG_RUNTIME_DIR` (0700, só o usuário).

## Como o coletor de logs não trava a máquina

São centenas de MB de log de sessão. Os coletores mantêm índice por
`(mtime, size)` em `~/.cache/ricestat/` e só releem o que mudou; o de cota lê a
partir do último offset, porque o log só cresce.
