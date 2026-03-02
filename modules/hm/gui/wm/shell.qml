import Quickshell
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

PanelWindow {
    id: bar
    screen: primaryScreen
    anchors.top: true
    anchors.left: true
    anchors.right: true
    height: 32

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Item { Layout.preferredWidth: 12 }

        Text {
            text: new Date().toLocaleTimeString(Qt.locale(), "HH:mm")
            Timer {
                interval: 1000
                running: true
                onTriggered: bar.update()
            }
            color: "#cdd6f4"
            font.pixelSize: 14
            font.family: "JetBrains Mono"
        }

        Item { Layout.preferredWidth: 8 }

        Text {
            text: new Date().toLocaleDateString(Qt.locale(), "ddd MMM d")
            color: "#a6adc8"
            font.pixelSize: 14
            font.family: "JetBrains Mono"
        }

        Item { Layout.preferredWidth: 0; Layout.fillWidth: true }

        RowLayout {
            spacing: 4
            Repeater {
                model: SystemTray.items
                Image {
                    source: modelData.icon
                    width: 18
                    height: 18
                }
            }
        }

        Item { Layout.preferredWidth: 12 }
    }
}
