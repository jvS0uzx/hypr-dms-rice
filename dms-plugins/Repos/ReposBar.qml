// Pílula e popout dos repositórios locais.
//
// Exposição, não inventário: o que se perde é trabalho que ninguém commitou.
// Mesma linguagem do cartão da área de trabalho — faixa de commits sem push
// no topo, número herói com os arquivos fora de commit, e uma linha por
// repositório pesado com nome, branch, ↑/↓ e a barra partida entre o que o
// git rastreia e o que ele nunca viu. Foi o segundo segmento que um
// `git add -A` levou junto uma vez, com um zip de configuração de servidor.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    readonly property color cWarn: "#d29922"
    readonly property color cCrit: "#f85149"
    readonly property string mono: "JetBrainsMono Nerd Font"

    // Acima deste número de arquivos o repositório ganha linha própria com
    // barra. Abaixo, é ruído de trabalho em andamento e cai na lista rasa.
    property int heavyAt: (pluginData && pluginData.heavyAt) ? pluginData.heavyAt : 20
    property bool hideLight: pluginData ? pluginData.hideLight === true : false
    property bool hideWhenClean: pluginData ? pluginData.hideWhenClean === true : false

    property bool hasData: src.hasData
    property int dirtyCount: hasData ? (src.repos.dirty_count || 0) : 0
    property int totalRepos: hasData ? (src.repos.total || 0) : 0
    property int exposed: src.sumDirty()
    property int aheadCommits: src.sumAhead()
    property var aheadRepos: src.aheadList()
    property var heavy: src.heavyList(heavyAt)
    property var light: src.lightList(heavyAt)
    property int maxDirty: src.maxDirty()
    property bool calm: hasData && exposed === 0 && aheadCommits === 0

    readonly property color tracked: Theme.withAlpha(Theme.surfaceText, 0.72)
    readonly property color untracked: Theme.withAlpha(Theme.surfaceText, 0.32)

    visible: !hideWhenClean || !hasData || dirtyCount > 0 || aheadCommits > 0

    // Leitor inline de propósito: arquivo QML irmão não resolve como tipo
    // dentro de um plugin do DMS — o componente não nasce e não há erro no
    // log. Duplicar o leitor por superfície é o preço.
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
            out.sort(function (a, b) { return (b.ahead || 0) - (a.ahead || 0) })
            return out
        }
        function maxDirty() {
            var m = 1
            var p = pending()
            for (var i = 0; i < p.length; i++)
                m = Math.max(m, dirtyOf(p[i]))
            return m
        }
        // Sem push, atrás do origin ou com erro entram na lista principal
        // mesmo com um arquivo só: commit que nunca subiu não é ruído.
        function notable(r) {
            return (r.ahead || 0) > 0 || (r.behind || 0) > 0 || !!r.error
        }
        function heavyList(at) {
            var out = []
            var p = pending()
            for (var i = 0; i < p.length; i++)
                if (dirtyOf(p[i]) >= at || notable(p[i]))
                    out.push(p[i])
            out.sort(function (a, b) { return dirtyOf(b) - dirtyOf(a) })
            return out
        }
        function lightList(at) {
            var out = []
            var p = pending()
            for (var i = 0; i < p.length; i++)
                if (dirtyOf(p[i]) < at && dirtyOf(p[i]) > 0 && !notable(p[i]))
                    out.push(p[i])
            out.sort(function (a, b) { return dirtyOf(b) - dirtyOf(a) })
            return out
        }
        function offMain(r) {
            var b = String(r.branch || "")
            return b !== "" && b !== "main" && b !== "master"
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

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: root.hasData ? "commit" : "cloud_off"
                size: 16
                color: root.hasData ? Theme.surfaceText : Theme.surfaceTextMedium
                anchors.verticalCenter: parent.verticalCenter
            }

            // Repositórios com trabalho não commitado. Mono: o número muda
            // sozinho e a barra não pode dançar junto.
            StyledText {
                text: root.hasData ? String(root.dirtyCount) : "—"
                font.family: root.mono
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }

            // Commit que existe só nesta máquina é outra classe de perda: tem
            // lugar e cor próprios em vez de somar no mesmo número.
            StyledText {
                visible: root.aheadCommits > 0
                text: "↑" + root.aheadCommits
                font.family: root.mono
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
                color: root.cWarn
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXXS

            DankIcon {
                name: root.hasData ? "commit" : "cloud_off"
                size: 16
                color: root.hasData ? Theme.surfaceText : Theme.surfaceTextMedium
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                text: root.hasData ? String(root.dirtyCount) : "—"
                font.family: root.mono
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                visible: root.aheadCommits > 0
                text: "↑" + root.aheadCommits
                font.family: root.mono
                font.pixelSize: Theme.fontSizeSmall
                color: root.cWarn
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutWidth: 500
    popoutHeight: 640

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
                            text: "REPOSITÓRIOS"
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
                                color: root.aheadCommits > 0 ? root.cWarn : Theme.withAlpha(Theme.surfaceText, 0.3)
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.dirtyCount + " de " + root.totalRepos + " com alteração"
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

                    // Commits sem push primeiro, um por repositório: arquivo
                    // sujo é bagunça, commit que só existe aqui é trabalho que
                    // um disco morto leva embora.
                    Rectangle {
                        visible: root.hasData && root.aheadCommits > 0
                        width: parent.width
                        height: aheadCol.implicitHeight + 16
                        radius: 6
                        color: Theme.withAlpha(root.cWarn, 0.12)

                        Column {
                            id: aheadCol
                            x: 8
                            y: 8
                            width: parent.width - 16
                            spacing: 4

                            Repeater {
                                model: root.aheadRepos

                                Item {
                                    width: aheadCol.width
                                    height: 18

                                    DankIcon {
                                        id: upIco
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: "cloud_upload"
                                        size: 16
                                        color: root.cWarn
                                    }
                                    StyledText {
                                        anchors.left: upIco.right
                                        anchors.leftMargin: 8
                                        anchors.right: upN.left
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        elide: Text.ElideRight
                                        wrapMode: Text.NoWrap
                                        text: modelData.name + (src.offMain(modelData) ? "  " + modelData.branch : "")
                                        font.pixelSize: 12
                                        color: Theme.surfaceText
                                    }
                                    StyledText {
                                        id: upN
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.ahead + (modelData.ahead === 1 ? " commit sem push" : " commits sem push")
                                        font.pixelSize: 11
                                        color: root.cWarn
                                    }
                                }
                            }
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

                    // No popout cabe a lista inteira dos pesados; o cartão
                    // corta em seis.
                    Column {
                        visible: root.hasData && root.heavy.length > 0
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: root.heavy

                            Item {
                                width: body.width
                                height: modelData.error ? 46 : 32

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
                                    color: modelData.error ? root.cCrit : Theme.surfaceText
                                }

                                // Branch só quando não é a principal: é o
                                // lembrete de trabalho parado no meio.
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
                                        width: 34
                                        horizontalAlignment: Text.AlignRight
                                        text: src.dirtyOf(modelData)
                                        font.family: root.mono
                                        font.pixelSize: 12
                                        color: Theme.surfaceText
                                    }
                                }

                                // Barra empilhada na escala do maior
                                // repositório: modificados, depois novos.
                                Row {
                                    id: bar
                                    anchors.left: parent.left
                                    y: 24
                                    height: 4
                                    spacing: 1
                                    property real pxPerFile: parent.width / Math.max(1, root.maxDirty)

                                    Rectangle {
                                        height: 4
                                        radius: 2
                                        width: src.trackedOf(modelData) > 0 ? Math.max(2, src.trackedOf(modelData) * bar.pxPerFile) : 0
                                        color: root.tracked
                                    }
                                    Rectangle {
                                        height: 4
                                        radius: 2
                                        width: src.untrackedOf(modelData) > 0 ? Math.max(2, src.untrackedOf(modelData) * bar.pxPerFile) : 0
                                        color: root.untracked
                                    }
                                }

                                StyledText {
                                    visible: !!modelData.error
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    y: 30
                                    elide: Text.ElideRight
                                    wrapMode: Text.NoWrap
                                    text: modelData.error ? String(modelData.error) : ""
                                    font.pixelSize: 11
                                    color: root.cCrit
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: root.hasData && !root.hideLight && root.light.length > 0
                        width: parent.width
                        height: 1
                        color: Theme.withAlpha(Theme.outline, 0.25)
                    }

                    Item {
                        visible: root.hasData && !root.hideLight && root.light.length > 0
                        width: parent.width
                        height: 14

                        StyledText {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "ABAIXO DE " + root.heavyAt + " ARQUIVOS"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1
                            color: Theme.surfaceTextSecondary
                        }
                    }

                    // Os leves em grade de duas colunas: servem de contexto,
                    // não pedem ação, então não merecem linha inteira.
                    Grid {
                        visible: root.hasData && !root.hideLight && root.light.length > 0
                        width: parent.width
                        columns: 2
                        columnSpacing: 16
                        rowSpacing: 4

                        Repeater {
                            model: root.hideLight ? [] : root.light

                            Item {
                                width: (body.width - 16) / 2
                                height: 18

                                StyledText {
                                    anchors.left: parent.left
                                    anchors.right: lc.left
                                    anchors.rightMargin: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight
                                    wrapMode: Text.NoWrap
                                    text: modelData.name
                                    font.pixelSize: 12
                                    color: Theme.surfaceTextMedium
                                }
                                StyledText {
                                    id: lc
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: src.dirtyOf(modelData)
                                    font.family: root.mono
                                    font.pixelSize: 11
                                    color: Theme.surfaceTextSecondary
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
