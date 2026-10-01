// Pílula da barra e popout da frota.
//
// Mesma linguagem dos widgets de área de trabalho: rótulo em caixa alta,
// ponto de estado com resumo, tabela com colunas CPU/MEM/DISCO/CTR e cor de
// estado só em quem passou do limiar da própria medida. O resto é tinta
// neutra — assim a cor é notícia, não decoração.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    readonly property color cOk: "#3fb950"
    readonly property color cWarn: "#d29922"
    readonly property color cCrit: "#f85149"
    readonly property string mono: "JetBrainsMono Nerd Font"

    property var hosts: src.hosts
    property bool hasData: src.hasData
    property int down: hasData ? src.hosts.down : 0
    property int dbDown: hasData ? src.hosts.databases_down : 0
    property bool alarm: down > 0 || dbDown > 0

    // Um limiar por medida, as mesmas chaves do widget de área de trabalho:
    // disco em 60% já pede atenção; CPU em 60% não quer dizer nada.
    property int warnCpu: (pluginData && pluginData.warnCpu) ? pluginData.warnCpu : 85
    property int warnMem: (pluginData && pluginData.warnMem) ? pluginData.warnMem : 85
    property int warnDisk: (pluginData && pluginData.warnDisk) ? pluginData.warnDisk : 60

    // 0 calmo, 1 atenção, 2 crítico — mesma régua do cartão.
    property int level: {
        if (!hasData) return 1
        if (alarm) return 2
        var lv = 0
        for (var i = 0; i < hosts.hosts.length; i++) {
            var h = hosts.hosts[i]
            var m = src.memPct(h)
            if (h.load_pct >= 95 || m >= 95 || h.disk_pct >= 85) return 2
            if (h.load_pct >= warnCpu || m >= warnMem || h.disk_pct >= warnDisk) lv = 1
        }
        return lv
    }
    readonly property color levelColor: level >= 2 ? cCrit : (level === 1 ? cWarn : cOk)

    // Pior medida em termos de "quanto do limiar já foi gasto": 78% de disco
    // com risca em 60 é mais grave que 80% de CPU com risca em 85.
    property var worst: src.worstMetric()

    // Leitor inline de propósito: arquivo QML irmão não resolve como tipo
    // dentro de um plugin do DMS — o componente não nasce e não há erro
    // visível. Duplicar o leitor por superfície é o preço.
    QtObject {
        id: src
        property var snap: null
        property var hosts: snap && snap.hosts ? snap.hosts : null
        property string loadError: snap && snap.errors ? (snap.errors.hosts || "") : ""
        property bool hasData: hosts !== null && loadError === ""

        function memPct(h) {
            return h.mem_total_mb > 0 ? h.mem_used_mb / h.mem_total_mb * 100 : 0
        }
        function hostRatio(h) {
            if (!h.up) return 2
            return Math.max(h.load_pct / root.warnCpu, memPct(h) / root.warnMem, h.disk_pct / root.warnDisk)
        }
        function worstMetric() {
            var best = { who: "", label: "", pct: -1, ratio: -1 }
            if (!hasData) return best
            for (var i = 0; i < hosts.hosts.length; i++) {
                var h = hosts.hosts[i]
                if (!h.up) return { who: h.alias, label: "fora", pct: 100, ratio: 99 }
                var ms = [
                    { label: "cpu", pct: h.load_pct, w: root.warnCpu },
                    { label: "mem", pct: memPct(h), w: root.warnMem },
                    { label: "disco", pct: h.disk_pct, w: root.warnDisk }
                ]
                for (var j = 0; j < ms.length; j++) {
                    var r = ms[j].pct / ms[j].w
                    if (r > best.ratio) best = { who: h.alias, label: ms[j].label, pct: ms[j].pct, ratio: r }
                }
            }
            return best
        }
        function bytes(n) {
            if (n >= 1073741824) return (n / 1073741824).toFixed(1) + "G"
            if (n >= 1048576) return Math.round(n / 1048576) + "M"
            if (n >= 1024) return Math.round(n / 1024) + "K"
            return n + "B"
        }
        function uptime(sec) {
            var s = sec || 0
            if (s >= 86400) return Math.floor(s / 86400) + "d"
            if (s >= 3600) return Math.floor(s / 3600) + "h"
            return Math.floor(s / 60) + "m"
        }
        function engineShort(e) {
            var s = String(e || "").split("/")
            return s[s.length - 1].split(":")[0]
        }
        // Banco no ar sem healthcheck não é problema: fica neutro. Só
        // healthcheck falhando e banco fora ganham cor.
        function dbColor(d) {
            if (!d.up) return root.cCrit
            if (d.health === "u") return root.cWarn
            return Theme.withAlpha(Theme.surfaceText, 0.30)
        }
        function dbState(d) {
            if (!d.up) return "fora"
            if (d.health === "u") return "falhando"
            if (d.health === "h") return "saudável"
            return ""
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
    function hostTint(h) {
        if (!h.up) return cCrit
        var r = src.hostRatio(h)
        if (r >= 1) return cWarn
        return Theme.withAlpha(Theme.surfaceText, 0.45)
    }

    // Célula de medida: barra contra a risca do limiar + número. Componente
    // inline não enxerga ids do documento — tudo entra por propriedade.
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

    component SectionLabel: StyledText {
        font.pixelSize: 11
        font.weight: Font.DemiBold
        font.letterSpacing: 1.4
        color: Theme.surfaceTextMedium
    }

    // Pílula: cinco traços, uma máquina cada, na escala do próprio limiar.
    // Traço cheio = encostou na risca. O número é a pior medida da frota.
    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: root.alarm ? "error" : "dns"
                filled: root.alarm
                size: Theme.iconSize - 6
                color: root.alarm ? root.cCrit
                     : (root.hasData ? Theme.surfaceText : Theme.surfaceTextMedium)
                anchors.verticalCenter: parent.verticalCenter
            }

            Item {
                id: comb
                width: root.hasData ? root.hosts.hosts.length * 5 - 2 : 0
                height: 13
                visible: root.hasData
                anchors.verticalCenter: parent.verticalCenter

                Repeater {
                    model: root.hasData ? root.hosts.hosts : []

                    Rectangle {
                        x: index * 5
                        width: 3
                        height: Math.max(2, Math.round(13 * Math.min(1, src.hostRatio(modelData))))
                        y: comb.height - height
                        radius: 1
                        color: root.hostTint(modelData)

                        Behavior on height {
                            NumberAnimation {
                                duration: Theme.mediumDuration
                                easing.type: Theme.standardEasing
                            }
                        }
                    }
                }
            }

            // Mono: o número muda a cada tique e a barra não pode dançar.
            StyledText {
                text: {
                    if (!root.hasData) return "—"
                    if (root.alarm) return String(root.down + root.dbDown)
                    return Math.round(root.worst.pct) + "%"
                }
                font.family: root.mono
                font.pixelSize: Theme.fontSizeSmall
                color: root.level > 0 && root.hasData ? root.levelColor : Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXXS

            DankIcon {
                name: root.alarm ? "error" : "dns"
                filled: root.alarm
                size: Theme.iconSize - 6
                color: root.alarm ? root.cCrit : Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Item {
                id: vcomb
                width: 18
                height: root.hasData ? root.hosts.hosts.length * 3 : 0
                visible: root.hasData
                anchors.horizontalCenter: parent.horizontalCenter

                Repeater {
                    model: root.hasData ? root.hosts.hosts : []

                    Rectangle {
                        y: index * 3
                        height: 2
                        width: Math.max(2, Math.round(18 * Math.min(1, src.hostRatio(modelData))))
                        radius: 1
                        color: root.hostTint(modelData)
                    }
                }
            }

            StyledText {
                text: root.hasData ? Math.round(root.worst.pct) + "%" : "—"
                font.family: root.mono
                font.pixelSize: Theme.fontSizeSmall
                color: root.level > 0 && root.hasData ? root.levelColor : Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutWidth: 480
    popoutHeight: 620

    popoutContent: Component {
        PopoutComponent {
            // Cabeçalho próprio em vez do padrão do DMS: é o mesmo do cartão
            // da área de trabalho, e o olho reconhece o painel pelo formato.
            headerText: ""
            showCloseButton: false

            Item {
                id: wrap
                width: parent.width
                implicitHeight: body.implicitHeight

                readonly property real hostW: 70
                readonly property real roleW: 54
                readonly property real ctrW: 34
                readonly property real cellW: Math.max(60, (width - 14 - hostW - roleW - ctrW) / 3)

                Column {
                    id: body
                    width: parent.width
                    spacing: 8

                    Item {
                        width: parent.width
                        height: 18

                        SectionLabel {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "FROTA"
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
                                color: root.levelColor
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

                    StyledText {
                        visible: !root.hasData
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: src.loadError !== "" ? src.loadError : "Snapshot não encontrado.\nsystemctl --user status ricestat"
                        font.pixelSize: 12
                        color: Theme.surfaceTextMedium
                    }

                    // Uma frase com endereço: qual máquina, qual medida, contra
                    // qual risca. Número solto não diz de onde veio.
                    StyledText {
                        visible: root.hasData && root.worst.pct >= 0
                        width: parent.width
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                        text: root.alarm
                            ? root.down + " máquina(s) e " + root.dbDown + " banco(s) fora"
                            : "mais perto do limite: " + root.worst.who + ", " + root.worst.label + " em " + Math.round(root.worst.pct) + "%"
                        font.pixelSize: 12
                        color: root.level > 0 ? root.levelColor : Theme.surfaceTextMedium
                    }

                    Row {
                        visible: root.hasData
                        width: parent.width
                        height: 12

                        Item { width: 14 + wrap.hostW + wrap.roleW; height: 1 }
                        ColHead { width: wrap.cellW; text: "CPU " + root.warnCpu }
                        ColHead { width: wrap.cellW; text: "MEM " + root.warnMem }
                        ColHead { width: wrap.cellW; text: "DISCO " + root.warnDisk }
                        ColHead { width: wrap.ctrW; text: "CTR"; horizontalAlignment: Text.AlignRight }
                    }

                    Column {
                        visible: root.hasData
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: root.hasData ? root.hosts.hosts : []

                            Row {
                                width: parent.width
                                height: 24

                                Item {
                                    width: 14
                                    height: parent.height

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 7
                                        height: 7
                                        radius: 3.5
                                        color: modelData.up ? Theme.withAlpha(Theme.surfaceText, 0.30) : root.cCrit
                                    }
                                }

                                StyledText {
                                    width: wrap.hostW
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.alias
                                    elide: Text.ElideRight
                                    wrapMode: Text.NoWrap
                                    font.pixelSize: 13
                                    font.weight: modelData.up ? Font.Medium : Font.DemiBold
                                    color: modelData.up ? Theme.surfaceText : root.cCrit
                                }

                                StyledText {
                                    width: wrap.roleW
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.up ? modelData.role + " · " + src.uptime(modelData.uptime_sec) : modelData.role
                                    elide: Text.ElideRight
                                    wrapMode: Text.NoWrap
                                    font.pixelSize: 11
                                    color: Theme.surfaceTextSecondary
                                }

                                Cell {
                                    visible: modelData.up
                                    width: wrap.cellW - 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    value: modelData.load_pct
                                    warn: root.warnCpu
                                    tint: root.tintFor(value, root.warnCpu)
                                    numColor: root.numFor(value, root.warnCpu)
                                }
                                Item { visible: modelData.up; width: 8; height: 1 }
                                Cell {
                                    visible: modelData.up
                                    width: wrap.cellW - 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    value: src.memPct(modelData)
                                    warn: root.warnMem
                                    tint: root.tintFor(value, root.warnMem)
                                    numColor: root.numFor(value, root.warnMem)
                                }
                                Item { visible: modelData.up; width: 8; height: 1 }
                                Cell {
                                    visible: modelData.up
                                    width: wrap.cellW - 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    value: modelData.disk_pct
                                    warn: root.warnDisk
                                    tint: root.tintFor(value, root.warnDisk)
                                    numColor: root.numFor(value, root.warnDisk)
                                }
                                Item { visible: modelData.up; width: 8; height: 1 }

                                StyledText {
                                    visible: modelData.up
                                    width: wrap.ctrW
                                    anchors.verticalCenter: parent.verticalCenter
                                    horizontalAlignment: Text.AlignRight
                                    text: modelData.containers_up
                                    font.family: root.mono
                                    font.pixelSize: 12
                                    color: Theme.surfaceTextMedium
                                }

                                StyledText {
                                    visible: !modelData.up
                                    width: wrap.cellW * 3 + wrap.ctrW
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

                    Rectangle {
                        visible: root.hasData && root.hosts.databases > 0
                        width: parent.width
                        height: 1
                        color: Theme.withAlpha(Theme.outline, 0.25)
                    }

                    // Bancos por máquina: no popout há espaço para a lista que
                    // o cartão resume em uma contagem.
                    Item {
                        visible: root.hasData && root.hosts.databases > 0
                        width: parent.width
                        height: 16

                        ColHead {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "BANCOS"
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0

                            ColHead { width: 54; text: "CON"; horizontalAlignment: Text.AlignRight }
                            ColHead { width: 58; text: "TAM"; horizontalAlignment: Text.AlignRight }
                        }
                    }

                    Column {
                        visible: root.hasData
                        width: parent.width
                        spacing: 0

                        Repeater {
                            model: root.hasData ? root.hosts.hosts : []

                            Column {
                                width: body.width
                                visible: (modelData.databases || []).length > 0
                                property string hostAlias: modelData.alias

                                Repeater {
                                    model: modelData.databases || []

                                    Item {
                                        width: body.width
                                        height: 20

                                        Rectangle {
                                            id: ddot
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 6
                                            height: 6
                                            radius: 3
                                            color: src.dbColor(modelData)
                                        }
                                        StyledText {
                                            id: dname
                                            x: 14
                                            width: Math.min(implicitWidth, 170)
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.name
                                            elide: Text.ElideRight
                                            wrapMode: Text.NoWrap
                                            font.pixelSize: 12
                                            color: modelData.up ? Theme.surfaceText : root.cCrit
                                        }
                                        StyledText {
                                            anchors.left: dname.right
                                            anchors.leftMargin: 6
                                            anchors.right: stateT.left
                                            anchors.rightMargin: 6
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: parent.parent.hostAlias + " · " + src.engineShort(modelData.engine)
                                            elide: Text.ElideRight
                                            wrapMode: Text.NoWrap
                                            font.pixelSize: 11
                                            color: Theme.surfaceTextSecondary
                                        }
                                        StyledText {
                                            id: stateT
                                            anchors.right: conT.left
                                            anchors.rightMargin: 4
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: text !== "" && text !== "saudável"
                                            text: src.dbState(modelData)
                                            font.pixelSize: 11
                                            color: src.dbColor(modelData)
                                        }
                                        StyledText {
                                            id: conT
                                            anchors.right: sizeT.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 54
                                            horizontalAlignment: Text.AlignRight
                                            text: modelData.connections > 0 ? modelData.connections : "—"
                                            font.family: root.mono
                                            font.pixelSize: 12
                                            color: Theme.surfaceTextMedium
                                        }
                                        StyledText {
                                            id: sizeT
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 58
                                            horizontalAlignment: Text.AlignRight
                                            text: modelData.size_bytes > 0 ? src.bytes(modelData.size_bytes) : "—"
                                            font.family: root.mono
                                            font.pixelSize: 12
                                            color: Theme.surfaceText
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
