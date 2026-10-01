// Deploys na área de trabalho: o que está quebrado, o que está subindo agora,
// e o resto em uma grade compacta.
//
// Até aqui o estado dos 11 pipelines só existia como um "3" vermelho na
// barra — que diz que há problema, mas não onde nem desde quando. O deploy do
// gestao-ativos ficou quebrado 15 dias antes de alguém notar; a idade da
// falha é o dado que faltava na tela.
//
// Somente leitura, como a pílula: clicar abre o run no navegador, e nada
// daqui dispara rerun.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

DesktopPluginComponent {
    id: root

    minWidth: 320
    minHeight: 110

    readonly property color cOk: "#3fb950"
    readonly property color cWarn: "#d29922"
    readonly property color cCrit: "#f85149"
    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property int pad: 14

    property bool hasData: src.hasData
    property var d: hasData ? src.snap.deploys : null
    property var repos: d && d.repos ? d.repos : []
    property var failing: repos.filter(function (r) { return r.state === "failure" })
        .sort(function (a, b) { return new Date(a.at) - new Date(b.at) })
    property var running: repos.filter(function (r) { return r.state === "running" })
    property var rest: repos.filter(function (r) { return r.state !== "failure" && r.state !== "running" })
        .sort(function (a, b) { return new Date(b.at) - new Date(a.at) })

    property int level: !hasData ? 1 : (failing.length > 0 ? 2 : 0)

    // Relógio local só enquanto há deploy rodando: o coletor atualiza a cada
    // 15s, e um cronômetro que pula de 15 em 15 parece travado.
    property real now: Date.now()
    Timer {
        interval: 1000
        running: root.running.length > 0
        repeat: true
        onTriggered: root.now = Date.now()
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
        property string loadError: snap && snap.errors ? (snap.errors.deploys || "") : ""
        property bool hasData: snap !== null && snap.deploys !== undefined && snap.deploys !== null && loadError === ""

        function age(iso) {
            if (!iso) return "—"
            var s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000)
            if (s < 3600) return Math.max(1, Math.floor(s / 60)) + "min"
            if (s < 86400) return Math.floor(s / 3600) + "h"
            return Math.floor(s / 86400) + "d"
        }
        function clock(sec) {
            var s = Math.max(0, Math.floor(sec))
            var m = Math.floor(s / 60)
            var r = s % 60
            return m + ":" + (r < 10 ? "0" : "") + r
        }
    }

    function elapsed(r) {
        var base = r.elapsed_sec || 0
        var ts = src.snap && src.snap.ts ? new Date(src.snap.ts).getTime() : now
        return base + Math.max(0, (now - ts) / 1000)
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

    component SectionLabel: StyledText {
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
        border.color: root.level >= 2 ? Theme.withAlpha(root.cCrit, 0.45) : Theme.withAlpha(Theme.outline, 0.22)

        Rectangle {
            visible: root.level > 0
            x: 0
            y: Theme.cornerRadius
            width: 3
            height: parent.height - Theme.cornerRadius * 2
            radius: 1.5
            color: root.level >= 2 ? root.cCrit : root.cWarn
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

                StyledText {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "DEPLOYS"
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
                        color: root.running.length > 0 ? Theme.primary
                            : (root.failing.length > 0 ? root.cCrit : root.cOk)
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.running.length > 0
                            ? root.running.length + " subindo agora"
                            : (root.d ? root.d.ok + "/" + root.repos.length + " em dia" : "")
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

            // Ao vivo: um bloco por run em andamento, com passo atual e
            // progresso em passos — o feedback que falta entre `git push` e
            // "funcionou".
            Repeater {
                model: root.running

                Rectangle {
                    width: page.width
                    height: liveCol.implicitHeight + 16
                    radius: 8
                    color: Theme.withAlpha(Theme.primary, 0.10)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.primary, 0.30)

                    Column {
                        id: liveCol
                        x: 10
                        y: 8
                        width: parent.width - 20
                        spacing: 6

                        Item {
                            width: parent.width
                            height: 18

                            StyledText {
                                anchors.left: parent.left
                                anchors.right: timer.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                                text: modelData.name
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                color: Theme.surfaceText
                            }
                            StyledText {
                                id: timer
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: src.clock(root.elapsed(modelData))
                                font.family: root.mono
                                font.pixelSize: 13
                                color: Theme.primary
                            }
                        }

                        Rectangle {
                            id: liveRail
                            width: parent.width
                            height: 4
                            radius: 2
                            color: Theme.withAlpha(Theme.surfaceText, 0.12)

                            Rectangle {
                                width: modelData.steps_total > 0
                                    ? Math.max(4, liveRail.width * modelData.steps_done / modelData.steps_total) : 4
                                height: parent.height
                                radius: parent.radius
                                color: Theme.primary

                                Behavior on width {
                                    NumberAnimation {
                                        duration: Theme.mediumDuration
                                        easing.type: Theme.standardEasing
                                    }
                                }
                            }
                        }

                        StyledText {
                            width: parent.width
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            text: (modelData.steps_total > 0 ? "passo " + modelData.steps_done + "/" + modelData.steps_total + " · " : "")
                                + (modelData.current_step || "na fila")
                            font.pixelSize: 11
                            color: Theme.surfaceTextMedium
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (modelData.url) Qt.openUrlExternally(modelData.url)
                    }
                }
            }

            Item {
                visible: root.failing.length > 0
                width: parent.width
                height: 36

                StyledText {
                    id: hero
                    anchors.left: parent.left
                    anchors.baseline: parent.bottom
                    anchors.baselineOffset: -6
                    text: root.failing.length
                    font.family: root.mono
                    font.pixelSize: 30
                    font.weight: Font.DemiBold
                    color: root.cCrit
                }
                StyledText {
                    anchors.left: hero.right
                    anchors.leftMargin: 8
                    anchors.baseline: hero.baseline
                    text: root.failing.length === 1 ? "quebrado" : "quebrados"
                    font.pixelSize: 12
                    color: Theme.surfaceTextMedium
                }
                Column {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    spacing: 1

                    SectionLabel {
                        anchors.right: parent.right
                        text: "MAIS ANTIGO"
                    }
                    StyledText {
                        anchors.right: parent.right
                        text: root.failing.length > 0 ? "há " + src.age(root.failing[0].at) : ""
                        font.family: root.mono
                        font.pixelSize: 13
                        color: Theme.surfaceText
                    }
                }
            }

            Column {
                visible: root.failing.length > 0
                width: parent.width
                spacing: 2

                Repeater {
                    model: root.failing

                    Item {
                        width: parent.width
                        height: 36

                        Rectangle {
                            id: fdot
                            anchors.left: parent.left
                            y: 7
                            width: 7
                            height: 7
                            radius: 3.5
                            color: root.cCrit
                        }
                        StyledText {
                            id: fname
                            anchors.left: fdot.right
                            anchors.leftMargin: 8
                            anchors.right: fage.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: fdot.verticalCenter
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            text: modelData.name
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }
                        StyledText {
                            id: fage
                            anchors.right: parent.right
                            anchors.verticalCenter: fdot.verticalCenter
                            text: src.age(modelData.at)
                            font.family: root.mono
                            font.pixelSize: 12
                            color: root.cCrit
                        }
                        StyledText {
                            anchors.left: fname.left
                            anchors.right: parent.right
                            anchors.top: fname.bottom
                            anchors.topMargin: 1
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            text: modelData.error || modelData.title || ""
                            font.pixelSize: 11
                            color: Theme.surfaceTextSecondary
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (modelData.url) Qt.openUrlExternally(modelData.url)
                        }
                    }
                }
            }

            Rectangle {
                visible: root.failing.length > 0 && root.rest.length > 0
                width: parent.width
                height: 1
                color: Theme.withAlpha(Theme.outline, 0.25)
            }

            SectionLabel {
                visible: root.rest.length > 0
                text: "EM DIA · ÚLTIMO DEPLOY"
            }

            // Os que passaram em grade de duas colunas: servem de contexto,
            // não pedem ação, então não merecem uma linha inteira cada.
            Grid {
                visible: root.rest.length > 0
                width: parent.width
                columns: 2
                columnSpacing: 16
                rowSpacing: 4

                Repeater {
                    model: root.rest

                    Item {
                        width: (page.width - 16) / 2
                        height: 18

                        Rectangle {
                            id: odot
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6
                            height: 6
                            radius: 3
                            color: modelData.state === "success" ? Theme.withAlpha(root.cOk, 0.8) : Theme.withAlpha(Theme.surfaceText, 0.3)
                        }
                        StyledText {
                            anchors.left: odot.right
                            anchors.leftMargin: 7
                            anchors.right: oage.left
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            text: modelData.name
                            font.pixelSize: 12
                            color: Theme.surfaceTextMedium
                        }
                        StyledText {
                            id: oage
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: src.age(modelData.at)
                            font.family: root.mono
                            font.pixelSize: 11
                            color: Theme.surfaceTextSecondary
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (modelData.url) Qt.openUrlExternally(modelData.url)
                        }
                    }
                }
            }
        }
    }
}
