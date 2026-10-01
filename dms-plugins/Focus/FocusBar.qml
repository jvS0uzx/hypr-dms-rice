// Pílula da barra e popout do tempo por projeto.
//
// Mesma linguagem do cartão da área de trabalho: a distribuição é uma barra
// única segmentada — proporção se lê como área, sem comparar seis barrinhas
// soltas — e a legenda embaixo carrega nome, fatia e tempo na ordem dos
// segmentos. O popout acrescenta a semana, que o cartão não tem espaço para
// mostrar.
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

PluginComponent {
    id: root

    readonly property string mono: "JetBrainsMono Nerd Font"

    property bool hasData: src.hasData
    property bool empty: src.todaySec <= 0
    property string period: (pluginData && pluginData.period) ? pluginData.period : "today"
    property bool showProject: (pluginData && pluginData.showProject !== undefined) ? pluginData.showProject : true
    property int maxRows: (pluginData && pluginData.maxRows) ? pluginData.maxRows : 6

    // Tinta por posição: o líder no acento do tema, os seguintes em tons do
    // próprio tema, e a cauda em neutro. Mudou o wallpaper, muda tudo junto.
    function sliceColor(i, key) {
        if (key === "") return Theme.withAlpha(Theme.surfaceText, 0.22)
        if (i === 0) return Theme.primary
        if (i === 1) return Theme.secondary
        if (i === 2) return Theme.tertiary
        return Theme.withAlpha(Theme.surfaceText, 0.45 - (i - 3) * 0.08)
    }

    // Leitor inline de propósito: arquivo QML irmão não resolve como tipo
    // dentro de um plugin do DMS — o componente não nasce e não há erro
    // visível. Duplicar o leitor por superfície é o preço.
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
        property var week: hasData && focus.week ? focus.week : []

        // Classe de janela que chega no lugar de projeto. Mesma tabela do
        // cartão; o que não estiver aqui aparece com o nome cru.
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
        // 3h12 ou 48min. Abaixo de um minuto diz "<1min" em vez de mentir
        // "0min".
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
        // Os primeiros N no próprio tom, o resto somado em "outros": fatia de
        // 2px não comunica nada e ainda rouba a fresta de quem tem massa.
        function slices(list, n) {
            var out = []
            var rest = 0
            for (var i = 0; i < list.length; i++) {
                if (i < n) out.push({ key: list[i].project, seconds: list[i].seconds })
                else rest += list[i].seconds
            }
            if (rest > 0) out.push({ key: "", seconds: rest })
            return out
        }
        // A resposta para "o dia está espalhado demais?" é uma frase só, e
        // ela muda de forma conforme a resposta — não é um número solto.
        function spreadLine(list, total) {
            if (!list.length || total <= 0) return ""
            var top = list[0]
            var p = pct(top.seconds, total)
            if (p >= 50 || list.length <= 2) return label(top.project) + " leva " + p + "% do dia"
            return "nenhum passa de " + p + "%, o dia se dividiu em " + list.length
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

    // O coletor grava por tmp+rename, o que troca o inode e derruba o inotify
    // de vez em quando. O tique é rede de segurança, não o caminho normal.
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: snapFile.reload()
    }

    component SectionLabel: StyledText {
        font.pixelSize: 11
        font.weight: Font.DemiBold
        font.letterSpacing: 1.4
        color: Theme.surfaceTextMedium
    }

    // Barra segmentada + legenda de um período. Componente inline não
    // enxerga ids do documento: fatias e total entram prontos, e a cor vem
    // por função do root, que é alcançável pelo id.
    // Barra segmentada + legenda de um período, usada para o dia e a semana.
    component Distribution: Column {
        id: dist

        property var items: []
        property int total: 0
        // Componente inline não enxerga ids do documento: o root (cores) e o
        // leitor (rótulos, durações) entram por propriedade.
        property var owner: null
        property var reader: null

        spacing: 8

        Row {
            id: strip
            width: dist.width
            height: 10
            spacing: 2

            Repeater {
                model: dist.items

                Rectangle {
                    height: strip.height
                    radius: 3
                    width: Math.max(3, (strip.width - strip.spacing * (dist.items.length - 1)) * modelData.seconds / Math.max(1, dist.total))
                    color: dist.owner.sliceColor(index, modelData.key)
                }
            }
        }

        Column {
            width: dist.width
            spacing: 0

            Repeater {
                model: dist.items

                Item {
                    width: dist.width
                    height: 22

                    Rectangle {
                        id: sw
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8
                        height: 8
                        radius: 2
                        color: dist.owner.sliceColor(index, modelData.key)
                    }

                    StyledText {
                        id: nm
                        anchors.left: sw.right
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, parent.width - 150)
                        elide: Text.ElideMiddle
                        wrapMode: Text.NoWrap
                        text: dist.reader.label(modelData.key)
                        font.pixelSize: 13
                        font.weight: index === 0 ? Font.Medium : Font.Normal
                        color: dist.reader.isApp(modelData.key) || modelData.key === "" ? Theme.surfaceTextMedium : Theme.surfaceText
                    }

                    StyledText {
                        anchors.left: nm.right
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        visible: dist.reader.isApp(modelData.key)
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
                        text: dist.reader.pct(modelData.seconds, dist.total) + "%"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        color: Theme.surfaceTextSecondary
                    }

                    StyledText {
                        id: tm
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 52
                        horizontalAlignment: Text.AlignRight
                        text: dist.reader.dur(modelData.seconds)
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        color: index === 0 ? Theme.surfaceText : Theme.surfaceTextMedium
                    }
                }
            }
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            // Ponto no acento quando há janela em foco: é estado, e a pílula
            // é o lugar de estado.
            Item {
                width: 16
                height: 16
                anchors.verticalCenter: parent.verticalCenter

                DankIcon {
                    anchors.fill: parent
                    name: "center_focus_strong"
                    size: 16
                    color: root.hasData && !root.empty ? Theme.surfaceText : Theme.surfaceTextMedium
                }
                Rectangle {
                    visible: src.current !== ""
                    width: 5
                    height: 5
                    radius: 2.5
                    anchors.right: parent.right
                    anchors.top: parent.top
                    color: Theme.primary
                }
            }

            StyledText {
                visible: root.showProject && text !== ""
                text: {
                    if (!root.hasData) return ""
                    if (src.current !== "") return src.label(src.current)
                    if (src.today.length > 0) return src.label(src.today[0].project)
                    return ""
                }
                width: Math.min(implicitWidth, 96)
                elide: Text.ElideMiddle
                wrapMode: Text.NoWrap
                font.pixelSize: Theme.fontSizeSmall
                color: src.current !== "" && !src.isApp(src.current) ? Theme.surfaceText : Theme.surfaceTextMedium
                anchors.verticalCenter: parent.verticalCenter
            }

            // Mono porque o número muda sozinho e a barra não pode dançar junto.
            StyledText {
                text: root.hasData ? src.dur(root.period === "week" ? src.weekSec : src.todaySec) : "—"
                font.family: root.mono
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXXS

            DankIcon {
                name: "center_focus_strong"
                size: 16
                color: root.hasData && !root.empty ? Theme.surfaceText : Theme.surfaceTextMedium
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.hasData ? src.dur(root.period === "week" ? src.weekSec : src.todaySec) : "—"
                font.family: root.mono
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutWidth: 400
    popoutHeight: 560

    popoutContent: Component {
        PopoutComponent {
            // Cabeçalho próprio, o mesmo do cartão da área de trabalho.
            headerText: ""
            showCloseButton: false

            Item {
                width: parent.width
                implicitHeight: body.implicitHeight

                Column {
                    id: body
                    width: parent.width
                    spacing: 10

                    Item {
                        width: parent.width
                        height: 18

                        SectionLabel {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "FOCO"
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
                                width: Math.min(implicitWidth, 240)
                                elide: Text.ElideMiddle
                                wrapMode: Text.NoWrap
                                text: src.current !== ""
                                    ? "agora · " + src.label(src.current)
                                      + (src.window !== "" && src.window !== src.current ? " · " + src.window : "")
                                    : "sem janela em foco"
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

                    // Estado vazio diz o que acontece a seguir em vez de mostrar
                    // um zero e calar.
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
                            text: "o coletor lê a janela ativa a cada 15 segundos e resolve o projeto pelo diretório do processo. o primeiro nome aparece depois de um minuto de trabalho. nada sai da máquina."
                            font.pixelSize: 12
                            color: Theme.surfaceTextMedium
                        }
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

                    StyledText {
                        visible: root.hasData && !root.empty
                        width: parent.width
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                        text: src.spreadLine(src.today, src.todaySec)
                        font.pixelSize: 12
                        color: Theme.surfaceTextMedium
                    }

                    Distribution {
                        visible: root.hasData && !root.empty
                        width: parent.width
                        items: src.slices(src.today, root.maxRows)
                        total: src.todaySec
                        owner: root
                        reader: src
                    }

                    Rectangle {
                        visible: root.hasData && src.weekSec > src.todaySec
                        width: parent.width
                        height: 1
                        color: Theme.withAlpha(Theme.outline, 0.25)
                    }

                    // A semana só aparece quando já difere do dia — antes
                    // disso seria a mesma barra duas vezes.
                    Item {
                        visible: root.hasData && src.weekSec > src.todaySec
                        width: parent.width
                        height: 16

                        SectionLabel {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "ÚLTIMOS 7 DIAS"
                        }
                        StyledText {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: src.dur(src.weekSec)
                            font.family: root.mono
                            font.pixelSize: 12
                            color: Theme.surfaceTextMedium
                        }
                    }

                    Distribution {
                        visible: root.hasData && src.weekSec > src.todaySec
                        width: parent.width
                        items: src.slices(src.week, root.maxRows)
                        total: src.weekSec
                        owner: root
                        reader: src
                    }
                }
            }
        }
    }
}
