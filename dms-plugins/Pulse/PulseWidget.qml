// Infra: servidores e sites de produção resumidos num ponto na barra.
//
// Apagado, nada a fazer. Âmbar ou vermelho, o número diz quantas áreas pedem
// atenção e o popout diz quais. Deploys e cota do Claude têm pílula própria;
// repositórios, inbox e Tailscale saíram a pedido (01/10/2026): informação
// que não muda decisão do dia é ruído na barra.
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

    property var snap: null
    property bool hasData: snap !== null

    // Limiares espelham os defaults do plugin Fleet. Se um dia divergirem, o
    // pulso e a frota passam a discordar sobre a mesma máquina.
    readonly property int warnCpu: 85
    readonly property int warnMem: 85
    readonly property int warnDisk: 60

    // Uma entrada por área: nível 0/1/2 e a frase que explica o nível.
    property var areas: {
        var s = snap
        var out = []
        if (!s) return out

        if (s.hosts && s.hosts.hosts) {
            var lv = 0, why = ""
            var hs = s.hosts.hosts
            for (var i = 0; i < hs.length; i++) {
                var h = hs[i]
                if (!h.up) { lv = 2; why = h.alias + " sem resposta"; break }
                var mem = h.mem_total_mb > 0 ? h.mem_used_mb / h.mem_total_mb * 100 : 0
                var checks = [["cpu", h.load_pct, warnCpu, 95], ["memória", mem, warnMem, 95], ["disco", h.disk_pct, warnDisk, 85]]
                for (var c = 0; c < checks.length; c++) {
                    var k = checks[c]
                    var l = k[1] >= k[3] ? 2 : (k[1] >= k[2] ? 1 : 0)
                    if (l > lv) { lv = l; why = h.alias + " " + k[0] + " " + Math.round(k[1]) + "%" }
                }
            }
            if (lv < 2 && s.hosts.databases_down > 0) { lv = 2; why = s.hosts.databases_down + " banco(s) fora" }
            out.push({ key: "servidores", icon: "dns", level: lv, text: lv > 0 ? why : s.hosts.up + "/" + hs.length + " no ar" })
        }

        if (s.services && s.services.items) {
            var sl = 0, sw = ""
            var it = s.services.items
            for (var j = 0; j < it.length; j++) {
                var sv = it[j]
                var l2 = !sv.ok ? 2 : ((sv.recent_fail || 0) > 0 ? 1 : 0)
                if (sv.cert_days !== undefined && sv.cert_days >= 0) {
                    if (sv.cert_days < 5) l2 = 2
                    else if (sv.cert_days < 15) l2 = Math.max(l2, 1)
                }
                if (l2 > sl) {
                    sl = l2
                    sw = sv.name + (!sv.ok ? " " + (sv.status || sv.error || "fora")
                        : (sv.recent_fail > 0 ? " falhou " + sv.recent_fail + "x" : " cert " + sv.cert_days + "d"))
                }
            }
            out.push({ key: "sites", icon: "public", level: sl, text: sl > 0 ? sw : it.length + " respondendo" })
        }

        out.sort(function (a, b) { return b.level - a.level })
        return out
    }

    property int worst: {
        var w = 0
        for (var i = 0; i < areas.length; i++) w = Math.max(w, areas[i].level)
        return w
    }
    property int attention: areas.filter(function (a) { return a.level > 0 }).length
    readonly property color worstColor: !hasData ? Theme.surfaceTextMedium : (worst >= 2 ? cCrit : (worst === 1 ? cWarn : cOk))

    function levelColor(l) {
        return l >= 2 ? cCrit : (l === 1 ? cWarn : Theme.withAlpha(Theme.surfaceText, 0.3))
    }

    FileView {
        id: snapFile
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ricestat.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.snap = JSON.parse(text())
            } catch (e) {
                root.snap = null
            }
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: snapFile.reload()
    }

    horizontalBarPill: Component {
        Row {
            spacing: 6

            DankIcon {
                name: "dns"
                size: Theme.iconSize
                filled: root.worst > 0
                color: root.worst > 0 ? root.worstColor : Theme.surfaceTextMedium
                anchors.verticalCenter: parent.verticalCenter
            }

            // Número só quando há o que contar: "0" na barra é ruído.
            StyledText {
                visible: root.attention > 0
                text: String(root.attention)
                font.family: root.mono
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.DemiBold
                color: root.worstColor
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 2

            DankIcon {
                name: "dns"
                size: Theme.iconSize
                filled: root.worst > 0
                color: root.worst > 0 ? root.worstColor : Theme.surfaceTextMedium
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                visible: root.attention > 0
                text: String(root.attention)
                font.family: root.mono
                font.pixelSize: Theme.fontSizeSmall
                color: root.worstColor
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutWidth: 380
    popoutHeight: 60 + root.areas.length * 44 + 16

    popoutContent: Component {
        PopoutComponent {
            headerText: "Infra"
            detailsText: !root.hasData ? "ricestat não está publicando o snapshot"
                : (root.attention === 0 ? "nada pedindo atenção" : root.attention + (root.attention === 1 ? " área pedindo atenção" : " áreas pedindo atenção"))
            showCloseButton: true

            Column {
                width: parent.width
                spacing: 2

                Repeater {
                    model: root.areas

                    Rectangle {
                        width: parent.width
                        height: 42
                        radius: 8
                        color: modelData.level > 0 ? Theme.withAlpha(root.levelColor(modelData.level), 0.10) : "transparent"

                        Rectangle {
                            id: dot
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8
                            height: 8
                            radius: 4
                            color: root.levelColor(modelData.level)
                        }
                        DankIcon {
                            id: ico
                            anchors.left: dot.right
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            name: modelData.icon
                            size: 18
                            color: Theme.surfaceTextMedium
                        }
                        StyledText {
                            id: nm
                            anchors.left: ico.right
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 96
                            text: modelData.key.toUpperCase()
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1.2
                            color: Theme.surfaceTextMedium
                        }
                        StyledText {
                            anchors.left: nm.right
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignRight
                            wrapMode: Text.NoWrap
                            elide: Text.ElideRight
                            text: modelData.text
                            font.pixelSize: 13
                            color: modelData.level > 0 ? Theme.surfaceText : Theme.surfaceTextMedium
                        }
                    }
                }

            }
        }
    }
}
