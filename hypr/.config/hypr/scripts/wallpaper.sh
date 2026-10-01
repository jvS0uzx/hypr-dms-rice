#!/usr/bin/env bash
# Troca o wallpaper — de uma tela ou de todas — e recolore o desktop a partir
# do wallpaper do notebook.
#
#   wallpaper.sh picker                    escolhe a tela (se houver mais de uma) e a imagem
#   wallpaper.sh set <arquivo> [tela]      sem tela: todas
#   wallpaper.sh random [tela]
#   wallpaper.sh restore                   repõe a imagem de cada tela (roda no login)
set -euo pipefail

# Pasta de imagens do sistema (~/Imagens em pt-BR, ~/Pictures em inglês).
WALL_DIR=${RICE_WALL_DIR:-$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/wallpaper}
STATE_DIR="$HOME/.cache/wallpaper"      # um arquivo por tela, com o caminho da imagem
LEGACY="$HOME/.cache/current_wallpaper" # estado antigo, de antes de haver uma imagem por tela
# As cores do tema saem do wallpaper da tela principal: a de menor id (num
# notebook, a tela embutida). RICE_MAIN_MONITOR força outra.
MAIN=${RICE_MAIN_MONITOR:-$(hyprctl monitors -j | jq -r 'min_by(.id).name')}

screens() { hyprctl monitors -j | jq -r '.[].name'; }

# Aplica a imagem numa tela. Só a tela principal recolore o tema: a cor do
# sistema não pode mudar porque o monitor externo trocou de imagem.
apply_one() {
    local img=$1 screen=$2
    [[ -f "$img" ]] || { echo "wallpaper inexistente: $img" >&2; return 1; }
    # O DMS desenha o wallpaper por tela (precisa de "Papéis de Parede por
    # Monitor" ligado nele); awww cobre o caso de o shell estar fora do ar.
    if ! dms ipc call wallpaper setFor "$screen" "$img" >/dev/null 2>&1; then
        awww img --outputs "$screen" "$img" --transition-type grow --transition-fps 60 --transition-duration 1
    fi
    mkdir -p "$STATE_DIR"
    echo "$img" >"$STATE_DIR/$screen"
    [[ $screen == "$MAIN" ]] && recolor "$img"
    return 0
}

recolor() {
    # --prefer é obrigatório desde o matugen 4: sem terminal interativo e com
    # várias cores candidatas na imagem, ele aborta em vez de escolher.
    # "saturation" pega o acento mais vivo, que é o que um rice escuro quer.
    matugen image "$1" --mode dark --prefer saturation
    hyprctl reload >/dev/null
}

apply() {
    local img=$1 target=${2:-}
    if [[ -n $target ]]; then
        apply_one "$img" "$target"
    else
        for s in $(screens); do apply_one "$img" "$s"; done
    fi
}

pick_image() {
    find "$WALL_DIR" -type f \( -name '*.png' -o -name '*.jpg' \) -printf '%f\n' | sort |
        fuzzel --dmenu --prompt "${1:-wallpaper}> "
}

# Nome legível de cada tela no menu; a escolha volta como nome do conector.
pick_screen() {
    local opts="Todas as telas"
    for s in $(screens); do
        if [[ $s == "$MAIN" ]]; then opts+=$'\n'"Notebook ($s)"; else opts+=$'\n'"Monitor externo ($s)"; fi
    done
    local sel
    sel=$(printf '%s\n' "$opts" | fuzzel --dmenu --prompt 'tela> ') || return 1
    [[ -z $sel ]] && return 1
    [[ $sel == "Todas as telas" ]] && echo "" || echo "$sel" | sed -E 's/.*\((.*)\)/\1/'
}

case "${1:-restore}" in
    set) apply "$2" "${3:-}" ;;
    random) apply "$(find "$WALL_DIR" -type f \( -name '*.png' -o -name '*.jpg' \) | shuf -n1)" "${2:-}" ;;
    restore)
        for s in $(screens); do
            img=""
            [[ -f "$STATE_DIR/$s" ]] && img=$(cat "$STATE_DIR/$s")
            [[ -z $img && -f $LEGACY ]] && img=$(cat "$LEGACY")
            [[ -z $img ]] && img=$(find "$WALL_DIR" -maxdepth 1 -type f \( -name '*.png' -o -name '*.jpg' \) 2>/dev/null | sort | head -1)
            [[ -z $img ]] && continue # sem wallpaper nenhum: fica o fundo do DMS
            apply_one "$img" "$s" || true
        done
        ;;
    picker)
        target=""
        if (($(screens | wc -l) > 1)); then
            target=$(pick_screen) || exit 0
        fi
        label=${target:-todas}
        sel=$(pick_image "wallpaper ($label)") || exit 0
        [[ -n $sel ]] && apply "$WALL_DIR/$sel" "$target"
        ;;
    *) echo "uso: $0 {picker|set <arquivo> [tela]|random [tela]|restore}" >&2; exit 1 ;;
esac
