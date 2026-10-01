#!/usr/bin/env bash
set -euo pipefail
DEST="$HOME/Imagens/Capturas de tela/$(date +%Y-%m-%d_%H-%M-%S).png"

# anotar: abre o satty para desenhar seta e destaque antes de salvar. Para
# abrir issue ou comentar PR, a seta vale mais que a imagem crua.
if [[ "${1:-}" == "anotar" ]]; then
    grim -g "$(slurp -d)" - | satty --filename - \
        --output-filename "$DEST" \
        --early-exit --copy-command wl-copy
    exit 0
fi

case "${1:-region}" in
    region) grim -g "$(slurp -d)" - ;;
    full)   grim - ;;
    *) echo "uso: $0 {region|full|anotar}" >&2; exit 1 ;;
esac | tee "$DEST" | wl-copy

notify-send "Screenshot" "$(basename "$DEST")" -i "$DEST"
