import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "tailnet"

    StyledText {
        text: "Tailnet"
        font.pixelSize: Theme.fontSizeLarge
        color: Theme.surfaceText
    }

    StyledText {
        text: "Os dados vêm do ricestat. Nada é coletado por este widget."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceTextMedium
    }

    ToggleSetting {
        settingKey: "hideWhenHealthy"
        label: "Esconder a pílula quando tudo está online"
        defaultValue: false
    }
}
