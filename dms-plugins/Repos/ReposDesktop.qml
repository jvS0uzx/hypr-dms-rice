// Briefing de abertura de sessão: o que existe só nesta máquina.
//
// O número alto é a quantidade de arquivos que hoje um `git add -A` levaria
// junto — foi assim que um zip de configuração de servidor entrou num commit.
// Acima dele, quando houver, a faixa dos commits sem push: é o único risco
// real de perda daqui, então é a única coisa que acende o friso.
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

    readonly property color cWarn: "#d29922"
    readonly property color cCrit: "#f85149"
    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property int pad: 14

    property int heavyAt: (pluginData && pluginData.heavyAt) ? pluginData.heavyAt : 20
    property bool hideLight: pluginData ? pluginData.hideLight === true : false
    property int maxRows: 6

    property bool hasData: src.hasData
    property int totalRepos: hasData ? (src.repos.total || 0) : 0
    property int dirtyCount: hasData ? (src.repos.dirty_count || 0) : 0
    property int exposed: src.sumDirty()
    property int aheadCommits: src.sumAhead()
    property var aheadRepos: src.aheadList()
    property var heavy: src.heavyList(heavyAt)
    property var light: src.lightList(heavyAt)
    property int maxDirty: src.maxDirty()
    property bool calm: hasData && exposed === 0 && aheadCommits === 0

    property int level: !hasData ? 1 : (aheadCommits > 0 ? 1 : 0)

    readonly property color tracked: Theme.withAlpha(Theme.surfaceText, 0.72)
    readonly property color untracked: Theme.withAlpha(Theme.surfaceText, 0.32)

    readonly property real fitHeight: page.implicitHeight + pad * 2
    onFitHeightChanged: fit()
    onWidthChanged: fit()
    function fit() {
        if (typeof requestResize === "function" && width > 0)
            requestResize(width, Math.max(minHeight, Math.ceil(fitHeight)))
    }

    // Leitor inline de propósito: arquivo QML irmão não resolve como tipo
    // dentro de um plugin do DMS — o componente não nasce e não há erro no
    // log.
    QtObject {
        id: src

        property var snap: null
        property var repos: snap && snap.repos ? snap.repos : null
        property string loadError: snap && snap.errors ? (snap.errors.repos || "") : ""
        property bool hasData: repos !== null && loadError === ""

        function pending() {
            return hasData && repos.pending ? repos.pending : []
        }
        function dirtyOf(r) {
            return r.dirty || 0
        }
        function untrackedOf(r) {
            return Math.min(r.untracked || 0, dirtyOf(r))
        }
        function trackedOf(r) {
            return Math.max(0, dirtyOf(r) - untrackedOf(r))
        }
        function sumDirty() {
            var s = 0
            var p = pending()
            for (var i = 0; i < p.length; i++)
                s += dirtyOf(p[i])
            return s
        }
        function sumAhead() {
            var s = 0
            var p = pending()
            for (var i = 0; i < p.length; i++)
                s += (p[i].ahead || 0)
            return s
        }
        function aheadList() {
            var out = []
            var p = pending()
            for (var i = 0; i < p.length; i++)
                if ((p[i].ahead || 0) > 0)
                    out.push(p[i])
            return out
        }
        function maxDirty() {
            var m = 1
            var p = pending()
            for (var i = 0; i < p.length; i++)
                m = Math.max(m, dirtyOf(p[i]))
            return m
        }
        function heavyList(at) {
            var out = []
            var p = pending()
            for (var i = 0; i < p.length; i++)
                if (dirtyOf(p[i]) >= at || p[i].error || (p[i].ahead || 0) > 0)
                    out.push(p[i])
            out.sort(function (a, b) { return dirtyOf(b) - dirtyOf(a) })
            return out
        }
        function lightList(at) {
            var out = []
            var p = pending()
            for (var i = 0; i < p.length; i++)
                if (dirtyOf(p[i]) < at && dirtyOf(p[i]) > 0 && !p[i].error && !((p[i].ahead || 0) > 0))
                    out.push(p[i])
            return out
        }
        function offMain(r) {
            var b = String(r.branch || "")
            return b !== "" && b !== "main" && b !== "master"
        }
        function aheadWhere() {
            var a = aheadList()
            if (a.length === 0) return ""
            if (a.length === 1) return a[0].name
            return a.length + " repositórios"
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

    component Swatch: Row {
        property color tint
        property string label
        spacing: 4

        Rectangle {
            width: 8
            height: 8
            radius: 2
            color: parent.tint
            anchors.verticalCenter: parent.verticalCenter
        }
        StyledText {
            text: parent.label
            font.pixelSize: 10
            color: Theme.surfaceTextSecondary
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainer, 0.92)
        border.width: 1
        border.color: root.level > 0 ? Theme.withAlpha(root.cWarn, 0.45) : Theme.withAlpha(Theme.outline, 0.22)

        Rectangle {
            visible: root.level > 0
            x: 0
            y: Theme.cornerRadius
            width: 3
            height: parent.height - Theme.cornerRadius * 2
            radius: 1.5
            color: root.cWarn
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
                    text: "REPOSITÓRIOS"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.4
                    color: Theme.surfaceTextMedium
                }

                StyledText {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.hasData
                    text: root.dirtyCount + " de " + root.totalRepos + " com alteração"
                    font.pixelSize: 11
                    color: Theme.surfaceTextMedium
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

            // Commits sem push primeiro: arquivo sujo é bagunça, commit que só
            // existe aqui é trabalho que um disco morto leva embora.
            Rectangle {
                visible: root.hasData && root.aheadCommits > 0
                width: parent.width
                height: 28
                radius: 6
                color: Theme.withAlpha(root.cWarn, 0.12)

                DankIcon {
                    id: upIco
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    name: "cloud_upload"
                    size: 16
                    color: root.cWarn
                }
                StyledText {
                    anchors.left: upIco.right
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    text: root.aheadCommits + (root.aheadCommits === 1 ? " commit sem push em " : " commits sem push em ") + src.aheadWhere()
                    font.pixelSize: 12
                    color: Theme.surfaceText
                }
            }

            Item {
                visible: root.hasData && !root.calm
                width: parent.width
                height: 36

                StyledText {
                    id: hero
                    anchors.left: parent.left
                    anchors.baseline: parent.bottom
                    anchors.baselineOffset: -6
                    text: root.exposed
                    font.family: root.mono
                    font.pixelSize: 30
                    font.weight: Font.DemiBold
                    color: Theme.surfaceText
                }
                StyledText {
                    anchors.left: hero.right
                    anchors.leftMargin: 8
                    anchors.right: legend.left
                    anchors.rightMargin: 8
                    anchors.baseline: hero.baseline
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    text: "arquivos fora de commit"
                    font.pixelSize: 12
                    color: Theme.surfaceTextMedium
                }
                Column {
                    id: legend
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    spacing: 3

                    Swatch { tint: root.tracked; label: "modificados" }
                    Swatch { tint: root.untracked; label: "novos" }
                }
            }

            StyledText {
                visible: root.calm
                text: "tudo commitado e enviado"
                font.pixelSize: 14
                color: Theme.surfaceText
            }

            Column {
                visible: root.hasData && root.heavy.length > 0
                width: parent.width
                spacing: 2

                Repeater {
                    model: root.heavy.slice(0, root.maxRows)

                    Item {
                        width: parent.width
                        height: 32

                        // Clique abre o lazygit no repositório: ver o que são
                        // os 283 arquivos custa um clique, não um cd.
                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: -6
                            anchors.rightMargin: -6
                            radius: 6
                            color: Theme.withAlpha(Theme.surfaceText, repoHover.containsMouse ? 0.06 : 0)
                        }
                        MouseArea {
                            id: repoHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (modelData.path) Quickshell.execDetached(["kitty", "--directory", modelData.path,
                                "--title", "git · " + modelData.name, "-e", "lazygit"])
                        }

                        StyledText {
                            id: nm
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.topMargin: 2
                            width: Math.min(implicitWidth, parent.width * 0.5)
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            text: modelData.name
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }

                        // Branch só quando não é a principal: é o lembrete de
                        // trabalho parado no meio.
                        StyledText {
                            anchors.left: nm.right
                            anchors.leftMargin: 6
                            anchors.right: badges.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: nm.verticalCenter
                            visible: src.offMain(modelData)
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            text: modelData.branch || ""
                            font.family: root.mono
                            font.pixelSize: 10
                            color: Theme.surfaceTextSecondary
                        }

                        Row {
                            id: badges
                            anchors.right: parent.right
                            anchors.verticalCenter: nm.verticalCenter
                            spacing: 8

                            StyledText {
                                visible: (modelData.ahead || 0) > 0
                                text: "↑" + modelData.ahead
                                font.family: root.mono
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: root.cWarn
                            }
                            StyledText {
                                visible: (modelData.behind || 0) > 0
                                text: "↓" + modelData.behind
                                font.family: root.mono
                                font.pixelSize: 12
                                color: Theme.primary
                            }
                            StyledText {
                                visible: !!modelData.error
                                text: "erro"
                                font.pixelSize: 11
                                color: root.cCrit
                            }
                            StyledText {
                                width: 34
                                horizontalAlignment: Text.AlignRight
                                text: src.dirtyOf(modelData)
                                font.family: root.mono
                                font.pixelSize: 12
                                color: Theme.surfaceText
                            }
                        }

                        // Barra empilhada na escala do maior repositório:
                        // modificados à esquerda, novos em seguida.
                        Row {
                            id: bar
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            height: 4
                            spacing: 1
                            property real unit: parent.width / Math.max(1, root.maxDirty)

                            Rectangle {
                                height: 4
                                radius: 2
                                width: src.trackedOf(modelData) > 0 ? Math.max(2, src.trackedOf(modelData) * bar.unit) : 0
                                color: root.tracked
                            }
                            Rectangle {
                                height: 4
                                radius: 2
                                width: src.untrackedOf(modelData) > 0 ? Math.max(2, src.untrackedOf(modelData) * bar.unit) : 0
                                color: root.untracked
                            }
                        }
                    }
                }
            }

            StyledText {
                visible: root.hasData && !root.hideLight && (root.light.length > 0 || root.heavy.length > root.maxRows)
                width: parent.width
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                text: {
                    var rest = root.heavy.slice(root.maxRows).concat(root.light)
                    var names = []
                    for (var i = 0; i < rest.length; i++) names.push(rest[i].name)
                    return "+" + rest.length + " outros: " + names.join(", ")
                }
                font.pixelSize: 11
                color: Theme.surfaceTextSecondary
            }
        }
    }
}
