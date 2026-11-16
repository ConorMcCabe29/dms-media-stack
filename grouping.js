.pragma library
// Shared by the bar widget and the settings page, so both list containers the same way.
//
// Settings used (all optional, from pluginData):
//   custom:     { "<container>": { name: "Display name", group: "Group name" } }
//   order:      ["jellyfin", "navidrome", ...]  container order; unlisted ones follow the built-in order, then A-Z
//   groupOrder: ["Media", "Downloading", ...]   group order; unlisted ones follow the defaults
//   groups:     advanced, hand-edited replacement for defaultGroups below
//   links / labels: the grey label shown after a container's name

var defaultLabels = {
    "jellyfin": "Films & TV", "plex": "Films & TV", "emby": "Films & TV",
    "seerr": "Requests", "jellyseerr": "Requests", "overseerr": "Requests", "ombi": "Requests",
    "radarr": "Films", "sonarr": "TV shows", "lidarr": "Music", "readarr": "Books", "bazarr": "Subtitles",
    "prowlarr": "Indexers", "jackett": "Indexers", "flaresolverr": "Cloudflare bypass",
    "qbittorrent": "Downloads", "transmission": "Downloads", "sabnzbd": "Downloads", "nzbget": "Downloads",
    "slskd": "Soulseek", "soularr": "Soulseek ↔ Lidarr",
    "navidrome": "Music streaming", "audiobookshelf": "Audiobooks", "recommendarr": "Recommendations",
    "gluetun": "VPN", "vpn": "VPN"
};

var defaultGroups = [
    { name: "Media",       collapsible: false,
                           members: ["jellyfin", "plex", "emby", "navidrome", "audiobookshelf", "novel-reader"] },
    { name: "Request",     members: ["seerr", "jellyseerr", "overseerr", "ombi", "recommendarr"] },
    { name: "Libraries",   members: ["radarr", "sonarr", "lidarr", "readarr", "bazarr"] },
    { name: "Downloading", members: ["qbittorrent", "transmission", "sabnzbd", "nzbget", "prowlarr", "jackett",
                                     "slskd", "soularr", "flaresolverr", "gluetun", "vpn"] }
];

function baseGroups(pd) { return (pd && pd.groups) || defaultGroups; }

function custom(pd, name) { return ((pd && pd.custom) || {})[name] || {}; }

function displayName(pd, name) { return custom(pd, name).name || name; }

function label(pd, name) {
    var links = (pd && pd.links) || [];
    for (var i = 0; i < links.length; i++)
        if (links[i].container === name && links[i].label) return links[i].label;
    var labels = (pd && pd.labels) || {};
    if (labels[name] !== undefined) return labels[name];
    return defaultLabels[name] || "";
}

// Group a container is in when nobody has picked one for it.
function defaultGroupOf(pd, name) {
    var gs = baseGroups(pd);
    for (var i = 0; i < gs.length; i++)
        if (gs[i].members.indexOf(name) >= 0) return gs[i].name;
    return "Other";
}

function groupOf(pd, name) { return custom(pd, name).group || defaultGroupOf(pd, name); }

// Order: the user's "order" list first, then the built-in group order, then A-Z.
function sortContainers(pd, list) {
    var order = (pd && pd.order) || [];
    var builtIn = [].concat.apply([], baseGroups(pd).map(function (g) { return g.members; }));
    var rank = function (arr, name) { var i = arr.indexOf(name); return i < 0 ? 1e9 : i; };
    return list.slice().sort(function (a, b) {
        return rank(order, a.name) - rank(order, b.name)
            || rank(builtIn, a.name) - rank(builtIn, b.name)
            || displayName(pd, a.name).localeCompare(displayName(pd, b.name));
    });
}

// -> [{ name, collapsible, members: [container, ...] }] with empty groups left out.
function build(pd, containers) {
    var byGroup = {};
    var sorted = sortContainers(pd, containers || []);
    for (var i = 0; i < sorted.length; i++) {
        var g = groupOf(pd, sorted[i].name);
        (byGroup[g] = byGroup[g] || []).push(sorted[i]);
    }
    var names = [];
    var add = function (n) { if (byGroup[n] && names.indexOf(n) < 0) names.push(n); };
    ((pd && pd.groupOrder) || []).forEach(add);
    baseGroups(pd).forEach(function (g) { add(g.name); });
    Object.keys(byGroup).filter(function (n) { return n !== "Other"; }).sort().forEach(add);
    add("Other");
    return names.map(function (n) {
        var def = baseGroups(pd).filter(function (g) { return g.name === n; })[0];
        return { name: n, collapsible: def && def.collapsible === false ? false : true, members: byGroup[n] };
    });
}

// Container names in the order they're shown, for the given grouping mode.
function flatOrder(pd, containers, mode) {
    var list = mode === "none" ? sortContainers(pd, containers || [])
        : [].concat.apply([], build(pd, containers).map(function (g) { return g.members; }));
    return list.map(function (c) { return c.name; });
}
