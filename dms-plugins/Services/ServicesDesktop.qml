// Serviços: o que o usuário vê, não o que a máquina diz.
//
// A Frota responde "node1 no ar"; aqui a pergunta é "o site abre?". São
// coisas diferentes — em 30/09 os dois nós estavam no ar e o gestor de ativos
// devolvia 500 alternado. A coluna de falhas recentes existe para esse caso:
// um erro intermitente some da checagem atual e fica na contagem.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

DesktopPluginComponent {
    id: root

    minWidth: 340
    minHeight: 110

    readonly property color cOk: "#3fb950"
    readonly property color cWarn: "#d29922"
    readonly property color cCrit: "#f85149"
    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property int pad: 14

    property var svc: src.snap && src.snap.services ? src.snap.services : null
    property bool hasData: svc !== null && src.loadError === ""
    property var items: {
        if (!hasData || !svc.items) return []
        // Quebrado primeiro, depois quem falhou há pouco, depois o resto.
        return svc.items.slice().sort(function (a, b) {
            return rank(b) - rank(a)
        })
    }

    function rank(it) {
        if (!it.ok) return 3
        if ((it.recent_fail || 0) > 0) return 2
        if (it.cert_days >= 0 && it.cert_days < 15) return 1
        return 0
    }

    property int level: {
        if (!hasData) return 1
        var l = 0
        for (var i = 0; i < items.length; i++) {
            var r = rank(items[i])
            if (r === 3) return 2
            if (r > 0) l = 1
        }
        return l
    }
    readonly property color levelColor: level >= 2 ? cCrit : cWarn

    function short(name) {
        // Nome curto: primeiro rótulo do domínio ("app.exemplo.com" vira "app").
        return String(name).split(".")[0]
    }
    function certColor(d) {
        if (d < 0) return Theme.surfaceTextSecondary
        if (d < 5) return cCrit
        if (d < 15) return cWarn
        return Theme.surfaceTextMedium
    }

    readonly property real fitHeight: page.implicitHeight + pad * 2
    onFitHeightChanged: fit()
    onWidthChanged: fit()
    function fit() {
        if (typeof requestResize === "function" && width > 0)
            requestResize(width, Math.max(minHeight, Math.ceil(fitHeight)))
    }

    // Leitor inline de propósito: arquivo QML irmão não resolve como tipo
    // dentro de um plugin do DMS.
    QtObject {
        id: src
        property var snap: null
        property string loadError: snap && snap.errors ? (snap.errors.services || "") : ""
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

    component ColHead: StyledText {
        font.pixelSize: 10
        font.weight: Font.DemiBold
        font.letterSpacing: 1
        color: Theme.surfaceTextSecondary
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
                    text: "SERVIÇOS"
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
                        text: root.hasData ? root.svc.ok + "/" + root.items.length + " respondendo" : ""
                        font.pixelSize: 11
                        color: Theme.surfaceTextMedium
                    }
                }
            }

            Row {
                visible: root.hasData
                width: parent.width
                height: 12

                Item { width: 15; height: 1 }
                ColHead { width: parent.width - 15 - 44 - 64 - 60 - 44; text: "DOMÍNIO" }
                ColHead { width: 44; text: "HTTP"; horizontalAlignment: Text.AlignRight }
                ColHead { width: 64; text: "LATÊNCIA"; horizontalAlignment: Text.AlignRight }
                ColHead { width: 60; text: "FALHAS"; horizontalAlignment: Text.AlignRight }
                ColHead { width: 44; text: "TLS"; horizontalAlignment: Text.AlignRight }
            }

            Column {
                visible: root.hasData
                width: parent.width
                spacing: 2

                Repeater {
                    model: root.items

                    Item {
                        width: parent.width
                        height: 24

                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: -6
                            anchors.rightMargin: -6
                            radius: 6
                            color: Theme.withAlpha(Theme.surfaceText, rowHover.containsMouse ? 0.06 : 0)
                        }
                        MouseArea {
                            id: rowHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (modelData.url) Qt.openUrlExternally(modelData.url)
                        }

                        Row {
                            anchors.fill: parent

                            Item {
                                width: 15
                                height: parent.height
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 7
                                    height: 7
                                    radius: 3.5
                                    color: !modelData.ok ? root.cCrit
                                        : (modelData.recent_fail > 0 ? root.cWarn : Theme.withAlpha(Theme.surfaceText, 0.3))
                                }
                            }
                            StyledText {
                                width: parent.width - 15 - 44 - 64 - 60 - 44
                                anchors.verticalCenter: parent.verticalCenter
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                                text: root.short(modelData.name)
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                color: modelData.ok ? Theme.surfaceText : root.cCrit
                            }
                            StyledText {
                                width: 44
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                text: modelData.status > 0 ? modelData.status : "—"
                                font.family: root.mono
                                font.pixelSize: 12
                                color: modelData.ok ? Theme.surfaceTextMedium : root.cCrit
                            }
                            StyledText {
                                width: 64
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                text: modelData.latency_ms > 0 ? modelData.latency_ms + "ms" : "—"
                                font.family: root.mono
                                font.pixelSize: 12
                                color: modelData.latency_ms > 2000 ? root.cWarn : Theme.surfaceTextMedium
                            }
                            StyledText {
                                width: 60
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                text: (modelData.recent_fail || 0) + "/" + (modelData.recent_n || 0)
                                font.family: root.mono
                                font.pixelSize: 12
                                color: modelData.recent_fail > 0 ? (modelData.ok ? root.cWarn : root.cCrit) : Theme.surfaceTextSecondary
                            }
                            StyledText {
                                width: 44
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                text: modelData.cert_days >= 0 ? modelData.cert_days + "d" : "—"
                                font.family: root.mono
                                font.pixelSize: 12
                                color: root.certColor(modelData.cert_days)
                            }
                        }
                    }
                }
            }

            StyledText {
                visible: root.hasData
                width: parent.width
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                text: "falhas = últimas " + (root.items.length > 0 ? root.items[0].recent_n : 0) + " checagens, uma por minuto · checa só a raiz, páginas com login ficam de fora"
                font.pixelSize: 10
                color: Theme.surfaceTextSecondary
            }

            StyledText {
                visible: !root.hasData
                width: parent.width
                text: src.loadError !== "" ? src.loadError : "ricestat não está publicando serviços.\nsystemctl --user status ricestat"
                font.pixelSize: 12
                color: Theme.surfaceTextMedium
            }
        }
    }
}
