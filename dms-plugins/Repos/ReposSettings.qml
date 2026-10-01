import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "repos"

    StyledText {
        text: "Repositórios"
        font.pixelSize: Theme.fontSizeLarge
        color: Theme.surfaceText
    }

    StyledText {
        text: "Estado lido do snapshot do ricestat. Nada é coletado aqui e nenhum comando git é disparado — o widget só lê."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceTextMedium
    }

    StyledText {
        text: "A barra mede o que um `git add -A` levaria junto: o segmento claro são os arquivos que o git ainda não rastreia, e é deles que vem o acidente."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceTextMedium
    }

    SliderSetting {
        settingKey: "heavyAt"
        label: "Tratar como muitas alterações a partir de"
        defaultValue: 20
        minimum: 3
        maximum: 120
        unit: " arquivos"
    }

    ToggleSetting {
        settingKey: "hideLight"
        label: "Esconder repositórios abaixo desse número"
        description: "Um ou dois arquivos abertos quase sempre é trabalho em andamento."
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "hideWhenClean"
        label: "Esconder a pílula quando não há pendência"
        defaultValue: false
    }
}
