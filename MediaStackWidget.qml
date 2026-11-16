import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins
import "grouping.js" as G

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

    function label(name) { return G.label(pluginData, name) }

    // Groups are dropdowns (closed by default) unless they set collapsible: false.
    // Which ones are open is remembered until the shell restarts.
    property var expanded: ({})
    function toggle(name) {
        const e = Object.assign({}, expanded)
        e[name] = !e[name]
        expanded = e
    }

    // [{ header: "Media", … }, container, container, { header: "Request", … }, …]
    // Rows of closed groups are left out; their header shows a running count instead.
    // Settings: "dropdowns" (default), "open" (headers, never collapsed) or "none" (one flat list).
    // Names, groups and order come from the "Containers" section of the settings (see grouping.js).
    readonly property string grouping: pluginData.grouping || "dropdowns"
    readonly property var grouped: {
        if (grouping === "none") return G.sortContainers(pluginData, containers)
        const out = []
        for (const g of G.build(pluginData, containers)) {
            const collapsible = g.collapsible && grouping === "dropdowns"
            const open = !collapsible || !!expanded[g.name]
            const up = g.members.filter(c => c.state === "running").length
            const unhealthy = g.members.some(c => (c.status ?? "").includes("unhealthy"))
            out.push({ header: g.name, collapsible, open, up, total: g.members.length,
                       health: up < g.members.length ? "down" : unhealthy ? "unhealthy" : "ok" })
            if (open) out.push(...g.members)
        }
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

    // Popout size from settings (pixels); the list scrolls once it's taller than listHeight.
    readonly property int listHeight: Math.max(150, parseInt(pluginData.listHeight ?? 600) || 600)
    popoutWidth: Math.max(300, parseInt(pluginData.popoutWidth ?? 380) || 380)
    popoutContent: Component {
        PopoutComponent {
            id: pop
            headerText: "Media stack"
            detailsText: !root.reachable ? "Media VM unreachable"
                : `${root.running} of ${root.total} running · right-click the pill opens ${root.primary}`

            Flickable {
                width: parent.width
                height: Math.min(list.implicitHeight, root.listHeight)
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
                            sourceComponent: modelData.header === undefined ? serviceRow
                                           : modelData.collapsible ? groupToggle : groupHeader
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

            // Dropdown header: chevron + name, and a running count with a status dot.
            Component {
                id: groupToggle
                StyledRect {
                    id: tog
                    readonly property var modelData: parent?.modelData ?? ({})
                    readonly property color healthColor: modelData.health === "down" ? Theme.error
                        : modelData.health === "unhealthy" ? Theme.warning : Theme.success
                    height: 36
                    radius: Theme.cornerRadius
                    color: togArea.containsMouse ? Theme.chipSurface : "transparent"

                    DIcon {
                        id: chevron
                        name: "chevron_right"
                        size: Theme.iconSizeSmall
                        color: Theme.primary
                        rotation: tog.modelData.open ? 90 : 0
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.spacingS - 2
                        Behavior on rotation { NumberAnimation { duration: 120 } }
                    }
                    StyledText {
                        anchors.left: chevron.right
                        anchors.leftMargin: Theme.spacingXS
                        anchors.verticalCenter: parent.verticalCenter
                        text: tog.modelData.header ?? ""
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.DemiBold
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0.6
                        color: Theme.primary
                    }
                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXS
                        DIcon {
                            name: "circle"
                            filled: true
                            size: 8
                            color: tog.healthColor
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        StyledText {
                            text: `${tog.modelData.up}/${tog.modelData.total}`
                            color: tog.modelData.health === "ok" ? Theme.surfaceVariantText : tog.healthColor
                            font.pixelSize: Theme.fontSizeSmall
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    MouseArea {
                        id: togArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggle(tog.modelData.header)
                    }
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
                        readonly property string shown: G.displayName(root.pluginData, row.modelData.name)
                        text: row.lbl ? `${shown} <font color="${Theme.surfaceVariantText}">(${row.lbl})</font>` : shown
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
