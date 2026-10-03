import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "calendar_layout.js" as CalendarLayout
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    property int monthShift: 0
    property var viewingDate: CalendarLayout.getDateInXMonthsTime(monthShift)
    property var calendarLayout: CalendarLayout.getCalendarLayout(viewingDate, monthShift === 0)
    property string selectedDateKey: localDateKey(new Date())
    property bool showingAgenda: false

    implicitWidth: 340
    implicitHeight: 350

    function localDateKey(value) {
        const year = value.getFullYear()
        const month = String(value.getMonth() + 1).padStart(2, "0")
        const day = String(value.getDate()).padStart(2, "0")
        return `${year}-${month}-${day}`
    }

    function selectedDateTitle() {
        const value = new Date(`${selectedDateKey}T12:00:00`)
        return value.toLocaleDateString(Qt.locale(), "dddd, MMMM d")
    }

    function eventTime(event) {
        if (event.itemType === "task") return Translation.tr("Task")
        if (event.allDay) return Translation.tr("All day")
        const start = new Date(event.start)
        const end = new Date(event.end)
        if (Number.isNaN(start.getTime())) return ""
        const startText = Qt.formatTime(start, "h:mm AP")
        if (Number.isNaN(end.getTime())) return startText
        return `${startText} – ${Qt.formatTime(end, "h:mm AP")}`
    }

    function openDay(dateKey) {
        selectedDateKey = dateKey
        showingAgenda = true
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape && showingAgenda) {
            showingAgenda = false
            event.accepted = true
        } else if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp)
            && event.modifiers === Qt.NoModifier && !showingAgenda) {
            monthShift += event.key === Qt.Key_PageDown ? 1 : -1
            event.accepted = true
        }
    }

    GoogleCalendarData {
        id: calendarData
    }

    StackLayout {
        id: calendarStack
        anchors.fill: parent
        currentIndex: root.showingAgenda ? 1 : 0

        // Month grid
        Item {
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                onWheel: event => {
                    if (event.angleDelta.y > 0) root.monthShift--
                    else if (event.angleDelta.y < 0) root.monthShift++
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 5

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    CalendarHeaderButton {
                        clip: true
                        buttonText: `${root.monthShift !== 0 ? "• " : ""}${root.viewingDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")}`
                        tooltipText: root.monthShift === 0 ? "" : Translation.tr("Jump to current month")
                        downAction: () => root.monthShift = 0
                    }
                    Item { Layout.fillWidth: true }
                    CalendarHeaderButton {
                        forceCircle: true
                        tooltipText: Translation.tr("Connect or repair Google Calendar")
                        downAction: () => calendarData.openSetup()
                        contentItem: MaterialSymbol {
                            text: "link"
                            iconSize: Appearance.font.pixelSize.larger
                            horizontalAlignment: Text.AlignHCenter
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                    CalendarHeaderButton {
                        forceCircle: true
                        enabled: !calendarData.refreshing
                        tooltipText: calendarData.errorText || Translation.tr("Refresh Google Calendar")
                        downAction: () => calendarData.refresh()
                        contentItem: MaterialSymbol {
                            text: calendarData.refreshing ? "progress_activity" : "refresh"
                            iconSize: Appearance.font.pixelSize.larger
                            horizontalAlignment: Text.AlignHCenter
                            color: calendarData.errorText ? Appearance.colors.colError : Appearance.colors.colOnLayer1
                            RotationAnimation on rotation {
                                running: calendarData.refreshing
                                from: 0
                                to: 360
                                duration: 900
                                loops: Animation.Infinite
                            }
                        }
                    }
                    CalendarHeaderButton {
                        forceCircle: true
                        downAction: () => root.monthShift--
                        contentItem: MaterialSymbol {
                            text: "chevron_left"
                            iconSize: Appearance.font.pixelSize.larger
                            horizontalAlignment: Text.AlignHCenter
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                    CalendarHeaderButton {
                        forceCircle: true
                        downAction: () => root.monthShift++
                        contentItem: MaterialSymbol {
                            text: "chevron_right"
                            iconSize: Appearance.font.pixelSize.larger
                            horizontalAlignment: Text.AlignHCenter
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 5
                    Repeater {
                        model: CalendarLayout.weekDays
                        delegate: CalendarDayButton {
                            required property var modelData
                            day: modelData.day
                            isToday: modelData.today
                            bold: true
                            enabled: false
                        }
                    }
                }

                Repeater {
                    model: 6
                    delegate: RowLayout {
                        required property int index
                        property int weekIndex: index
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 5

                        Repeater {
                            model: root.calendarLayout[weekIndex]
                            delegate: CalendarDayButton {
                                required property var modelData
                                day: modelData.day
                                dateKey: modelData.dateKey
                                isToday: modelData.today
                                selected: root.selectedDateKey === modelData.dateKey && root.showingAgenda
                                eventCount: calendarData.eventCount(modelData.dateKey)
                                eventColor: calendarData.firstEventColor(modelData.dateKey)
                                downAction: () => root.openDay(modelData.dateKey)
                            }
                        }
                    }
                }
            }
        }

        // Calendar events and Google Tasks for the selected date
        Item {
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    CalendarHeaderButton {
                        forceCircle: true
                        tooltipText: Translation.tr("Back to month")
                        downAction: () => root.showingAgenda = false
                        contentItem: MaterialSymbol {
                            text: "arrow_back"
                            iconSize: Appearance.font.pixelSize.larger
                            horizontalAlignment: Text.AlignHCenter
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.selectedDateTitle()
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }
                    CalendarHeaderButton {
                        forceCircle: true
                        enabled: !calendarData.refreshing
                        tooltipText: calendarData.errorText || Translation.tr("Refresh Google Calendar")
                        downAction: () => calendarData.refresh()
                        contentItem: MaterialSymbol {
                            text: calendarData.refreshing ? "progress_activity" : "refresh"
                            iconSize: Appearance.font.pixelSize.larger
                            horizontalAlignment: Text.AlignHCenter
                            color: calendarData.errorText ? Appearance.colors.colError : Appearance.colors.colOnLayer1
                            RotationAnimation on rotation {
                                running: calendarData.refreshing
                                from: 0
                                to: 360
                                duration: 900
                                loops: Animation.Infinite
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    visible: calendarData.errorText.length > 0
                    implicitHeight: errorText.implicitHeight + 14
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2

                    StyledText {
                        id: errorText
                        anchors.fill: parent
                        anchors.margins: 7
                        text: calendarData.errorText
                        color: Appearance.colors.colError
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }

                ListView {
                    id: agendaList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 6
                    model: calendarData.eventsOn(root.selectedDateKey)

                    delegate: Rectangle {
                        id: eventCard
                        required property var modelData
                        width: agendaList.width
                        implicitHeight: Math.max(58, eventColumn.implicitHeight + 18)
                        radius: Appearance.rounding.small
                        color: eventMouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 4
                            radius: 2
                            color: eventCard.modelData.color || Appearance.colors.colPrimary
                        }

                        ColumnLayout {
                            id: eventColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 14
                            anchors.rightMargin: 10
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                text: eventCard.modelData.title
                                font.weight: Font.DemiBold
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer2
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: {
                                    let detail = root.eventTime(eventCard.modelData)
                                    if (eventCard.modelData.location) detail += `  •  ${eventCard.modelData.location}`
                                    return detail
                                }
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: eventCard.modelData.calendarName
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: eventCard.modelData.color || Appearance.colors.colPrimary
                                elide: Text.ElideRight
                            }
                        }

                        MaterialSymbol {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 10
                            visible: eventCard.modelData.itemType === "task"
                            text: "task_alt"
                            iconSize: Appearance.font.pixelSize.normal
                            color: eventCard.modelData.color || Appearance.colors.colPrimary
                        }

                        MouseArea {
                            id: eventMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: eventCard.modelData.link ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (eventCard.modelData.link) Qt.openUrlExternally(eventCard.modelData.link)
                            }
                        }
                    }

                    ScrollBar.vertical: ScrollBar {}
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: agendaList.count === 0
                    spacing: 8

                    Item { Layout.fillHeight: true }
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: calendarData.hasCache ? "event_available" : "cloud_off"
                        iconSize: 34
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: calendarData.hasCache
                            ? Translation.tr("No events or tasks on this day")
                            : Translation.tr("Connect Google Calendar to see events and tasks")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.normal
                        wrapMode: Text.Wrap
                    }
                    CalendarHeaderButton {
                        Layout.alignment: Qt.AlignHCenter
                        visible: !calendarData.hasCache
                        buttonText: Translation.tr("Set up Google Calendar")
                        downAction: () => calendarData.openSetup()
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }
}
