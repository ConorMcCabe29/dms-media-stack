import QtQuick
import qs.Common
import qs.Widgets
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Plugins
import "grouping.js" as G

PluginSettings {
    id: root
    pluginId: "mediaStack"

    StringSetting {
        settingKey: "host"
        label: "SSH host"
        description: "user@host of the VM running Docker (key auth, no password prompt)"
        placeholder: "user@192.168.1.10"
    }
    StringSetting {
        settingKey: "primary"
        label: "Right-click opens"
        description: "Container whose link opens when you right-click the pill"
        placeholder: "jellyfin"
        defaultValue: "jellyfin"
    }
    SelectionSetting {
        settingKey: "intervalSec"
        label: "Check every"
        options: [
            { label: "30 seconds", value: "30" },
            { label: "1 minute", value: "60" },
            { label: "5 minutes", value: "300" }
        ]
        defaultValue: "60"
    }
    ToggleSetting {
        settingKey: "alerts"
        label: "Notifications"
        description: "Notify when a container stops, turns unhealthy, comes back, or the VM can't be reached"
        defaultValue: true
    }
    SelectionSetting {
        settingKey: "grouping"
        label: "Grouping"
        description: "How containers are listed in the popout"
        options: [
            { label: "Groups as dropdowns", value: "dropdowns" },
            { label: "Groups, always open", value: "open" },
            { label: "No groups (A–Z list)", value: "none" }
        ]
        defaultValue: "dropdowns"
    }
    StringSetting {
        id: heightSetting
        settingKey: "listHeight"
        label: "List height (px)"
        description: "Tallest the container list gets before it scrolls. Type a number of pixels, at least 150."
        placeholder: "600"
        defaultValue: "600"
    }
    StringSetting {
        id: widthSetting
        settingKey: "popoutWidth"
        label: "Popout width (px)"
        description: "Width of the popout in pixels, at least 300."
        placeholder: "380"
        defaultValue: "380"
    }
    // Copies the size the popout's list measured the last time it was open into the two boxes above.
    Row {
        id: fit
        readonly property int fitW: PluginService.globalVars["mediaStack"]?.fitWidth ?? 0
        readonly property int fitH: PluginService.globalVars["mediaStack"]?.fitHeight ?? 0
        readonly property bool ready: fitW > 0 && fitH > 0
        spacing: Theme.spacingM

        StyledRect {
            width: fitRow.implicitWidth + Theme.spacingM * 2
            height: 36
            radius: Theme.cornerRadius
            color: fitArea.containsMouse && fit.ready ? Theme.primaryHover : Theme.chipSurface
            opacity: fit.ready ? 1 : 0.5
            Row {
                id: fitRow
                anchors.centerIn: parent
                spacing: Theme.spacingXS
                DIcon { name: "fit_screen"; size: 18; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                StyledText { text: "Fit to current list"; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeMedium; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea {
                id: fitArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: fit.ready ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (!fit.ready) return
                    root.saveValue("listHeight", String(Math.max(150, fit.fitH)))
                    root.saveValue("popoutWidth", String(Math.max(300, fit.fitW)))
                    heightSetting.loadValue()
                    widthSetting.loadValue()
                }
            }
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            text: fit.ready ? `${fit.fitW} × ${fit.fitH} px, as the list looked when the popout was last open`
                            : "Open the popout once, then come back here"
        }
    }
    // ---- Containers: rename, regroup and reorder every container the VM reports ----
    Column {
        id: org
        width: parent.width
        spacing: Theme.spacingS

        readonly property var containers: PluginService.globalVars["mediaStack"]?.containers ?? []
        property var custom: ({})
        property var order: []
        property var groupOrder: []
        property string mode: "dropdowns"
        property var groups: undefined

        function reload() {
            custom = copy(root.loadValue("custom", {}) || {})
            order = copy(root.loadValue("order", []) || [])
            groupOrder = copy(root.loadValue("groupOrder", []) || [])
            mode = root.loadValue("grouping", "dropdowns") || "dropdowns"
            groups = root.loadValue("groups", undefined)
        }
        Component.onCompleted: Qt.callLater(reload)
        Connections {
            target: root
            function onSettingChanged() { org.mode = root.loadValue("grouping", "dropdowns") || "dropdowns" }
        }

        readonly property var pd: ({ custom: custom, order: order, groupOrder: groupOrder, groups: groups })
        // Same layout as the popout: [{ name, members }] or one unnamed group in "No groups" mode.
        readonly property var layout: mode === "none"
            ? [{ name: "", members: G.sortContainers(pd, containers) }]
            : G.build(pd, containers)

        function copy(v) { return JSON.parse(JSON.stringify(v)) }

        function setField(name, field, value) {
            const c = copy(custom)
            const entry = c[name] || {}
            value = value.trim()
            if (value) entry[field] = value; else delete entry[field]
            if (Object.keys(entry).length) c[name] = entry; else delete c[name]
            if (JSON.stringify(c) === JSON.stringify(custom)) return
            root.saveValue("custom", c)
            if (field === "group") { custom = c; return }    // moves the row, so rebuild the list
            // A new display name doesn't move anything: update in place so the boxes aren't rebuilt mid-typing.
            if (c[name]) custom[name] = c[name]; else delete custom[name]
        }

        // Swap a container with its neighbour (dir -1 up, +1 down) in the shown order.
        function move(name, dir) {
            const list = G.flatOrder(pd, containers, mode)
            const i = list.indexOf(name), j = i + dir
            if (i < 0 || j < 0 || j >= list.length) return
            if (mode !== "none" && G.groupOf(pd, list[j]) !== G.groupOf(pd, name)) return
            ;[list[i], list[j]] = [list[j], list[i]]
            order = list
            root.saveValue("order", list)
        }

        function moveGroup(name, dir) {
            const list = layout.map(g => g.name)
            const i = list.indexOf(name), j = i + dir
            if (i < 0 || j < 0 || j >= list.length) return
            ;[list[i], list[j]] = [list[j], list[i]]
            groupOrder = list
            root.saveValue("groupOrder", list)
        }

        function reset() {
            custom = {}; order = []; groupOrder = []
            root.saveValue("custom", {}); root.saveValue("order", []); root.saveValue("groupOrder", [])
        }

        StyledText {
            text: "Containers"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            color: Theme.surfaceText
        }
        StyledText {
            width: parent.width
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            text: "Give a container a display name, move it to another group (type an existing or new group name; leave empty for the default), and use the arrows to change the order. Changes save when you press Enter or leave the box."
        }
        StyledText {
            visible: org.containers.length === 0
            width: parent.width
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.warning
            text: "No containers yet. Set the SSH host above and wait for the first check."
        }

        Repeater {
            model: org.layout
            delegate: Column {
                id: grp
                required property var modelData
                required property int index
                width: org.width
                spacing: 4

                // group header with its own up/down arrows
                Item {
                    visible: grp.modelData.name !== ""
                    width: parent.width
                    height: visible ? 32 : 0
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: grp.modelData.name
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.DemiBold
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0.6
                        color: Theme.primary
                    }
                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        Repeater {
                            model: [{ icon: "arrow_upward", dir: -1 }, { icon: "arrow_downward", dir: 1 }]
                            delegate: StyledRect {
                                required property var modelData
                                readonly property bool enabledArrow: modelData.dir < 0 ? grp.index > 0 : grp.index < org.layout.length - 1
                                width: 28; height: 28; radius: 14
                                color: ga.containsMouse && enabledArrow ? Theme.chipSurface : "transparent"
                                DIcon { anchors.centerIn: parent; name: parent.modelData.icon; size: 16
                                        color: parent.enabledArrow ? Theme.primary : Theme.surfaceVariantText; opacity: parent.enabledArrow ? 1 : 0.35 }
                                MouseArea { id: ga; anchors.fill: parent; hoverEnabled: true
                                            cursorShape: parent.enabledArrow ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: if (parent.enabledArrow) org.moveGroup(grp.modelData.name, parent.modelData.dir) }
                            }
                        }
                    }
                }

                Repeater {
                    model: grp.modelData.members
                    delegate: Row {
                        id: crow
                        required property var modelData
                        required property int index
                        readonly property var entry: org.custom[modelData.name] || {}
                        spacing: Theme.spacingS
                        width: grp.width

                        StyledText {
                            width: Math.max(90, crow.width * 0.24)
                            anchors.verticalCenter: parent.verticalCenter
                            text: crow.modelData.name
                            elide: Text.ElideRight
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                        }
                        DTextField {
                            width: Math.max(110, crow.width * 0.30)
                            anchors.verticalCenter: parent.verticalCenter
                            placeholderText: "Display name"
                            text: crow.entry.name || ""
                            onEditingFinished: org.setField(crow.modelData.name, "name", text)
                        }
                        DTextField {
                            width: Math.max(100, crow.width * 0.26)
                            anchors.verticalCenter: parent.verticalCenter
                            placeholderText: G.defaultGroupOf(org.pd, crow.modelData.name)
                            text: crow.entry.group || ""
                            onEditingFinished: org.setField(crow.modelData.name, "group", text)
                        }
                        Repeater {
                            model: [{ icon: "arrow_upward", dir: -1 }, { icon: "arrow_downward", dir: 1 }]
                            delegate: StyledRect {
                                required property var modelData
                                readonly property bool enabledArrow: modelData.dir < 0 ? crow.index > 0 : crow.index < grp.modelData.members.length - 1
                                anchors.verticalCenter: parent.verticalCenter
                                width: 28; height: 28; radius: 14
                                color: ca.containsMouse && enabledArrow ? Theme.chipSurface : "transparent"
                                DIcon { anchors.centerIn: parent; name: parent.modelData.icon; size: 16
                                        color: parent.enabledArrow ? Theme.surfaceText : Theme.surfaceVariantText; opacity: parent.enabledArrow ? 1 : 0.35 }
                                MouseArea { id: ca; anchors.fill: parent; hoverEnabled: true
                                            cursorShape: parent.enabledArrow ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: if (parent.enabledArrow) org.move(crow.modelData.name, parent.modelData.dir) }
                            }
                        }
                    }
                }
            }
        }

        StyledRect {
            visible: Object.keys(org.custom).length > 0 || org.order.length > 0 || org.groupOrder.length > 0
            width: resetRow.implicitWidth + Theme.spacingM * 2
            height: 32
            radius: Theme.cornerRadius
            color: resetArea.containsMouse ? Theme.chipSurface : "transparent"
            Row {
                id: resetRow
                anchors.centerIn: parent
                spacing: Theme.spacingXS
                DIcon { name: "restart_alt"; size: 16; color: Theme.surfaceVariantText; anchors.verticalCenter: parent.verticalCenter }
                StyledText { text: "Reset names, groups and order"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { id: resetArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: org.reset() }
        }
    }

    ListSettingWithInput {
        settingKey: "links"
        label: "Links"
        description: "Optional. Where clicking a container opens, and the name shown next to it. Without a link, a container opens its first published port on the host (http://host:port)."
        fields: [
            { id: "container", label: "Container name", placeholder: "jellyfin", required: true, width: 140 },
            { id: "url", label: "Link", placeholder: "https://jellyfin.example.com", width: 220 },
            { id: "label", label: "Label (optional)", placeholder: "Films & TV", width: 130 }
        ]
    }
}
