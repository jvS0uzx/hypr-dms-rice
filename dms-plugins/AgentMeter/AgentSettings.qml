import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "agentMeter"

    StyledText {
        text: "Agent Meter"
        font.pixelSize: Theme.fontSizeLarge
        color: Theme.surfaceText
    }

    StyledText {
        text: "Custo lido do campo cost-state dos logs de sessão. O valor já vem calculado — nada é estimado aqui."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceTextMedium
    }

    SelectionSetting {
        settingKey: "pillMetric"
        label: "Valor na barra"
        options: [
            { label: "Hoje", value: "today" },
            { label: "Semana", value: "week" },
            { label: "Mês", value: "month" }
        ]
        defaultValue: "today"
    }
}
