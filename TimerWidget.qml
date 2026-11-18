import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "quick-timer"
    popoutWidth: 320
    popoutHeight: Math.min(620, 280 + Math.ceil(root.instances.length / 3) * 44
                           + (root.mode === "stopwatch" && root.laps && root.laps.length > 0 ? 80 : 0))

    property string mode: "timer"
    property string phase: "idle"
    property double endAt: 0
    property double remainingMs: 0
    property double totalMs: 0
    property string timerLabel: ""
    property string alarmTime: ""
    property double startAt: 0
    property double accumulatedMs: 0
    property var laps: []
    property var instances: []
    property string instanceId: ""
    property double nowMs: Date.now()
    property string lastRaw: ""

    // The pill only exists while a timer, alarm, or stopwatch is active (running, paused or ringing).
    visible: phase !== "idle"

    readonly property double remMs: phase === "running" ? Math.max(0, endAt - nowMs)
                                  : phase === "paused" ? remainingMs : 0
    readonly property double stopwatchMs: mode === "stopwatch"
                                  ? ((phase === "running" ? Math.max(0, nowMs - startAt) : 0) + accumulatedMs)
                                  : 0
    readonly property real progress: totalMs > 0 ? Math.min(1, remMs / totalMs) : 0
    readonly property string pillText: phase === "ringing" ? "Done"
                                     : mode === "alarm" ? (alarmTime !== "" ? alarmTime : fmt(remMs))
                                     : mode === "stopwatch" ? fmtElapsed(stopwatchMs, false)
                                     : fmt(remMs)
    readonly property int activeCount: instances.filter(x => x.phase !== "idle").length
    readonly property color pillColor: phase === "ringing" ? Theme.error
                                     : phase === "paused" ? Theme.surfaceVariantText
                                     : Theme.primary
    readonly property string pillIcon: phase === "ringing" ? "alarm_on"
                                     : phase === "paused" ? "pause"
                                     : mode === "alarm" ? "alarm" : "timer"

    function fmt(ms) {
        const total = Math.ceil(ms / 1000)
        const h = Math.floor(total / 3600)
        const m = Math.floor((total % 3600) / 60)
        const s = total % 60
        const p = n => (n < 10 ? "0" : "") + n
        return h > 0 ? h + ":" + p(m) + ":" + p(s) : p(m) + ":" + p(s)
    }

    function fmtElapsed(ms, showTenths) {
        const safeMs = Math.max(0, ms)
        const totalSec = Math.floor(safeMs / 1000)
        const h = Math.floor(totalSec / 3600)
        const m = Math.floor((totalSec % 3600) / 60)
        const s = totalSec % 60
        const p = n => (n < 10 ? "0" : "") + n
        const base = h > 0 ? h + ":" + p(m) + ":" + p(s) : p(m) + ":" + p(s)
        if (showTenths) {
            const tenths = Math.floor((safeMs % 1000) / 100)
            return base + "." + tenths
        }
        return base
    }

    function send(action, seconds, label, targetId) {
        PluginService.setGlobalVar("duxTimer", "cmd", JSON.stringify({
            id: Date.now() + "-" + Math.random(),
            action: action,
            seconds: seconds || 0,
            label: label || "",
            instanceId: targetId || instanceId
        }))
    }

    function selectInstance(id) {
        const item = instances.find(x => x.id === id)
        if (!item)
            return
        instanceId = item.id
        mode = item.mode || "timer"
        phase = item.phase || "idle"
        endAt = item.endAt || 0
        remainingMs = item.remainingMs || 0
        totalMs = item.totalMs || 0
        timerLabel = item.label || ""
        alarmTime = item.alarmTime || ""
        startAt = item.startAt || 0
        accumulatedMs = item.accumulatedMs || 0
        laps = Array.isArray(item.laps) ? item.laps : []
    }

    function instanceTabText(item) {
        const typeName = item.mode === "alarm" ? "Alarm" : item.mode === "stopwatch" ? "Stopwatch" : "Timer"
        if (item.label)
            return typeName + " · " + item.label
        const sameType = instances.filter(x => x.mode === item.mode)
        return sameType.length > 1 ? typeName + " " + (sameType.indexOf(item) + 1) : typeName
    }

    function sync() {
        nowMs = Date.now()
        const raw = PluginService.getGlobalVar("duxTimer", "timer", "")
        if (raw === lastRaw)
            return
        lastRaw = raw
        try {
            const t = JSON.parse(raw)
            instances = Array.isArray(t.instances) ? t.instances : (t.phase && t.phase !== "idle" ? [t] : [])
            const active = instances.find(x => x.id === (t.selectedId || t.id)) || instances[instances.length - 1]
            if (active)
                selectInstance(active.id)
            else {
                instanceId = ""
                mode = "timer"; phase = "idle"; endAt = 0; remainingMs = 0
                totalMs = 0; timerLabel = ""; alarmTime = ""; startAt = 0
                accumulatedMs = 0; laps = []
            }
        } catch (e) {
            mode = "timer"
            phase = "idle"
            endAt = 0
            remainingMs = 0
            totalMs = 0
            timerLabel = ""
            alarmTime = ""
            startAt = 0
            accumulatedMs = 0
            laps = []
        }
    }

    Timer {
        interval: root.phase === "running" ? (root.mode === "stopwatch" ? 100 : 250) : 500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.sync()
    }

    component TimerButton: StyledRect {
        id: btn
        property string icon: ""
        property string text: ""
        signal clicked()

        width: btnRow.implicitWidth + Theme.spacingM * 2
        height: 40
        radius: Theme.cornerRadius
        color: btnMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

        Row {
            id: btnRow
            anchors.centerIn: parent
            spacing: Theme.spacingXS

            DankIcon {
                visible: btn.icon !== ""
                name: btn.icon
                size: 18
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: btn.text
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: {
                    if (root.mode === "timer" || root.mode === "stopwatch") {
                        if (root.phase === "running")
                            root.send("pause")
                        else if (root.phase === "paused")
                            root.send("resume")
                    } else if (root.mode === "alarm") {
                        root.send("cancel")
                    }
                }
            }

            DankIcon {
                name: root.pillIcon
                size: root.iconSize
                color: root.pillColor
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: root.activeCount > 1 ? root.pillText + " · " + root.activeCount : root.pillText
                font.pixelSize: Theme.fontSizeMedium
                color: root.phase === "ringing" ? Theme.error : Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: {
                    if (root.mode === "timer" || root.mode === "stopwatch") {
                        if (root.phase === "running")
                            root.send("pause")
                        else if (root.phase === "paused")
                            root.send("resume")
                    } else if (root.mode === "alarm") {
                        root.send("cancel")
                    }
                }
            }

            DankIcon {
                name: root.pillIcon
                size: root.iconSize
                color: root.pillColor
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                text: root.activeCount > 1 ? root.pillText + " · " + root.activeCount : root.pillText
                font.pixelSize: Theme.fontSizeSmall
                color: root.phase === "ringing" ? Theme.error : Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: pop

            headerText: root.mode === "alarm" ? "Alarm" : (root.mode === "stopwatch" ? "Stopwatch" : "Timer")
            detailsText: root.timerLabel !== "" ? root.timerLabel
                       : root.mode === "alarm" && root.alarmTime !== "" ? "Scheduled for " + root.alarmTime
                       : root.mode === "stopwatch" ? (root.phase === "paused" ? "Paused" : "Running")
                       : root.phase === "idle" ? "Start a countdown or stopwatch" : ""
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM

                Flow {
                    visible: root.instances.length > 1
                    width: parent.width
                    spacing: Theme.spacingXS
                    Repeater {
                        model: root.instances
                        delegate: StyledRect {
                            width: Math.floor((parent.width - Theme.spacingXS * 2) / 3)
                            height: 38
                            radius: Theme.cornerRadius
                            color: modelData.id === root.instanceId ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                            StyledText {
                                anchors.centerIn: parent
                                width: parent.width - Theme.spacingS
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                color: modelData.id === root.instanceId ? Theme.primary : Theme.surfaceText
                                text: root.instanceTabText(modelData)
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectInstance(modelData.id)
                            }
                        }
                    }
                }

                StyledText {
                    visible: root.phase !== "idle"
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.phase === "ringing" ? (root.mode === "alarm" ? "Alarm!" : "Time's up")
                        : root.mode === "alarm" && root.alarmTime !== "" ? root.alarmTime
                        : root.mode === "stopwatch" ? root.fmtElapsed(root.stopwatchMs, true)
                        : root.fmt(root.remMs)
                    font.pixelSize: Theme.fontSizeXLarge * 2
                    font.weight: Font.Bold
                    color: root.phase === "ringing" ? Theme.error : Theme.surfaceText
                }

                StyledText {
                    visible: root.phase === "running" && root.mode === "alarm"
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "In " + root.fmt(root.remMs)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                StyledRect {
                    visible: (root.phase === "running" || root.phase === "paused") && root.mode !== "stopwatch"
                    width: parent.width
                    height: 6
                    radius: 3
                    color: Theme.surfaceContainerHighest

                    StyledRect {
                        width: parent.width * root.progress
                        height: parent.height
                        radius: 3
                        color: Theme.primary
                    }
                }

                Item {
                    visible: root.phase !== "idle"
                    width: parent.width
                    height: controls.implicitHeight

                    Row {
                        id: controls
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Theme.spacingS

                        // Countdown Timer controls
                        TimerButton {
                            visible: root.mode === "timer" && root.phase === "running"
                            icon: "pause"
                            text: "Pause"
                            onClicked: root.send("pause")
                        }
                        TimerButton {
                            visible: root.mode === "timer" && root.phase === "paused"
                            icon: "play_arrow"
                            text: "Resume"
                            onClicked: root.send("resume")
                        }
                        TimerButton {
                            visible: root.mode === "timer" && (root.phase === "running" || root.phase === "paused")
                            icon: "add"
                            text: "1 min"
                            onClicked: root.send("add", 60)
                        }
                        TimerButton {
                            visible: root.mode === "timer" && root.phase === "ringing"
                            icon: "replay"
                            text: "Again"
                            onClicked: root.send("again")
                        }

                        // Stopwatch controls
                        TimerButton {
                            visible: root.mode === "stopwatch" && root.phase === "running"
                            icon: "pause"
                            text: "Pause"
                            onClicked: root.send("pause")
                        }
                        TimerButton {
                            visible: root.mode === "stopwatch" && root.phase === "paused"
                            icon: "play_arrow"
                            text: "Resume"
                            onClicked: root.send("resume")
                        }
                        TimerButton {
                            visible: root.mode === "stopwatch" && root.phase === "running"
                            icon: "flag"
                            text: "Lap"
                            onClicked: root.send("lap")
                        }
                        TimerButton {
                            visible: root.mode === "stopwatch"
                            icon: "close"
                            text: "Reset"
                            onClicked: {
                                root.send("cancel")
                                pop.closePopout()
                            }
                        }

                        // Countdown / Alarm dismiss or cancel
                        TimerButton {
                            visible: root.mode !== "stopwatch"
                            icon: root.phase === "ringing" ? "check" : "close"
                            text: root.phase === "ringing" ? "Dismiss" : "Cancel"
                            onClicked: {
                                root.send("cancel")
                                if (root.phase === "ringing")
                                    pop.closePopout()
                            }
                        }
                    }
                }

                // Laps list for stopwatch
                Column {
                    visible: root.mode === "stopwatch" && root.laps && root.laps.length > 0
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: "Laps"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    ListView {
                        width: parent.width
                        height: Math.min(100, (root.laps ? root.laps.length : 0) * 24)
                        clip: true
                        model: (root.laps || []).slice().reverse()
                        delegate: Row {
                            width: ListView.view.width
                            height: 24
                            spacing: Theme.spacingS

                            StyledText {
                                width: 50
                                text: "Lap " + modelData.index
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                            StyledText {
                                width: (parent.width - 50 - Theme.spacingS) / 2
                                text: "+" + root.fmtElapsed(modelData.lapMs, true)
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                            }
                            StyledText {
                                width: (parent.width - 50 - Theme.spacingS) / 2
                                horizontalAlignment: Text.AlignRight
                                text: root.fmtElapsed(modelData.totalMs, true)
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                        }
                    }
                }

                StyledText {
                    visible: root.phase === "idle"
                    text: "Quick start"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                Flow {
                    visible: root.phase === "idle"
                    width: parent.width
                    spacing: Theme.spacingS

                    TimerButton {
                        icon: "timer"
                        text: "Stopwatch"
                        onClicked: root.send("startStopwatch")
                    }

                    Repeater {
                        model: [5, 10, 15, 25, 60]
                        TimerButton {
                            text: modelData + " min"
                            onClicked: root.send("start", modelData * 60)
                        }
                    }
                }
            }
        }
    }
}
