// Janela de cobrança de 5 horas do Claude Code, lida de relance.
//
// Três perguntas, nesta ordem de altura na tela: quanto tempo falta na
// janela, se o ritmo atual vai passar do maior consumo já visto, e como esta
// janela se compara com as anteriores. A versão anterior dava metade do
// cartão a um gráfico sem eixo; aqui o histórico é o último e o menor bloco.
//
// Em tokens, não em dólares: 97% do volume é leitura de cache, e o número
// que importa é o que mede a cota.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

DesktopPluginComponent {
    id: root

    minWidth: 320
    // Altura mínima = conteúdo fixo + um gráfico legível. Acima disso a
    // altura é do usuário, e o gráfico cresce junto.
    minHeight: Math.ceil(page.implicitHeight + pad * 2 + (hasData ? 10 + 22 + 16 + 48 : 0))

    readonly property color cWarn: "#d29922"
    readonly property color cCrit: "#f85149"
    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property int pad: 14

    property bool hasData: src.hasData
    property var q: hasData ? src.snap.quota : null
    property bool open: hasData && q.active === true
    property var agents: src.snap && src.snap.agents ? src.snap.agents : null
    property int activeSessions: agents ? (agents.active_count || 0) : 0

    property real peak: q ? Math.max(1, q.peak_block_tokens || 0) : 1
    property bool overRecord: open && (q.projected || 0) > peak
    property bool limitHit: q && q.limit_hits && q.limit_hits.length > 0

    property int level: limitHit ? 2 : (overRecord ? 1 : 0)
    readonly property color levelColor: level >= 2 ? cCrit : cWarn


    // Leitor inline de propósito: arquivo QML irmão não resolve como tipo
    // dentro de um plugin do DMS — o componente não nasce e não há erro
    // visível.
    QtObject {
        id: src

        property var snap: null
        property string loadError: snap && snap.errors ? (snap.errors.quota || "") : ""
        property bool hasData: snap !== null && snap.quota !== undefined && snap.quota !== null && loadError === ""

        function tokens(n) {
            if (n === undefined || n === null) return "—"
            if (n >= 1e9) return (n / 1e9).toFixed(1).replace(".", ",") + "B"
            if (n >= 1e6) return (n / 1e6).toFixed(n >= 1e8 ? 0 : 1).replace(".", ",") + "M"
            if (n >= 1e3) return Math.round(n / 1e3) + "k"
            return String(n)
        }
        function hm(minutes) {
            if (minutes === undefined || minutes < 0) return "—"
            var h = Math.floor(minutes / 60), m = minutes % 60
            return h > 0 ? h + "h" + (m < 10 ? "0" : "") + m : m + "min"
        }
        function clock(iso) {
            if (!iso) return ""
            var d = new Date(iso)
            return ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2)
        }
        function stamp(iso) {
            var d = new Date(iso)
            return d.getDate() + " " + d.getHours() + "h"
        }
        function since(sec) {
            if (sec === undefined || sec === null || sec < 0) return "—"
            if (sec < 120) return "respondendo"
            var m = Math.round(sec / 60)
            return "ocioso há " + (m < 60 ? m + "min" : hm(m))
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

    component Stat: Column {
        property string label
        property string value
        property color valueColor: Theme.surfaceText
        spacing: 2

        StyledText {
            text: parent.label
            font.pixelSize: 10
            font.weight: Font.DemiBold
            font.letterSpacing: 1
            color: Theme.surfaceTextSecondary
        }
        StyledText {
            text: parent.value
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 14
            color: parent.valueColor
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainer, 0.92)
        border.width: 1
        border.color: root.level > 0 ? Theme.withAlpha(root.levelColor, 0.45) : Theme.withAlpha(Theme.outline, 0.22)

        Rectangle {
            visible: root.level > 0
            x: 0
            y: Theme.cornerRadius
            width: 3
            height: parent.height - Theme.cornerRadius * 2
            radius: 1.5
            color: root.levelColor
        }

        Column {
            id: page
            x: root.pad
            y: root.pad
            width: root.width - root.pad * 2
            spacing: 10

            Item {
                width: parent.width
                height: 18

                // Logo da IA medida. Hoje só o Claude tem dado de uso legível
                // nesta máquina; os ícones de outras ferramentas estão em icons/.
                Image {
                    id: aiLogo
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    sourceSize: Qt.size(32, 32)
                    source: Qt.resolvedUrl("icons/claude.svg")
                }

                StyledText {
                    anchors.left: aiLogo.right
                    anchors.leftMargin: 7
                    anchors.verticalCenter: parent.verticalCenter
                    text: "CLAUDE · COTA"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.4
                    color: Theme.surfaceTextMedium
                }

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
                        color: root.q && root.q.idle_sec < 120 ? Theme.primary : Theme.withAlpha(Theme.surfaceText, 0.3)
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.q ? src.since(root.q.idle_sec)
                            + (root.activeSessions > 0 ? " · " + root.activeSessions + (root.activeSessions === 1 ? " sessão" : " sessões") : "") : ""
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

            StyledText {
                visible: root.hasData && !root.open
                width: parent.width
                wrapMode: Text.WordWrap
                text: "nenhuma janela aberta — a próxima começa na primeira mensagem."
                font.pixelSize: 13
                color: Theme.surfaceText
            }

            // Tempo restante é o número alto: é ele que decide se vale
            // começar uma tarefa grande agora ou esperar a virada.
            Item {
                visible: root.open
                width: parent.width
                height: 36

                StyledText {
                    id: hoursLeft
                    anchors.left: parent.left
                    anchors.baseline: parent.bottom
                    anchors.baselineOffset: -6
                    text: root.q ? src.hm(root.q.minutes_left) : ""
                    font.family: root.mono
                    font.pixelSize: 30
                    font.weight: Font.DemiBold
                    color: Theme.surfaceText
                }
                StyledText {
                    anchors.left: hoursLeft.right
                    anchors.leftMargin: 6
                    anchors.baseline: hoursLeft.baseline
                    text: "restantes"
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
                        text: "JANELA"
                        font.pixelSize: 10
                        font.letterSpacing: 1
                        color: Theme.surfaceTextSecondary
                    }
                    StyledText {
                        anchors.right: parent.right
                        text: root.q ? src.clock(root.q.block_start) + "–" + src.clock(root.q.block_end) : ""
                        font.family: root.mono
                        font.pixelSize: 13
                        color: Theme.surfaceText
                    }
                }
            }

            // Régua da janela: uma risca por hora, preenchida até agora.
            Item {
                visible: root.open
                width: parent.width
                height: 8

                Rectangle {
                    id: rail
                    anchors.fill: parent
                    radius: 4
                    color: Theme.withAlpha(Theme.surfaceText, 0.10)

                    Rectangle {
                        width: root.q ? rail.width * Math.min(1, root.q.minutes_elapsed / Math.max(1, root.q.block_minutes)) : 0
                        height: parent.height
                        radius: parent.radius
                        color: Theme.primary
                    }
                }
                Repeater {
                    model: root.q ? Math.max(0, Math.floor(root.q.block_minutes / 60) - 1) : 0
                    Rectangle {
                        x: Math.round(rail.width * (index + 1) * 60 / Math.max(1, root.q.block_minutes))
                        width: 1
                        height: rail.height
                        color: Theme.withAlpha(Theme.surfaceContainer, 0.9)
                    }
                }
            }

            // Tokens contra o recorde próprio, com a projeção como risca. É a
            // pergunta "essa janela vai ser a mais pesada?" em uma barra.
            Column {
                visible: root.open
                width: parent.width
                spacing: 6

                Item {
                    width: parent.width
                    height: 16

                    StyledText {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "TOKENS"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1
                        color: Theme.surfaceTextSecondary
                    }
                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        StyledText {
                            text: root.q ? src.tokens(root.q.block_tokens) : ""
                            font.family: root.mono
                            font.pixelSize: 13
                            color: Theme.surfaceText
                        }
                        StyledText {
                            text: "/ recorde " + src.tokens(root.peak)
                            font.family: root.mono
                            font.pixelSize: 12
                            color: Theme.surfaceTextSecondary
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 12

                    Rectangle {
                        id: tokRail
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 6
                        radius: 3
                        color: Theme.withAlpha(Theme.surfaceText, 0.10)

                        Rectangle {
                            width: root.q ? Math.max(2, tokRail.width * Math.min(1, root.q.block_tokens / root.peak)) : 0
                            height: parent.height
                            radius: parent.radius
                            color: root.overRecord ? root.cWarn : Theme.withAlpha(Theme.surfaceText, 0.6)
                        }
                    }
                    Rectangle {
                        x: root.q ? Math.min(tokRail.width - 2, Math.round(tokRail.width * Math.min(1, (root.q.projected || 0) / root.peak))) : 0
                        width: 2
                        height: parent.height
                        radius: 1
                        color: root.overRecord ? root.cWarn : Theme.surfaceText
                    }
                }

                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    text: root.q
                        ? (root.overRecord
                            ? "no ritmo atual, fecha em " + src.tokens(root.q.projected) + " — acima do recorde"
                            : "no ritmo atual, fecha em " + src.tokens(root.q.projected) + " às " + src.clock(root.q.block_end))
                        : ""
                    font.pixelSize: 11
                    color: root.overRecord ? root.cWarn : Theme.surfaceTextMedium
                }
            }

            Grid {
                visible: root.open
                width: parent.width
                columns: 4
                columnSpacing: 0

                Stat {
                    width: parent.width / 4
                    label: "RITMO"
                    value: root.q ? src.tokens(root.q.burn_per_min) + "/min" : ""
                }
                Stat {
                    width: parent.width / 4
                    label: "PEDIDOS"
                    value: root.q ? String(root.q.block_requests) : ""
                }
                Stat {
                    width: parent.width / 4
                    label: "CACHE"
                    value: root.q && root.q.block_tokens > 0 ? Math.round(root.q.block_cache_read / root.q.block_tokens * 100) + "%" : "—"
                }
                Stat {
                    width: parent.width / 4
                    label: "7 DIAS"
                    value: root.q ? src.tokens(root.q.week_tokens) : ""
                }
            }

        }

        // Histórico ocupa o que sobra do cartão: esticar o widget dá mais
        // gráfico, não mais vazio. Clique alterna entre janelas de 5 horas e
        // o retroativo hora a hora das últimas 48 horas.
        Item {
            id: hist
            visible: root.hasData
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: page.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: root.pad
            anchors.rightMargin: root.pad
            anchors.topMargin: 10
            anchors.bottomMargin: root.pad

            property bool hourly: false
            property int hover: -1
            property var blocks: root.q && root.q.recent ? root.q.recent : []
            property var hours: root.q && root.q.hourly ? root.q.hourly : []
            property var series: hourly ? hours : blocks
            property real chartTop: 22
            property real axis: 16
            property real chartH: Math.max(20, height - chartTop - axis)
            property real colW: series.length > 0 ? width / series.length : width
            property real peakH: {
                if (!hourly) return root.peak
                var m = 1
                for (var i = 0; i < hours.length; i++) m = Math.max(m, hours[i].tokens)
                return m
            }

            Item {
                width: parent.width
                height: 16

                Row {
                    spacing: 12
                    anchors.verticalCenter: parent.verticalCenter

                    Repeater {
                        model: [{ k: false, t: "JANELAS" }, { k: true, t: "48 HORAS" }]
                        StyledText {
                            text: modelData.t
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1
                            color: hist.hourly === modelData.k ? Theme.primary : Theme.surfaceTextSecondary

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: hist.hourly = modelData.k
                            }
                        }
                    }
                }

                StyledText {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        if (hist.hover < 0 || hist.hover >= hist.series.length)
                            return hist.hourly ? "pico " + src.tokens(hist.peakH) + "/h" : "recorde " + src.tokens(root.peak)
                        var it = hist.series[hist.hover]
                        var d = new Date(it.start)
                        var when = d.getDate() + "/" + (d.getMonth() + 1) + " " + ("0" + d.getHours()).slice(-2) + "h"
                        return when + " · " + src.tokens(it.tokens) + (hist.hourly ? " · " + it.requests + " pedidos" : "")
                    }
                    font.family: root.mono
                    font.pixelSize: 11
                    color: hist.hover >= 0 ? Theme.surfaceText : Theme.surfaceTextSecondary
                }
            }

            // Linha tracejada do teto da escala: recorde nas janelas, pico
            // horário no retroativo.
            Row {
                y: hist.chartTop
                width: parent.width
                spacing: 4
                Repeater {
                    model: Math.floor(hist.width / 8)
                    Rectangle {
                        width: 4
                        height: 1
                        color: Theme.withAlpha(Theme.surfaceText, 0.3)
                    }
                }
            }

            Repeater {
                model: hist.series

                Item {
                    x: index * hist.colW
                    y: hist.chartTop
                    width: hist.colW
                    height: hist.chartH + hist.axis

                    property bool current: root.open && (hist.hourly
                        ? index === hist.series.length - 1
                        : modelData.start === root.q.block_start)
                    // Hora que pertence à janela aberta ganha o acento fraco:
                    // mostra onde a janela começou dentro do retroativo.
                    property bool inBlock: hist.hourly && root.open
                        && new Date(modelData.start) >= new Date(root.q.block_start)

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: hist.chartH - height
                        width: Math.max(2, Math.min(hist.hourly ? hist.colW - 2 : 56, hist.colW * (hist.hourly ? 0.8 : 0.6)))
                        height: modelData.tokens > 0 ? Math.max(2, hist.chartH * Math.min(1, modelData.tokens / hist.peakH)) : 0
                        radius: hist.hourly ? 1 : 3
                        color: parent.current ? Theme.primary
                            : hist.hover === index ? Theme.withAlpha(Theme.surfaceText, 0.6)
                            : parent.inBlock ? Theme.withAlpha(Theme.primary, 0.55)
                            : Theme.withAlpha(Theme.surfaceText, 0.28)
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: hist.chartH + 3
                        visible: !hist.hourly || new Date(modelData.start).getHours() % 6 === 0
                        text: hist.hourly ? new Date(modelData.start).getHours() + "h" : src.stamp(modelData.start)
                        font.family: root.mono
                        font.pixelSize: 10
                        color: Theme.surfaceTextSecondary
                    }
                }
            }

            MouseArea {
                y: hist.chartTop
                width: parent.width
                height: hist.chartH + hist.axis
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: mouse => hist.hover = Math.floor(mouse.x / hist.colW)
                onExited: hist.hover = -1
                onClicked: hist.hourly = !hist.hourly
            }
        }
    }
}
