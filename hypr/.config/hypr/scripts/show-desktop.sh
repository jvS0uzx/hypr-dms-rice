#!/usr/bin/env bash
# "Mostrar a área de trabalho" do KDE. O Hyprland não tem isso: o equivalente é
# estacionar tudo do workspace atual num workspace especial e trazer de volta na
# segunda chamada.
set -euo pipefail

# Com a configuração em Lua, `hyprctl dispatch` recebe uma expressão Lua.
move_silent() { # <endereço> <workspace>
    hyprctl dispatch "hl.dsp.window.move({ window = \"address:$1\", workspace = \"$2\", follow = false })" >/dev/null
}

STASH="special:areadetrabalho"
ws=$(hyprctl activeworkspace -j | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')

stashed=$(hyprctl clients -j | python3 -c '
import sys, json
print(sum(1 for c in json.load(sys.stdin) if c["workspace"]["name"] == "special:areadetrabalho"))')

if [[ "$stashed" -gt 0 ]]; then
    for addr in $(hyprctl clients -j | python3 -c '
import sys, json
for c in json.load(sys.stdin):
    if c["workspace"]["name"] == "special:areadetrabalho":
        print(c["address"])'); do
        move_silent "$addr" "$ws"
    done
else
    for addr in $(hyprctl clients -j | python3 -c "
import sys, json
for c in json.load(sys.stdin):
    if c['workspace']['id'] == $ws:
        print(c['address'])"); do
        move_silent "$addr" "$STASH"
    done
fi
