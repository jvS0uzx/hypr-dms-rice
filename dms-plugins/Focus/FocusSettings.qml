import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "focus"

    StyledText {
        text: "Foco"
        font.pixelSize: Theme.fontSizeLarge
        color: Theme.surfaceText
    }

    StyledText {
        text: "O coletor amostra a janela ativa do Hyprland a cada 15 segundos e resolve o projeto pelo diretório de trabalho do processo. Quando a janela não está sob um repositório, a categoria vira a classe da janela. Nada sai da máquina."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceTextMedium
    }

    SelectionSetting {
        settingKey: "period"
        label: "Tempo mostrado na pílula"
        options: [
            { label: "Hoje", value: "today" },
            { label: "Últimos 7 dias", value: "week" }
        ]
        defaultValue: "today"
    }

    ToggleSetting {
        settingKey: "showProject"
        label: "Mostrar o nome do projeto na pílula"
        defaultValue: true
    }

    SliderSetting {
        settingKey: "maxRows"
        label: "Projetos listados no popout e na área de trabalho"
        defaultValue: 6
        minimum: 3
        maximum: 10
        unit: ""
    }
}
