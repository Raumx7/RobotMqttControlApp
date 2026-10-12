import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: window
    visible: true
    width: 1000
    height: 640
    title: "Touch Panel - Robot Control"

    background: Rectangle { color: "#141419" }

    // ============================================================
    // Columna izquierda: joystick + botones
    // ============================================================
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 15

        // --- Barra superior con estado de conexión ---
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
                text: backend.connected ? "Conectado al broker" : "Desconectado"
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

        // --- Área principal: joystick a la izquierda, botones a la derecha ---
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

                    // Valor anterior publicado (para evitar spam)
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

                            // Redondeo a enteros
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

            // ---------- Botones de comandos ----------
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                spacing: 12

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
                        text: "Square"
                        Layout.preferredWidth: 130
                        Layout.preferredHeight: 50
                        onClicked: backend.send_command("S 100 2000 1000")
                    }
                }
            }
        }

        // ============================================================
        // Panel de respuesta JSON
        // ============================================================
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

                Text {
                    text: "Robot response (raw)"
                    color: "#00adb5"
                    font.pixelSize: 14
                    font.bold: true
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