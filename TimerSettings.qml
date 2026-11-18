import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "duxTimer"

    StyledText {
        width: parent.width
        text: "Quick Timer"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Start timers, alarms, or a stopwatch from the launcher (type \"quick timer 10\", \"quick alarm 7:30AM\", or \"quick stopwatch\") or with: dms ipc call quicktimer stopwatch"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "playSound"
        label: "Play sound"
        description: "Play an alert sound when the timer finishes"
        defaultValue: true
    }

    SliderSetting {
        settingKey: "autoDismiss"
        label: "Auto-dismiss"
        description: "Remove the bar pill this long after the timer finishes (0 = stay until dismissed)"
        defaultValue: 30
        minimum: 0
        maximum: 300
        unit: "sec"
    }
}
