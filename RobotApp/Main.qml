import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: window
    visible: true
    width: 1200
    height: 780
    title: "Robot Control Panel"

    background: Rectangle { color: "#141419" }

    // ============================================================
    // Main Layout
    // ============================================================
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        // ---------- Top Bar ----------
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                width: 14; height: 14; radius: 7
                color: backend.connected ? "#00adb5" : "#555"
            }

            Text {
                text: backend.connected ? "Connected to broker" : "Disconnected"
                color: "white"
                font.pixelSize: 14
            }

            Item { Layout.fillWidth: true }

            Text {
                text: "Robot Control"
                color: "#00adb5"
                font.pixelSize: 18
                font.bold: true
            }
        }

        // ---------- Central Row ----------
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            // =====================================================
            // Left Column: Robot Schema + Status
            // =====================================================
            ColumnLayout {
                Layout.preferredWidth: 400
                Layout.fillHeight: true
                spacing: 10

                // ----- Robot Schema (top view, vertical) -----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 400
                    color: "#1b1b22"
                    border.color: "#393e46"
                    border.width: 1
                    radius: 10

                    // Chassis background color based on state
                    property color chassisColor: {
                        if (backend.mode === "autonomous")
                            return "#4a2e5a" // Purple
                        if (backend.leftPower !== 0 || backend.rightPower !== 0)
                            return "#1e3a5f" // Steel Blue
                        return "#2a2a33"     // Dark Gray
                    }

                    // ----- Chassis (vertical rounded body, front pointing up) -----
                    Rectangle {
                        id: chassis
                        anchors.centerIn: parent
                        width: 150
                        height: 330
                        radius: 50
                        color: parent.chassisColor
                        border.color: "#00adb5"
                        border.width: 3

                        Behavior on color { ColorAnimation { duration: 300 } }

                        // Longitudinal axis line (Decorative, now vertical)
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            width: 2
                            height: parent.height - 90
                            color: "#00adb5"
                            opacity: 0.15
                        }

                        // ----- Wheels (along the long sides of the chassis) -----
                        // Left Front
                        Rectangle {
                            width: 30; height: 84; radius: 8
                            x: -15
                            y: 45
                            // Color based on direction: Cyan for forward, Burnt Orange for reverse
                            color: backend.leftPower > 0 ? "#00adb5"
                                 : backend.leftPower < 0 ? "#d65a31"
                                 : "#3a3a45"
                            border.color: "#393e46"
                            border.width: 2
                            Behavior on color { ColorAnimation { duration: 200 } }

                            Text {
                                anchors.centerIn: parent
                                text: backend.leftPower > 0 ? "▲"
                                    : backend.leftPower < 0 ? "▼"
                                    : "•"
                                color: "white"
                                font.pixelSize: 16
                                font.bold: true
                            }
                        }

                        // Right Front
                        Rectangle {
                            width: 30; height: 84; radius: 8
                            x: parent.width - 15
                            y: 45
                            color: backend.rightPower > 0 ? "#00adb5"
                                 : backend.rightPower < 0 ? "#d65a31"
                                 : "#3a3a45"
                            border.color: "#393e46"
                            border.width: 2
                            Behavior on color { ColorAnimation { duration: 200 } }

                            Text {
                                anchors.centerIn: parent
                                text: backend.rightPower > 0 ? "▲"
                                    : backend.rightPower < 0 ? "▼"
                                    : "•"
                                color: "white"
                                font.pixelSize: 16
                                font.bold: true
                            }
                        }

                        // Left Rear
                        Rectangle {
                            width: 30; height: 84; radius: 8
                            x: -15
                            y: parent.height - 129
                            color: backend.leftPower > 0 ? "#00adb5"
                                 : backend.leftPower < 0 ? "#d65a31"
                                 : "#3a3a45"
                            border.color: "#393e46"
                            border.width: 2
                            Behavior on color { ColorAnimation { duration: 200 } }

                            Text {
                                anchors.centerIn: parent
                                text: backend.leftPower > 0 ? "▲"
                                    : backend.leftPower < 0 ? "▼"
                                    : "•"
                                color: "white"
                                font.pixelSize: 16
                                font.bold: true
                            }
                        }

                        // Right Rear
                        Rectangle {
                            width: 30; height: 84; radius: 8
                            x: parent.width - 15
                            y: parent.height - 129
                            color: backend.rightPower > 0 ? "#00adb5"
                                 : backend.rightPower < 0 ? "#d65a31"
                                 : "#3a3a45"
                            border.color: "#393e46"
                            border.width: 2
                            Behavior on color { ColorAnimation { duration: 200 } }

                            Text {
                                anchors.centerIn: parent
                                text: backend.rightPower > 0 ? "▲"
                                    : backend.rightPower < 0 ? "▼"
                                    : "•"
                                color: "white"
                                font.pixelSize: 16
                                font.bold: true
                            }
                        }

                        // "FRONT" Label
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: 14
                            text: "FRONT"
                            color: "#00adb5"
                            font.pixelSize: 10
                            font.bold: true
                            opacity: 0.5
                        }
                    }
                }

                // ----- Status Panel -----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150
                    color: "#1b1b22"
                    border.color: "#393e46"
                    border.width: 1
                    radius: 10

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 8

                        Text {
                            text: "Robot Status"
                            color: "#00adb5"
                            font.pixelSize: 14
                            font.bold: true
                        }

                        GridLayout {
                            columns: 2
                            rowSpacing: 6
                            columnSpacing: 20

                            Text { text: "Left motor:"; color: "#aaa"; font.pixelSize: 13 }
                            Text {
                                text: backend.leftPower
                                color: backend.leftPower > 0 ? "#00adb5"
                                     : backend.leftPower < 0 ? "#d65a31"
                                     : "#777"
                                font.pixelSize: 13
                                font.bold: true
                            }

                            Text { text: "Right motor:"; color: "#aaa"; font.pixelSize: 13 }
                            Text {
                                text: backend.rightPower
                                color: backend.rightPower > 0 ? "#00adb5"
                                     : backend.rightPower < 0 ? "#d65a31"
                                     : "#777"
                                font.pixelSize: 13
                                font.bold: true
                            }

                            Text { text: "Mode:"; color: "#aaa"; font.pixelSize: 13 }
                            Text {
                                text: backend.mode
                                color: backend.mode === "autonomous" ? "#b388ff" : "#00adb5"
                                font.pixelSize: 13
                                font.bold: true
                            }

                            Text { text: "Brake mode:"; color: "#aaa"; font.pixelSize: 13 }
                            Text {
                                text: backend.brakeMode
                                color: backend.brakeMode === "brake" ? "#d65a31" : "#00adb5"
                                font.pixelSize: 13
                                font.bold: true
                            }
                        }
                    }
                }
            }

            // =====================================================
            // Right Column: Joystick, Commands & Last Responses
            // =====================================================
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 14

                // ----- Joystick + Buttons -----
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 280
                    spacing: 24

                    // --- Joystick ---
                    ColumnLayout {
                        Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                        spacing: 10

                        Text {
                            text: "Joystick"
                            color: "#00adb5"
                            font.pixelSize: 16
                            font.bold: true
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Rectangle {
                            id: joystickBase
                            width: 200
                            height: 200
                            radius: width / 2
                            color: "#222831"
                            border.color: "#393e46"
                            border.width: 4

                            property real outputX: 0
                            property real outputY: 0
                            property int lastSentX: 0
                            property int lastSentY: 0

                            Rectangle {
                                id: joystickStick
                                width: 74
                                height: 74
                                radius: width / 2
                                color: "#00adb5"

                                x: (joystickBase.width / 2) - (width / 2)
                                y: (joystickBase.height / 2) - (height / 2)

                                Behavior on x { NumberAnimation { duration: 50; easing.type: Easing.OutQuad } }
                                Behavior on y { NumberAnimation { duration: 50; easing.type: Easing.OutQuad } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                preventStealing: true

                                function updateJoystickPosition(mx, my) {
                                    const cx = joystickBase.width / 2;
                                    const cy = joystickBase.height / 2;
                                    const dx = mx - cx;
                                    const dy = my - cy;
                                    const dist = Math.sqrt(dx * dx + dy * dy);
                                    const maxD = (joystickBase.width / 2) - (joystickStick.width / 2);

                                    if (dist > maxD) {
                                        const a = Math.atan2(dy, dx);
                                        joystickStick.x = cx + Math.cos(a) * maxD - (joystickStick.width / 2);
                                        joystickStick.y = cy + Math.sin(a) * maxD - (joystickStick.height / 2);
                                        joystickBase.outputX = Math.cos(a) * 100;
                                        joystickBase.outputY = -Math.sin(a) * 100;
                                    } else {
                                        joystickStick.x = mx - (joystickStick.width / 2);
                                        joystickStick.y = my - (joystickStick.height / 2);
                                        joystickBase.outputX = (dx / maxD) * 100;
                                        joystickBase.outputY = -(dy / maxD) * 100;
                                    }

                                    const xi = Math.round(joystickBase.outputX);
                                    const yi = Math.round(joystickBase.outputY);

                                    if (xi !== joystickBase.lastSentX || yi !== joystickBase.lastSentY) {
                                        joystickBase.lastSentX = xi;
                                        joystickBase.lastSentY = yi;
                                        backend.actualizar_joystick(xi, yi);
                                    }
                                }

                                onPositionChanged: (m) => updateJoystickPosition(m.x, m.y)
                                onPressed:         (m) => updateJoystickPosition(m.x, m.y)

                                onReleased: {
                                    joystickStick.x = (joystickBase.width / 2) - (joystickStick.width / 2);
                                    joystickStick.y = (joystickBase.height / 2) - (joystickStick.height / 2);
                                    joystickBase.outputX = 0;
                                    joystickBase.outputY = 0;
                                    joystickBase.lastSentX = 0;
                                    joystickBase.lastSentY = 0;
                                    backend.actualizar_joystick(0, 0);
                                }
                            }
                        }

                        Text {
                            text: "X: " + Math.round(joystickBase.outputX) +
                                  " | Y: " + Math.round(joystickBase.outputY)
                            color: "white"
                            font.pixelSize: 13
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }

                    // --- Command Buttons ---
                    ColumnLayout {
                        Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                        spacing: 10

                        Text {
                            text: "Commands"
                            color: "#00adb5"
                            font.pixelSize: 16
                            font.bold: true
                            Layout.alignment: Qt.AlignHCenter
                        }

                        GridLayout {
                            columns: 2
                            rowSpacing: 10
                            columnSpacing: 10

                            Button {
                                text: "Forward"
                                Layout.preferredWidth: 120
                                Layout.preferredHeight: 44
                                onClicked: backend.send_command("A 0 100")
                            }
                            Button {
                                text: "Backward"
                                Layout.preferredWidth: 120
                                Layout.preferredHeight: 44
                                onClicked: backend.send_command("A 0 -100")
                            }
                            Button {
                                text: "Left"
                                Layout.preferredWidth: 120
                                Layout.preferredHeight: 44
                                onClicked: backend.send_command("A -100 0")
                            }
                            Button {
                                text: "Right"
                                Layout.preferredWidth: 120
                                Layout.preferredHeight: 44
                                onClicked: backend.send_command("A 100 0")
                            }
                            Button {
                                text: "Stop"
                                Layout.preferredWidth: 120
                                Layout.preferredHeight: 44
                                highlighted: true
                                onClicked: backend.send_command("X")
                            }
                            Button {
                                text: "Square Auto"
                                Layout.preferredWidth: 120
                                Layout.preferredHeight: 44
                                onClicked: backend.send_command("S 100 2000 800")
                            }
                        }

                        // --- Brake Mode ---
                        Text {
                            text: "Brake Mode"
                            color: "#00adb5"
                            font.pixelSize: 13
                            font.bold: true
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 8
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 10

                            Button {
                                text: "Coast"
                                Layout.preferredWidth: 110
                                Layout.preferredHeight: 40
                                checkable: true
                                checked: backend.brakeMode === "coast"
                                onClicked: backend.set_brake_mode("coast")
                            }
                            Button {
                                text: "Brake"
                                Layout.preferredWidth: 110
                                Layout.preferredHeight: 40
                                checkable: true
                                checked: backend.brakeMode === "brake"
                                onClicked: backend.set_brake_mode("brake")
                            }
                        }
                    }
                }

                // ----- Last Responses (last 10, newest first, no scrolling) -----
                Rectangle {
                    Layout.fillWidth: true
                    // Fixed height: header + 10 lines. Sized so no scrolling is needed.
                    Layout.preferredHeight: 250
                    Layout.maximumHeight: 250
                    color: "#1b1b22"
                    border.color: "#393e46"
                    border.width: 2
                    radius: 10

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Last Response"
                                color: "#00adb5"
                                font.pixelSize: 14
                                font.bold: true
                            }
                            Item { Layout.fillWidth: true }
                            Button {
                                text: "Clear"
                                Layout.preferredWidth: 70
                                Layout.preferredHeight: 26
                                onClicked: backend.clear_response()
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: "#101015"
                            radius: 4
                            clip: true

                            Column {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 2

                                Repeater {
                                    model: backend.lastResponses

                                    Text {
                                        width: parent.width
                                        height: 17
                                        text: modelData
                                        elide: Text.ElideRight
                                        color: "#e0e0e0"
                                        font.family: "monospace"
                                        font.pixelSize: 13
                                        // Dim older entries slightly to highlight the newest one
                                        opacity: index === 0 ? 1.0 : 0.7
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
