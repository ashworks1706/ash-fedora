pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

// Read-only search adapter for the on-demand Google Calendar cache. It never
// contacts Google; changes are picked up when the calendar refresh rewrites
// the cache file.
Singleton {
    id: root

    property string cachePath: `${Directories.home}/.cache/illogical-impulse/google-calendar/events.json`
    property list<var> entries: []
    readonly property var preparedEntries: entries.map(entry => ({
        name: Fuzzy.prepare(`${entry.title} ${entry.calendarName} ${entry.description} ${entry.location} ${entry.dateKey}`),
        entry: entry
    }))

    function todayKey(): string {
        const now = new Date();
        const month = String(now.getMonth() + 1).padStart(2, "0");
        const day = String(now.getDate()).padStart(2, "0");
        return `${now.getFullYear()}-${month}-${day}`;
    }

    function fuzzyQuery(search: string): var {
        const query = search.trim();
        if (query.length === 0) {
            return entries
                .filter(entry => entry.dateKey >= todayKey())
                .slice(0, 30);
        }
        return Fuzzy.go(query, preparedEntries, {
            all: true,
            key: "name"
        }).map(result => result.obj.entry).slice(0, 30);
    }

    function load(): void {
        cacheFile.reload();
    }

    FileView {
        id: cacheFile
        path: Qt.resolvedUrl(root.cachePath)
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const payload = JSON.parse(cacheFile.text());
                root.entries = Array.isArray(payload.events) ? payload.events : [];
            } catch (error) {
                root.entries = [];
                console.warn("[CalendarSearch] Could not parse calendar cache:", error);
            }
        }
        onLoadFailed: root.entries = []
    }

    Component.onCompleted: load()
}
