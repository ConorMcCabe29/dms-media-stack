import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

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
        settingKey: "listHeight"
        label: "List height (px)"
        description: "Tallest the container list gets before it scrolls. Type a number of pixels, at least 150."
        placeholder: "600"
        defaultValue: "600"
    }
    SliderSetting {
        settingKey: "popoutWidth"
        label: "Popout width"
        minimum: 300
        maximum: 800
        defaultValue: 380
        unit: "px"
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
