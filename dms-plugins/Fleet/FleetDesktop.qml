// Frota em tabela: uma linha por máquina, três medidas em colunas alinhadas.
//
// A versão anterior tinha três medidores de 28px por linha com rótulo de uma
// letra — ilegíveis a um braço de distância. Coluna com cabeçalho único lê
// na vertical: o olho desce pela coluna "disco" e acha o node2 sem ler nada.
//
// Linguagem comum dos widgets de área de trabalho: cartão translúcido, rótulo
// em caixa alta, friso à esquerda que só acende quando há algo a fazer, e
// cor de estado só em quem passou do limiar. O resto é tinta neutra.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

DesktopPluginComponent {
    id: root

    minWidth: 360
    minHeight: 120

    readonly property color cOk: "#3fb950"
    readonly property color cWarn: "#d29922"
    readonly property color cCrit: "#f85149"
    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property int pad: 14

    property var hosts: src.hosts
    property bool hasData: src.hasData
    // Um limiar por medida: disco sobe devagar e em 60% já dá tempo de agir;
    // CPU em 60% não quer dizer nada. Em 29/09 o disco do node2 em 78% eram
    // 90 GB de cache de build morto.
    property int warnCpu: pluginData.warnCpu || 85
    property int warnMem: pluginData.warnMem || 85
    property int warnDisk: pluginData.warnDisk || 60
    property int warnStopped: pluginData.warnStopped || 0

    // 0 calmo, 1 atenção, 2 crítico — acende o friso do cartão.
    property int level: {
        if (!hasData) return 1
        var lv = 0
        for (var i = 0; i < hosts.hosts.length; i++) {
            var h = hosts.hosts[i]
            if (!h.up) return 2
            var m = src.memPct(h)
            if (h.load_pct >= 95 || m >= 95 || h.disk_pct >= 85) return 2
            if (h.load_pct >= warnCpu || m >= warnMem || h.disk_pct >= warnDisk) lv = 1
            if (warnStopped > 0 && h.containers_down >= warnStopped) lv = Math.max(lv, 1)
        }
        if (hosts.databases_down > 0) return 2
        return lv
    }
    readonly property color levelColor: level >= 2 ? cCrit : (level === 1 ? cWarn : "transparent")

    // Colunas calculadas da largura, não fixas: o cartão pode ser esticado e
    // as barras crescem junto em vez de sobrar espaço à direita.
    readonly property real innerW: width - pad * 2
    readonly property real hostW: 62
    readonly property real roleW: 52
    readonly property real ctrW: 34
    readonly property real cellW: Math.max(60, (innerW - 14 - hostW - roleW - ctrW) / 3)

    readonly property real fitHeight: page.implicitHeight + pad * 2
    onFitHeightChanged: fit()
    onWidthChanged: fit()
    function fit() {
        if (typeof requestResize === "function" && width > 0)
            requestResize(width, Math.max(minHeight, Math.ceil(fitHeight)))
    }

    // Leitor inline de propósito: arquivo QML irmão não resolve como tipo
    // dentro de um plugin do DMS — o componente não nasce, sem erro visível.
    QtObject {
        id: src
        property var snap: null
        property var hosts: snap && snap.hosts ? snap.hosts : null
        property string loadError: snap && snap.errors ? (snap.errors.hosts || "") : ""
        property bool hasData: hosts !== null && loadError === ""

        function memPct(h) {
            return h.mem_total_mb > 0 ? h.mem_used_mb / h.mem_total_mb * 100 : 0
        }
        function uptime(sec) {
            var s = sec || 0
            if (s >= 86400) return Math.floor(s / 86400) + "d"
            if (s >= 3600) return Math.floor(s / 3600) + "h"
            return Math.floor(s / 60) + "m"
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

    // O coletor grava por tmp+rename, o que troca o inode e às vezes derruba
    // o inotify. O tique é rede de segurança, não o caminho normal.
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: snapFile.reload()
    }

    // Célula de medida: barra contra o limiar + número. Componente inline não
    // enxerga ids do documento, então cor e limiar entram prontos.
    component Cell: Item {
        id: c

        property real value: 0
        property real warn: 75
        property color tint
        property color numColor

        implicitHeight: 16

        Rectangle {
            id: track
            anchors.left: parent.left
            anchors.right: num.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            height: 4
            radius: 2
            color: Theme.withAlpha(Theme.surfaceText, 0.10)

            Rectangle {
                width: Math.max(2, track.width * Math.min(1, c.value / 100))
                height: parent.height
                radius: parent.radius
                color: c.tint

                Behavior on width {
                    NumberAnimation {
                        duration: Theme.mediumDuration
                        easing.type: Theme.standardEasing
                    }
                }
            }

            Rectangle {
                x: Math.round(track.width * Math.min(1, c.warn / 100))
                y: -2
                width: 1
                height: 8
                color: Theme.withAlpha(Theme.surfaceText, 0.35)
            }
        }

        StyledText {
            id: num
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            horizontalAlignment: Text.AlignRight
            text: Math.round(c.value)
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            color: c.numColor
        }
    }

    component ColHead: StyledText {
        font.pixelSize: 10
        font.weight: Font.DemiBold
        font.letterSpacing: 1
        color: Theme.surfaceTextSecondary
    }

    function tintFor(v, w) {
        if (v >= 95) return cCrit
        if (v >= w) return cWarn
        return Theme.withAlpha(Theme.surfaceText, 0.42)
    }
    function numFor(v, w) {
        if (v >= 95) return cCrit
        if (v >= w) return cWarn
        return Theme.surfaceTextMedium
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
            width: root.innerW
            spacing: 8

            Item {
                width: parent.width
                height: 18

                StyledText {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "FROTA"
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
                        color: root.level >= 2 ? root.cCrit : (root.level === 1 ? root.cWarn : root.cOk)
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.hasData
                            ? root.hosts.up + "/" + root.hosts.hosts.length + " no ar · " + root.hosts.databases + " bancos"
                            : ""
                        font.pixelSize: 11
                        color: Theme.surfaceTextMedium
                    }
                }
            }

            Row {
                visible: root.hasData
                width: parent.width
                height: 12
                spacing: 0

                Item { width: 14 + root.hostW + root.roleW; height: 1 }
                ColHead { width: root.cellW; text: "CPU" }
                ColHead { width: root.cellW; text: "MEM" }
                ColHead { width: root.cellW; text: "DISCO" }
                ColHead { width: root.ctrW; text: "CTR"; horizontalAlignment: Text.AlignRight }
            }

            Column {
                visible: root.hasData
                width: parent.width
                spacing: 2

                Repeater {
                    model: root.hasData ? root.hosts.hosts : []

                    // Clique na máquina abre o lazydocker dela: do "node2 com
                    // CPU alta" ao contêiner culpado em um passo.
                    Item {
                        width: parent.width
                        height: 24

                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: -6
                            anchors.rightMargin: -6
                            radius: 6
                            color: Theme.withAlpha(Theme.surfaceText, hostHover.containsMouse ? 0.06 : 0)
                        }

                        MouseArea {
                            id: hostHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached(["kitty", "--title", "docker · " + modelData.alias, "-e",
                                "env", "DOCKER_CONTEXT=" + (modelData.alias === "local" ? "default" : modelData.alias), "lazydocker"])
                        }

                        Row {
                            width: parent.width
                            height: 24
                            spacing: 0

                            Item {
                                width: 14
                                height: parent.height

                                // Máquina no ar não ganha verde: ponto verde em
                                // cinco linhas vira papel de parede. Só a queda
                                // pinta.
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 7
                                    height: 7
                                    radius: 3.5
                                    color: modelData.up ? Theme.withAlpha(Theme.surfaceText, 0.30) : root.cCrit
                                }
                            }

                            StyledText {
                                width: root.hostW
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.alias
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                                font.pixelSize: 13
                                font.weight: modelData.up ? Font.Medium : Font.DemiBold
                                color: modelData.up ? Theme.surfaceText : root.cCrit
                            }

                            StyledText {
                                width: root.roleW
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.role
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                                font.pixelSize: 11
                                color: Theme.surfaceTextSecondary
                            }

                            Cell {
                                visible: modelData.up
                                width: root.cellW - 8
                                anchors.verticalCenter: parent.verticalCenter
                                value: modelData.load_pct
                                warn: root.warnCpu
                                tint: root.tintFor(value, root.warnCpu)
                                numColor: root.numFor(value, root.warnCpu)
                            }
                            Item { visible: modelData.up; width: 8; height: 1 }
                            Cell {
                                visible: modelData.up
                                width: root.cellW - 8
                                anchors.verticalCenter: parent.verticalCenter
                                value: src.memPct(modelData)
                                warn: root.warnMem
                                tint: root.tintFor(value, root.warnMem)
                                numColor: root.numFor(value, root.warnMem)
                            }
                            Item { visible: modelData.up; width: 8; height: 1 }
                            Cell {
                                visible: modelData.up
                                width: root.cellW - 8
                                anchors.verticalCenter: parent.verticalCenter
                                value: modelData.disk_pct
                                warn: root.warnDisk
                                tint: root.tintFor(value, root.warnDisk)
                                numColor: root.numFor(value, root.warnDisk)
                            }
                            Item { visible: modelData.up; width: 8; height: 1 }

                            StyledText {
                                visible: modelData.up
                                width: root.ctrW
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                text: modelData.containers_up
                                font.family: root.mono
                                font.pixelSize: 12
                                color: root.warnStopped > 0 && modelData.containers_down >= root.warnStopped
                                    ? root.cWarn : Theme.surfaceTextMedium
                            }

                            // Máquina fora: o motivo ocupa as colunas de medida,
                            // que não têm o que mostrar.
                            StyledText {
                                visible: !modelData.up
                                width: root.cellW * 3 + root.ctrW
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.error || "sem resposta"
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                                font.pixelSize: 12
                                color: root.cCrit
                            }
                        }
                    }
                }
            }

            Rectangle {
                visible: root.hasData
                width: parent.width
                height: 1
                color: Theme.withAlpha(Theme.outline, 0.25)
            }

            // Bancos como contagem: cinco máquinas com oito bancos viram
            // catorze linhas, e aí ninguém lê nenhuma. Só os que caíram ganham
            // nome — são os únicos que pedem ação.
            Item {
                visible: root.hasData
                width: parent.width
                height: 16

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    DankIcon {
                        name: "database"
                        size: 14
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.hasData && root.hosts.databases_down > 0 ? root.cCrit : Theme.surfaceTextSecondary
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            if (!root.hasData) return ""
                            if (root.hosts.databases_down === 0) return root.hosts.databases + " bancos respondendo"
                            var names = []
                            for (var i = 0; i < root.hosts.hosts.length; i++) {
                                var dbs = root.hosts.hosts[i].databases || []
                                for (var j = 0; j < dbs.length; j++)
                                    if (!dbs[j].up) names.push(dbs[j].name + "@" + root.hosts.hosts[i].alias)
                            }
                            return "fora: " + names.join(", ")
                        }
                        font.pixelSize: 12
                        color: root.hasData && root.hosts.databases_down > 0 ? root.cCrit : Theme.surfaceTextMedium
                    }
                }

                StyledText {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.hasData
                    text: {
                        if (!root.hasData) return ""
                        var down = 0
                        for (var i = 0; i < root.hosts.hosts.length; i++) down += root.hosts.hosts[i].containers_down || 0
                        return down + " contêineres parados"
                    }
                    font.pixelSize: 11
                    color: Theme.surfaceTextSecondary
                }
            }

            StyledText {
                visible: !root.hasData
                width: parent.width
                wrapMode: Text.WordWrap
                text: src.loadError !== "" ? src.loadError : "ricestat não está publicando o snapshot.\nsystemctl --user status ricestat"
                font.pixelSize: 12
                color: Theme.surfaceTextMedium
            }
        }
    }
}
