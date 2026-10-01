import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "deployRadar"

    StyledText {
        text: "Deploy Radar"
        font.pixelSize: Theme.fontSizeLarge
        color: Theme.surfaceText
    }

    StyledText {
        text: "Lê o último run de deploy.yml em cada repositório de ~/.config/ricestat/repos.txt. Somente leitura — o widget não redispara execução."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceTextMedium
    }

    SelectionSetting {
        settingKey: "commitTitle"
        label: "Mostrar a mensagem do commit"
        options: [
            { label: "Só nas que falharam", value: "broken" },
            { label: "Nunca", value: "never" },
            { label: "Sempre", value: "always" }
        ]
        defaultValue: "broken"
    }

    ToggleSetting {
        settingKey: "onlyWhenBroken"
        label: "Mostrar a pílula só quando algo está falhando"
        defaultValue: false
    }
}
