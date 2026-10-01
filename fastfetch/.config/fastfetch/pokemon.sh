#!/usr/bin/env bash
# Sorteia um dos favoritos para o logo do fastfetch.
#
# O `-rn` do pokemon-colorscripts sorteia por nome mas não aceita forma, e as
# megas são metade da graça — por isso o sorteio é feito aqui, e cada entrada
# carrega a própria forma. Se a forma não existir naquela versão do pacote, cai
# para o pokémon base em vez de não imprimir nada.
set -uo pipefail

FAVORITOS=(
    "charizard:mega-x"
    "charizard:mega-y"
    "krookodile:"
    "lucario:mega"
    "gengar:mega"
    "tyranitar:mega"
    "garchomp:mega"
    "rayquaza:mega"
    "gyarados:mega"
    "blaziken:mega"
    "dragonite:"
    "greninja:"
    "mimikyu:"
    "aggron:mega"
)

command -v pokemon-colorscripts >/dev/null || {
    echo "pokemon-colorscripts não instalado"
    echo "yay -S pokemon-colorscripts-git"
    exit 0
}

escolha=${FAVORITOS[RANDOM % ${#FAVORITOS[@]}]}
nome=${escolha%%:*}
forma=${escolha##*:}

if [[ -n "$forma" ]]; then
    pokemon-colorscripts -n "$nome" -f "$forma" --no-title 2>/dev/null && exit 0
fi
pokemon-colorscripts -n "$nome" --no-title 2>/dev/null || pokemon-colorscripts -r --no-title
