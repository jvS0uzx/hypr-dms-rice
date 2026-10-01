-- Atalhos espelhados do KDE desta máquina (lidos de ~/.config/kglobalshortcutsrc).
-- Exceção pedida: fechar janela é Super+X, além do Alt+F4 do KDE.
local mod = "SUPER"
local scripts = "~/.config/hypr/scripts/"
local exec = hl.dsp.exec_cmd

local function bind(keys, action, opts) return hl.bind(keys, action, opts) end

-- ── Janelas ────────────────────────────────────────────────────────────────
-- Alt+Tab precisa do bring_to_top junto: cycle_next só muda o foco, e
-- flutuante fica sempre acima de lado-a-lado — sem levantar, a janela focada
-- continua escondida.
for _, m in ipairs({ "ALT", mod }) do
    bind(m .. " + Tab", function()
        hl.dispatch(hl.dsp.window.cycle_next())
        hl.dispatch(hl.dsp.window.bring_to_top())
    end)
    bind(m .. " + SHIFT + Tab", function()
        hl.dispatch(hl.dsp.window.cycle_next({ next = false }))
        hl.dispatch(hl.dsp.window.bring_to_top())
    end)
end

bind("ALT + F4", hl.dsp.window.close())                 -- KDE: Window Close
bind(mod .. " + X", hl.dsp.window.close())              -- pedido
bind(mod .. " + CTRL + Escape", hl.dsp.window.kill())   -- KDE: Kill Window

bind(mod .. " + Page_Up", hl.dsp.window.fullscreen({ mode = "maximized" })) -- KDE: Window Maximize
bind(mod .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
bind(mod .. " + SHIFT + F", hl.dsp.window.float({ action = "toggle" }))
bind(mod .. " + P", hl.dsp.window.pseudo())
bind(mod .. " + J", hl.dsp.layout("togglesplit"))

-- Minimizar não existe no Hyprland; o equivalente honesto é estacionar a janela
-- num workspace especial e trazer de volta.
bind(mod .. " + Page_Down", hl.dsp.window.move({ workspace = "special:minimizadas", follow = false }))
bind(mod .. " + Backspace", hl.dsp.workspace.toggle_special("minimizadas"))

-- Foco entre janelas — KDE: Meta+Alt+setas
-- Mover a janela — KDE: Meta+setas (lá é encaixe em metade da tela)
for _, d in ipairs({ "left", "right", "up", "down" }) do
    bind(mod .. " + ALT + " .. d, hl.dsp.focus({ direction = d }))
    bind(mod .. " + " .. d, hl.dsp.window.move({ direction = d }))
end

-- Entre monitores — KDE: Meta+Shift+setas
bind(mod .. " + SHIFT + right", hl.dsp.window.move({ monitor = "r" }))
bind(mod .. " + SHIFT + left",  hl.dsp.window.move({ monitor = "l" }))

bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- ── Áreas de trabalho ──────────────────────────────────────────────────────
-- KDE: Meta+Ctrl+setas troca de desktop, Meta+Ctrl+Shift+setas leva a janela.
for d, rel in pairs({ left = "e-1", up = "e-1", right = "e+1", down = "e+1" }) do
    bind(mod .. " + CTRL + " .. d, hl.dsp.focus({ workspace = rel }))
    bind(mod .. " + CTRL + SHIFT + " .. d, hl.dsp.window.move({ workspace = rel }))
end

-- KDE: Meta+F1..F4
for i = 1, 4 do
    bind(mod .. " + F" .. i, hl.dsp.focus({ workspace = i }))
end

for i = 1, 10 do
    local key = i % 10 -- 10 cai na tecla 0
    bind(mod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end
bind(mod .. " + S", hl.dsp.workspace.toggle_special("magic"))
bind(mod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))
bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
bind(mod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- ── Visão geral e lançadores ───────────────────────────────────────────────
bind(mod .. " + W", exec("dms ipc call hypr toggleOverview"))          -- KDE: Overview
bind(mod .. " + G", exec("dms ipc call hypr toggleOverview"))          -- KDE: Grid View
bind(mod .. " + D", exec(scripts .. "show-desktop.sh"))                -- KDE: Show Desktop
bind(mod .. " + grave", exec(scripts .. "widgets-peek.sh"))            -- painel de monitoramento por cima das janelas
bind(mod .. " + SHIFT + grave", exec(scripts .. "widgets-tela.sh"))    -- widgets: notebook ↔ monitor externo
bind(mod .. " + R", exec("dms ipc call spotlight toggle"))
bind("ALT + space", exec("dms ipc call spotlight toggle"))             -- KDE: KRunner
bind("ALT + F2", exec("dms ipc call spotlight toggle"))
bind(mod .. " + V", exec("dms ipc call clipboard toggle"))             -- KDE: Klipper
bind(mod .. " + slash", exec("dms ipc call keybinds toggle"))          -- folha de atalhos

-- ── Apps ───────────────────────────────────────────────────────────────────
bind(mod .. " + T", exec(apps.terminal))
bind(mod .. " + Return", exec(apps.terminal))
bind(mod .. " + N", exec(apps.browser))
bind(mod .. " + E", exec(apps.filemgr))
bind(mod .. " + SHIFT + W", exec(scripts .. "wallpaper.sh picker"))

-- ── Sistema ────────────────────────────────────────────────────────────────
bind(mod .. " + L", exec("hyprlock"))
bind("CTRL + ALT + Delete", exec("dms ipc call powermenu toggle"))     -- KDE: sair
bind(mod .. " + SHIFT + Escape", hl.dsp.exit())                        -- sai sem depender do DMS (tela preta, shell travado)
bind(mod .. " + Y", exec("dms ipc call notifications toggle"))
bind("Print", exec(scripts .. "screenshot.sh region"))
bind("CTRL + Print", exec(scripts .. "screenshot.sh anotar"))          -- captura + anotação
bind(mod .. " + SHIFT + C", exec("hyprpicker -a"))                     -- cor sob o cursor
bind("SHIFT + Print", exec(scripts .. "screenshot.sh full"))

-- ── Áudio / mídia / brilho ─────────────────────────────────────────────────
-- locked: funciona com a tela bloqueada; repeating: segurar a tecla repete.
local hold = { locked = true, repeating = true }
bind("XF86AudioRaiseVolume",  exec("wpctl set-volume -l 1.4 @DEFAULT_AUDIO_SINK@ 5%+"), hold)
bind("XF86AudioLowerVolume",  exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), hold)
bind("XF86AudioMute",         exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
bind("XF86AudioMicMute",      exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
bind("XF86AudioPlay",         exec("playerctl play-pause"), { locked = true })
bind("XF86AudioNext",         exec("playerctl next"), { locked = true })
bind("XF86AudioPrev",         exec("playerctl previous"), { locked = true })
bind("XF86MonBrightnessUp",   exec("brightnessctl set 5%+"), hold)
bind("XF86MonBrightnessDown", exec("brightnessctl set 5%-"), hold)
