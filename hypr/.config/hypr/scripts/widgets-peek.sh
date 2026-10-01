#!/usr/bin/env bash
# Traz os widgets de monitoramento para cima das janelas, e devolve na segunda
# chamada. Diferente do Super+D, não mexe em janela nenhuma: é espiar o painel
# no meio do trabalho, não sair dele.
#
# O estado mora no próprio DMS (flag de overlay por instância), então o atalho
# continua coerente depois de reiniciar o shell.
set -euo pipefail

mapfile -t ids < <(dms ipc call desktopWidget list | awk '/\[enabled\]/ && !/desktopClock|systemMonitor/ {print $1}')
[[ ${#ids[@]} -eq 0 ]] && exit 0

if dms ipc call desktopWidget status "${ids[0]}" | grep -q 'overlay: true'; then
    want=false
else
    want=true
fi

for id in "${ids[@]}"; do
    dms ipc call desktopWidget setOverlay "$id" "$want" >/dev/null
done
