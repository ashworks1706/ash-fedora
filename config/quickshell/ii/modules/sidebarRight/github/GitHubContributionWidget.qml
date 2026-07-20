import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Rectangle {
    id: root

    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1
    implicitHeight: 142

    property bool refreshing: false
    property string errorText: ""
    property string username: Config.options.sidebar.github?.username ?? "your-github-username"
    property int requestedWeeks: Config.options.sidebar.github?.weeks ?? 26
    property string tokenFilePath: trimFileProtocol(Config.options.sidebar.github?.tokenFilePath ?? `${Directories.config}/quickshell/ii/secrets/github_token`)
    property string cachePath: trimFileProtocol(Config.options.sidebar.github?.cachePath ?? `${Directories.state}/user/github-contributions.json`)
    property string scriptPath: Quickshell.shellPath("scripts/github/fetch_contributions.py")
    property var contributionWeeks: []
    property var cells: []
    property int total: 0
    property string updatedAt: ""
    property string source: "cache"

    function trimFileProtocol(path) {
        const text = String(path ?? "")
        return text.startsWith("file://") ? text.slice(7) : text
    }

    function rebuildCells() {
        const next = []
        for (let weekIndex = 0; weekIndex < contributionWeeks.length; ++weekIndex) {
            const days = contributionWeeks[weekIndex].days ?? []
            for (let dayIndex = 0; dayIndex < 7; ++dayIndex) {
                const day = days[dayIndex] ?? { count: 0, level: 0, date: "" }
                next.push({
                    weekIndex: weekIndex,
                    dayIndex: dayIndex,
                    count: day.count ?? 0,
                    level: day.level ?? 0,
                    date: day.date ?? ""
                })
            }
        }
        cells = next
    }

    function loadCache() {
        cacheFileView.reload()
    }

    function refresh() {
        if (refreshing) return
        errorText = ""
        refreshing = true
        fetchProcess.command = [
            scriptPath,
            "--username", username,
            "--token-file", tokenFilePath,
            "--cache", cachePath,
            "--weeks", String(requestedWeeks)
        ]
        fetchProcess.running = true
    }

    function parseCache(text) {
        const payload = JSON.parse(text)
        username = payload.username ?? username
        contributionWeeks = Array.isArray(payload.weeks) ? payload.weeks : []
        total = payload.total ?? 0
        updatedAt = payload.updatedAt ?? ""
        source = payload.source ?? "cache"
        rebuildCells()
    }

    function levelColor(level) {
        const accent = Appearance.colors.colPrimary
        const empty = Appearance.colors.colOnLayer1
        if (level <= 0) return Qt.rgba(empty.r, empty.g, empty.b, 0.10)
        if (level === 1) return Qt.rgba(accent.r, accent.g, accent.b, 0.42)
        if (level === 2) return Qt.rgba(accent.r, accent.g, accent.b, 0.62)
        if (level === 3) return Qt.rgba(accent.r, accent.g, accent.b, 0.82)
        return Appearance.colors.colPrimary
    }

    function formatUpdatedAt(value) {
        if (!value) return Translation.tr("Never refreshed")
        const date = new Date(value)
        if (Number.isNaN(date.getTime())) return Translation.tr("Cache loaded")
        return Translation.tr("Updated %1").arg(Qt.formatDateTime(date, "MMM d, h:mm AP"))
    }

    Component.onCompleted: loadCache()

    FileView {
        id: cacheFileView
        path: Qt.resolvedUrl(root.cachePath)
        onLoaded: {
            try {
                root.parseCache(cacheFileView.text())
                root.errorText = ""
            } catch (error) {
                root.errorText = Translation.tr("Could not read GitHub cache")
                root.contributionWeeks = []
                root.cells = []
            }
        }
        onLoadFailed: error => {
            root.contributionWeeks = []
            root.cells = []
            root.errorText = ""
        }
    }

    Process {
        id: fetchProcess
        property string stderrText: ""
        command: []
        stderr: SplitParser {
            onRead: line => {
                if (line) fetchProcess.stderrText = line
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.refreshing = false
            if (exitCode === 0) {
                root.loadCache()
            } else {
                root.errorText = fetchProcess.stderrText || Translation.tr("GitHub refresh failed")
            }
            fetchProcess.stderrText = ""
        }
    }

    Item {
        anchors.fill: parent
        anchors.margins: 12

        Item {
            id: heatmapArea
            anchors.fill: parent
            visible: root.cells.length > 0
            readonly property int weekCount: Math.max(1, root.contributionWeeks.length)
            readonly property real gap: 4
            readonly property real cellSize: Math.max(6, Math.min((width - ((weekCount - 1) * gap)) / weekCount, (height - (6 * gap)) / 7))

            GridLayout {
                anchors.centerIn: parent
                rows: 7
                columns: heatmapArea.weekCount
                rowSpacing: heatmapArea.gap
                columnSpacing: heatmapArea.gap

                Repeater {
                    model: root.cells
                    Rectangle {
                        required property var modelData
                        Layout.row: modelData.dayIndex
                        Layout.column: modelData.weekIndex
                        Layout.preferredWidth: heatmapArea.cellSize
                        Layout.preferredHeight: heatmapArea.cellSize
                        radius: Math.max(2, heatmapArea.cellSize * 0.22)
                        color: root.levelColor(modelData.level)

                        ToolTip.visible: cellMouseArea.containsMouse
                        ToolTip.text: modelData.date ? Translation.tr("%1 contributions on %2").arg(modelData.count).arg(modelData.date) : ""

                        MouseArea {
                            id: cellMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            visible: root.cells.length === 0
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2

            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - 20
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.errorText || Translation.tr("No contribution cache yet")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer2
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("Click refresh to fetch GitHub")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }

        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            implicitWidth: 32
            implicitHeight: 32
            radius: Appearance.rounding.full
            color: refreshMouseArea.containsMouse ? Appearance.colors.colLayer2Hover : Qt.rgba(0, 0, 0, 0.18)

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.refreshing ? "sync" : "refresh"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnLayer2
                RotationAnimation on rotation {
                    running: root.refreshing
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 900
                }
            }

            MouseArea {
                id: refreshMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: !root.refreshing
                onClicked: root.refresh()
            }
        }
    }
}
