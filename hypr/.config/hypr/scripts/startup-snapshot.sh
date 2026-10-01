#!/usr/bin/env bash
# Retrato da sessão 25 s depois do Hyprland subir. Existe porque a tela preta
# na inicialização (01/10/2026) não deixou rastro: o log do Hyprland e o do
# DMS ficam em /run/user, que é apagado no logout. Guarda as 5 últimas.
set -u
sleep 25
dir="$HOME/.local/state/hypr-startup/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$dir"
hyprctl monitors >"$dir/monitors.txt" 2>&1
hyprctl layers   >"$dir/layers.txt"   2>&1
hyprctl clients  >"$dir/clients.txt"  2>&1
hyprctl configerrors >"$dir/configerrors.txt" 2>&1
pgrep -a -f 'dms|quickshell|qs ' >"$dir/processos.txt" 2>&1
cp "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log" "$dir/" 2>/dev/null
qs=$(ls -td "$XDG_RUNTIME_DIR"/quickshell/by-id/*/ 2>/dev/null | head -1)
[ -n "$qs" ] && strings "$qs/log.qslog" >"$dir/dms.log" 2>/dev/null
cd "$HOME/.local/state/hypr-startup" && ls -1d */ | head -n -5 | xargs -r rm -r
