export ZSH="$HOME/.oh-my-zsh"

# Vazio de propósito: o prompt é o starship, logo abaixo.
ZSH_THEME=""

plugins=(git zsh-autosuggestions zsh-syntax-highlighting docker docker-compose)

source $ZSH/oh-my-zsh.sh

export PATH="$HOME/.local/bin:$PATH"
export PATH="$PATH:$(go env GOPATH)/bin"
export EDITOR='nvim'

eval "$($HOME/.local/bin/mise activate zsh)"
eval "$(starship init zsh)"

# --- rice ---
alias wall='~/.config/hypr/scripts/wallpaper.sh'
alias wallr='~/.config/hypr/scripts/wallpaper.sh random'
alias dots='cd ~/dotfiles'
alias hypr-errors='hyprctl configerrors'

# --- substitutos modernos ---
alias ls='eza --icons --group-directories-first'
alias ll='eza -lah --icons --group-directories-first --git'
alias lt='eza --tree --level=2 --icons'
alias cat='bat --style=plain --paging=never'
alias f='yazi'
alias ff='~/.config/fastfetch/ff.sh'

# ── Navegação e histórico ──────────────────────────────────────────────────
# zoxide antes do alias de cd: ele reescreve `cd` e precisa ver o comando cru.
eval "$(zoxide init zsh --cmd cd)"
eval "$(direnv hook zsh)"

# fzf ANTES do atuin: os dois disputam o Ctrl+R, e quem carrega por último
# ganha. O atuin é que deve ficar com a busca de histórico — o fzf continua
# dono do Ctrl+T (arquivos) e do Alt+C (diretórios).
source /usr/share/fzf/key-bindings.zsh 2>/dev/null
source /usr/share/fzf/completion.zsh 2>/dev/null
eval "$(atuin init zsh --disable-up-arrow)"

# fzf lendo o .gitignore: em repositório grande, listar node_modules é ruído.
export FZF_DEFAULT_COMMAND='rg --files --hidden --glob "!.git"'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_DEFAULT_OPTS='--height 45% --layout=reverse --border=sharp --info=inline'

# ── Git e contêineres ──────────────────────────────────────────────────────
# O tema vem do matugen num arquivo à parte; o lazygit aceita vários configs
# separados por vírgula, e assim o config versionado nunca é sobrescrito.
export LG_CONFIG_FILE="$HOME/.config/lazygit/config.yml,$HOME/.config/lazygit/theme.yml"
alias lg='lazygit' 
alias ld='lazydocker'

# Docker nos servidores sem SSH na mão: `dk <contexto> ps` em vez de ssh + compose.
dk() {
    local ctx=$1; shift
    docker --context "$ctx" "$@"
}
# E a interface completa num nó: logs, restart, uso por contêiner.
ldr() { lazydocker --context "${1:?uso: ldr <contexto docker>}"; }

alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'

# ── VPS ────────────────────────────────────────────────────────────────────
# Seletor em vez de decorar apelido.
vps() {
    local alvo
    # Servidores remotos do hosts.txt do ricestat (apelido papel destino).
    alvo=$(awk '!/^[[:space:]]*#/ && NF >= 3 && $3 != "local" {print $1 "\t" $3}' ~/.config/ricestat/hosts.txt |
        fzf --prompt 'vps> ' --height 20% --with-nth 1 --delimiter '\t' | cut -f2)
    [[ -n "$alvo" ]] || return
    # zellij do lado de lá: conexão que cai não mata o comando em produção.
    ssh -t "$alvo" 'command -v zellij >/dev/null && zellij attach -c ricestat || $SHELL -l'
}

# Fastfetch na abertura do shell interativo. Só em terminal de verdade: em
# sessão SSH, dentro do Claude Code ou num pipe, ele só atrapalha.
if [[ -o interactive && -z "$SSH_CONNECTION" && -z "$CLAUDECODE" && -t 1 ]]; then
    ~/.config/fastfetch/ff.sh
fi
