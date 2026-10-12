import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: window
    visible: true
    width: 1000
    height: 720
    title: "Touch panel - Robot Control"

    background: Rectangle { color: "#141419" }

    // ============================================================
    // Layout principal
    // ============================================================
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 12

        // ---------- Barra superior ----------
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                width: 14
                height: 14
                radius: 7
                color: backend.connected ? "#4caf50" : "#f44336"
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

        // ---------- Estado actual del robot ----------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            color: "#1b1b22"
            border.color: "#393e46"
            border.width: 1
            radius: 8

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 24

                Text {
                    text: "State:"
                    color: "#00adb5"
                    font.pixelSize: 14
                    font.bold: true
                }

                Text {
                    text: "L: " + backend.leftPower
                    color: "white"
                    font.pixelSize: 14
                }

                Text {
                    text: "R: " + backend.rightPower
                    color: "white"
                    font.pixelSize: 14
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "Brake mode:"
                    color: "#00adb5"
                    font.pixelSize: 14
                    font.bold: true
                }

                Rectangle {
                    width: 90
                    height: 26
                    radius: 13
                    color: backend.brakeMode === "brake" ? "#f44336" : "#4caf50"

                    Text {
                        anchors.centerIn: parent
                        text: backend.brakeMode === "brake" ? "BRAKE" : "COAST"
                        color: "white"
                        font.pixelSize: 12
                        font.bold: true
                    }
                }
            }
        }

        // ---------- Área central: joystick + comandos ----------
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 30

            // ---------- Joystick ----------
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                spacing: 15

                Text {
                    text: "Joystick"
                    color: "#00adb5"
                    font.pixelSize: 18
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                }

                Rectangle {
                    id: joystickBase
                    width: 220
                    height: 220
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
                        width: 80
                        height: 80
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
                            const centerX = joystickBase.width / 2;
                            const centerY = joystickBase.height / 2;

                            const dx = mx - centerX;
                            const dy = my - centerY;
                            const distance = Math.sqrt(dx * dx + dy * dy);
                            const maxDistance = (joystickBase.width / 2) - (joystickStick.width / 2);

                            if (distance > maxDistance) {
                                const angle = Math.atan2(dy, dx);
                                joystickStick.x = centerX + Math.cos(angle) * maxDistance - (joystickStick.width / 2);
                                joystickStick.y = centerY + Math.sin(angle) * maxDistance - (joystickStick.height / 2);

                                joystickBase.outputX = Math.cos(angle) * 100;
                                joystickBase.outputY = -Math.sin(angle) * 100;
                            } else {
                                joystickStick.x = mx - (joystickStick.width / 2);
                                joystickStick.y = my - (joystickStick.height / 2);

                                joystickBase.outputX = (dx / maxDistance) * 100;
                                joystickBase.outputY = -(dy / maxDistance) * 100;
                            }

                            const xi = Math.round(joystickBase.outputX);
                            const yi = Math.round(joystickBase.outputY);

                            // Solo publicamos si cambió respecto al último enviado
                            if (xi !== joystickBase.lastSentX || yi !== joystickBase.lastSentY) {
                                joystickBase.lastSentX = xi;
                                joystickBase.lastSentY = yi;
                                backend.actualizar_joystick(xi, yi);
                            }
                        }

                        onPositionChanged: (mouse) => updateJoystickPosition(mouse.x, mouse.y)
                        onPressed:         (mouse) => updateJoystickPosition(mouse.x, mouse.y)

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
                    font.pixelSize: 16
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            // ---------- Botones de comando ----------
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                spacing: 15

                Text {
                    text: "Commands"
                    color: "#00adb5"
                    font.pixelSize: 18
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                }

                GridLayout {
                    columns: 2
                    rowSpacing: 12
                    columnSpacing: 12

                    Button {
                        text: "Forward"
                        Layout.preferredWidth: 130
                        Layout.preferredHeight: 50
                        onClicked: backend.send_command("A 0 100")
                    }

                    Button {
                        text: "Backward"
                        Layout.preferredWidth: 130
                        Layout.preferredHeight: 50
                        onClicked: backend.send_command("A 0 -100")
                    }

                    Button {
                        text: "Left"
                        Layout.preferredWidth: 130
                        Layout.preferredHeight: 50
                        onClicked: backend.send_command("A -100 0")
                    }

                    Button {
                        text: "Right"
                        Layout.preferredWidth: 130
                        Layout.preferredHeight: 50
                        onClicked: backend.send_command("A 100 0")
                    }

                    Button {
                        text: "Stop"
                        Layout.preferredWidth: 130
                        Layout.preferredHeight: 50
                        highlighted: true
                        onClicked: backend.send_command("X")
                    }

                    Button {
                        text: "Auton-Square"
                        Layout.preferredWidth: 130
                        Layout.preferredHeight: 50
                        onClicked: backend.send_command("S 100 2000 800")
                    }
                }

                // ---------- Modo de freno ----------
                Text {
                    text: "Brake mode"
                    color: "#00adb5"
                    font.pixelSize: 14
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 10
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 12

                    Button {
                        text: "Coast"
                        Layout.preferredWidth: 120
                        Layout.preferredHeight: 45
                        checkable: true
                        checked: backend.brakeMode === "coast"
                        onClicked: backend.set_brake_mode("coast")
                    }

                    Button {
                        text: "Brake"
                        Layout.preferredWidth: 120
                        Layout.preferredHeight: 45
                        checkable: true
                        checked: backend.brakeMode === "brake"
                        onClicked: backend.set_brake_mode("brake")
                    }
                }
            }
        }

        // ---------- Panel de respuesta JSON ----------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 180
            color: "#1b1b22"
            border.color: "#393e46"
            border.width: 2
            radius: 8

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "Robot response (raw)"
                        color: "#00adb5"
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    Button {
                        text: "Clean"
                        Layout.preferredWidth: 80
                        Layout.preferredHeight: 28
                        onClicked: backend.send_command("")  // no-op; ver nota abajo
                    }
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    TextArea {
                        id: responseArea
                        readOnly: true
                        wrapMode: TextEdit.WrapAnywhere
                        color: "#e0e0e0"
                        font.family: "monospace"
                        font.pixelSize: 13
                        text: backend.lastResponse

                        background: Rectangle {
                            color: "#101015"
                            radius: 4
                        }
                    }
                }
            }
        }
    }
}