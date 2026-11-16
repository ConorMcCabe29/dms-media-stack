# Media Stack (DMS plugin)

A DankMaterialShell / Dux Shell bar widget for a Docker media server (Jellyfin, *arr apps, downloaders…) on another machine, checked over SSH.

- **Bar pill:** server icon (green = all running, amber = something stopped/unhealthy, red = VM unreachable) and `running/total`.
- **Click:** grouped list of containers with uptime; click one to open its link. By default Media is always shown and the other groups are dropdowns (closed by default) whose header shows how many are running; settings can keep every group open or drop grouping.
- **Right-click:** opens the `primary` container (default jellyfin).
- **Notifications** when a container stops, turns unhealthy, comes back, or the VM can't be reached twice in a row.

One daemon polls `ssh <host> docker ps -a` (every `intervalSec`) and shares the result with every bar through plugin global vars, so two monitors don't mean two SSH calls.

## Requirements

- DankMaterialShell / Dux Shell (tested on 2.1.2 with niri)
- A Linux VM/server running Docker that you can SSH into, as a user in the `docker` group
- `ssh`, `git`, `python3` on your PC; `notify-send` (libnotify) for alerts, `xdg-open` for links

## Install

    curl -fsSL https://raw.githubusercontent.com/ConorMcCabe29/dms-media-stack/main/install.sh | bash

The installer asks for your VM's `user@address`, sets up SSH key login if you don't have it yet
(creates a key and runs `ssh-copy-id`, so you type the VM password once), checks that `docker ps` works
there, saves the host, enables the plugin and adds it to your bar. DMS restarts once while it does this;
the old `settings.json` / `plugin_settings.json` are backed up next to the originals.
Run it again to update the plugin or change the host.

If `docker ps` fails with "permission denied", run `sudo usermod -aG docker <user>` on the VM,
log out of it, and run the installer again.

**Manual install** (e.g. to hack on it):

    git clone https://github.com/ConorMcCabe29/dms-media-stack ~/.config/dms/plugins/mediaStack
    dms ipc call plugins enable mediaStack

then set the host in Settings → Plugins → Media Stack and add "Media Stack" in Settings → Dank Bar → Widgets.

## Settings

Everything is in Settings → Plugins → Media Stack: SSH host, right-click target, check interval,
notifications, **grouping** (dropdowns, always-open groups, or one A–Z list), **list height** and
**popout width** (type the pixels), and **Links**: per container, the URL it opens (e.g. `jellyfin` →
`https://jelly.example.com`) and an optional label. Without a link, a container opens its first
published TCP port on the host (`http://<host>:<port>`).

The older `urls` / `labels` maps in `~/.config/dms/plugin_settings.json` still work; Links set in
the settings page win over them.

## IPC

    dms ipc call mediaStack status    # e.g. "12/12 running: ..."
    dms ipc call mediaStack refresh

## Licence

MIT
