import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins

// Owns independent timer, alarm, and stopwatch instances.
PluginComponent {
    id: root
    readonly property string pid: "duxTimer"
    property var instances: []
    property string selectedId: ""
    property string lastCmdId: ""
    readonly property bool playSound: pluginData.playSound ?? true
    readonly property int autoDismissSec: pluginData.autoDismiss ?? 30
    readonly property double maxDateMs: 8640000000000000
    readonly property int maxLabelLength: 200

    function snapshot() {
        const selected = findInstance(selectedId) || {}
        return JSON.stringify(Object.assign({}, selected, { instances: instances, selectedId: selectedId }))
    }
    function publish() {
        const s = snapshot()
        PluginService.setGlobalVar(pid, "timer", s)
        if (pluginService) pluginService.savePluginState(pid, "timer", s)
    }
    function findInstance(id) {
        for (let i = 0; i < instances.length; i++)
            if (instances[i].id === id) return instances[i]
        return null
    }
    function replaceInstance(updated) {
        const next = instances.slice()
        const index = next.findIndex(x => x.id === updated.id)
        if (index >= 0) next[index] = updated
        else next.push(updated)
        instances = next
        selectedId = updated.id
        publish()
    }
    function newInstance(mode, label, extra) {
        if (instances.length >= 100)
            return null
        const now = Date.now()
        const item = Object.assign({
            id: now + "-" + Math.random(), mode: mode, phase: "running",
            endAt: 0, remainingMs: 0, totalMs: 0, startAt: 0,
            accumulatedMs: 0, laps: [], label: String(label || "").slice(0, maxLabelLength), alarmTime: ""
        }, extra || {})
        item.alarmTime = String(item.alarmTime || "").slice(0, maxLabelLength)
        instances = instances.concat([item])
        selectedId = item.id
        publish()
        return item
    }
    function startTimer(seconds, label) {
        const durationMs = Number(seconds) * 1000
        if (!Number.isFinite(durationMs) || durationMs <= 0 || durationMs > maxDateMs - Date.now()) return
        newInstance("timer", label, { totalMs: durationMs, endAt: Date.now() + durationMs })
    }
    function startAlarm(targetMs, label, timeStr) {
        targetMs = Number(targetMs)
        if (!Number.isFinite(targetMs) || targetMs <= Date.now() || targetMs > maxDateMs) return
        newInstance("alarm", label, { totalMs: targetMs - Date.now(), endAt: targetMs, alarmTime: timeStr || "" })
    }
    function startStopwatch(label) {
        newInstance("stopwatch", label, { startAt: Date.now() })
    }
    function targetFor(c) {
        if (c.instanceId) return findInstance(c.instanceId)
        if (c.mode) {
            for (let i = instances.length - 1; i >= 0; i--)
                if (instances[i].mode === c.mode && instances[i].phase !== "idle") return instances[i]
        }
        return findInstance(selectedId) || (instances.length ? instances[instances.length - 1] : null)
    }
    function change(item, action, seconds) {
        if (!item) return
        let x = Object.assign({}, item)
        if (action === "cancel" || action === "reset") {
            instances = instances.filter(v => v.id !== x.id)
            if (selectedId === x.id) selectedId = instances.length ? instances[instances.length - 1].id : ""
            publish()
            return
        }
        if (action === "pause" || (action === "toggle" && x.phase === "running")) {
            if (x.phase !== "running") return
            if (x.mode === "stopwatch") {
                x.accumulatedMs += Math.max(0, Date.now() - x.startAt)
                x.startAt = 0
            } else {
                x.remainingMs = Math.max(0, x.endAt - Date.now())
            }
            x.phase = "paused"
        } else if (action === "resume" || (action === "toggle" && x.phase === "paused")) {
            if (x.phase !== "paused") return
            if (x.mode === "stopwatch") x.startAt = Date.now()
            else x.endAt = Date.now() + x.remainingMs
            x.phase = "running"
        } else if (action === "lap" && x.mode === "stopwatch") {
            const elapsed = x.accumulatedMs + (x.phase === "running" ? Date.now() - x.startAt : 0)
            const prior = x.laps.length ? x.laps[x.laps.length - 1].totalMs : 0
            const lastLap = x.laps.length ? x.laps[x.laps.length - 1] : null
            const lastIdx = lastLap && Number.isFinite(Number(lastLap.index)) ? Number(lastLap.index) : x.laps.length
            x.laps = x.laps.concat([{ index: lastIdx + 1, lapMs: elapsed - prior, totalMs: elapsed }]).slice(-1000)
        } else if (action === "add" && x.mode !== "stopwatch") {
            const requested = Number(seconds)
            const ms = (Number.isFinite(requested) && requested > 0 ? requested : 60) * 1000
            const baseAt = x.phase === "running" ? x.endAt : Date.now() + (x.remainingMs || 0)
            if (!Number.isFinite(ms) || ms <= 0 || ms > maxDateMs - baseAt) return
            if (x.phase === "running") x.endAt += ms
            else if (x.phase === "paused") x.remainingMs += ms
            x.totalMs += ms
        } else if (action === "again" && x.totalMs > 0) {
            x.mode = "timer"; x.phase = "running"; x.endAt = Date.now() + x.totalMs
            x.remainingMs = 0; x.alarmTime = ""
        }
        replaceInstance(x)
    }
    function finish(item) {
        const x = Object.assign({}, item, { phase: "ringing", endAt: 0, remainingMs: 0, ringAt: Date.now() })
        replaceInstance(x)
        const isAlarm = x.mode === "alarm"
        const title = isAlarm ? "Alarm" : "Timer finished"
        const msg = isAlarm ? (x.label ? x.label + (x.alarmTime ? " (" + x.alarmTime + ")" : "") : (x.alarmTime ? "Alarm for " + x.alarmTime : "Your alarm is ringing"))
                          : (x.label || "Your timer is up")
        Quickshell.execDetached(["notify-send", "-a", "Quick Timer", "-u", "critical", "-i", "alarm-clock", title, msg])
        ToastService.showInfo(title, msg)
        if (playSound) Quickshell.execDetached(["sh", "-c", "paplay /usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga 2>/dev/null || canberra-gtk-play -i alarm-clock-elapsed 2>/dev/null"])
    }
    function handleCommand(c) {
        if (c.action === "start") return startTimer(c.seconds, c.label)
        if (c.action === "startAlarm") return startAlarm(c.targetMs, c.label, c.timeStr)
        if (c.action === "startStopwatch") return startStopwatch(c.label)
        change(targetFor(c), c.action, c.seconds)
    }
    function pollCommand() {
        const raw = PluginService.getGlobalVar(pid, "cmd", "")
        if (!raw) return
        let c
        try { c = JSON.parse(raw) } catch (e) { return }
        if (!c || !c.id || c.id === lastCmdId) return
        lastCmdId = c.id
        handleCommand(c)
    }
    Timer {
        interval: 250; running: true; repeat: true
        onTriggered: {
            root.pollCommand()
            const now = Date.now()
            const before = root.instances.slice()
            let changed = false
            for (let i = 0; i < before.length; i++) {
                const x = before[i]
                if (x.phase === "running" && x.mode !== "stopwatch" && now >= x.endAt) {
                    root.finish(x); changed = true
                }
            }
            const kept = root.instances.filter(x => !(x.phase === "ringing" && root.autoDismissSec > 0 && now - (x.ringAt || now) >= root.autoDismissSec * 1000))
            if (kept.length !== root.instances.length) {
                root.instances = kept
                if (!root.findInstance(root.selectedId)) root.selectedId = kept.length ? kept[kept.length - 1].id : ""
                changed = true
            }
            if (changed) root.publish()
        }
    }
    IpcHandler {
        target: "quicktimer"
        function start(seconds: int): string { root.startTimer(seconds, ""); return "started" }
        function startNamed(seconds: int, label: string): string { root.startTimer(seconds, label); return "started" }
        function stopwatch(): string { root.startStopwatch(""); return "started" }
        function stopwatchNamed(label: string): string { root.startStopwatch(label); return "started" }
        function lap(): string { root.change(root.targetFor({ mode: "stopwatch" }), "lap", 0); return "lap recorded" }
        function toggle(): string { root.change(root.targetFor({}), "toggle", 0); return "updated" }
        function add(seconds: int): string { root.change(root.targetFor({}), "add", seconds); return "updated" }
        function cancel(): string { root.change(root.targetFor({}), "cancel", 0); return "cancelled" }
        function reset(): string { root.change(root.targetFor({}), "reset", 0); return "reset" }
        function status(): string { return root.snapshot() }
    }
    Component.onCompleted: {
        const oldRaw = PluginService.getGlobalVar(pid, "cmd", "")
        if (oldRaw) { try { lastCmdId = JSON.parse(oldRaw).id || "" } catch (e) {} }
        const saved = pluginService ? pluginService.loadPluginState(pid, "timer", "") : ""
        if (saved) {
            try {
                const t = JSON.parse(saved)
                if (Array.isArray(t.instances)) {
                    instances = t.instances.slice(0, 100).filter(x => x && typeof x === "object"
                        && typeof x.id === "string" && x.id.length <= 100
                        && ["timer", "alarm", "stopwatch"].includes(x.mode)
                        && ["running", "paused", "ringing"].includes(x.phase))
                    selectedId = instances.some(x => x.id === t.selectedId) ? t.selectedId : (instances.length ? instances[instances.length - 1].id : "")
                } else if (t.phase && t.phase !== "idle") {
                    if (["timer", "alarm", "stopwatch"].includes(t.mode)
                        && ["running", "paused", "ringing"].includes(t.phase)) {
                        t.id = "restored-" + Date.now()
                        instances = [t]
                        selectedId = t.id
                    }
                }
            } catch (e) { instances = []; selectedId = "" }
        }
        const now = Date.now()
        const restored = []
        for (let i = 0; i < instances.length; i++) {
            let x = Object.assign({}, instances[i])
            x.label = String(x.label || "").slice(0, maxLabelLength)
            x.laps = Array.isArray(x.laps) ? x.laps.slice(-1000) : []
            if (x.mode !== "stopwatch" && (!Number.isFinite(Number(x.endAt)) || Number(x.endAt) > maxDateMs))
                continue
            if (x.phase === "running" && x.mode !== "stopwatch" && now >= x.endAt) {
                x.phase = "ringing"; x.endAt = 0; x.ringAt = now
            }
            if (x.phase === "ringing" && !x.ringAt) x.ringAt = now
            restored.push(x)
        }
        instances = restored
        publish()
    }
}
