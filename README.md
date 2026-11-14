# Media Stack (DMS plugin)

Port of niri-bar's media-stack widget to DankMaterialShell / Dux Shell.

- **Bar pill:** server icon (green = all running, amber = something stopped/unhealthy, red = VM unreachable) and `running/total`.
- **Click:** grouped list of containers with uptime; click one to open its link.
- **Right-click:** opens the `primary` container (default jellyfin).
- **Notifications** when a container stops, turns unhealthy, comes back, or the VM can't be reached twice in a row.

One daemon polls `ssh <host> docker ps -a` (every `intervalSec`) and shares the result with every bar through plugin global vars, so two monitors don't mean two SSH calls.

## Install

    ln -s ~/Projects/dms-media-stack ~/.config/dms/plugins/mediaStack
    dms ipc call plugins enable mediaStack

Then add "Media Stack" to a bar in Settings → Dank Bar → Widgets.

## Settings

Host, right-click target, interval and notifications are in Settings → Plugins → Media Stack.
Links and labels are in `~/.config/dms/plugin_settings.json` under `mediaStack.urls` / `mediaStack.labels`
(e.g. `"urls": { "jellyfin": "https://jelly.example.com" }`). Without a custom link, a container links
to its first published TCP port on the host. DMS reads that file only at startup, so stop DMS
(`systemctl --user stop dms`) before editing it, then start it again.

## IPC

    dms ipc call mediaStack status    # e.g. "12/12 running: ..."
    dms ipc call mediaStack refresh
