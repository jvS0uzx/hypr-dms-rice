# seeds

Cópias iniciais dos arquivos que o **matugen gera** a partir do wallpaper.

Não são pacotes do stow de propósito: se fossem, `~/.config/hypr/colors.conf` seria
um symlink para dentro deste repositório e cada troca de wallpaper deixaria o
`git status` sujo.

O `install.sh` copia estas sementes para `~/.config/` como arquivos reais, e daí em
diante o matugen sobrescreve os arquivos reais. Para mudar como uma cor é usada,
edite o template em `matugen/.config/matugen/templates/` — não a semente.
