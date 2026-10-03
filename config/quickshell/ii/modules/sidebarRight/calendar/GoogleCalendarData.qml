import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property var events: []
    property var calendars: []
    property string generatedAt: ""
    property string errorText: ""
    property bool refreshing: false
    property bool hasCache: events.length > 0 || generatedAt.length > 0

    readonly property string homePath: Quickshell.env("HOME")
    readonly property string cachePath: `${homePath}/.cache/illogical-impulse/google-calendar/events.json`
    readonly property string scriptPath: Quickshell.shellPath("scripts/calendar/google_calendar.py")

    function eventsOn(dateKey) {
        if (!dateKey) return []
        return events.filter(event => event.dateKey === dateKey)
    }

    function eventCount(dateKey) {
        return eventsOn(dateKey).length
    }

    function firstEventColor(dateKey) {
        const matching = eventsOn(dateKey)
        return matching.length > 0 ? matching[0].color : "transparent"
    }

    function loadCache() {
        cacheFile.reload()
    }

    function refresh() {
        if (refreshing) return
        errorText = ""
        refreshing = true
        refreshProcess.command = ["uv", "run", "--script", scriptPath, "refresh"]
        refreshProcess.running = true
    }

    function openSetup() {
        Quickshell.execDetached([
            "kitty", "--class", "google-calendar-setup", "--title", "Google Calendar Setup",
            "-e", "uv", "run", "--script", scriptPath, "setup"
        ])
    }

    function parseCache(text) {
        const payload = JSON.parse(text)
        events = Array.isArray(payload.events) ? payload.events : []
        calendars = Array.isArray(payload.calendars) ? payload.calendars : []
        generatedAt = payload.generatedAt ?? ""
        errorText = ""
    }

    Component.onCompleted: loadCache()

    FileView {
        id: cacheFile
        path: Qt.resolvedUrl(root.cachePath)
        onLoaded: {
            try {
                root.parseCache(cacheFile.text())
            } catch (error) {
                root.events = []
                root.calendars = []
                root.errorText = "Calendar cache is unreadable"
            }
        }
        onLoadFailed: error => {
            root.events = []
            root.calendars = []
            root.generatedAt = ""
        }
    }

    Process {
        id: refreshProcess
        property string stderrText: ""
        command: []
        stderr: SplitParser {
            onRead: line => {
                if (line) refreshProcess.stderrText = line
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.refreshing = false
            if (exitCode === 0) {
                root.loadCache()
            } else {
                root.errorText = refreshProcess.stderrText || "Calendar refresh failed"
            }
            refreshProcess.stderrText = ""
        }
    }
}
