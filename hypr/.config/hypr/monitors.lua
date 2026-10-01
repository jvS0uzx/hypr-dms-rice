-- Monitores. A regra coringa pega qualquer tela na resolução preferida e
-- posiciona automaticamente (a próxima entra à direita). Para fixar uma tela,
-- descomente e ajuste — nomes dos conectores em `hyprctl monitors`.
--
-- hl.monitor({ output = "eDP-1",    mode = "1920x1080@60", position = "0x0",        scale = 1 })
-- hl.monitor({ output = "HDMI-A-1", mode = "preferred",    position = "auto-right", scale = 1 })
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
