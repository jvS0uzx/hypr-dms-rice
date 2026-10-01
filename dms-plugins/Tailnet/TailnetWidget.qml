import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var snap: null
    property var tailnet: snap && snap.tailnet ? snap.tailnet : null
    property string loadError: snap && snap.errors ? (snap.errors.tailnet || "") : ""
    property bool hasData: tailnet !== null && loadError === ""
    property bool allUp: hasData && tailnet.offline === 0
    property int online: hasData ? tailnet.online : 0
    property int offline: hasData ? tailnet.offline : 0
    property int total: online + offline

    // Cor de estado é fixa e nunca tematizada: "offline" precisa ler como
    // vermelho com qualquer wallpaper. E a cor nunca decide sozinha — cada nó
    // sai com glifo e rótulo, que é o que mantém a leitura para quem não
    // distingue as duas pontas da escala.
    readonly property color good: "#0ca30c"
    readonly property color critical: "#d03b3b"

    // Chamada nominal: quem não responde encabeça a lista, e entre os mudos
    // vem primeiro quem sumiu há mais tempo. Depois esta máquina, que é o ponto
    // de referência de quem está lendo, e só então o resto da rede.
    property var roster: {
        if (!hasData)
            return []
        var out = tailnet.nodes.slice()
        out.sort(function (a, b) {
            if (a.online !== b.online)
                return a.online ? 1 : -1
            if (!a.online)
                return (Date.parse(a.last_seen) || 0) - (Date.parse(b.last_seen) || 0)
            if (a.self !== b.self)
                return a.self ? -1 : 1
            return 0
        })
        return out
    }

    function since(iso) {
        if (!iso)
            return ""
        var mins = Math.floor((Date.now() - new Date(iso).getTime()) / 60000)
        if (mins < 1) return "agora"
        if (mins < 60) return mins + "min"
        if (mins < 1440) return Math.floor(mins / 60) + "h"
        return Math.floor(mins / 1440) + "d"
    }

    // O glifo da esquerda diz que tipo de máquina é aquela — servidor, o
    // desktop de quem lê, um notebook de alguém. Quando o nó cai, o estado
    // ganha a vaga: saber que é Windows não ajuda quem precisa saber que sumiu.
    function nodeIcon(node) {
        if (!node.online)
            return "cloud_off"
        if (node.self)
            return "computer"
        var os = (node.os || "").toLowerCase()
        if (os.indexOf("windows") >= 0) return "laptop_windows"
        if (os.indexOf("mac") >= 0 || os.indexOf("ios") >= 0) return "laptop_mac"
        if (os.indexOf("android") >= 0) return "smartphone"
        return "dns"
    }

    property bool hideWhenHealthy: pluginData.hideWhenHealthy || false
    property bool pillVisible: !(hideWhenHealthy && allUp)

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

    // O coletor grava por tmp+rename, o que troca o inode e às vezes derruba o
    // inotify do FileView. O tique é a rede de segurança, não o caminho normal.
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: snapFile.reload()
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS
            visible: root.pillVisible

            DankIcon {
                name: root.allUp ? "lan" : "link_off"
                size: Theme.iconSize
                color: root.hasData ? (root.allUp ? Theme.primary : root.critical) : Theme.surfaceTextMedium
                filled: !root.allUp && root.hasData
                anchors.verticalCenter: parent.verticalCenter
            }

            // Algarismo monoespaçado: a pílula não pode mudar de largura quando
            // um nó cai, ou a barra inteira dança.
            StyledText {
                text: root.hasData ? root.online + "/" + root.total : "—"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: root.allUp ? Font.Normal : Font.DemiBold
                color: root.hasData && !root.allUp ? root.critical : Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            visible: root.pillVisible

            DankIcon {
                name: root.allUp ? "lan" : "link_off"
                size: Theme.iconSize
                color: root.hasData ? (root.allUp ? Theme.primary : root.critical) : Theme.surfaceTextMedium
                filled: !root.allUp && root.hasData
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.hasData ? String(root.online) : "—"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Theme.fontSizeSmall
                font.weight: root.allUp ? Font.Normal : Font.DemiBold
                color: root.hasData && !root.allUp ? root.critical : Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutWidth: 420
    popoutHeight: 440

    popoutContent: Component {
        PopoutComponent {
            headerText: "Tailnet"
            // O número grande abaixo já responde a pergunta; a mesma frase em
            // prosa aqui em cima só roubaria a vez dele.
            detailsText: ""
            showCloseButton: true

            Item {
                width: parent.width
                implicitHeight: body.implicitHeight

                Column {
                    id: body
                    width: parent.width
                    spacing: Theme.spacingM

                    Column {
                        visible: !root.hasData
                        width: parent.width
                        spacing: Theme.spacingS

                        Row {
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "cloud_off"
                                size: 20
                                color: root.critical
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: "o ricestat não respondeu"
                                font.pixelSize: Theme.fontSizeLarge
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        StyledText {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: root.loadError !== ""
                                ? root.loadError
                                : "o snapshot não foi encontrado. confira o coletor:"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceTextMedium
                        }

                        Rectangle {
                            width: parent.width
                            height: 30
                            radius: 6
                            color: Theme.surfaceContainer

                            StyledText {
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                text: "systemctl --user status ricestat"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                            }
                        }
                    }

                    // Quando alguém cai, o número alto é o que falta, não o que
                    // sobra: é a pergunta que traz a pessoa até aqui.
                    Row {
                        visible: root.hasData
                        leftPadding: Theme.spacingS
                        spacing: Theme.spacingS

                        DankIcon {
                            name: root.allUp ? "lan" : "link_off"
                            size: 21
                            color: root.allUp ? root.good : root.critical
                            filled: !root.allUp
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: root.allUp ? String(root.total) : String(root.offline)
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 34
                            font.weight: Font.DemiBold
                            font.letterSpacing: -1
                            color: root.allUp ? root.good : root.critical
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            spacing: 1
                            anchors.verticalCenter: parent.verticalCenter

                            StyledText {
                                text: root.allUp ? "no ar" : "fora do ar"
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }

                            Row {
                                spacing: 4

                                StyledText {
                                    visible: !root.allUp
                                    text: String(root.online)
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceTextMedium
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    visible: !root.allUp
                                    text: "de"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceTextMedium
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    visible: !root.allUp
                                    text: String(root.total)
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceTextMedium
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    text: root.allUp ? "a tailnet inteira responde" : "respondendo"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceTextMedium
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 0

                        Repeater {
                            model: root.roster

                            Column {
                                id: nodeWrap
                                width: body.width
                                spacing: 0

                                // Único fio do painel: fecha o bloco de quem não
                                // responde. Num dia em que todos respondem ele
                                // some, e não sobra cromo nenhum na tela.
                                readonly property bool bayBreak: index === root.offline
                                                                 && root.offline > 0
                                                                 && root.offline < root.total

                                Item {
                                    width: parent.width
                                    height: nodeWrap.bayBreak ? 13 : 0
                                    visible: nodeWrap.bayBreak

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: 2
                                        width: parent.width - 4
                                        height: 1
                                        color: Theme.outline
                                        opacity: 0.35
                                    }
                                }

                                Item {
                                    id: nodeRow
                                    width: parent.width
                                    height: 46

                                    readonly property bool down: !modelData.online

                                    // Mesma borda de estado do Deploy Radar: as
                                    // duas superfícies são a mesma gramática, o
                                    // que muda é o que cada coluna carrega.
                                    Rectangle {
                                        x: 2
                                        y: 8
                                        width: 3
                                        height: nodeRow.height - 16
                                        radius: 2
                                        color: nodeRow.down ? root.critical : root.good
                                        opacity: nodeRow.down ? 1 : 0.45
                                    }

                                    DankIcon {
                                        id: kindIcon
                                        anchors.left: parent.left
                                        anchors.leftMargin: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: root.nodeIcon(modelData)
                                        size: 18
                                        color: nodeRow.down ? root.critical
                                             : (modelData.self ? Theme.primary : Theme.surfaceTextMedium)
                                        filled: nodeRow.down
                                    }

                                    // O IP fica porque é o campo que sai daqui
                                    // colado num ssh. Mono alinha os quatro
                                    // octetos e a coluna vira uma régua.
                                    StyledText {
                                        id: addr
                                        anchors.right: parent.right
                                        anchors.rightMargin: Theme.spacingS
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.ip
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: nodeRow.down ? Theme.surfaceTextSecondary : Theme.surfaceTextMedium
                                        width: 108
                                        horizontalAlignment: Text.AlignRight
                                    }

                                    Column {
                                        anchors.left: kindIcon.right
                                        anchors.leftMargin: Theme.spacingS
                                        anchors.right: addr.left
                                        anchors.rightMargin: Theme.spacingM
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 2

                                        Row {
                                            width: parent.width
                                            spacing: Theme.spacingS

                                            StyledText {
                                                text: modelData.name
                                                font.pixelSize: Theme.fontSizeMedium
                                                font.weight: nodeRow.down ? Font.DemiBold : Font.Normal
                                                color: Theme.surfaceText
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            StyledText {
                                                visible: modelData.self === true
                                                text: "esta máquina"
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: Theme.primary
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        Row {
                                            width: parent.width
                                            spacing: 4

                                            StyledText {
                                                text: nodeRow.down ? "sem resposta há" : "responde"
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: nodeRow.down ? root.critical : Theme.surfaceTextMedium
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            StyledText {
                                                visible: nodeRow.down
                                                text: root.since(modelData.last_seen)
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.weight: Font.DemiBold
                                                color: root.critical
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            StyledText {
                                                text: (modelData.os || "").toLowerCase()
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: Theme.surfaceTextSecondary
                                                leftPadding: Theme.spacingXS
                                                anchors.verticalCenter: parent.verticalCenter
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
}
