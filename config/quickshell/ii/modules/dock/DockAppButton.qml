import qs.services
import qs.modules.common
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets

DockButton {
    id: root
    property var appToplevel
    property var appListRoot
    property int lastFocused: -1
    property real iconSize: 35
    property real countDotWidth: 10
    property real countDotHeight: 4
    property bool launchPending: false
    property real clickFlashOpacity: 0
    property bool appIsActive: appToplevel.toplevels.find(t => (t.activated == true)) !== undefined

    readonly property bool isSeparator: appToplevel.appId === "SEPARATOR"
    readonly property var desktopEntry: DesktopEntries.heuristicLookup(appToplevel.appId)
    enabled: !isSeparator
    implicitWidth: isSeparator ? 1 : implicitHeight - topInset - bottomInset

    function launchApp() {
        const entry = DesktopEntries.heuristicLookup(appToplevel.appId);
        if (entry) {
            entry.execute();
            return;
        }

        const fuzzyMatches = AppSearch.fuzzyQuery(appToplevel.appId);
        if (fuzzyMatches.length > 0) {
            fuzzyMatches[0].execute();
            return;
        }

        Hyprland.dispatch(`exec ${appToplevel.appId}`);
    }

    Loader {
        active: isSeparator
        anchors {
            fill: parent
            topMargin: dockVisualBackground.margin + dockRow.padding + Appearance.rounding.normal
            bottomMargin: dockVisualBackground.margin + dockRow.padding + Appearance.rounding.normal
        }
        sourceComponent: DockSeparator {}
    }

    Loader {
        anchors.fill: parent
        active: appToplevel.toplevels.length > 0
        sourceComponent: MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: {
                appListRoot.lastHoveredButton = root
                appListRoot.buttonHovered = true
                lastFocused = appToplevel.toplevels.length - 1
            }
            onExited: {
                if (appListRoot.lastHoveredButton === root) {
                    appListRoot.buttonHovered = false
                }
            }
        }
    }

    onClicked: {
        clickFlashAnim.restart();
        if (appToplevel.toplevels.length === 0) {
            launchPending = true;
            launchFeedbackTimer.restart();
            launchApp();
            return;
        }
        lastFocused = (lastFocused + 1) % appToplevel.toplevels.length
        appToplevel.toplevels[lastFocused].activate()
    }

    middleClickAction: () => {
        launchPending = true;
        launchFeedbackTimer.restart();
        clickFlashAnim.restart();
        launchApp();
    }

    altAction: () => {
        TaskbarApps.togglePin(appToplevel.appId);
    }

    Connections {
        target: appToplevel
        ignoreUnknownSignals: true
        function onToplevelsChanged() {
            if ((appToplevel?.toplevels?.length ?? 0) > 0) {
                launchPending = false;
                launchFeedbackTimer.stop();
            }
        }
    }

    Timer {
        id: launchFeedbackTimer
        interval: 1800
        running: false
        repeat: false
        onTriggered: launchPending = false
    }

    SequentialAnimation {
        id: clickFlashAnim
        PropertyAction { target: root; property: "clickFlashOpacity"; value: 0.32 }
        NumberAnimation {
            target: root
            property: "clickFlashOpacity"
            to: 0
            duration: 260
            easing.type: Easing.OutQuad
        }
    }

    contentItem: Loader {
        active: !isSeparator
        sourceComponent: Item {
            anchors.centerIn: parent
            scale: root.down ? 0.92 : (root.launchPending ? 0.97 : 1.0)

            Behavior on scale {
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }

            Loader {
                id: iconImageLoader
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                active: !root.isSeparator
                sourceComponent: IconImage {
                    source: Quickshell.iconPath(AppSearch.guessIcon(appToplevel.appId), "image-missing")
                    implicitSize: root.iconSize
                    opacity: root.launchPending ? 0.8 : 1
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 130
                            easing.type: Easing.OutQuad
                        }
                    }
                }
            }

            Rectangle {
                anchors {
                    fill: iconImageLoader
                    margins: -4
                }
                radius: Appearance.rounding.full
                color: Appearance.colors.colPrimary
                opacity: root.down ? 0.22 : (root.launchPending ? 0.14 : root.clickFlashOpacity)
                Behavior on opacity {
                    NumberAnimation {
                        duration: 130
                        easing.type: Easing.OutQuad
                    }
                }
            }

            Loader {
                active: Config.options.dock.monochromeIcons
                anchors.fill: iconImageLoader
                sourceComponent: Item {
                    Desaturate {
                        id: desaturatedIcon
                        visible: false // There's already color overlay
                        anchors.fill: parent
                        source: iconImageLoader
                        desaturation: 0.8
                    }
                    ColorOverlay {
                        anchors.fill: desaturatedIcon
                        source: desaturatedIcon
                        color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)
                    }
                }
            }

            RowLayout {
                spacing: 3
                anchors {
                    top: iconImageLoader.bottom
                    topMargin: 2
                    horizontalCenter: parent.horizontalCenter
                }
                Repeater {
                    model: root.launchPending && appToplevel.toplevels.length === 0 ? 1 : Math.min(appToplevel.toplevels.length, 3)
                    delegate: Rectangle {
                        required property int index
                        radius: Appearance.rounding.full
                        implicitWidth: (appToplevel.toplevels.length <= 3) ?
                            root.countDotWidth : root.countDotHeight // Circles when too many
                        implicitHeight: root.countDotHeight
                        color: (root.launchPending && appToplevel.toplevels.length === 0)
                            ? Appearance.colors.colPrimary
                            : (appIsActive ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4))
                        opacity: (root.launchPending && appToplevel.toplevels.length === 0) ? 0.45 : 1
                        SequentialAnimation on opacity {
                            running: root.launchPending && appToplevel.toplevels.length === 0
                            loops: Animation.Infinite
                            NumberAnimation { to: 1; duration: 250; easing.type: Easing.OutQuad }
                            NumberAnimation { to: 0.35; duration: 400; easing.type: Easing.InOutQuad }
                        }
                    }
                }
            }
        }
    }
}
