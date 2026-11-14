import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins

// Bar pill: server icon coloured by health + "running/total".
// Click: grouped list of containers; click one to open it in the browser.
// Right-click: open the primary service (settings: primary, default jellyfin).
PluginComponent {
    id: root

    PluginGlobalVar { id: gContainers; varName: "containers"; defaultValue: [] }
    PluginGlobalVar { id: gReachable; varName: "reachable"; defaultValue: false }
    PluginGlobalVar { id: gLoaded; varName: "loaded"; defaultValue: false }
    PluginGlobalVar { id: gChecking; varName: "checking"; defaultValue: false }
    PluginGlobalVar { id: gRefresh; varName: "refreshRequest"; defaultValue: 0 }

    readonly property var containers: gContainers.value || []
    readonly property bool reachable: gReachable.value
    readonly property bool loaded: gLoaded.value
    readonly property bool checking: gChecking.value
    readonly property int running: containers.filter(c => c.state === "running").length
    readonly property int total: containers.length
    readonly property bool healthy: reachable && running === total && !containers.some(c => c.status.includes("unhealthy"))
    readonly property color stateColor: !reachable ? Theme.error : healthy ? Theme.success : Theme.warning
    readonly property string primary: pluginData.primary ?? "jellyfin"

    function refresh() { gRefresh.set((gRefresh.value || 0) + 1) }
    function open(name) {
        const c = containers.find(c => c.name === name)
        if (c?.url) Quickshell.execDetached(["xdg-open", c.url])
    }

    readonly property var defaultLabels: ({
        "jellyfin": "Films & TV", "plex": "Films & TV", "emby": "Films & TV",
        "seerr": "Requests", "jellyseerr": "Requests", "overseerr": "Requests", "ombi": "Requests",
        "radarr": "Films", "sonarr": "TV shows", "lidarr": "Music", "readarr": "Books", "bazarr": "Subtitles",
        "prowlarr": "Indexers", "jackett": "Indexers", "flaresolverr": "Cloudflare bypass",
        "qbittorrent": "Downloads", "transmission": "Downloads", "sabnzbd": "Downloads", "nzbget": "Downloads",
        "slskd": "Soulseek", "soularr": "Soulseek ↔ Lidarr",
        "navidrome": "Music streaming", "audiobookshelf": "Audiobooks", "recommendarr": "Recommendations",
        "gluetun": "VPN", "vpn": "VPN"
    })
    function label(name) { return pluginData.labels?.[name] ?? defaultLabels[name] ?? "" }

    readonly property var defaultGroups: [
        { name: "Watch & listen", members: ["jellyfin", "plex", "emby", "navidrome", "audiobookshelf", "novel-reader"] },
        { name: "Request",        members: ["seerr", "jellyseerr", "overseerr", "ombi", "recommendarr"] },
        { name: "Libraries",      members: ["radarr", "sonarr", "lidarr", "readarr", "bazarr"] },
        { name: "Downloading",    members: ["qbittorrent", "transmission", "sabnzbd", "nzbget", "prowlarr", "jackett",
                                            "slskd", "soularr", "flaresolverr", "gluetun", "vpn"] }
    ]
    // [{ header: "Watch & listen" }, container, container, { header: "Request" }, …]
    readonly property var grouped: {
        const out = [], placed = new Set()
        for (const g of (pluginData.groups ?? defaultGroups)) {
            const members = g.members.map(n => containers.find(c => c.name === n)).filter(c => c)
            if (!members.length) continue
            out.push({ header: g.name })
            for (const c of members) { out.push(c); placed.add(c.name) }
        }
        const rest = containers.filter(c => !placed.has(c.name))
        if (rest.length) { out.push({ header: "Other" }); out.push(...rest) }
        return out
    }

    pillRightClickAction: () => open(primary)

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            visible: root.loaded
            DIcon {
                name: "dns"
                filled: true
                color: root.stateColor
                size: root.iconSize
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: root.reachable ? `${root.running}/${root.total}` : "off"
                color: Theme.widgetTextColor ?? Theme.surfaceText
                font.pixelSize: root.textSize
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            visible: root.loaded
            DIcon {
                name: "dns"
                filled: true
                color: root.stateColor
                size: root.iconSize
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                text: root.reachable ? `${root.running}/${root.total}` : "off"
                color: Theme.widgetTextColor ?? Theme.surfaceText
                font.pixelSize: root.textSize
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutWidth: 380
    popoutContent: Component {
        PopoutComponent {
            id: pop
            headerText: "Media stack"
            detailsText: !root.reachable ? "Media VM unreachable"
                : `${root.running} of ${root.total} running · right-click the pill opens ${root.primary}`

            Flickable {
                width: parent.width
                height: Math.min(list.implicitHeight, 600)
                contentHeight: list.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: list
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: root.grouped
                        delegate: Loader {
                            required property var modelData
                            width: list.width
                            sourceComponent: modelData.header !== undefined ? groupHeader : serviceRow
                        }
                    }

                    StyledRect {
                        width: parent.width
                        height: 36
                        radius: Theme.cornerRadius
                        color: recheckArea.containsMouse ? Theme.chipSurface : "transparent"
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            x: Theme.spacingS
                            spacing: Theme.spacingS
                            DIcon { name: "refresh"; size: Theme.iconSizeSmall; color: Theme.surfaceText; anchors.verticalCenter: parent.verticalCenter }
                            StyledText { text: root.checking ? "Checking…" : "Recheck now"; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeMedium; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea { id: recheckArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.refresh() }
                    }
                }
            }

            Component {
                id: groupHeader
                StyledText {
                    readonly property var modelData: parent?.modelData ?? ({})
                    text: modelData.header ?? ""
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 0.6
                    color: Theme.primary
                    leftPadding: Theme.spacingS
                    topPadding: Theme.spacingS
                    bottomPadding: 2
                }
            }

            Component {
                id: serviceRow
                StyledRect {
                    id: row
                    readonly property var modelData: parent?.modelData ?? ({ name: "", state: "", status: "" })
                    readonly property bool up: modelData.state === "running"
                    readonly property bool unhealthy: (modelData.status ?? "").includes("unhealthy")
                    readonly property string lbl: root.label(modelData.name)
                    height: 36
                    radius: Theme.cornerRadius
                    color: rowArea.containsMouse && modelData.url ? Theme.chipSurface : "transparent"

                    DIcon {
                        id: dot
                        name: "circle"
                        filled: true
                        size: 10
                        color: !row.up ? Theme.error : row.unhealthy ? Theme.warning : Theme.success
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.spacingS + 3
                    }
                    StyledText {
                        anchors.left: dot.right
                        anchors.leftMargin: Theme.spacingS + 3
                        anchors.right: detail.left
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: row.lbl ? `${row.modelData.name} <font color="${Theme.surfaceVariantText}">(${row.lbl})</font>` : row.modelData.name
                        textFormat: Text.StyledText
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                    }
                    StyledText {
                        id: detail
                        anchors.right: link.left
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.up ? (row.modelData.status ?? "").replace(/^Up /, "").replace(/ \(.*\)$/, "") : row.modelData.state
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    DIcon {
                        id: link
                        name: "open_in_new"
                        size: Theme.iconSizeSmall
                        color: Theme.surfaceVariantText
                        opacity: row.modelData.url ? 1 : 0
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !!row.modelData.url
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.open(row.modelData.name); pop.closePopout() }
                    }
                }
            }
        }
    }
}
