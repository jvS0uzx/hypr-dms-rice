-- Hyprland — entrypoint em Lua. Módulos em arquivos separados para o stow não
-- virar um arquivo de 400 linhas.
--
-- Migrado do formato .conf em 01/10/2026: o Hyprland 0.57 remove o suporte a
-- ele. Com hyprland.lua presente, o .conf é ignorado.

-- Os módulos são procurados na pasta real do arquivo. Como o stow liga este
-- arquivo a partir do dotfiles, a pasta real é o repositório — e colors.lua,
-- gerado pelo matugen, mora em ~/.config/hypr, fora dele. Sem esta linha o
-- require("colors") falha no login.
package.path = os.getenv("HOME") .. "/.config/hypr/?.lua;" .. package.path

require("monitors")
local colors = require("colors") -- gerado pelo matugen a partir do wallpaper

-- Atalhos e regras leem estes nomes; mudar o terminal é trocar aqui.
apps = {
    terminal = "kitty",
    browser  = "brave",
    filemgr  = "thunar",
    launcher = "fuzzel",
}

require("rules")
require("keybinds")

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
-- Iris Xe: força o Mesa a não cair em software rendering no multi-monitor
hl.env("LIBVA_DRIVER_NAME", "iHD")
hl.env("WLR_RENDERER_ALLOW_SOFTWARE", "0")

hl.on("hyprland.start", function()
    hl.exec_cmd("dms run")
    -- Retrato da inicialização em ~/.local/state/hypr-startup (ver o script).
    hl.exec_cmd("~/.config/hypr/scripts/startup-snapshot.sh")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("/usr/lib/polkit-kde-authentication-agent-1")
    -- O Plasma iniciava o kwalletd por conta própria; o Hyprland não. Sem ele o
    -- `gh` perde o token (guardado no keyring) e passa a falar com o GitHub sem
    -- autenticação — repositório privado responde 404, não 403, então o erro não
    -- parece de credencial.
    hl.exec_cmd("/usr/bin/kwalletd6")
    hl.exec_cmd("wl-paste --watch cliphist store")
    -- Sem isto, fechar a janela de origem esvazia a área de transferência — é
    -- comportamento do Wayland, não bug, e pega todo mundo de surpresa.
    hl.exec_cmd("wl-clip-persist --clipboard regular")
    hl.exec_cmd("~/.config/hypr/scripts/wallpaper.sh restore")
end)

hl.config({
    input = {
        kb_layout    = "br",
        kb_model     = "abnt2",
        kb_options   = "terminate:ctrl_alt_bksp",
        follow_mouse = 1,
        sensitivity  = 0,
        touchpad = {
            natural_scroll       = true,
            disable_while_typing = true,
            tap_to_click         = true,
        },
    },

    general = {
        gaps_in          = 5,
        gaps_out         = 12,
        border_size      = 2,
        col = {
            active_border   = { colors = { colors.border, colors.border_alt }, angle = 45 },
            inactive_border = colors.inactive,
        },
        resize_on_border = true,
        layout           = "dwindle",
    },

    decoration = {
        rounding         = 10,
        active_opacity   = 1.0,
        inactive_opacity = 0.92,
        shadow = {
            enabled        = true,
            range          = 20,
            render_power   = 3,
            color          = colors.shadow,
            color_inactive = colors.shadow_inactive,
        },
        -- passes 3 + size 6 derruba o frametime no Iris Xe quando há vídeo em tela.
        blur = {
            enabled           = true,
            size              = 5,
            passes            = 2,
            new_optimizations = true,
            ignore_opacity    = true,
            noise             = 0.02,
            contrast          = 1.0,
            brightness        = 0.9,
            vibrancy          = 0.17,
        },
    },

    animations = { enabled = true },

    dwindle = { preserve_split = true },

    misc = {
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        force_default_wallpaper  = 0,
        vrr                      = 0,
    },
})

-- Curvas com nome do que elas fazem, não do que elas são.
hl.curve("saida",   { type = "bezier", points = { {0.16, 1.00}, {0.30, 1.00} } }) -- easeOutExpo: rápido e que não repica
hl.curve("repique", { type = "bezier", points = { {0.34, 1.56}, {0.64, 1.00} } }) -- easeOutBack: passa do ponto e volta
hl.curve("inercia", { type = "bezier", points = { {0.22, 1.00}, {0.36, 1.00} } }) -- desliza como se tivesse massa
hl.curve("seco",    { type = "bezier", points = { {0.30, 0.00}, {0.80, 0.15} } }) -- entrada dura, para o que some

-- Janela nasce com um repique curto e morre encolhendo depressa. Abrir é
-- evento, fechar é limpeza — não merecem a mesma duração.
hl.animation({ leaf = "windowsIn",   enabled = true, speed = 4.0, bezier = "repique", style = "popin 88%" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 2.6, bezier = "seco",    style = "popin 92%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3.4, bezier = "inercia", style = "slide" })

-- Borda acompanha o foco num tempo próprio: lenta demais parece atraso,
-- rápida demais pisca a cada troca de janela.
hl.animation({ leaf = "border",  enabled = true, speed = 7.0, bezier = "saida" })
hl.animation({ leaf = "fade",    enabled = true, speed = 2.8, bezier = "saida" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 2.0, bezier = "seco" })

-- Área de trabalho desliza na horizontal com inércia — é o movimento que dá
-- noção de que elas estão lado a lado, não empilhadas.
hl.animation({ leaf = "workspaces",    enabled = true, speed = 4.2, bezier = "inercia", style = "slide" })
hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 3.6, bezier = "inercia", style = "slide" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 3.0, bezier = "saida",   style = "slide" })

-- Camadas do shell (barra, popout, lançador) entram de onde estão ancoradas.
hl.animation({ leaf = "layers",    enabled = true, speed = 3.0, bezier = "repique", style = "slide" })
hl.animation({ leaf = "layersIn",  enabled = true, speed = 3.2, bezier = "repique", style = "slide" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 2.2, bezier = "seco",    style = "slide" })

hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 4.0, bezier = "repique", style = "slidevert" })

-- Borda com gradiente girando — o efeito mais chamativo do Hyprland e o mais
-- caro: `loop` mantém a GPU redesenhando a borda o tempo todo, sem parar, e
-- neste notebook isso é bateria contínua por enfeite. Fica documentado e
-- desligado; para ligar, descomente e aceite o custo.
-- hl.animation({ leaf = "borderangle", enabled = true, speed = 30, bezier = "linear", style = "loop" })

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
