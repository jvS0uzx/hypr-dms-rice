import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var deploys: src.deploys
    property bool hasData: src.hasData
    property int failing: hasData ? deploys.failing : 0
    property int running: hasData ? deploys.running : 0
    property int unknown: hasData ? deploys.unknown : 0
    property int total: hasData ? deploys.repos.length : 0

    // O estado da pílula é o pior estado da frota: é o que decide se alguém
    // precisa parar o que está fazendo.
    property string worst: {
        if (!hasData)
            return "unknown"
        if (failing > 0)
            return "failure"
        if (running > 0)
            return "running"
        return "success"
    }

    // Enquanto há run em andamento a pílula é do run, não da frota: o usuário
    // acabou de dar push e olha a barra para saber em que passo está. A falha
    // antiga continua visível ao lado, em marcador próprio.
    property bool live: hasData && running > 0
    property string pillState: live ? "running" : worst

    // O run que a pílula cronometra é o que começou por último — é o push que
    // acabou de sair da mão do usuário.
    property var leadRun: {
        if (!live)
            return null
        var best = null
        for (var i = 0; i < deploys.repos.length; i++) {
            var r = deploys.repos[i]
            if (r.state !== "running")
                continue
            if (!best || src.num(r.elapsed_sec) < src.num(best.elapsed_sec))
                best = r
        }
        return best
    }

    // Quantas tiras vão para a baia de cima. É também onde cai o único fio do
    // painel: a quebra entre "precisa de você" e "pode esperar".
    property int attention: failing + running + unknown

    // Tira de voo: o que está rodando agora encabeça a baia — é a única linha
    // que muda sozinha enquanto a tela está aberta. Depois vêm as falhas, a
    // mais antiga primeiro, porque deploy parado envelhece: 41 dias é pior
    // notícia que 2 horas. Na baia de baixo vale o inverso: o deploy mais
    // recente é o mais informativo.
    property var strips: {
        if (!hasData)
            return []
        var rank = {
            "running": 0,
            "failure": 1,
            "unknown": 2,
            "success": 3
        }
        var out = deploys.repos.slice()
        out.sort(function (a, b) {
            var ra = rank[a.state] !== undefined ? rank[a.state] : 2
            var rb = rank[b.state] !== undefined ? rank[b.state] : 2
            if (ra !== rb)
                return ra - rb
            if (ra === 0)
                return src.num(a.elapsed_sec) - src.num(b.elapsed_sec)
            var ta = Date.parse(a.at) || 0
            var tb = Date.parse(b.at) || 0
            return ra === 1 ? ta - tb : tb - ta
        })
        return out
    }

    property int heroNumber: {
        if (!hasData)
            return 0
        if (worst === "failure")
            return failing
        if (worst === "running")
            return running
        return total
    }

    property string heroWord: {
        if (worst === "failure")
            return "falhando"
        if (worst === "running")
            return "rodando"
        if (worst === "success")
            return "no ar"
        return "sem dado"
    }

    property bool onlyWhenBroken: pluginData.onlyWhenBroken || false

    // "broken" (padrão), "never" ou "always". O padrão existe porque onze
    // mensagens de commit empilhadas viram parágrafo, não lista — mas a escolha
    // é de quem olha o painel todo dia.
    property string commitTitle: pluginData.commitTitle || "broken"
    property bool pillVisible: !(onlyWhenBroken && worst === "success")

    // Leitor inline de propósito: arquivo QML irmão não resolve como tipo
    // dentro de um plugin do DMS — o componente não nasce e não há erro
    // visível. Duplicar o leitor por superfície é o preço.
    QtObject {
        id: src
        property var snap: null
        property var deploys: snap && snap.deploys ? snap.deploys : null
        property string loadError: snap && snap.errors ? (snap.errors.deploys || "") : ""
        property bool hasData: deploys !== null && loadError === ""
        readonly property color good: "#3fb950"
        readonly property color warning: "#d29922"
        readonly property color critical: "#f85149"

        // Marca d'água do progresso por run_id. Vive fora da tira porque o
        // modelo é recriado a cada coleta — dentro do delegate o valor
        // anterior morreria antes de servir para comparar.
        property var peaks: ({})

        function stColor(s) {
            if (s === "failure") return critical
            if (s === "running") return Theme.primary
            if (s === "success") return good
            return "#8a8a8a"
        }
        function stIcon(s) {
            if (s === "failure") return "cancel"
            if (s === "running") return "progress_activity"
            if (s === "success") return "check_circle"
            return "help"
        }
        function stLabel(s) {
            if (s === "failure") return "falhou"
            if (s === "running") return "rodando"
            if (s === "success") return "passou"
            return "sem dado"
        }
        function num(v) {
            return (typeof v === "number" && isFinite(v)) ? v : 0
        }
        function jobsOf(r) {
            return (r && r.jobs && r.jobs.length) ? r.jobs : []
        }
        // Relógio do run em curso: minuto e segundo, largura estável em mono.
        function fmtClock(sec) {
            var s = Math.max(0, Math.floor(num(sec)))
            var m = Math.floor(s / 60)
            var r = s % 60
            if (m < 60)
                return m + ":" + (r < 10 ? "0" + r : String(r))
            var mm = m % 60
            return Math.floor(m / 60) + "h" + (mm < 10 ? "0" + mm : String(mm))
        }
        // Guarda o teto já alcançado e devolve o anterior: quando um job novo
        // entra no meio do run o total cresce e a fração cai. A barra anda
        // para trás de verdade e o teto antigo fica marcado, em vez de o
        // medidor fingir que nunca esteve mais adiante.
        function peakOf(id, frac) {
            var k = String(id || 0)
            var prev = peaks[k] !== undefined ? peaks[k] : frac
            peaks[k] = Math.max(prev, frac)
            return prev
        }
        function elapsed(iso) {
            if (!iso || iso.indexOf("0001-01-01") === 0) return ""
            var mins = Math.floor((Date.now() - new Date(iso).getTime()) / 60000)
            if (mins < 1) return "agora"
            if (mins < 60) return mins + "min"
            if (mins < 1440) return Math.floor(mins / 60) + "h"
            return Math.floor(mins / 1440) + "d"
        }
        // A tira só mostra a branch quando ela não é main, porque main é o
        // caso normal e repetir "main" onze vezes não informa nada. Branch
        // fora da main num repositório com deploy.yml é que é notícia.
        function branchTag(b) {
            return (!b || b === "main") ? "" : b
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

    // Somente leitura: clicar abre o run no navegador, nada daqui dispara
    // rerun.
    function openRun(url) {
        if (url)
            Qt.openUrlExternally(url)
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS
            visible: root.pillVisible

            DankIcon {
                name: src.stIcon(root.pillState)
                size: Theme.iconSize
                color: src.stColor(root.pillState)
                anchors.verticalCenter: parent.verticalCenter

                RotationAnimation on rotation {
                    running: root.pillState === "running"
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 1400
                }
            }

            // Algarismo monoespaçado: a pílula não pode mudar de largura quando
            // o número muda, ou a barra inteira dança a cada coleta. Com run em
            // curso o número vira o relógio dele — é a pergunta do momento.
            StyledText {
                text: {
                    if (!root.hasData)
                        return "—"
                    if (root.live)
                        return root.running > 1
                            ? String(root.running)
                            : src.fmtClock(root.liveElapsed(root.leadRun))
                    return root.failing > 0 ? String(root.failing) : String(root.total)
                }
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: (root.live || root.failing > 0) ? Font.DemiBold : Font.Normal
                color: root.live ? Theme.primary : (root.failing > 0 ? src.critical : Theme.surfaceText)
                width: (root.live && root.running === 1) ? 42 : implicitWidth
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
            }

            // A falha antiga não some porque um run começou: ela recua para um
            // marcador, com glifo próprio, e continua contando.
            Row {
                visible: root.live && root.failing > 0
                spacing: 2
                anchors.verticalCenter: parent.verticalCenter

                DankIcon {
                    name: "cancel"
                    size: 16
                    color: src.critical
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: String(root.failing)
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Theme.fontSizeSmall
                    color: src.critical
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            visible: root.pillVisible

            DankIcon {
                name: src.stIcon(root.pillState)
                size: Theme.iconSize
                color: src.stColor(root.pillState)
                anchors.horizontalCenter: parent.horizontalCenter

                RotationAnimation on rotation {
                    running: root.pillState === "running"
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 1400
                }
            }

            StyledText {
                text: {
                    if (!root.hasData)
                        return "—"
                    if (root.live)
                        return root.running > 1
                            ? String(root.running)
                            : src.fmtClock(root.liveElapsed(root.leadRun))
                    return root.failing > 0 ? String(root.failing) : String(root.total)
                }
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Theme.fontSizeSmall
                font.weight: (root.live || root.failing > 0) ? Font.DemiBold : Font.Normal
                color: root.live ? Theme.primary : (root.failing > 0 ? src.critical : Theme.surfaceText)
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Row {
                visible: root.live && root.failing > 0
                spacing: 1
                anchors.horizontalCenter: parent.horizontalCenter

                DankIcon {
                    name: "cancel"
                    size: 11
                    color: src.critical
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: String(root.failing)
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Theme.fontSizeSmall
                    color: src.critical
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // Relógio local só enquanto há run: o coletor escreve a cada 15s, e um
    // cronômetro que pula de 15 em 15 parece travado.
    property real now: Date.now()
    Timer {
        interval: 1000
        running: root.live
        repeat: true
        onTriggered: root.now = Date.now()
    }

    function liveElapsed(r) {
        if (!r)
            return 0
        var ts = src.snap && src.snap.ts ? new Date(src.snap.ts).getTime() : now
        return src.num(r.elapsed_sec) + Math.max(0, (now - ts) / 1000)
    }

    property var runningList: strips.filter(function (r) { return r.state === "running" })
    property var brokenList: strips.filter(function (r) { return r.state === "failure" })
    property var restList: strips.filter(function (r) { return r.state !== "failure" && r.state !== "running" })

    // Popout sem rolagem: a altura acompanha o conteúdo, bloco a bloco, para
    // que um run que ganha job no meio não empurre a última linha para fora.
    property int popH: {
        var h = 40
        if (!hasData)
            return 200
        for (var i = 0; i < runningList.length; i++)
            h += 86 + Math.min(src.jobsOf(runningList[i]).length > 1 ? src.jobsOf(runningList[i]).length : 0, 3) * 18
        if (brokenList.length > 0)
            h += 52 + brokenList.length * (commitTitle === "never" ? 26 : 42) + 12
        if (restList.length > 0)
            h += 30 + (commitTitle === "always" ? restList.length * 42 : Math.ceil(restList.length / 2) * 24)
        return h
    }

    popoutWidth: 440
    popoutHeight: popH

    popoutContent: Component {
        PopoutComponent {
            headerText: ""
            detailsText: ""
            showCloseButton: false

            Item {
                width: parent.width
                implicitHeight: body.implicitHeight

                Column {
                    id: body
                    width: parent.width
                    spacing: 12

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
                                color: root.live ? Theme.primary : (root.failing > 0 ? src.critical : src.good)
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.live
                                    ? root.running + " subindo agora"
                                    : (root.total - root.failing - root.unknown) + "/" + root.total + " em dia"
                                font.pixelSize: 11
                                color: Theme.surfaceTextMedium
                            }
                        }
                    }

                    StyledText {
                        visible: !root.hasData
                        width: parent.width
                        text: src.loadError !== "" ? src.loadError : "Snapshot não encontrado.\nsystemctl --user status ricestat"
                        font.pixelSize: 12
                        color: Theme.surfaceTextMedium
                    }

                    // Ao vivo: o feedback entre `git push` e "funcionou".
                    // Com mais de um job, cada um ganha sua linha de passo.
                    Repeater {
                        model: root.runningList

                        Rectangle {
                            id: liveCard
                            width: body.width
                            height: liveCol.implicitHeight + 20
                            radius: 8
                            color: Theme.withAlpha(Theme.primary, 0.10)
                            border.width: 1
                            border.color: Theme.withAlpha(Theme.primary, 0.30)

                            readonly property var jobs: src.jobsOf(modelData)

                            Column {
                                id: liveCol
                                x: 12
                                y: 10
                                width: parent.width - 24
                                spacing: 6

                                Item {
                                    width: parent.width
                                    height: 18

                                    StyledText {
                                        anchors.left: parent.left
                                        anchors.right: clock.left
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        elide: Text.ElideRight
                                        wrapMode: Text.NoWrap
                                        text: modelData.name + (src.branchTag(modelData.branch) !== "" ? "  ·  " + modelData.branch : "")
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        color: Theme.surfaceText
                                    }
                                    StyledText {
                                        id: clock
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: src.fmtClock(root.liveElapsed(modelData))
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 14
                                        color: Theme.primary
                                    }
                                }

                                Rectangle {
                                    id: rail
                                    width: parent.width
                                    height: 4
                                    radius: 2
                                    color: Theme.withAlpha(Theme.surfaceText, 0.12)

                                    Rectangle {
                                        width: src.num(modelData.steps_total) > 0
                                            ? Math.max(4, rail.width * modelData.steps_done / modelData.steps_total) : 4
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
                                    text: (src.num(modelData.steps_total) > 0 ? "passo " + modelData.steps_done + "/" + modelData.steps_total + " · " : "")
                                        + (modelData.current_step || "na fila")
                                    font.pixelSize: 11
                                    color: Theme.surfaceTextMedium
                                }

                                Repeater {
                                    model: liveCard.jobs.length > 1 ? liveCard.jobs.slice(0, 3) : []

                                    Item {
                                        width: liveCol.width
                                        height: 14

                                        Rectangle {
                                            id: jdot
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 5
                                            height: 5
                                            radius: 2.5
                                            color: modelData.state === "failure" ? src.critical
                                                : modelData.state === "success" ? src.good : Theme.primary
                                        }
                                        StyledText {
                                            anchors.left: jdot.right
                                            anchors.leftMargin: 6
                                            anchors.right: jsteps.left
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            elide: Text.ElideRight
                                            wrapMode: Text.NoWrap
                                            text: modelData.name + (modelData.current_step ? " · " + modelData.current_step : "")
                                            font.pixelSize: 11
                                            color: Theme.surfaceTextSecondary
                                        }
                                        StyledText {
                                            id: jsteps
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.steps_done + "/" + modelData.steps_total
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 10
                                            color: Theme.surfaceTextSecondary
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openRun(modelData.url)
                            }
                        }
                    }

                    Item {
                        visible: root.brokenList.length > 0
                        width: parent.width
                        height: 36

                        StyledText {
                            id: hero
                            anchors.left: parent.left
                            anchors.baseline: parent.bottom
                            anchors.baselineOffset: -6
                            text: root.brokenList.length
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 30
                            font.weight: Font.DemiBold
                            color: src.critical
                        }
                        StyledText {
                            anchors.left: hero.right
                            anchors.leftMargin: 8
                            anchors.baseline: hero.baseline
                            text: root.brokenList.length === 1 ? "quebrado" : "quebrados"
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
                                text: "MAIS ANTIGO"
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                font.letterSpacing: 1
                                color: Theme.surfaceTextSecondary
                            }
                            StyledText {
                                anchors.right: parent.right
                                text: root.brokenList.length > 0 ? "há " + src.elapsed(root.brokenList[0].at) : ""
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                                color: Theme.surfaceText
                            }
                        }
                    }

                    // Quebrados, o mais antigo primeiro: deploy parado
                    // envelhece, e 41 dias é pior notícia que 2 horas.
                    Column {
                        visible: root.brokenList.length > 0
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: root.brokenList

                            Rectangle {
                                width: body.width
                                height: root.commitTitle === "never" ? 24 : 40
                                radius: 6
                                color: hov.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.06) : "transparent"

                                Rectangle {
                                    id: fdot
                                    x: 6
                                    y: 9
                                    width: 7
                                    height: 7
                                    radius: 3.5
                                    color: src.critical
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
                                    text: modelData.name + (src.branchTag(modelData.branch) !== "" ? "  ·  " + modelData.branch : "")
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                }
                                StyledText {
                                    id: fage
                                    anchors.right: parent.right
                                    anchors.rightMargin: 6
                                    anchors.verticalCenter: fdot.verticalCenter
                                    text: hov.containsMouse ? "abrir run ↗" : src.elapsed(modelData.at)
                                    font.family: hov.containsMouse ? Theme.fontFamily : "JetBrainsMono Nerd Font"
                                    font.pixelSize: hov.containsMouse ? 11 : 12
                                    color: hov.containsMouse ? Theme.primary : src.critical
                                }
                                StyledText {
                                    visible: root.commitTitle !== "never"
                                    anchors.left: fname.left
                                    anchors.right: parent.right
                                    anchors.rightMargin: 6
                                    anchors.top: fname.bottom
                                    anchors.topMargin: 1
                                    elide: Text.ElideRight
                                    wrapMode: Text.NoWrap
                                    text: modelData.error || modelData.title || ""
                                    font.pixelSize: 11
                                    color: Theme.surfaceTextSecondary
                                }

                                MouseArea {
                                    id: hov
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.openRun(modelData.url)
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: root.brokenList.length > 0 && root.restList.length > 0
                        width: parent.width
                        height: 1
                        color: Theme.withAlpha(Theme.outline, 0.25)
                    }

                    StyledText {
                        visible: root.restList.length > 0
                        text: "EM DIA · ÚLTIMO DEPLOY"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1
                        color: Theme.surfaceTextSecondary
                    }

                    // Em dia vira grade: serve de contexto, não pede ação.
                    // Com a preferência "always" volta a ser lista, porque aí
                    // o título do commit precisa de largura.
                    Grid {
                        visible: root.restList.length > 0
                        width: parent.width
                        columns: root.commitTitle === "always" ? 1 : 2
                        columnSpacing: 16
                        rowSpacing: root.commitTitle === "always" ? 2 : 6

                        Repeater {
                            model: root.restList

                            Item {
                                width: root.commitTitle === "always" ? body.width : (body.width - 16) / 2
                                height: root.commitTitle === "always" ? 40 : 18

                                Rectangle {
                                    id: odot
                                    anchors.left: parent.left
                                    y: 6
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: modelData.state === "success" ? Theme.withAlpha(src.good, 0.8) : Theme.withAlpha(Theme.surfaceText, 0.3)
                                }
                                StyledText {
                                    id: oname
                                    anchors.left: odot.right
                                    anchors.leftMargin: 7
                                    anchors.right: oage.left
                                    anchors.rightMargin: 6
                                    anchors.verticalCenter: odot.verticalCenter
                                    elide: Text.ElideRight
                                    wrapMode: Text.NoWrap
                                    text: modelData.name
                                    font.pixelSize: 12
                                    color: ohov.containsMouse ? Theme.surfaceText : Theme.surfaceTextMedium
                                }
                                StyledText {
                                    id: oage
                                    anchors.right: parent.right
                                    anchors.verticalCenter: odot.verticalCenter
                                    text: src.elapsed(modelData.at)
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                    color: Theme.surfaceTextSecondary
                                }
                                StyledText {
                                    visible: root.commitTitle === "always"
                                    anchors.left: oname.left
                                    anchors.right: parent.right
                                    anchors.top: oname.bottom
                                    anchors.topMargin: 1
                                    elide: Text.ElideRight
                                    wrapMode: Text.NoWrap
                                    text: modelData.title || ""
                                    font.pixelSize: 11
                                    color: Theme.surfaceTextSecondary
                                }

                                MouseArea {
                                    id: ohov
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.openRun(modelData.url)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
