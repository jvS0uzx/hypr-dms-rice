import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "fleet"

    StyledText {
        text: "Frota"
        font.pixelSize: Theme.fontSizeLarge
        color: Theme.surfaceText
    }

    StyledText {
        text: "Máquinas e bancos vêm de ~/.config/ricestat/hosts.txt. O probe é somente leitura e a resposta mede menos de 200 bytes por máquina, de minuto em minuto."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceTextMedium
    }

    StyledText {
        text: "Cada medida entra no briefing a partir do seu próprio limiar. Disco sobe devagar e merece aviso cedo; cpu alta costuma ser build em andamento."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceTextMedium
    }

    SliderSetting {
        settingKey: "warnDisk"
        label: "Avisar de disco a partir de"
        defaultValue: 60
        minimum: 40
        maximum: 95
        unit: "%"
    }

    SliderSetting {
        settingKey: "warnCpu"
        label: "Avisar de cpu a partir de"
        defaultValue: 85
        minimum: 50
        maximum: 99
        unit: "%"
    }

    SliderSetting {
        settingKey: "warnMem"
        label: "Avisar de memória a partir de"
        defaultValue: 85
        minimum: 50
        maximum: 99
        unit: "%"
    }

    SliderSetting {
        settingKey: "warnStopped"
        label: "Avisar de contêiner parado a partir de (0 desliga)"
        defaultValue: 0
        minimum: 0
        maximum: 20
        unit: ""
    }
}
