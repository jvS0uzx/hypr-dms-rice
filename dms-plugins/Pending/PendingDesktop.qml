// Pendências: o que tem prazo ou está parado há tempo demais.
//
// Os outros widgets mostram estado; este mostra dívida. A diferença importa
// porque dívida não dispara alerta — a chave da Tailscale do node1 vence num
// dia qualquer sem que nada esteja "vermelho" até o minuto em que o cluster
// inteiro some. Cada item diz o que fazer, não só o que está errado.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

DesktopPluginComponent {
    id: root

    minWidth: 320
    minHeight: 90

    readonly property color cOk: "#3fb950"
    readonly property color cWarn: "#d29922"
    readonly property color cCrit: "#f85149"
    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property int pad: 14

    property var snap: null
    property bool hasData: snap !== null

    // Cada item: sev 1/2, ícone, título, o que fazer, prazo curto à direita
    // e, quando houver, para onde o clique leva.
    property var items: {
        var s = snap
        var out = []
        if (!s) return out

        if (s.tailnet && s.tailnet.nodes) {
            for (var i = 0; i < s.tailnet.nodes.length; i++) {
                var n = s.tailnet.nodes[i]
                if (n.key_days >= 0 && n.key_days <= 14)
                    out.push({ sev: n.key_days <= 7 ? 2 : 1, icon: "key",
                               title: "chave Tailscale de " + n.name + " vence",
                               todo: "desligar expiração da chave no admin da Tailscale",
                               due: n.key_days === 0 ? "hoje" : n.key_days + "d", days: n.key_days,
                               url: "https://login.tailscale.com/admin/machines" })
            }
        }

        if (s.inbox && s.inbox.age_hours >= 24) {
            var d = Math.floor(s.inbox.age_hours / 24)
            out.push({ sev: s.inbox.age_hours >= 72 ? 2 : 1, icon: "inbox",
                       title: "inbox do Telegram sem coleta",
                       todo: "rodar /inbox — a Bot API apaga mensagem com mais de 24h",
                       due: d > 0 ? d + "d" : s.inbox.age_hours + "h", url: "" })
        }

        if (s.deploys && s.deploys.repos) {
            var failing = s.deploys.repos.filter(function (r) { return r.state === "failure" })
            if (failing.length > 0) {
                var oldest = failing.reduce(function (a, b) { return new Date(a.at) < new Date(b.at) ? a : b })
                var age = Math.floor((Date.now() - new Date(oldest.at)) / 86400000)
                out.push({ sev: 2, icon: "rocket_launch",
                           title: failing.length + (failing.length === 1 ? " deploy quebrado" : " deploys quebrados"),
                           todo: failing.map(function (r) { return r.name }).join(", "),
                           due: age + "d", url: oldest.url || "" })
            }
        }

        if (s.services && s.services.items) {
            for (var j = 0; j < s.services.items.length; j++) {
                var sv = s.services.items[j]
                var host = String(sv.name).split(".")[0]  // nome curto: primeiro rótulo do domínio
                if (sv.cert_days >= 0 && sv.cert_days < 15)
                    out.push({ sev: sv.cert_days < 5 ? 2 : 1, icon: "lock_clock",
                               title: "certificado de " + host + " vence",
                               todo: "conferir a renovação do certbot no LB",
                               due: sv.cert_days + "d", days: sv.cert_days, url: "" })
            }
        }

        if (s.hosts && s.hosts.hosts) {
            for (var k = 0; k < s.hosts.hosts.length; k++) {
                var h = s.hosts.hosts[k]
                if (h.disk_full_days > 0 && h.disk_full_days <= 60)
                    out.push({ sev: h.disk_full_days <= 14 ? 2 : 1, icon: "hard_drive",
                               title: "disco de " + h.alias + " enche no ritmo atual",
                               todo: "+" + (h.disk_trend_pct_day || 0).toFixed(1) + " p.p./dia — procurar cache de build e log",
                               due: h.disk_full_days + "d", days: h.disk_full_days, url: "" })
            }
        }

        if (s.repos && s.repos.pending) {
            var ahead = s.repos.pending.filter(function (r) { return (r.ahead || 0) > 0 })
            if (ahead.length > 0) {
                var total = ahead.reduce(function (a, r) { return a + r.ahead }, 0)
                out.push({ sev: 1, icon: "cloud_upload",
                           title: total + " commits só nesta máquina",
                           todo: "push em " + ahead.map(function (r) { return r.name }).join(", "),
                           due: "", url: "" })
            }
        }

        // Mesma gravidade: prazo mais curto primeiro. Chave que vence em 3
        // dias passa na frente de deploy quebrado há 42 — este já quebrou,
        // aquela ainda dá para evitar.
        out.sort(function (a, b) {
            if (b.sev !== a.sev) return b.sev - a.sev
            return (a.days === undefined ? 9999 : a.days) - (b.days === undefined ? 9999 : b.days)
        })
        return out
    }

    property int level: {
        var l = 0
        for (var i = 0; i < items.length; i++) l = Math.max(l, items[i].sev)
        return l
    }
    readonly property color levelColor: level >= 2 ? cCrit : cWarn

    readonly property real fitHeight: page.implicitHeight + pad * 2
    onFitHeightChanged: fit()
    onWidthChanged: fit()
    function fit() {
        if (typeof requestResize === "function" && width > 0)
            requestResize(width, Math.max(minHeight, Math.ceil(fitHeight)))
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
            spacing: 8

            Item {
                width: parent.width
                height: 18

                StyledText {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "PENDÊNCIAS"
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
                        text: root.items.length === 0 ? "nada pendente" : root.items.length + (root.items.length === 1 ? " item" : " itens")
                        font.pixelSize: 11
                        color: Theme.surfaceTextMedium
                    }
                }
            }

            Repeater {
                model: root.items

                Item {
                    width: page.width
                    height: 40

                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: -6
                        anchors.rightMargin: -6
                        radius: 6
                        color: Theme.withAlpha(Theme.surfaceText, modelData.url && itemHover.containsMouse ? 0.06 : 0)
                    }
                    MouseArea {
                        id: itemHover
                        anchors.fill: parent
                        hoverEnabled: !!modelData.url
                        cursorShape: modelData.url ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (modelData.url) Qt.openUrlExternally(modelData.url)
                    }

                    DankIcon {
                        id: ic
                        anchors.left: parent.left
                        y: 3
                        name: modelData.icon
                        size: 16
                        color: modelData.sev >= 2 ? root.cCrit : root.cWarn
                    }
                    StyledText {
                        id: tt
                        anchors.left: ic.right
                        anchors.leftMargin: 10
                        anchors.right: due.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: ic.verticalCenter
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                        text: modelData.title
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }
                    StyledText {
                        id: due
                        anchors.right: parent.right
                        anchors.verticalCenter: ic.verticalCenter
                        text: modelData.due
                        font.family: root.mono
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: modelData.sev >= 2 ? root.cCrit : root.cWarn
                    }
                    StyledText {
                        anchors.left: tt.left
                        anchors.right: parent.right
                        anchors.top: tt.bottom
                        anchors.topMargin: 2
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                        text: modelData.todo
                        font.pixelSize: 11
                        color: Theme.surfaceTextSecondary
                    }
                }
            }
        }
    }
}
