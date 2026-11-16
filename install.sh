#!/usr/bin/env bash
# Media Stack plugin for DankMaterialShell / Dux Shell: installer.
#
#   curl -fsSL https://raw.githubusercontent.com/ConorMcCabe29/dms-media-stack/main/install.sh | bash
#
# What it does (asks before each step that changes something):
#   1. puts the plugin in <dms config>/plugins/mediaStack (git clone, or git pull if it's already there)
#   2. asks for your VM's SSH login and sets up key login if needed (makes a key, runs ssh-copy-id)
#   3. checks that `docker ps` works on the VM without sudo
#   4. saves the host into DMS's plugin settings, enables the plugin and adds it to your bar
# Run it again any time to update the plugin or change the host.
set -euo pipefail

REPO="${MEDIASTACK_REPO:-https://github.com/ConorMcCabe29/dms-media-stack.git}"
PLUGIN_ID="mediaStack"

bold=$'\e[1m'; green=$'\e[32m'; yellow=$'\e[33m'; red=$'\e[31m'; reset=$'\e[0m'
say()  { printf '%s==>%s %s\n' "$bold" "$reset" "$*"; }
ok()   { printf '  %s✓%s %s\n' "$green" "$reset" "$*"; }
warn() { printf '  %s!%s %s\n' "$yellow" "$reset" "$*"; }
die()  { printf '%sError:%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

# Prompts read from the terminal, so this works when piped from curl.
[ -r /dev/tty ] || die "run this from a terminal (it needs to ask you a few things)"
ask() {   # ask "Question" default -> echoes the answer
    local reply
    read -r -p "  $1${2:+ [$2]}: " reply </dev/tty
    echo "${reply:-$2}"
}
yes_no() {   # yes_no "Question" Y|N
    local reply def="$2"
    read -r -p "  $1 [$([ "$def" = Y ] && echo Y/n || echo y/N)]: " reply </dev/tty
    reply="${reply:-$def}"
    [[ "$reply" =~ ^[Yy] ]]
}

# ---------------------------------------------------------------- 0. checks
say "Checking what's installed"
command -v dms >/dev/null || die "DankMaterialShell / Dux Shell (the 'dms' command) isn't installed"
ok "dms $(dms version 2>/dev/null | grep -oE 'v[0-9][^ ]*' | head -1)"
for c in ssh git python3; do
    command -v "$c" >/dev/null || die "'$c' is missing; install it with your package manager and run this again"
done
ok "ssh, git, python3"
command -v notify-send >/dev/null && ok "notify-send" \
    || warn "notify-send is missing (package libnotify): the widget works, but you won't get alerts"
command -v xdg-open >/dev/null || warn "xdg-open is missing (package xdg-utils): clicking a container won't open it"

# DMS keeps its config in ~/.config/dms (newer) or ~/.config/DankMaterialShell (older).
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
if   [ -d "$CFG/dms" ];               then DMS_DIR="$CFG/dms"
elif [ -d "$CFG/DankMaterialShell" ]; then DMS_DIR="$CFG/DankMaterialShell"
else                                       DMS_DIR="$CFG/dms"
fi
PLUGIN_DIR="$DMS_DIR/plugins/$PLUGIN_ID"
ok "DMS config: $DMS_DIR"

# ---------------------------------------------------------------- 1. plugin files
say "Installing the plugin"
mkdir -p "$DMS_DIR/plugins"
if [ -L "$PLUGIN_DIR" ]; then
    ok "$PLUGIN_DIR is a symlink to $(readlink -f "$PLUGIN_DIR"); leaving it alone"
elif [ -d "$PLUGIN_DIR/.git" ]; then
    git -C "$PLUGIN_DIR" pull --ff-only --quiet && ok "updated to $(git -C "$PLUGIN_DIR" log -1 --format=%h)"
elif [ -e "$PLUGIN_DIR" ]; then
    die "$PLUGIN_DIR already exists and isn't a git checkout; move it away and run this again"
else
    git clone --quiet --depth 1 "$REPO" "$PLUGIN_DIR" && ok "installed to $PLUGIN_DIR"
fi

# ---------------------------------------------------------------- 2. SSH
say "Connecting to your VM"
echo "  The widget runs 'docker ps' on the machine with your containers over SSH."
current_host=$(python3 - "$DMS_DIR/plugin_settings.json" "$PLUGIN_ID" <<'EOF' 2>/dev/null || true
import json, sys
print(json.load(open(sys.argv[1])).get(sys.argv[2], {}).get("host", ""))
EOF
)
HOST=""
while [ -z "$HOST" ]; do
    HOST=$(ask "SSH login for the VM, as user@address (e.g. me@192.168.1.10)" "$current_host")
    [[ "$HOST" == *@* ]] || { warn "include the user name, like me@192.168.1.10"; HOST=""; }
done

ssh_ok() { ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$HOST" "$@" </dev/null; }

if ssh_ok true 2>/dev/null; then
    ok "key login to $HOST already works"
else
    warn "can't log in to $HOST without a password yet"
    if ! ls ~/.ssh/id_*.pub >/dev/null 2>&1; then
        if yes_no "Create an SSH key on this PC (~/.ssh/id_ed25519, no passphrase)?" Y; then
            mkdir -p ~/.ssh && chmod 700 ~/.ssh
            ssh-keygen -q -t ed25519 -N "" -C "$(whoami)@$(hostname) media-stack" -f ~/.ssh/id_ed25519
            ok "key created"
        else
            die "the widget needs key login (it can't type a password); set one up and run this again"
        fi
    fi
    echo "  Copying your key to the VM. Type $HOST's password when asked (this is the only time)."
    ssh-copy-id -o StrictHostKeyChecking=accept-new "$HOST" </dev/tty || die "ssh-copy-id failed; check the address and password"
    ssh_ok true 2>/dev/null || die "key login still doesn't work. If your key has a passphrase, add it to ssh-agent first."
    ok "key login works"
fi

# ---------------------------------------------------------------- 3. docker
if out=$(ssh_ok "docker ps --format '{{.Names}}'" 2>&1); then
    n=$(printf '%s' "$out" | grep -c . || true)
    ok "docker works on the VM ($n running containers)"
elif printf '%s' "$out" | grep -qi "permission denied"; then
    user="${HOST%@*}"
    warn "'$user' can't use docker without sudo. On the VM, run:"
    echo "        sudo usermod -aG docker $user"
    echo "  then log out of the VM and run this installer again."
    exit 1
elif printf '%s' "$out" | grep -qi "not found"; then
    die "docker isn't installed on $HOST (or isn't on the PATH for SSH logins)"
else
    die "running docker on the VM failed: $out"
fi

# ---------------------------------------------------------------- 4. DMS settings
say "Configuring DMS"
add_to_bar=0
yes_no "Add Media Stack to the right side of your bar?" Y && add_to_bar=1

# DMS only reads these files at startup and rewrites them when it saves,
# so it has to be stopped while they're edited.
via_systemd=0
systemctl --user is-active --quiet dms 2>/dev/null && via_systemd=1
echo "  DMS has to restart to pick up the settings (your bar will blink for a second)."
if [ $via_systemd = 1 ]; then systemctl --user stop dms; else dms kill >/dev/null 2>&1 || true; fi
sleep 1

stamp=$(date +%Y%m%d-%H%M%S)
for f in plugin_settings.json settings.json; do
    [ -f "$DMS_DIR/$f" ] && cp "$DMS_DIR/$f" "$DMS_DIR/$f.bak-$stamp-mediastack"
done

python3 - "$DMS_DIR" "$PLUGIN_ID" "$HOST" "$add_to_bar" <<'EOF'
import json, os, sys
d, pid, host, add = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"

def load(name):
    try:
        with open(os.path.join(d, name)) as f: return json.load(f)
    except FileNotFoundError: return {}

def save(name, data):
    p = os.path.join(d, name)
    with open(p + ".tmp", "w") as f: json.dump(data, f, indent=2)
    os.replace(p + ".tmp", p)

ps = load("plugin_settings.json")
s = ps.setdefault(pid, {})
s.update(enabled=True, host=host)
s.setdefault("intervalSec", "60")
s.setdefault("alerts", True)
save("plugin_settings.json", ps)
print("  ✓ host saved, plugin enabled")

if add:
    st = load("settings.json")
    bars = st.get("barConfigs") or []
    if not bars:
        print("  ! couldn't find your bar in settings.json; add it by hand (see below)")
    elif any(w.get("id") == pid for b in bars for k in ("leftWidgets", "centerWidgets", "rightWidgets")
             for w in b.get(k, []) if isinstance(w, dict)):
        print("  ✓ already on your bar")
    else:
        bars[0].setdefault("rightWidgets", []).insert(0, {"id": pid, "enabled": True})
        save("settings.json", st)
        print("  ✓ added to your bar")
EOF

if [ $via_systemd = 1 ]; then
    systemctl --user start dms
else
    setsid -f dms run -d >/dev/null 2>&1 </dev/null
fi
ok "DMS restarted (settings backed up as *.bak-$stamp-mediastack)"

# Give the shell a moment, then make sure it saw the plugin.
for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    dms ipc call plugins enable "$PLUGIN_ID" >/dev/null 2>&1 && break
done

cat <<EOF

${green}${bold}Done.${reset} The server icon on your bar shows how many containers are running:
  green = all fine, amber = something stopped or unhealthy, red = can't reach the VM.

  Click it            list of containers; click one to open it
  Right-click it      opens jellyfin (change it in settings)
  Settings            Settings → Plugins → Media Stack: host, check interval,
                      notifications, and Links (your own URLs / names per container)
  Not on the bar?     Settings → Dank Bar → Widgets → add "Media Stack"
  Check from terminal dms ipc call $PLUGIN_ID status
  Update later        run this installer again
EOF
