// O dia de relance: quanto rendeu, onde foi parar, e o que está aberto agora.
//
// A distribuição virou uma barra única segmentada — a proporção entre
// projetos se lê como área, sem comparar seis barrinhas soltas. A legenda
// embaixo carrega nome, fatia e tempo, na mesma ordem dos segmentos.
//
// Quando o coletor não acha diretório de projeto, ele cai para a classe da
// janela ("kitty", "com.danklinux.dms"). Esse nome cru é traduzido e marcado
// como aplicativo, para não se passar por projeto.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

DesktopPluginComponent {
    id: root

    minWidth: 300
    minHeight: 110

    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property int pad: 14

    property bool hasData: src.hasData
    property bool empty: src.todaySec <= 0
    property int maxRows: (pluginData && pluginData.maxRows) ? pluginData.maxRows : 5

    // Segmentos: os primeiros N no próprio tom, o resto somado em "outros".
    property var slices: {
        var list = src.today
        var out = []
        var rest = 0
        for (var i = 0; i < list.length; i++) {
            if (i < maxRows) out.push({ key: list[i].project, seconds: list[i].seconds })
            else rest += list[i].seconds
        }
        if (rest > 0) out.push({ key: "", seconds: rest })
        return out
    }

    // Tinta por posição: o líder no acento do tema, os seguintes em tons do
    // próprio tema, e a cauda em neutro. Mudou o wallpaper, muda tudo junto.
    function sliceColor(i, key) {
        if (key === "") return Theme.withAlpha(Theme.surfaceText, 0.22)
        if (i === 0) return Theme.primary
        if (i === 1) return Theme.secondary
        if (i === 2) return Theme.tertiary
        return Theme.withAlpha(Theme.surfaceText, 0.45 - (i - 3) * 0.08)
    }

    readonly property real fitHeight: page.implicitHeight + pad * 2
    onFitHeightChanged: fit()
    onWidthChanged: fit()
    function fit() {
        if (typeof requestResize === "function" && width > 0)
            requestResize(width, Math.max(minHeight, Math.ceil(fitHeight)))
    }

    // Leitor inline de propósito: arquivo QML irmão não resolve como tipo
    // dentro de um plugin do DMS — o componente não nasce e não há erro
    // visível.
    QtObject {
        id: src

        property var snap: null
        property var focus: snap && snap.focus ? snap.focus : null
        property string loadError: snap && snap.errors ? (snap.errors.focus || "") : ""
        property bool hasData: focus !== null && loadError === ""

        property string current: hasData ? (focus.current || "") : ""
        property string window: hasData ? (focus.window || "") : ""
        property int todaySec: hasData ? (focus.today_sec || 0) : 0
        property int weekSec: hasData ? (focus.week_sec || 0) : 0
        property var today: hasData && focus.today ? focus.today : []

        // Classe de janela que chega no lugar de projeto. Não é lista
        // exaustiva: o que não estiver aqui aparece com o nome cru.
        readonly property var apps: ({
            "kitty": "terminal", "foot": "terminal", "Alacritty": "terminal",
            "com.mitchellh.ghostty": "terminal", "org.wezfurlong.wezterm": "terminal",
            "firefox": "navegador", "zen": "navegador", "chromium": "navegador",
            "google-chrome": "navegador", "brave-browser": "navegador",
            "com.danklinux.dms": "shell do DMS", "obsidian": "Obsidian",
            "cursor": "Cursor", "code": "VS Code", "Code": "VS Code",
            "discord": "Discord", "vesktop": "Discord", "org.telegram.desktop": "Telegram",
            "spotify": "Spotify", "thunar": "arquivos", "org.gnome.Nautilus": "arquivos"
        })

        function isApp(key) {
            return apps[key] !== undefined
        }
        function label(key) {
            if (key === "") return "outros"
            return apps[key] !== undefined ? apps[key] : key
        }
        function dur(sec) {
            var s = Math.max(0, Math.floor(sec || 0))
            if (s < 60) return s > 0 ? "<1min" : "0min"
            var m = Math.floor(s / 60)
            if (m < 60) return m + "min"
            var h = Math.floor(m / 60)
            var r = m % 60
            return h + "h" + (r < 10 ? "0" + r : String(r))
        }
        function pct(sec, total) {
            return total > 0 ? Math.round(sec / total * 100) : 0
        }
    }

    FileView {
        id: snapFile
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ricestat.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                src.snap = JSON.parse(text())
            } catch (e) {
                src.snap = null
            }
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: snapFile.reload()
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainer, 0.92)
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.22)

        Column {
            id: page
            x: root.pad
            y: root.pad
            width: root.width - root.pad * 2
            spacing: 10

            Item {
                width: parent.width
                height: 18

                StyledText {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "FOCO"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.4
                    color: Theme.surfaceTextMedium
                }

                // O agora mora no cabeçalho: é estado, não histórico.
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    visible: root.hasData

                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        anchors.verticalCenter: parent.verticalCenter
                        color: src.current !== "" ? Theme.primary : Theme.withAlpha(Theme.surfaceText, 0.3)
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: src.current !== "" ? "agora · " + src.label(src.current) : "sem janela em foco"
                        font.pixelSize: 11
                        color: Theme.surfaceTextMedium
                    }
                }
            }

            StyledText {
                visible: !root.hasData
                width: parent.width
                wrapMode: Text.WordWrap
                text: src.loadError !== "" ? src.loadError : "Snapshot não encontrado.\nsystemctl --user status ricestat"
                font.pixelSize: 12
                color: Theme.surfaceTextMedium
            }

            Item {
                visible: root.hasData && !root.empty
                width: parent.width
                height: 36

                StyledText {
                    id: total
                    anchors.left: parent.left
                    anchors.baseline: parent.bottom
                    anchors.baselineOffset: -6
                    text: src.dur(src.todaySec)
                    font.family: root.mono
                    font.pixelSize: 30
                    font.weight: Font.DemiBold
                    color: Theme.surfaceText
                }

                StyledText {
                    anchors.left: total.right
                    anchors.leftMargin: 6
                    anchors.baseline: total.baseline
                    text: "hoje"
                    font.pixelSize: 12
                    color: Theme.surfaceTextMedium
                }

                Column {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    spacing: 1

                    StyledText {
                        anchors.right: parent.right
                        text: "SEMANA"
                        font.pixelSize: 10
                        font.letterSpacing: 1
                        color: Theme.surfaceTextSecondary
                    }
                    StyledText {
                        anchors.right: parent.right
                        text: src.dur(src.weekSec)
                        font.family: root.mono
                        font.pixelSize: 13
                        color: Theme.surfaceText
                    }
                }
            }

            // Barra segmentada. 2px de fresta entre segmentos para cada um
            // ter borda própria, e largura mínima de 3px para fatia pequena
            // não sumir.
            Row {
                id: strip
                visible: root.hasData && !root.empty
                width: parent.width
                height: 10
                spacing: 2

                Repeater {
                    model: root.slices

                    Rectangle {
                        height: strip.height
                        radius: 3
                        width: Math.max(3, (strip.width - strip.spacing * (root.slices.length - 1)) * modelData.seconds / Math.max(1, src.todaySec))
                        color: root.sliceColor(index, modelData.key)
                    }
                }
            }

            Column {
                visible: root.hasData && !root.empty
                width: parent.width
                spacing: 0

                Repeater {
                    model: root.slices

                    Item {
                        width: parent.width
                        height: 22

                        Rectangle {
                            id: sw
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8
                            height: 8
                            radius: 2
                            color: root.sliceColor(index, modelData.key)
                        }

                        StyledText {
                            id: nm
                            anchors.left: sw.right
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, parent.width - 150)
                            elide: Text.ElideMiddle
                            wrapMode: Text.NoWrap
                            text: src.label(modelData.key)
                            font.pixelSize: 13
                            font.weight: index === 0 ? Font.Medium : Font.Normal
                            color: src.isApp(modelData.key) || modelData.key === "" ? Theme.surfaceTextMedium : Theme.surfaceText
                        }

                        StyledText {
                            anchors.left: nm.right
                            anchors.leftMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            visible: src.isApp(modelData.key)
                            text: "app"
                            font.pixelSize: 10
                            color: Theme.surfaceTextSecondary
                        }

                        StyledText {
                            anchors.right: tm.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 36
                            horizontalAlignment: Text.AlignRight
                            text: src.pct(modelData.seconds, src.todaySec) + "%"
                            font.family: root.mono
                            font.pixelSize: 12
                            color: Theme.surfaceTextSecondary
                        }

                        StyledText {
                            id: tm
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 52
                            horizontalAlignment: Text.AlignRight
                            text: src.dur(modelData.seconds)
                            font.family: root.mono
                            font.pixelSize: 12
                            color: index === 0 ? Theme.surfaceText : Theme.surfaceTextMedium
                        }
                    }
                }
            }

            // Estado vazio diz o que acontece a seguir em vez de mostrar zero.
            Column {
                visible: root.hasData && root.empty
                width: parent.width
                spacing: 4

                StyledText {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "nada registrado ainda hoje"
                    font.pixelSize: 14
                    color: Theme.surfaceText
                }
                StyledText {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "o coletor lê a janela ativa a cada 15 segundos; o primeiro projeto entra depois de um minuto de trabalho."
                    font.pixelSize: 12
                    color: Theme.surfaceTextMedium
                }
            }
        }
    }
}
