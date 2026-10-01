// A pergunta que esta pílula responde é "posso continuar trabalhando?", não
// "quanto gastei no mês". O limite do Claude Code é uma janela de 5 horas; o
// que importa é quanto dela já foi, a que ritmo, e quando reseta.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var q: src.quota
    property var agents: src.agents
    property bool hasQuota: src.hasQuota
    property bool anyActive: src.hasData && src.agents.active_count > 0

    // Fração da janela já decorrida. É o eixo do trilho: tempo, não consumo.
    property real elapsedFrac: (hasQuota && q.block_minutes > 0)
        ? Math.max(0, Math.min(1, q.minutes_elapsed / q.block_minutes)) : 0

    property int hourTicks: hasQuota ? Math.max(0, Math.round(q.block_minutes / 60) - 1) : 4

    // limit_hits cobre sete dias. Um limite batido anteontem não é alarme
    // agora — só conta o que caiu dentro desta janela.
    property int hitsNow: {
        if (!hasQuota || !q.limit_hits) return 0
        var t0 = Date.parse(q.block_start), n = 0
        for (var i = 0; i < q.limit_hits.length; i++)
            if (Date.parse(q.limit_hits[i].at) >= t0) n++
        return n
    }

    // Sem teto declarado pela conta, a maior janela já registrada é a única
    // referência honesta de "cheio". Não invento porcentagem de limite.
    property string alertKind: {
        if (!hasQuota) return "off"
        if (hitsNow > 0) return "limite"
        if (q.peak_block_tokens > 0 && q.projected > q.peak_block_tokens) return "pico"
        return "normal"
    }

    readonly property color warning: "#d29922"
    readonly property color critical: "#f85149"

    // Teto no glifo: a pílula é uma coluna (glifo, número, trilho) e não pode
    // passar da espessura do widget na barra.
    readonly property real pillIcon: Math.max(14, Math.min(root.iconSize, 20))

    // Cor de estado nunca anda sozinha: sempre com o glifo e o rótulo abaixo.
    readonly property color alertColor: alertKind === "limite" ? critical
                                      : alertKind === "pico" ? warning
                                      : Theme.surfaceTextMedium
    readonly property string alertGlyph: alertKind === "limite" ? "block"
                                       : alertKind === "pico" ? "trending_up" : "smart_toy"
    readonly property string alertShort: alertKind === "limite" ? "limite"
                                       : alertKind === "pico" ? "pico" : ""
    readonly property string alertLine: alertKind === "limite"
        ? "limite batido dentro desta janela"
        : "a projeção passa a maior janela já registrada"

    // 97% dos tokens desta janela sao cache relido. O numero grande sozinho
    // engana, entao a divisao anda colada nele. A cor forte fica no que foi
    // processado agora; o volume relido fica em tinta neutra, recessiva.
    property var mix: {
        if (!hasQuota) return []
        var ti = q.block_in || 0, to = q.block_out || 0
        var tr = q.block_cache_read || 0, tw = q.block_cache_write || 0
        var tot = ti + to + tr + tw
        if (tot <= 0) return []
        // A cor segue o campo, nunca a posicao: ordenar por valor muda so a
        // ordem de leitura, cada faixa mantem o tom do seu campo.
        var defs = [
            { key: "cache lido",    v: tr, c: Theme.withAlpha(Theme.surfaceText, 0.22) },
            { key: "cache escrito", v: tw, c: Theme.withAlpha(Theme.primary, 0.45) },
            { key: "saída",         v: to, c: Theme.withAlpha(Theme.primary, 0.72) },
            { key: "entrada",       v: ti, c: Theme.primary }
        ]
        defs.sort(function (a, b) { return b.v - a.v })
        var out = []
        for (var i = 0; i < defs.length; i++)
            out.push({ key: defs[i].key, v: defs[i].v, c: defs[i].c,
                       frac: defs[i].v / tot,
                       value: src.tokens(defs[i].v),
                       pct: src.pct(defs[i].v, tot) })
        return out
    }

    property bool hasIdle: hasQuota && q.idle_sec !== undefined && q.idle_sec !== null
    property string idleLine: hasIdle ? "última resposta " + src.since(q.idle_sec) : ""

    // Janela rolante de sete dias: nao tem ancora de reset, entao nunca "reseta
    // em". So "ultimos 7 dias".
    property bool hasWeek: hasQuota && q.week_tokens !== undefined && q.week_tokens !== null
    property string weekLine: hasWeek
        ? "últimos 7 dias    " + src.tokens(q.week_tokens) + " tokens    "
          + String(q.week_requests || 0) + " respostas"
        : ""

    property var figures: hasQuota ? [
        { value: src.tokens(Math.round(q.burn_per_min)) + "/min", label: "ritmo" },
        { value: src.tokens(q.projected), label: "projeção" },
        { value: String(q.block_requests), label: "respostas" },
        { value: String(src.hasData ? agents.active_count : 0), label: "ativos" }
    ] : []

    property var costs: src.hasData ? [
        { value: src.money(agents.today_usd), label: "hoje" },
        { value: src.money(agents.week_usd), label: "semana" },
        { value: src.money(agents.month_usd), label: "mês" }
    ] : []

    // Componente inline (QML 6): arquivo irmão não resolve como tipo dentro de
    // um plugin do DMS. Nada aqui lê id externo — tudo entra por propriedade.
    component Stat: Column {
        property string label
        property string value
        property color valueColor: Theme.surfaceText
        spacing: 2

        StyledText {
            text: parent.label
            font.pixelSize: 10
            font.weight: Font.DemiBold
            font.letterSpacing: 1
            color: Theme.surfaceTextSecondary
        }
        StyledText {
            text: parent.value
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 14
            color: parent.valueColor
        }
    }

    component Caps: StyledText {
        font.pixelSize: 10
        font.weight: Font.DemiBold
        font.letterSpacing: 1
        color: Theme.surfaceTextSecondary
    }

    property real peak: hasQuota ? Math.max(1, q.peak_block_tokens || 0) : 1

    // Altura do popout segue o que existe: faixa de alerta e lista de limites
    // só ocupam espaço quando têm o que dizer.
    property int popH: {
        if (!hasQuota) return 220
        var h = 530
        if (alertKind !== "normal") h += 40
        if (q.limit_hits && q.limit_hits.length > 0) h += 22 + Math.min(q.limit_hits.length, 3) * 16
        return h
    }

    // Leitor inline de propósito: arquivo QML irmão não resolve como tipo
    // dentro de um plugin do DMS — o componente não nasce e não há erro
    // visível. Duplicar o leitor por superfície é o preço.
    QtObject {
        id: src
        property var snap: null
        property var agents: snap && snap.agents ? snap.agents : null
        property var quota: snap && snap.quota ? snap.quota : null
        property bool hasQuota: quota !== null && quota.active
        property bool hasData: agents !== null
        property string loadError: snap && snap.errors ? (snap.errors.agents || "") : ""
        readonly property color good: "#3fb950"
        readonly property color warning: "#d29922"
        readonly property color critical: "#f85149"

        function money(v) { return (v === undefined || v === null) ? "—" : "$" + v.toFixed(2) }
        function tokens(n) {
            if (n === undefined || n === null) return "—"
            if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
            if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
            if (n >= 1e3) return Math.round(n / 1e3) + "k"
            return String(n)
        }
        function hm(minutes) {
            if (minutes === undefined || minutes < 0) return "—"
            var h = Math.floor(minutes / 60), m = minutes % 60
            return h > 0 ? h + "h" + (m < 10 ? "0" : "") + m : m + "min"
        }
        function clock(iso) {
            if (!iso) return ""
            var d = new Date(iso)
            return ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2)
        }
        function shortModel(name) { return String(name).replace("claude-", "").replace("-20251001", "") }
        function pct(part, whole) {
            if (!whole || whole <= 0) return "\u2014"
            var p = 100 * part / whole
            if (p > 0 && p < 0.1) return "<0.1%"
            return p.toFixed(1) + "%"
        }
        // "agora" abaixo de um minuto e meio: mais fino que isso o numero muda a
        // cada tique do coletor e vira ruido em vez de informacao.
        function since(sec) {
            if (sec === undefined || sec === null || sec < 0) return "\u2014"
            if (sec < 90) return "agora"
            var m = Math.round(sec / 60)
            return m < 60 ? "há " + m + "min" : "há " + hm(m)
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

    // O número da pílula é o tempo que sobra, porque é o único acionável. O
    // consumo vira o trilho fino embaixo — informa sem disputar a leitura.
    horizontalBarPill: Component {
        Column {
            id: pill
            spacing: 2

            Row {
                id: pillRow
                spacing: Theme.spacingXS

                Item {
                    width: root.pillIcon
                    height: root.pillIcon
                    anchors.verticalCenter: parent.verticalCenter

                    // Em estado normal, o logo da IA medida; em alerta (limite, pico), o
                    // símbolo do alerta, que é o que precisa ser lido de relance.
                    Image {
                        anchors.fill: parent
                        visible: root.alertKind === "normal" || root.alertKind === "off"
                        sourceSize: Qt.size(root.pillIcon * 2, root.pillIcon * 2)
                        source: Qt.resolvedUrl("icons/claude.svg")
                        opacity: root.alertKind === "off" ? 0.5 : 1
                    }
                    DankIcon {
                        anchors.fill: parent
                        visible: !(root.alertKind === "normal" || root.alertKind === "off")
                        name: root.alertGlyph
                        size: root.pillIcon
                        color: root.alertColor
                    }

                    // Agents rodando agora. Ponto parado, não piscando: barra
                    // de status não é lugar de animação perpétua.
                    Rectangle {
                        visible: root.anyActive
                        width: 5
                        height: 5
                        radius: 2.5
                        anchors.right: parent.right
                        anchors.top: parent.top
                        color: Theme.primary
                    }
                }

                StyledText {
                    text: root.hasQuota ? src.hm(root.q.minutes_left) : "—"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    visible: root.alertShort !== ""
                    text: root.alertShort
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceTextMedium
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Rectangle {
                width: pillRow.width
                height: 2
                radius: 1
                color: Theme.withAlpha(Theme.surfaceText, 0.16)
                visible: root.hasQuota

                Rectangle {
                    width: parent.width * root.elapsedFrac
                    height: parent.height
                    radius: 1
                    color: Theme.primary

                    Behavior on width {
                        NumberAnimation { duration: 620; easing.type: Easing.OutCubic }
                    }
                }
            }
        }
    }

    verticalBarPill: Component {
        Column {
            id: vpill
            spacing: 2

            Item {
                width: root.pillIcon
                height: root.pillIcon
                anchors.horizontalCenter: parent.horizontalCenter

                // Em estado normal, o logo da IA medida; em alerta (limite, pico), o
                // símbolo do alerta, que é o que precisa ser lido de relance.
                Image {
                    anchors.fill: parent
                    visible: root.alertKind === "normal" || root.alertKind === "off"
                    sourceSize: Qt.size(root.pillIcon * 2, root.pillIcon * 2)
                    source: Qt.resolvedUrl("icons/claude.svg")
                    opacity: root.alertKind === "off" ? 0.5 : 1
                }
                DankIcon {
                    anchors.fill: parent
                    visible: !(root.alertKind === "normal" || root.alertKind === "off")
                    name: root.alertGlyph
                    size: root.pillIcon
                    color: root.alertColor
                }

                Rectangle {
                    visible: root.anyActive
                    width: 5
                    height: 5
                    radius: 2.5
                    anchors.right: parent.right
                    anchors.top: parent.top
                    color: Theme.primary
                }
            }

            StyledText {
                id: vnum
                text: root.hasQuota ? src.hm(root.q.minutes_left) : "—"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Rectangle {
                width: vnum.width
                height: 2
                radius: 1
                color: Theme.withAlpha(Theme.surfaceText, 0.16)
                visible: root.hasQuota
                anchors.horizontalCenter: parent.horizontalCenter

                Rectangle {
                    width: parent.width * root.elapsedFrac
                    height: parent.height
                    radius: 1
                    color: Theme.primary

                    Behavior on width {
                        NumberAnimation { duration: 620; easing.type: Easing.OutCubic }
                    }
                }
            }
        }
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
                            text: "CLAUDE · COTA"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1.4
                            color: Theme.surfaceTextMedium
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            visible: root.hasIdle

                            Rectangle {
                                width: 6
                                height: 6
                                radius: 3
                                anchors.verticalCenter: parent.verticalCenter
                                color: root.hasIdle && root.q.idle_sec < 120 ? Theme.primary : Theme.withAlpha(Theme.surfaceText, 0.3)
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.idleLine
                                    + (root.anyActive ? " · " + root.agents.active_count + (root.agents.active_count === 1 ? " sessão" : " sessões") : "")
                                font.pixelSize: 11
                                color: Theme.surfaceTextMedium
                            }
                        }
                    }

                    StyledText {
                        visible: !root.hasQuota
                        width: parent.width
                        text: src.loadError !== "" ? src.loadError
                            : (src.snap ? "nenhuma janela aberta — a próxima começa na primeira mensagem."
                                        : "Snapshot não encontrado.\nsystemctl --user status ricestat")
                        font.pixelSize: 13
                        color: Theme.surfaceText
                    }

                    // Alerta vira faixa, com glifo e frase: cor de estado
                    // nunca decide sozinha.
                    Rectangle {
                        visible: root.hasQuota && root.alertKind !== "normal"
                        width: parent.width
                        height: 28
                        radius: 6
                        color: Theme.withAlpha(root.alertColor, 0.12)

                        DankIcon {
                            id: alertIco
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            name: root.alertGlyph
                            size: 16
                            color: root.alertColor
                        }
                        StyledText {
                            anchors.left: alertIco.right
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            text: root.alertLine
                            font.pixelSize: 12
                            color: Theme.surfaceText
                        }
                    }

                    // Tempo restante é o número alto: decide se vale começar
                    // uma tarefa grande agora ou esperar a virada.
                    Item {
                        visible: root.hasQuota
                        width: parent.width
                        height: 36

                        StyledText {
                            id: hoursLeft
                            anchors.left: parent.left
                            anchors.baseline: parent.bottom
                            anchors.baselineOffset: -6
                            text: root.hasQuota ? src.hm(root.q.minutes_left) : ""
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 30
                            font.weight: Font.DemiBold
                            color: Theme.surfaceText
                        }
                        StyledText {
                            anchors.left: hoursLeft.right
                            anchors.leftMargin: 6
                            anchors.baseline: hoursLeft.baseline
                            text: "restantes"
                            font.pixelSize: 12
                            color: Theme.surfaceTextMedium
                        }
                        Column {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            spacing: 1

                            Caps {
                                anchors.right: parent.right
                                text: "JANELA"
                            }
                            StyledText {
                                anchors.right: parent.right
                                text: root.hasQuota ? src.clock(root.q.block_start) + "–" + src.clock(root.q.block_end) : ""
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                                color: Theme.surfaceText
                            }
                        }
                    }

                    // Régua da janela: tempo, não consumo. Uma risca por hora.
                    Item {
                        visible: root.hasQuota
                        width: parent.width
                        height: 8

                        Rectangle {
                            id: timeRail
                            anchors.fill: parent
                            radius: 4
                            color: Theme.withAlpha(Theme.surfaceText, 0.10)

                            Rectangle {
                                width: timeRail.width * root.elapsedFrac
                                height: parent.height
                                radius: parent.radius
                                color: Theme.primary
                            }
                        }
                        Repeater {
                            model: root.hourTicks
                            Rectangle {
                                x: Math.round(timeRail.width * (index + 1) / (root.hourTicks + 1))
                                width: 1
                                height: timeRail.height
                                color: Theme.withAlpha(Theme.surfaceContainer, 0.9)
                            }
                        }
                    }

                    // Tokens contra o recorde próprio, projeção como risca.
                    Column {
                        visible: root.hasQuota
                        width: parent.width
                        spacing: 6

                        Item {
                            width: parent.width
                            height: 16

                            Caps {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "TOKENS"
                            }
                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                StyledText {
                                    text: root.hasQuota ? src.tokens(root.q.block_tokens) : ""
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 13
                                    color: Theme.surfaceText
                                }
                                StyledText {
                                    text: "/ recorde " + src.tokens(root.peak)
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 12
                                    color: Theme.surfaceTextSecondary
                                }
                            }
                        }

                        Item {
                            width: parent.width
                            height: 12

                            Rectangle {
                                id: tokRail
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                height: 6
                                radius: 3
                                color: Theme.withAlpha(Theme.surfaceText, 0.10)

                                Rectangle {
                                    width: root.hasQuota ? Math.max(2, tokRail.width * Math.min(1, root.q.block_tokens / root.peak)) : 0
                                    height: parent.height
                                    radius: parent.radius
                                    color: root.alertKind === "pico" ? root.warning : Theme.withAlpha(Theme.surfaceText, 0.6)
                                }
                            }
                            Rectangle {
                                x: root.hasQuota ? Math.min(tokRail.width - 2, Math.round(tokRail.width * Math.min(1, (root.q.projected || 0) / root.peak))) : 0
                                width: 2
                                height: parent.height
                                radius: 1
                                color: root.alertKind === "pico" ? root.warning : Theme.surfaceText
                            }
                        }

                        StyledText {
                            width: parent.width
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            text: root.hasQuota ? "no ritmo atual, fecha em " + src.tokens(root.q.projected) + " às " + src.clock(root.q.block_end) : ""
                            font.pixelSize: 11
                            color: root.alertKind === "pico" ? root.warning : Theme.surfaceTextMedium
                        }
                    }

                    // Composição: 97% é cache relido, e o número grande
                    // sozinho engana. A cor forte fica no que é novo.
                    Column {
                        visible: root.mix.length > 0
                        width: parent.width
                        spacing: 6

                        Row {
                            id: mixBar
                            width: parent.width
                            height: 6
                            spacing: 1

                            Repeater {
                                model: root.mix
                                Rectangle {
                                    visible: modelData.v > 0
                                    height: mixBar.height
                                    radius: 2
                                    width: Math.max(2, (mixBar.width - 3) * modelData.frac)
                                    color: modelData.c
                                }
                            }
                        }

                        Grid {
                            width: parent.width
                            columns: 2
                            columnSpacing: 16
                            rowSpacing: 2

                            Repeater {
                                model: root.mix

                                Item {
                                    width: (body.width - 16) / 2
                                    height: 16

                                    Rectangle {
                                        id: sw
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 8
                                        height: 8
                                        radius: 2
                                        color: modelData.c
                                    }
                                    StyledText {
                                        anchors.left: sw.right
                                        anchors.leftMargin: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.key
                                        font.pixelSize: 11
                                        color: Theme.surfaceTextMedium
                                    }
                                    StyledText {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.value + "  " + modelData.pct
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 11
                                        color: Theme.surfaceTextSecondary
                                    }
                                }
                            }
                        }
                    }

                    Grid {
                        visible: root.hasQuota
                        width: parent.width
                        columns: 4

                        Repeater {
                            model: root.figures
                            Stat {
                                width: body.width / 4
                                label: modelData.label.toUpperCase()
                                value: modelData.value
                            }
                        }
                    }

                    Rectangle {
                        visible: root.hasQuota
                        width: parent.width
                        height: 1
                        color: Theme.withAlpha(Theme.outline, 0.25)
                    }

                    // Retroativo: no popout abre em 48 horas, porque é aqui
                    // que se vem conferir o passado. Hover mostra a hora.
                    Item {
                        id: hist
                        visible: src.quota !== null
                        width: parent.width
                        height: 150

                        property bool hourly: true
                        property int hover: -1
                        property var blocks: src.quota && src.quota.recent ? src.quota.recent : []
                        property var hours: src.quota && src.quota.hourly ? src.quota.hourly : []
                        property var series: hourly && hours.length > 0 ? hours : blocks
                        property real chartTop: 22
                        property real axis: 16
                        property real chartH: height - chartTop - axis
                        property real colW: series.length > 0 ? width / series.length : width
                        property real scaleMax: {
                            if (!hourly) return root.peak
                            var m = 1
                            for (var i = 0; i < hours.length; i++) m = Math.max(m, hours[i].tokens)
                            return m
                        }

                        Item {
                            width: parent.width
                            height: 16

                            Row {
                                spacing: 12
                                anchors.verticalCenter: parent.verticalCenter

                                Repeater {
                                    model: [{ k: true, t: "48 HORAS" }, { k: false, t: "JANELAS" }]
                                    StyledText {
                                        text: modelData.t
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        font.letterSpacing: 1
                                        color: hist.hourly === modelData.k ? Theme.primary : Theme.surfaceTextSecondary

                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -4
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: hist.hourly = modelData.k
                                        }
                                    }
                                }
                            }

                            StyledText {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: {
                                    if (hist.hover < 0 || hist.hover >= hist.series.length)
                                        return hist.hourly ? "pico " + src.tokens(hist.scaleMax) + "/h" : "recorde " + src.tokens(root.peak)
                                    var it = hist.series[hist.hover]
                                    var d = new Date(it.start)
                                    var when = d.getDate() + "/" + (d.getMonth() + 1) + " " + ("0" + d.getHours()).slice(-2) + "h"
                                    return when + " · " + src.tokens(it.tokens)
                                        + (hist.hourly ? " · " + (it.requests || 0) + " pedidos" : "")
                                }
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                color: hist.hover >= 0 ? Theme.surfaceText : Theme.surfaceTextSecondary
                            }
                        }

                        Row {
                            y: hist.chartTop
                            width: parent.width
                            spacing: 4
                            Repeater {
                                model: Math.floor(hist.width / 8)
                                Rectangle {
                                    width: 4
                                    height: 1
                                    color: Theme.withAlpha(Theme.surfaceText, 0.3)
                                }
                            }
                        }

                        Repeater {
                            model: hist.series

                            Item {
                                x: index * hist.colW
                                y: hist.chartTop
                                width: hist.colW
                                height: hist.chartH + hist.axis

                                property bool current: root.hasQuota && (hist.hourly
                                    ? index === hist.series.length - 1
                                    : modelData.start === root.q.block_start)
                                property bool inBlock: hist.hourly && root.hasQuota
                                    && new Date(modelData.start) >= new Date(root.q.block_start)

                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: hist.chartH - height
                                    width: Math.max(2, Math.min(hist.hourly ? hist.colW - 2 : 56, hist.colW * (hist.hourly ? 0.8 : 0.6)))
                                    height: modelData.tokens > 0 ? Math.max(2, hist.chartH * Math.min(1, modelData.tokens / hist.scaleMax)) : 0
                                    radius: hist.hourly ? 1 : 3
                                    color: parent.current ? Theme.primary
                                        : hist.hover === index ? Theme.withAlpha(Theme.surfaceText, 0.6)
                                        : parent.inBlock ? Theme.withAlpha(Theme.primary, 0.55)
                                        : Theme.withAlpha(Theme.surfaceText, 0.28)
                                }
                                StyledText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: hist.chartH + 3
                                    visible: !hist.hourly || new Date(modelData.start).getHours() % 6 === 0
                                    text: hist.hourly ? new Date(modelData.start).getHours() + "h" : src.clock(modelData.start)
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                    color: Theme.surfaceTextSecondary
                                }
                            }
                        }

                        MouseArea {
                            y: hist.chartTop
                            width: parent.width
                            height: hist.chartH + hist.axis
                            hoverEnabled: true
                            onPositionChanged: mouse => hist.hover = Math.floor(mouse.x / hist.colW)
                            onExited: hist.hover = -1
                        }
                    }

                    // Rodapé: o que não é da janela — semana rolante, custo e
                    // modelo. Contexto, em tinta baixa.
                    Column {
                        visible: src.hasData
                        width: parent.width
                        spacing: 4

                        StyledText {
                            visible: root.weekLine !== ""
                            width: parent.width
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            text: root.weekLine
                            font.pixelSize: 11
                            color: Theme.surfaceTextMedium
                        }
                        StyledText {
                            width: parent.width
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            text: {
                                var parts = []
                                for (var i = 0; i < root.costs.length; i++)
                                    parts.push(root.costs[i].label + " " + root.costs[i].value)
                                return "custo    " + parts.join("    ")
                            }
                            font.pixelSize: 11
                            color: Theme.surfaceTextSecondary
                        }
                        StyledText {
                            visible: root.hasQuota && root.q.by_model && root.q.by_model.length > 0
                            width: parent.width
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            text: {
                                if (!root.hasQuota || !root.q.by_model) return ""
                                var parts = []
                                for (var i = 0; i < root.q.by_model.length; i++)
                                    parts.push(src.shortModel(root.q.by_model[i].model) + " " + src.pct(root.q.by_model[i].tokens, root.q.block_tokens))
                                return "modelos    " + parts.join("    ")
                            }
                            font.pixelSize: 11
                            color: Theme.surfaceTextSecondary
                        }
                    }

                    Column {
                        visible: root.hasQuota && root.q.limit_hits && root.q.limit_hits.length > 0
                        width: parent.width
                        spacing: 2

                        Caps {
                            text: "LIMITES BATIDOS · 7 DIAS"
                            color: root.critical
                        }
                        Repeater {
                            model: root.hasQuota && root.q.limit_hits ? root.q.limit_hits.slice(-3) : []
                            StyledText {
                                text: new Date(modelData.at).toLocaleString(Qt.locale(), "dd/MM HH:mm")
                                    + "  " + modelData.kind + "  · volta " + src.clock(modelData.resets_at)
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                color: Theme.surfaceTextMedium
                            }
                        }
                    }
                }
            }
        }
    }
}
