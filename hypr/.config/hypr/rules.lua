-- SEM layer rule de blur.
--
-- A tentativa anterior casava ^(quickshell.*|dms.*)$ e borrava duas camadas que
-- ocupam quase a tela inteira: `quickshell` é o wallpaper (1920x1080) e
-- `dms:dankisland` mede 1920x692. Blur numa superfície desse tamanho não vira
-- barra translúcida — vira cortina sobre o desktop.
--
-- O DMS já desenha o próprio fundo. Se algum dia valer blur aqui, a regra tem
-- que casar só a faixa da barra e depender de um limiar de alpha, nunca a
-- camada inteira. Confira o tamanho real antes: `hyprctl layers`.

hl.window_rule({
    name    = "browser-transparency",
    match   = { class = "^(brave-browser|firefox|zen)$" },
    opacity = "0.97 0.92",
})
hl.window_rule({
    name    = "terminal-transparency",
    match   = { class = "^(kitty|ghostty)$" },
    opacity = "0.93 0.88",
})
-- Cursor e Obsidian ficam opacos: texto sobre wallpaper cansa a vista em sessão longa.
hl.window_rule({
    name    = "editores-opacos",
    match   = { class = "^(Cursor|code|obsidian)$" },
    opacity = "1.0 1.0",
})
hl.window_rule({
    name   = "picker-float",
    match  = { class = "^(pavucontrol|blueman-manager|nm-connection-editor|org.kde.polkit-kde-authentication-agent-1)$" },
    float  = true,
    size   = "800 600",
    center = true,
})
hl.window_rule({
    name  = "pip",
    match = { title = "^(Picture-in-Picture)$" },
    float = true,
    pin   = true,
    size  = "480 270",
    move  = "100%-500 100%-300",
})

-- ── Cada coisa no seu lugar ────────────────────────────────────────────────
-- Janela que sempre nasce onde se espera economiza o tempo de procurá-la. Os
-- números seguem o que já está na muscle memory: 1 terminal, 2 editor, 3 web.
hl.window_rule({ name = "editor-ws2",      match = { class = "^(Cursor|code|jetbrains-.*)$" },                    workspace = "2" })
hl.window_rule({ name = "navegador-ws3",   match = { class = "^(brave-browser|firefox|zen|google-chrome)$" },     workspace = "3" })
hl.window_rule({ name = "obsidian-ws4",    match = { class = "^(obsidian)$" },                                    workspace = "4" })
hl.window_rule({ name = "comunicacao-ws5", match = { class = "^(discord|Slack|thunderbird)$" },                    workspace = "5" })

-- Diálogo de arquivo sempre flutuante e centralizado: em layout lado-a-lado ele
-- reparticiona a tela inteira para viver dois segundos.
hl.window_rule({
    name   = "dialogos",
    match  = { title = "^(Open File|Save File|Abrir|Salvar como|Selecionar pasta).*$" },
    float  = true,
    size   = "900 600",
    center = true,
})
