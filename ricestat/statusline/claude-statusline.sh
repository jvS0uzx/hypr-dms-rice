#!/usr/bin/env bash
# Registrador de cota do ricestat, encaixado na frente da status line.
#
# O Claude Code entrega à status line, a cada redesenho, o percentual oficial
# da janela de 5 horas e da semanal (`rate_limits`). É o único lugar onde esse
# número existe fora da tela — então esta camada anota o valor e repassa a
# entrada intacta para a status line de verdade.
#
# Uso em ~/.claude/settings.json:
#   "statusLine": {"type": "command",
#                  "command": "bash /caminho/claude-statusline.sh <comando da status line atual>"}
set -uo pipefail

input=$(cat)
log="${XDG_DATA_HOME:-$HOME/.local/share}/ricestat/ratelimits.jsonl"

# Uma linha só quando o percentual muda: a status line redesenha várias vezes
# por minuto e o log não precisa de mil linhas iguais.
line=$(jq -c 'select(.rate_limits != null) | {
    at: (now | todate),
    five_hour_pct: .rate_limits.five_hour.used_percentage,
    five_hour_resets: .rate_limits.five_hour.resets_at,
    seven_day_pct: .rate_limits.seven_day.used_percentage,
    seven_day_resets: .rate_limits.seven_day.resets_at
}' <<<"$input" 2>/dev/null)

if [[ -n "$line" ]]; then
    key=$(jq -r '"\(.five_hour_pct)|\(.five_hour_resets)|\(.seven_day_pct)"' <<<"$line")
    state="${log%.jsonl}.last"
    if [[ "$key" != "$(cat "$state" 2>/dev/null)" ]]; then
        mkdir -p "$(dirname "$log")"
        printf '%s\n' "$line" >>"$log"
        printf '%s' "$key" >"$state"
    fi
fi

# Nunca atrapalhar a status line: sem comando atrás, não imprime nada.
if [[ $# -gt 0 ]]; then
    exec "$@" <<<"$input"
fi
