import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: button
    property string day
    property string dateKey: ""
    property int isToday
    property bool bold
    property bool selected: false
    property int eventCount: 0
    property color eventColor: Appearance.colors.colPrimary

    Layout.fillWidth: false
    Layout.fillHeight: false
    implicitWidth: 38; 
    implicitHeight: 38;

    toggled: selected || (isToday == 1)
    buttonRadius: Appearance.rounding.small
    
    contentItem: Item {
        anchors.fill: parent

        StyledText {
            anchors.fill: parent
            anchors.bottomMargin: button.eventCount > 0 ? 5 : 0
            text: button.day
            horizontalAlignment: Text.AlignHCenter
            font.weight: button.bold ? Font.DemiBold : Font.Normal
            color: (button.selected || button.isToday == 1) ? Appearance.m3colors.m3onPrimary :
                (button.isToday == 0) ? Appearance.colors.colOnLayer1 :
                Appearance.colors.colOutlineVariant

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4
            spacing: 2
            visible: button.eventCount > 0

            Repeater {
                model: Math.min(button.eventCount, 3)
                Rectangle {
                    required property int index
                    width: 4
                    height: 4
                    radius: 2
                    color: (button.selected || button.isToday == 1)
                        ? Appearance.m3colors.m3onPrimary
                        : button.eventColor
                }
            }
        }
    }
}
