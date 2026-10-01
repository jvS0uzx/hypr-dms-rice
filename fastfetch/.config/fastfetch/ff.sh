#!/usr/bin/env bash
# Wrapper do fastfetch: sorteia o pokémon e injeta a arte como dado.
# O fastfetch 2.68 não aceita logo.type "command" — só arquivo ou dado pronto.
set -uo pipefail
ARTE=$(~/.config/fastfetch/pokemon.sh 2>/dev/null)

if [[ -z "$ARTE" ]]; then
    exec fastfetch "$@"
fi
exec fastfetch --logo-type data-raw --logo "$ARTE" "$@"
