import QtQuick
import qs.Common
import qs.Services

// Type "quick timer 10", "quick timer 20 sec", "quick alarm 7:30AM", or "quick stopwatch" in the launcher.
QtObject {
    id: root

    property var pluginService: null
    property string pluginId: "duxTimer"
    property string trigger: "quick"

    signal itemsChanged

    function unitMultiplier(tok) {
        switch ((tok || "").toLowerCase()) {
        case "h": case "hr": case "hrs": case "hour": case "hours":
            return 3600
        case "m": case "min": case "mins": case "minute": case "minutes":
            return 60
        case "s": case "sec": case "secs": case "second": case "seconds":
            return 1
        default:
            return 0
        }
    }

    function parseAttachedDuration(tok) {
        const s = tok.toLowerCase()
        const re = /(\d+(?:\.\d+)?|\.\d+)\s*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)/g
        let total = 0
        let matchedLen = 0
        let m
        while ((m = re.exec(s)) !== null) {
            if (m.index !== matchedLen)
                return 0
            matchedLen = re.lastIndex
            const val = parseFloat(m[1])
            const mult = unitMultiplier(m[2])
            if (!(val >= 0) || mult === 0)
                return 0
            total += val * mult
        }
        return matchedLen === s.length && matchedLen > 0 ? total : 0
    }

    function parseTimerParts(parts) {
        let idx = 0
        let totalSec = 0
        let hasExplicitUnit = false
        const numRe = /^(?:\d+(?:\.\d+)?|\.\d+)$/

        while (idx < parts.length) {
            const tok = parts[idx]
            if (numRe.test(tok)) {
                const val = parseFloat(tok)
                const nextMult = idx + 1 < parts.length ? unitMultiplier(parts[idx + 1]) : 0
                if (nextMult > 0) {
                    totalSec += val * nextMult
                    hasExplicitUnit = true
                    idx += 2
                    continue
                }
                if (!hasExplicitUnit && idx === 0) {
                    totalSec += val * 60 // bare number = minutes
                    idx += 1
                    break
                }
                break
            }
            const attached = parseAttachedDuration(tok)
            if (attached > 0) {
                totalSec += attached
                hasExplicitUnit = true
                idx += 1
                continue
            }
            break
        }

        let label = parts.slice(idx).join(" ")
        label = label.replace(/[\"']/g, "").trim()
        return {
            seconds: Math.round(totalSec),
            label: label
        }
    }

    function parseAlarmParts(parts, nowMs) {
        if (!parts || parts.length === 0)
            return null

        let raw = parts[0]
        let consumed = 1
        if (parts.length > 1 && /^(?:am|pm)$/i.test(parts[1])) {
            raw += parts[1]
            consumed = 2
        }

        const m = raw.match(/^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$/i)
        if (!m)
            return null

        const hasColon = m[2] !== undefined
        const ampm = m[3] ? m[3].toLowerCase() : ""
        if (!ampm && !hasColon)
            return null

        let hour = parseInt(m[1], 10)
        const minute = hasColon ? parseInt(m[2], 10) : 0
        if (isNaN(hour) || isNaN(minute) || minute < 0 || minute > 59)
            return null

        let hour24 = hour
        if (ampm !== "") {
            if (hour < 1 || hour > 12)
                return null
            if (ampm === "am")
                hour24 = hour === 12 ? 0 : hour
            else
                hour24 = hour === 12 ? 12 : hour + 12
        } else if (hour < 0 || hour > 23) {
            return null
        }

        const now = nowMs !== undefined ? new Date(nowMs) : new Date()
        const target = new Date(now.getFullYear(), now.getMonth(), now.getDate(), hour24, minute, 0, 0)
        let isTomorrow = false
        if (target.getTime() <= now.getTime()) {
            target.setDate(target.getDate() + 1)
            isTomorrow = true
        }

        const period = hour24 >= 12 ? "PM" : "AM"
        const h12 = hour24 % 12 === 0 ? 12 : hour24 % 12
        const mm = (minute < 10 ? "0" : "") + minute
        const timeStr = h12 + ":" + mm + " " + period
        const secondsUntil = Math.max(1, Math.ceil((target.getTime() - now.getTime()) / 1000))

        let label = parts.slice(consumed).join(" ")
        label = label.replace(/[\"']/g, "").trim()
        return {
            targetMs: target.getTime(),
            timeStr: timeStr,
            isTomorrow: isTomorrow,
            secondsUntil: secondsUntil,
            label: label
        }
    }

    function describe(sec) {
        const h = Math.floor(sec / 3600)
        const m = Math.floor((sec % 3600) / 60)
        const s = sec % 60
        const parts = []
        if (h) parts.push(h + "h")
        if (m) parts.push(m + "m")
        if (s) parts.push(s + "s")
        return parts.join(" ")
    }

    function currentState() {
        try {
            const t = JSON.parse(PluginService.getGlobalVar("duxTimer", "timer", ""))
            const all = Array.isArray(t.instances) ? t.instances : (t.phase && t.phase !== "idle" ? [t] : [])
            const selected = all.find(x => x.id === t.selectedId) || all[all.length - 1] || {}
            return {
                mode: selected.mode || "timer",
                phase: selected.phase || "idle",
                instanceId: selected.id || "",
                instances: all
            }
        } catch (e) {
            return { mode: "timer", phase: "idle", instanceId: "", instances: [] }
        }
    }

    function sendCommand(payload) {
        const cmd = {
            id: Date.now() + "-" + Math.random(),
            action: payload.action || "",
            seconds: payload.seconds || 0,
            label: payload.label || ""
        }
        if (payload.targetMs !== undefined)
            cmd.targetMs = payload.targetMs
        if (payload.timeStr !== undefined)
            cmd.timeStr = payload.timeStr
        if (payload.instanceId !== undefined)
            cmd.instanceId = payload.instanceId
        PluginService.setGlobalVar("duxTimer", "cmd", JSON.stringify(cmd))
    }

    function getItems(query) {
        const q = (query || "").trim()
        const parts = q === "" ? [] : q.split(/\s+/)
        const sub = parts.length > 0 ? parts[0].toLowerCase() : ""
        const rest = parts.slice(1)
        const items = []
        const st = currentState()

        if (sub === "timer" && rest.length > 0) {
            const parsed = parseTimerParts(rest)
            const secs = parsed.seconds
            if (secs > 0) {
                items.push({
                    name: "Start timer " + rest.join(" "),
                    icon: "material:timer",
                    comment: parsed.label !== "" ? parsed.label : "Notifies you when it finishes",
                    action: JSON.stringify({
                        action: "start",
                        seconds: secs,
                        label: parsed.label
                    }),
                    categories: ["Timer"]
                })
            }
        } else if (sub === "alarm" && rest.length > 0) {
            const alarm = parseAlarmParts(rest)
            if (alarm) {
                items.push({
                    name: "Set alarm " + rest.join(" "),
                    icon: "material:alarm",
                    comment: (alarm.label !== "" ? alarm.label + " · " : "") + "In " + describe(alarm.secondsUntil),
                    action: JSON.stringify({
                        action: "startAlarm",
                        targetMs: alarm.targetMs,
                        timeStr: alarm.timeStr,
                        label: alarm.label
                    }),
                    categories: ["Alarm"]
                })
            }
        } else if (sub === "stopwatch" || sub === "sw") {
            const subCmd = rest.length > 0 ? rest[0].toLowerCase() : ""
            const sw = st.instances.slice().reverse().find(x => x.mode === "stopwatch" && (x.phase === "running" || x.phase === "paused"))
            if (sw && (subCmd === "lap" || subCmd === "pause" || subCmd === "stop" || subCmd === "resume" || subCmd === "start" || subCmd === "reset" || subCmd === "cancel")) {
                if (subCmd === "lap") {
                    items.push({
                        name: "Record lap",
                        icon: "material:flag",
                        comment: "",
                        action: JSON.stringify({ action: "lap", instanceId: sw.id }),
                        categories: ["Stopwatch"]
                    })
                } else if (subCmd === "pause" || subCmd === "stop") {
                    items.push({
                        name: "Pause stopwatch",
                        icon: "material:pause",
                        comment: "",
                        action: JSON.stringify({ action: "pause", instanceId: sw.id }),
                        categories: ["Stopwatch"]
                    })
                } else if (subCmd === "resume" || subCmd === "start") {
                    items.push({
                        name: "Resume stopwatch",
                        icon: "material:play_arrow",
                        comment: "",
                        action: JSON.stringify({ action: "resume", instanceId: sw.id }),
                        categories: ["Stopwatch"]
                    })
                } else if (subCmd === "reset" || subCmd === "cancel") {
                    items.push({
                        name: "Reset stopwatch",
                        icon: "material:close",
                        comment: "",
                        action: JSON.stringify({ action: "cancel", instanceId: sw.id }),
                        categories: ["Stopwatch"]
                    })
                }
            } else if (!sw || subCmd === "") {
                const lbl = rest.join(" ").replace(/[\"']/g, "").trim()
                items.push({
                    name: lbl !== "" ? "Start stopwatch: " + lbl : "Start stopwatch",
                    icon: "material:timer",
                    comment: lbl !== "" ? lbl : "Track elapsed time",
                    action: JSON.stringify({
                        action: "startStopwatch",
                        label: lbl
                    }),
                    categories: ["Stopwatch"]
                })
            }
        }

        if (st.mode !== "stopwatch" && (st.phase === "running" || st.phase === "paused")) {
            const currentName = st.mode === "alarm" ? "alarm" : "timer"
            items.push({
                name: (st.phase === "running" ? "Pause " : "Resume ") + currentName,
                icon: "material:" + (st.phase === "running" ? "pause" : "play_arrow"),
                comment: "",
                action: JSON.stringify({ action: "toggle", instanceId: st.instanceId }),
                categories: ["Timer"]
            })
            items.push({
                name: "Add 1 minute",
                icon: "material:add",
                comment: "",
                action: JSON.stringify({ action: "add", seconds: 60, instanceId: st.instanceId }),
                categories: ["Timer"]
            })
        } else if (st.mode === "stopwatch" && (st.phase === "running" || st.phase === "paused")) {
            items.push({
                name: st.phase === "running" ? "Pause stopwatch" : "Resume stopwatch",
                icon: "material:" + (st.phase === "running" ? "pause" : "play_arrow"),
                comment: "",
                action: JSON.stringify({ action: "toggle", instanceId: st.instanceId }),
                categories: ["Stopwatch"]
            })
            if (st.phase === "running") {
                items.push({
                    name: "Record lap",
                    icon: "material:flag",
                    comment: "",
                    action: JSON.stringify({ action: "lap", instanceId: st.instanceId }),
                    categories: ["Stopwatch"]
                })
            }
        }

        for (let i = 0; i < st.instances.length; i++) {
            const instance = st.instances[i]
            const targetName = instance.mode === "alarm" ? "alarm" : (instance.mode === "stopwatch" ? "stopwatch" : "timer")
            const actionVerb = instance.phase === "ringing" ? "Dismiss " : (instance.mode === "stopwatch" ? "Reset " : "Cancel ")
            items.push({
                name: actionVerb + targetName,
                icon: "material:close",
                comment: "",
                action: JSON.stringify({ action: "cancel", instanceId: instance.id }),
                categories: [instance.mode === "alarm" ? "Alarm" : (instance.mode === "stopwatch" ? "Stopwatch" : "Timer")]
            })
        }

        if ((q === "" || (sub === "timer" && rest.length === 0)) && st.instances.length === 0) {
            items.push({
                name: "Start stopwatch",
                icon: "material:timer",
                comment: "Track elapsed time",
                action: JSON.stringify({ action: "startStopwatch", label: "" }),
                categories: ["Stopwatch"]
            })
            const presets = [5, 10, 15, 25, 60]
            for (let i = 0; i < presets.length; i++) {
                items.push({
                    name: presets[i] + " minute timer",
                    icon: "material:timer",
                    comment: "",
                    action: JSON.stringify({ action: "start", seconds: presets[i] * 60, label: "" }),
                    categories: ["Timer"]
                })
            }
        }
        return items
    }

    function executeItem(item) {
        if (!item || !item.action)
            return
        try {
            sendCommand(JSON.parse(item.action))
        } catch (e) {}
    }
}
