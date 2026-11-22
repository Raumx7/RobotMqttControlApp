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

    // Closing the control panel closes the whole app (including the sensor & camera windows)
    onClosing: Qt.quit()

    // Environmental monitoring window (hidden until requested)
    SensorWindow { id: sensorWindow }

    // Camera & Color Detection window (hidden until requested)
    CameraWindow { id: cameraWindow }

    // ============================================================
    // Distance ranges (must match clamp_distance() on the robot)
    // ============================================================
    // Possible readings, nearest -> farthest. -1.0 is the "no reading" sentinel.
    readonly property var distLevels: [0, 2, 5, 10, 20, 30, 50, 80, 100, 120]

    // Range band colors, indexed like distLevels (0 = nearest ... 9 = farthest):
    // green when far, yellow at medium range, red when close.
    readonly property color colOff: "#2a2f38"
    readonly property var bandColors: [
        "#e5484d",   //   0 cm (contact)  red
        "#e5484d",   //   2 cm            red
        "#e5484d",   //   5 cm            red
        "#e5484d",   //  10 cm            red
        "#f5c518",   //  20 cm            yellow
        "#f5c518",   //  30 cm            yellow
        "#f5c518",   //  50 cm            yellow
        "#3fd27a",   //  80 cm            green
        "#3fd27a",   // 100 cm            green
        "#3fd27a"    // 120 cm            green
    ]

    // Color of range band i (0 = nearest to the robot)
    function bandColor(i) {
        return bandColors[i]
    }

    // Index of the band that matches a reading, or -1 when there is no data
    function distanceIndex(d) {
        if (d < 0) return -1
        var idx = 0
        for (var i = 0; i < distLevels.length; i++) {
            if (distLevels[i] <= d) idx = i
        }
        return idx
    }

    function distanceText(d) {
        return d < 0 ? "No data" : d.toFixed(1) + " cm"
    }

    function distanceColor(d) {
        return d < 0 ? "#777" : bandColor(distanceIndex(d))
    }

    // Raw robot response color: green if success is true, red if false
    function responseColor(line) {
        try {
            var obj = JSON.parse(line)
            if (obj && obj.success === true)  return "#46d37f"
            if (obj && obj.success === false) return "#ff6b6b"
        } catch (e) {
            // Not JSON: fall through to the default color
        }
        return "#e0e0e0"
    }

    // ============================================================
    // Reusable components
    // ============================================================

    // Glowing triangular direction button (points up; rotate it from the outside)
    component ArrowButton: Item {
        id: arrow
        property color tone: "#00adb5"
        readonly property bool hot: ma.pressed || ma.containsMouse
        signal clicked()

        width: 64
        height: 64
        scale: ma.pressed ? 0.88 : (ma.containsMouse ? 1.08 : 1.0)
        Behavior on scale { NumberAnimation { duration: 80 } }

        onHotChanged: cv.requestPaint()
        onToneChanged: cv.requestPaint()

        Canvas {
            id: cv
            anchors.fill: parent
            Component.onCompleted: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                var c = arrow.hot ? Qt.lighter(arrow.tone, 1.35) : arrow.tone
                ctx.shadowColor = arrow.tone
                ctx.shadowBlur = arrow.hot ? 14 : 9
                ctx.fillStyle = c
                ctx.strokeStyle = c
                ctx.lineJoin = "round"
                ctx.lineWidth = 6

                ctx.beginPath()
                ctx.moveTo(width / 2, 13)
                ctx.lineTo(width - 14, height - 15)
                ctx.lineTo(14, height - 15)
                ctx.closePath()
                ctx.fill()
                ctx.stroke()
            }
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            onClicked: arrow.clicked()
        }
    }

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
                text: backend.connected ? "Connected" : "Disconnected"
                color: "white"
                font.pixelSize: 14
            }

            TextField {
                id: ipInput
                text: backend.brokerIp
                placeholderText: "MQTT Broker IP"
                font.pixelSize: 13
                color: "white"
                background: Rectangle {
                    color: "#1b1b22"
                    border.color: "#393e46"
                    radius: 4
                }
                Layout.preferredWidth: 130
                Layout.preferredHeight: 28
                Layout.leftMargin: 10
            }

            Button {
                text: "Set IP"
                Layout.preferredHeight: 28
                onClicked: backend.set_broker_ip(ipInput.text)
            }

            Item { Layout.fillWidth: true }

            // Environmental status summary + button to open the sensor window
            Rectangle {
                width: 12; height: 12; radius: 6
                color: sensorWindow.online ? "#00adb5" : "#555"
            }

            Text {
                text: "Environment: " + sensorWindow.overallLabel
                color: "white"
                font.pixelSize: 13
            }

            Button {
                text: "Sensors"
                onClicked: {
                    sensorWindow.show()
                    sensorWindow.raise()
                    sensorWindow.requestActivate()
                }
            }

            Button {
                text: "Camera"
                onClicked: {
                    cameraWindow.show()
                    cameraWindow.raise()
                    cameraWindow.requestActivate()
                }
            }

            Item { Layout.preferredWidth: 20 }

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
                // Fixed width: nested layouts fill horizontally by default, which would
                // let this column steal the space from the right column.
                Layout.fillWidth: false
                Layout.preferredWidth: 400
                Layout.minimumWidth: 400
                Layout.maximumWidth: 400
                Layout.fillHeight: true
                spacing: 10

                // ----- Robot Schema (top view, vertical) + distance ranges -----
                Rectangle {
                    id: schemaPanel
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: 500
                    Layout.minimumHeight: 420

                    // Fan geometry (shared by the fans canvas and the chassis size)
                    readonly property real fanInner: 5     // gap between chassis edge and first band
                    readonly property real fanStep: 8      // radial size of one band (thickness + spacing)
                    readonly property real fanExtent: fanInner + fanStep * window.distLevels.length
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

                    // ----- Distance range fans (drawn behind the chassis) -----
                    // Concentric bands in front and behind the robot. A band is lit when the
                    // obstacle is at or inside that range, so the fan fills up as it gets closer.
                    Canvas {
                        id: rangeFans
                        anchors.fill: parent

                        property real front: backend.frontDistance
                        property real back:  backend.backDistance

                        onFrontChanged: requestPaint()
                        onBackChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        Component.onCompleted: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)

                            var n = window.distLevels.length
                            var cx = width / 2
                            var cy = height / 2
                            var halfH = chassis.height / 2
                            var inner = schemaPanel.fanInner
                            var step = schemaPanel.fanStep
                            var thick = step * 0.72
                            var span = 40 * Math.PI / 180

                            // Draws one continuous fan centered on a chassis edge
                            function drawFan(centerY, baseAngle, idx) {
                                ctx.lineWidth = thick
                                ctx.lineCap = "round"
                                for (var i = 0; i < n; i++) {
                                    var lit = idx >= 0 && i >= idx
                                    var color = lit ? window.bandColor(i) : window.colOff
                                    var r = inner + i * step + thick / 2

                                    ctx.strokeStyle = color
                                    ctx.shadowColor = color
                                    ctx.shadowBlur = lit ? 5 : 0

                                    ctx.beginPath()
                                    ctx.arc(cx, centerY, r, baseAngle - span, baseAngle + span, false)
                                    ctx.stroke()
                                }
                                ctx.shadowBlur = 0
                            }

                            drawFan(cy - halfH, -Math.PI / 2, window.distanceIndex(front))
                            drawFan(cy + halfH,  Math.PI / 2, window.distanceIndex(back))
                        }
                    }

                    // ----- Chassis (vertical rounded body, front pointing up) -----
                    Rectangle {
                        id: chassis
                        anchors.centerIn: parent
                        height: Math.min(320, schemaPanel.height - 2 * (schemaPanel.fanExtent + 12))
                        width: height * 0.52
                        radius: width * 0.34
                        color: parent.chassisColor

                        // Wheel geometry derived from the chassis size
                        readonly property real wheelH: height * 0.24
                        readonly property real wheelY: height * 0.10
                        border.color: "#00adb5"
                        border.width: 3

                        Behavior on color { ColorAnimation { duration: 300 } }

                        // Longitudinal axis line (Decorative, vertical)
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            width: 2
                            height: parent.height - 140
                            color: "#00adb5"
                            opacity: 0.15
                        }

                        // ----- Wheels (along the long sides of the chassis) -----
                        // Left Front
                        Rectangle {
                            width: 28; height: parent.wheelH; radius: 8
                            x: -14
                            y: parent.wheelY
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
                                font.pixelSize: 14
                                font.bold: true
                            }
                        }

                        // Right Front
                        Rectangle {
                            width: 28; height: parent.wheelH; radius: 8
                            x: parent.width - 14
                            y: parent.wheelY
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
                                font.pixelSize: 14
                                font.bold: true
                            }
                        }

                        // Left Rear
                        Rectangle {
                            width: 28; height: parent.wheelH; radius: 8
                            x: -14
                            y: parent.height - parent.wheelY - parent.wheelH
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
                                font.pixelSize: 14
                                font.bold: true
                            }
                        }

                        // Right Rear
                        Rectangle {
                            width: 28; height: parent.wheelH; radius: 8
                            x: parent.width - 14
                            y: parent.height - parent.wheelY - parent.wheelH
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
                                font.pixelSize: 14
                                font.bold: true
                            }
                        }

                        // "FRONT" label + front distance
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: 10
                            text: "FRONT"
                            color: "#00adb5"
                            font.pixelSize: 10
                            font.bold: true
                            opacity: 0.5
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: 26
                            text: window.distanceText(backend.frontDistance)
                            color: window.distanceColor(backend.frontDistance)
                            font.pixelSize: 12
                            font.bold: true
                        }

                        // "REAR" label + rear distance
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 10
                            text: "REAR"
                            color: "#00adb5"
                            font.pixelSize: 10
                            font.bold: true
                            opacity: 0.5
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 26
                            text: window.distanceText(backend.backDistance)
                            color: window.distanceColor(backend.backDistance)
                            font.pixelSize: 12
                            font.bold: true
                        }
                    }
                }

                // ----- Status Panel -----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 185
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

                            Text { text: "Front laser:"; color: "#aaa"; font.pixelSize: 13 }
                            Text {
                                text: window.distanceText(backend.frontDistance)
                                color: backend.frontDistance < 0 ? "#777"
                                     : backend.frontDistance < 20.0 ? "#d65a31"
                                     : "#00adb5"
                                font.pixelSize: 13
                                font.bold: true
                            }

                            Text { text: "Back laser:"; color: "#aaa"; font.pixelSize: 13 }
                            Text {
                                text: window.distanceText(backend.backDistance)
                                color: backend.backDistance < 0 ? "#777"
                                     : backend.backDistance < 20.0 ? "#d65a31"
                                     : "#00adb5"
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
                Layout.preferredWidth: 1000
                Layout.fillHeight: true
                spacing: 14

                // ----- Joystick + Command pad (same height, each centered in its half) -----
                RowLayout {
                    id: padRow
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: 262
                    spacing: 14

                    // --- Joystick ---
                    // Plain Item cell: fills its half of the row; the content is centered
                    // inside it with anchors (no dependency on the layout size -> no recursion).
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1

                        ColumnLayout {
                            anchors.horizontalCenter: parent.horizontalCenter
                            // Both pads use the same offset so their circles stay aligned
                            y: Math.max(0, (parent.height - 258) / 2)
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
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: 200
                                Layout.preferredHeight: 200
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
                    }

                    // --- D-Pad ---
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1

                        ColumnLayout {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: Math.max(0, (parent.height - 258) / 2)
                            spacing: 10

                            Text {
                                text: "D-Pad"
                                color: "#00adb5"
                                font.pixelSize: 16
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                            }

                            // --- Direction pad: arrow buttons + emergency STOP in the center ---
                            Rectangle {
                                id: dpad
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: 200
                                Layout.preferredHeight: 200
                                radius: 100
                                color: "#222831"
                                border.color: "#393e46"
                                border.width: 4

                                // Forward
                                ArrowButton {
                                    x: 68; y: 0
                                    rotation: 0
                                    onClicked: backend.send_command("A 0 100")
                                }
                                // Right
                                ArrowButton {
                                    x: 136; y: 68
                                    rotation: 90
                                    onClicked: backend.send_command("A 100 0")
                                }
                                // Backward
                                ArrowButton {
                                    x: 68; y: 136
                                    rotation: 180
                                    onClicked: backend.send_command("A 0 -100")
                                }
                                // Left
                                ArrowButton {
                                    x: 0; y: 68
                                    rotation: 270
                                    onClicked: backend.send_command("A -100 0")
                                }

                                // Emergency STOP
                                Rectangle {
                                    id: stopHalo
                                    anchors.centerIn: parent
                                    width: 92
                                    height: 92
                                    radius: 46
                                    color: Qt.rgba(0.9, 0.28, 0.3, stopArea.containsMouse ? 0.28 : 0.15)
                                }
                                Rectangle {
                                    id: stopButton
                                    anchors.centerIn: parent
                                    width: 78
                                    height: 78
                                    radius: 39
                                    color: stopArea.pressed ? "#c0353a" : "#e5484d"
                                    border.color: "#7f1d1f"
                                    border.width: 4
                                    scale: stopArea.pressed ? 0.94 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 80 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "STOP"
                                        color: "white"
                                        font.pixelSize: 16
                                        font.bold: true
                                    }

                                    MouseArea {
                                        id: stopArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: backend.send_command("X")
                                    }
                                }
                            }
                        }
                    }
                }

                // ----- Grouped sections: Autonomous routines + Brake Mode -----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    // --- Autonomous routines ---
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 96
                        color: "#1b1b22"
                        border.color: "#393e46"
                        border.width: 1
                        radius: 10

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            Text {
                                text: "Autonomous routines"
                                color: "#00adb5"
                                font.pixelSize: 14
                                font.bold: true
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Button {
                                    text: "Square Auto"
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    Layout.minimumWidth: 130
                                    Layout.preferredHeight: 44
                                    leftPadding: 38
                                    onClicked: backend.send_command("S 100 2000 700")

                                    // Square icon
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 16
                                        height: 16
                                        radius: 2
                                        color: "transparent"
                                        border.width: 2
                                        border.color: parent.palette.buttonText
                                    }
                                }

                                Button {
                                    text: "Rectangle Scan"
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    Layout.minimumWidth: 130
                                    Layout.preferredHeight: 44
                                    leftPadding: 38
                                    onClicked: backend.send_command("R 85 3000 1500 5000 800")

                                    // Rectangle icon
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 22
                                        height: 14
                                        radius: 2
                                        color: "transparent"
                                        border.width: 2
                                        border.color: parent.palette.buttonText
                                    }
                                }
                            }
                        }
                    }

                    // --- Brake Mode ---
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 96
                        color: "#1b1b22"
                        border.color: "#393e46"
                        border.width: 1
                        radius: 10

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            Text {
                                text: "Brake Mode"
                                color: "#00adb5"
                                font.pixelSize: 14
                                font.bold: true
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Button {
                                    text: "Coast"
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    Layout.preferredHeight: 44
                                    checkable: true
                                    checked: backend.brakeMode === "coast"
                                    onClicked: backend.set_brake_mode("coast")
                                }
                                Button {
                                    text: "Brake"
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    Layout.preferredHeight: 44
                                    checkable: true
                                    checked: backend.brakeMode === "brake"
                                    onClicked: backend.set_brake_mode("brake")
                                }
                            }
                        }
                    }
                }

                // ----- Last Responses -----
                Rectangle {
                    Layout.fillWidth: true
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
                                        // Green when success:true, red when success:false
                                        color: window.responseColor(modelData)
                                        font.family: "monospace"
                                        font.pixelSize: 13
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
