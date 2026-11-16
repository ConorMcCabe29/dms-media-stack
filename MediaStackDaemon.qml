import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins

// Runs once (not per bar): polls `docker ps` on the VM over SSH, shares the result
// with every bar pill through global vars, and sends notifications when a container
// stops, turns unhealthy, or comes back. Ported from niri-bar's MediaStack + Alerts.
PluginComponent {
    id: root

    readonly property string pid: "mediaStack"
    readonly property string host: pluginData.host || ""
    readonly property int intervalSec: Math.max(15, parseInt(pluginData.intervalSec || "60"))
    readonly property bool alerts: pluginData.alerts ?? true
    readonly property string hostIp: host.split("@").pop()

    function share(name, value) { PluginService.setGlobalVar(pid, name, value) }

    function refresh() {
        if (!host) { share("loaded", true); share("reachable", false); share("containers", []); return }
        if (!proc.running) { proc.running = true; share("checking", true) }
    }

    function urlFor(name, ports) {
        // Links set in Settings → Plugins → Media Stack win over the older hand-edited "urls" map.
        const link = (pluginData.links ?? []).find(l => l.container === name && l.url)
        const custom = link?.url || pluginData.urls?.[name]
        if (custom) return custom
        const m = /(?:0\.0\.0\.0|\[::\]|::):(\d+)->\d+\/tcp/.exec(ports)
        return m ? `http://${hostIp}:${m[1]}` : ""
    }

    function notify(title, body, urgent, icon) {
        Quickshell.execDetached(["notify-send", "-a", "Media stack", "-i", icon || "dialog-information",
                                 "-u", urgent ? "critical" : "normal", title, body])
    }

    // ---- alerts ----
    property var _lastStates: null       // name -> "ok" | "unhealthy" | "down"; null until first check
    property int _failures: 0
    property bool _unreachableSent: false
    function stateOf(c) { return c.state !== "running" ? "down" : c.status.includes("unhealthy") ? "unhealthy" : "ok" }

    function checkAlerts(reachable, containers) {
        if (!reachable) {
            _failures++
            if (alerts && _failures === 2 && !_unreachableSent) {   // one blip isn't worth a notification
                _unreachableSent = true
                notify("Media server unreachable", `Can't reach ${host} over SSH.`, true, "network-error")
            }
            return
        }
        _failures = 0
        if (_unreachableSent) {
            _unreachableSent = false
            if (alerts) notify("Media server is back", "The media stack can be reached again.", false, "network-server")
        }
        const now = {}
        for (const c of containers) now[c.name] = stateOf(c)
        const before = _lastStates
        _lastStates = now
        if (before === null || !alerts) return
        for (const name in now) {
            const was = before[name], is = now[name]
            if (was === undefined || was === is) continue
            if (is === "down") notify(`${name} stopped`, "A media stack container is no longer running.", true, "dialog-error")
            else if (is === "unhealthy") notify(`${name} is unhealthy`, "It's running but failing its health check.", true, "dialog-warning")
            else notify(`${name} is back`, was === "down" ? "Running again." : "Healthy again.", false, "dialog-information")
        }
        for (const name in before)
            if (!(name in now)) notify(`${name} removed`, "This container no longer exists on the server.", false, "dialog-warning")
    }

    Process {
        id: proc
        command: ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", root.host,
                  "docker ps -a --format '{{.Names}}|{{.State}}|{{.Status}}|{{.Ports}}'"]
        stdout: StdioCollector { id: out }
        onExited: code => {
            const ok = code === 0
            let list = PluginService.getGlobalVar(root.pid, "containers", [])
            if (ok) list = out.text.trim().split("\n").filter(l => l).map(l => {
                const p = l.split("|")
                return { name: p[0], state: p[1], status: p[2], url: root.urlFor(p[0], p[3] ?? "") }
            }).sort((a, b) => a.name.localeCompare(b.name))
            root.share("containers", list)
            root.share("reachable", ok)
            root.share("loaded", true)
            root.share("checking", false)
            root.checkAlerts(ok, list)
        }
    }

    Timer { interval: root.intervalSec * 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

    // A bar pill asks for a recheck by bumping "refreshRequest"; settings changes recheck too.
    Connections {
        target: PluginService
        function onGlobalVarChanged(pluginId, varName) {
            if (pluginId === root.pid && varName === "refreshRequest") root.refresh()
        }
    }
    onHostChanged: refresh()
    onPluginDataChanged: Qt.callLater(refresh)

    IpcHandler {
        target: "mediaStack"
        function refresh(): string { root.refresh(); return "checking" }
        function status(): string {
            const list = PluginService.getGlobalVar(root.pid, "containers", [])
            const up = list.filter(c => c.state === "running").length
            return PluginService.getGlobalVar(root.pid, "reachable", false)
                ? `${up}/${list.length} running: ` + list.map(c => `${c.name}=${c.state}`).join(", ")
                : `unreachable (host: ${root.host || "not set"})`
        }
    }
}
