#!/usr/bin/env bash
# Leva os widgets de monitoramento para o notebook ou para o monitor externo.
#   widgets-tela.sh            alterna entre as duas telas
#   widgets-tela.sh notebook   widgets no notebook (eDP-1)
#   widgets-tela.sh externo    widgets no monitor externo
#
# A escolha fica no próprio DMS (displayPreferences de cada widget) e ele
# aplica na hora. A posição é guardada por tela, então cada tela lembra o
# arranjo dela. Relógio e monitor de sistema do DMS ficam de fora.
set -euo pipefail

cfg="$HOME/.config/DankMaterialShell/settings.json"
# Tela principal: a de menor id (num notebook, a embutida). RICE_MAIN_MONITOR força outra.
interno=${RICE_MAIN_MONITOR:-$(hyprctl monitors -j | jq -r 'min_by(.id).name')}
externo=$(hyprctl monitors -j | jq -r --arg i "$interno" '[.[] | select(.name != $i)][0].name // empty')

alvo=${1:-alternar}
if [[ $alvo == alternar ]]; then
    atual=$(jq -r '[.desktopWidgetInstances[] | select(.widgetType == "agentMeter")][0].config.displayPreferences[0].name' "$cfg")
    [[ $atual == "$interno" ]] && alvo=externo || alvo=notebook
fi
case $alvo in
    notebook) tela=$interno ;;
    externo)
        if [[ -z $externo ]]; then
            notify-send -a Widgets "Nenhum monitor externo ligado" "Os widgets continuam no notebook."
            exit 0
        fi
        tela=$externo ;;
    *) echo "uso: $0 [notebook|externo]" >&2; exit 2 ;;
esac
modelo=$(hyprctl monitors -j | jq -r --arg t "$tela" '.[] | select(.name == $t) | .model')

tmp=$(mktemp)
jq --arg n "$tela" --arg m "$modelo" '
  .desktopWidgetInstances |= map(
    if (.widgetType | IN("desktopClock", "systemMonitor")) then .
    else .config.displayPreferences = [{name: $n, model: $m}] end)' "$cfg" >"$tmp"
# Grava por cima, no mesmo arquivo: o DMS vigia o inode, e um `mv` criaria um
# arquivo novo que ele não percebe até reiniciar.
cat "$tmp" >"$cfg" && rm -f "$tmp"
notify-send -a Widgets "Widgets em $tela" -t 2000
