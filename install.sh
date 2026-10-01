#!/usr/bin/env bash
# Instala o rice. Idempotente: pode rodar de novo sem quebrar nada.
set -euo pipefail

DOTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKGS=(
    hyprland hyprlock hypridle awww xdg-desktop-portal-hyprland
    quickshell dms-shell matugen
    kitty fuzzel cliphist wl-clipboard grim slurp
    starship fastfetch eza bat yazi cava btop
    fzf zoxide atuin lazygit lazydocker git-delta zellij direnv
    satty wl-clip-persist hyprpicker tealdeer duf procs
    brightnessctl playerctl pavucontrol network-manager-applet
    polkit-kde-agent qt6ct kvantum papirus-icon-theme
    ttf-jetbrains-mono-nerd inter-font noto-fonts noto-fonts-emoji
    thunar tumbler gvfs
    stow go
)

echo "==> pacotes"
sudo pacman -S --needed --noconfirm "${PKGS[@]}"

echo "==> backup das configs que o stow vai assumir"
BACKUP="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
for f in "$HOME/.zshrc" "$HOME/.config/kitty" "$HOME/.config/starship.toml" \
         "$HOME/.config/hypr" "$HOME/.config/matugen" "$HOME/.config/fontconfig"; do
    [[ -e "$f" && ! -L "$f" ]] && { mv "$f" "$BACKUP/"; echo "    movido: $f"; }
done
echo "    backup em $BACKUP"

# --no-folding: cria diretórios reais com symlink por arquivo, em vez de linkar a
# pasta inteira. É o que permite o matugen gravar colors.conf sem escrever no repo.
echo "==> stow"
cd "$DOTS"
for pkg in hypr matugen kitty zsh fontconfig fastfetch git lazygit zellij; do
    stow --no-folding -v -t "$HOME" "$pkg"
done

echo "==> sementes de cor (arquivos reais, sobrescritos pelo matugen depois)"
mkdir -p "$HOME/.config"/{hypr,kitty,gtk-3.0,gtk-4.0,fuzzel}
cp -n "$DOTS/seeds/hypr-colors.lua"      "$HOME/.config/hypr/colors.lua"
cp -n "$DOTS/seeds/hyprlock-colors.conf" "$HOME/.config/hypr/hyprlock-colors.conf"
cp -n "$DOTS/seeds/kitty-colors.conf"    "$HOME/.config/kitty/colors.conf"
cp -n "$DOTS/seeds/starship.toml"        "$HOME/.config/starship.toml"

mkdir -p "$HOME/.config/ricestat"
cp -n "$DOTS/seeds/repos.txt" "$HOME/.config/ricestat/repos.txt"
cp -n "$DOTS/seeds/hosts.txt" "$HOME/.config/ricestat/hosts.txt"
cp -n "$DOTS/seeds/services.txt" "$HOME/.config/ricestat/services.txt"
cp -n "$DOTS/seeds/code-roots.txt" "$HOME/.config/ricestat/code-roots.txt"
mkdir -p "$HOME/.cache/ricestat/ssh" && chmod 700 "$HOME/.cache/ricestat/ssh"

echo "==> contextos de docker para os servidores de ~/.config/ricestat/hosts.txt"
# Um contexto por servidor remoto ligado no hosts.txt (apelido papel destino).
# Sem servidor configurado, não cria nada.
awk '!/^[[:space:]]*#/ && NF >= 3 && $3 != "local" {print $1, $3}' "$HOME/.config/ricestat/hosts.txt" |
while read -r alias dest; do
    docker context inspect "$alias" >/dev/null 2>&1 && continue
    docker context create "$alias" --docker "host=ssh://$dest" --description "servidor $alias" >/dev/null \
        && echo "    contexto $alias"
done

echo "==> histórico do shell para o atuin"
atuin import auto >/dev/null 2>&1 || true

echo "==> ricestat (coletor dos widgets)"
mkdir -p "$HOME/.local/bin"
(cd "$DOTS/ricestat" && go build -o "$HOME/.local/bin/ricestat" ./cmd/ricestat)
mkdir -p "$HOME/.config/systemd/user"
# cópia, não symlink: o systemd trata unit symlinkada como alias de habilitação
# e devolve "Unit does not exist" no enable.
cp -f "$DOTS/ricestat/ricestat.service" "$HOME/.config/systemd/user/ricestat.service"
systemctl --user daemon-reload
systemctl --user enable --now ricestat.service || echo "    (o serviço sobe junto com a sessão gráfica)"

echo "==> plugins do DankMaterialShell"
mkdir -p "$HOME/.config/DankMaterialShell/plugins"
for plug in "$DOTS"/dms-plugins/*/; do
    name="$(basename "$plug")"
    ln -sfn "${plug%/}" "$HOME/.config/DankMaterialShell/plugins/$name"
    echo "    symlink: $name"
done
echo "    habilite em Settings > Plugins > Scan for Plugins"

echo "==> primeira geração de cores a partir do wallpaper"
# ./install.sh <imagem> usa essa imagem; sem argumento, a primeira da pasta de
# wallpapers. Sem nenhuma, ficam as cores de seeds/ até o primeiro Super+Shift+W.
walls="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/wallpaper"
mkdir -p "$walls"
# Pasta vazia ganha o wallpaper do repositório (gerado aqui, livre de direitos).
if [[ -z "$(find "$walls" -maxdepth 1 -type f \( -name '*.png' -o -name '*.jpg' \) 2>/dev/null | head -1)" ]]; then
    cp -n "$DOTS"/wallpapers/*.png "$walls/"
fi
WALL="${1:-$(find "$walls" -maxdepth 1 -type f \( -name '*.png' -o -name '*.jpg' \) 2>/dev/null | sort | head -1)}"
if [[ -n "$WALL" && -f "$WALL" ]]; then
    matugen image "$WALL" --mode dark --prefer saturation
    mkdir -p "$HOME/.cache/wallpaper"
    echo "$WALL" > "$HOME/.cache/current_wallpaper"
else
    echo "    nenhum wallpaper em $walls — coloque imagens lá e use Super+Shift+W"
fi

echo
echo "Pronto. Saia da sessão, escolha 'Hyprland' no SDDM e entre."
echo "O Plasma continua instalado — se algo der errado, ele ainda está no seletor."
