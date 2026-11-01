import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Environmental monitoring window (temperature + relative humidity).
// Place this file next to Main.qml (RobotApp/SensorWindow.qml).
ApplicationWindow {
    id: win
    visible: false
    width: 780
    height: 620
    minimumWidth: 640
    minimumHeight: 540
    title: "Environmental Monitoring"

    // Independent window (not forced on top of the control panel)
    transientParent: null

    background: Rectangle { color: "#0f1216" }

    // ============================================================
    // Thresholds (edit here to adjust the criteria)
    // ============================================================
    // Temperature (Celsius)
    readonly property real tempScaleMin:    0
    readonly property real tempScaleMax:    50
    readonly property real tempComfortMin:  18   // optimal comfort range: 18 - 21
    readonly property real tempComfortMax:  21
    readonly property real tempWarning:     25   // must always stay below 25
    readonly property real tempCritical:    27   // "high temperature" above 27

    // Relative humidity (%)
    readonly property real humCriticalLow:  40   // NOTE: critical limits are an assumption,
    readonly property real humWarningLow:   55   // optimal range 55 - 65 comes from the
    readonly property real humWarningHigh:  65   // reference document
    readonly property real humCriticalHigh: 80

    // Telemetry older than this is considered stale
    readonly property int staleTimeoutMs: 10000

    // ============================================================
    // Levels and colors
    // ============================================================
    readonly property int levelNoData:   -1
    readonly property int levelNormal:    0
    readonly property int levelMonitor:   1
    readonly property int levelCritical:  2

    readonly property color colorNormal:   "#3fb950"
    readonly property color colorMonitor:  "#f5a623"
    readonly property color colorCritical: "#f0444b"
    readonly property color colorNoData:   "#6b7280"

    function levelColor(level) {
        switch (level) {
        case levelNormal:   return colorNormal
        case levelMonitor:  return colorMonitor
        case levelCritical: return colorCritical
        default:            return colorNoData
        }
    }

    function levelLabel(level) {
        switch (level) {
        case levelNormal:   return "NORMAL"
        case levelMonitor:  return "MONITOR"
        case levelCritical: return "CRITICAL"
        default:            return hasData ? "NO SIGNAL" : "NO DATA"
        }
    }

    function tempLevelOf(t) {
        if (t > tempCritical)                      return levelCritical
        if (t >= tempWarning || t < tempComfortMin) return levelMonitor
        return levelNormal
    }

    function humLevelOf(h) {
        if (h < humCriticalLow || h > humCriticalHigh) return levelCritical
        if (h < humWarningLow  || h > humWarningHigh)  return levelMonitor
        return levelNormal
    }

    function tempDetail(t) {
        if (t > tempCritical)    return "High temperature (above " + tempCritical + " °C)"
        if (t >= tempWarning)    return "Above recommended maximum (" + tempWarning + " °C)"
        if (t < tempComfortMin)  return "Below comfort range (" + tempComfortMin + " °C)"
        if (t <= tempComfortMax) return "Optimal comfort range (" + tempComfortMin + "–" + tempComfortMax + " °C)"
        return "Acceptable, above optimal comfort range"
    }

    function humDetail(h) {
        if (h < humCriticalLow)  return "Very dry air (below " + humCriticalLow + " %)"
        if (h > humCriticalHigh) return "Very humid air (above " + humCriticalHigh + " %)"
        if (h < humWarningLow)   return "Air too dry (below " + humWarningLow + " %)"
        if (h > humWarningHigh)  return "Air too humid (above " + humWarningHigh + " %)"
        return "Optimal range (" + humWarningLow + "–" + humWarningHigh + " %)"
    }

    // ============================================================
    // Data state
    // ============================================================
    readonly property real temp: backend.temperature
    readonly property real hum:  backend.humidity
    readonly property bool hasData: backend.hasTelemetry

    property real nowMs: Date.now()
    property real lastUpdateMs: 0

    readonly property bool online: hasData && (nowMs - lastUpdateMs) < staleTimeoutMs
    readonly property int ageSec: Math.max(0, Math.floor((nowMs - lastUpdateMs) / 1000))

    readonly property int tempLevel: online ? tempLevelOf(temp) : levelNoData
    readonly property int humLevel:  online ? humLevelOf(hum)   : levelNoData

    // Exposed so the main window can show a summary badge
    readonly property int overallLevel: online ? Math.max(tempLevel, humLevel) : levelNoData
    readonly property string overallLabel: levelLabel(overallLevel)
    readonly property color overallColor: levelColor(overallLevel)

    readonly property string alertMessage: {
        if (!hasData)
            return "Waiting for telemetry from the robot..."
        if (!online)
            return "No telemetry for " + ageSec + " s. Showing last known values."
        var parts = []
        if (tempLevel > levelNormal) parts.push("Temperature: " + tempDetail(temp))
        if (humLevel  > levelNormal) parts.push("Humidity: " + humDetail(hum))
        if (temp >= tempWarning && hum > humWarningHigh)
            parts.push("Combined heat and humidity reduce working performance")
        if (parts.length === 0)
            return "All parameters are within the normal range."
        return parts.join("   •   ")
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: win.nowMs = Date.now()
    }

    Connections {
        target: backend
        function onTelemetryChanged() {
            win.lastUpdateMs = Date.now()
            win.nowMs = win.lastUpdateMs
        }
    }

    // ============================================================
    // UI
    // ============================================================
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // ---------- Header ----------
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: "Environmental Monitoring"
                color: "#e6edf3"
                font.pixelSize: 20
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                width: 10; height: 10; radius: 5
                color: win.online ? win.colorNormal : win.colorNoData
            }

            Text {
                text: (backend.sensorId !== "" ? "Sensor " + backend.sensorId + "  ·  " : "")
                      + (win.hasData ? "Last update: " + win.ageSec + " s ago" : "Waiting for data")
                color: "#9aa4b0"
                font.pixelSize: 13
            }
        }

        // ---------- Overall status banner ----------
        Rectangle {
            id: banner
            Layout.fillWidth: true
            Layout.preferredHeight: bannerCol.implicitHeight + 24
            radius: 10
            color: win.overallColor
            Behavior on color { ColorAnimation { duration: 250 } }

            // Pulse while critical to draw attention
            SequentialAnimation on opacity {
                running: win.overallLevel === win.levelCritical && win.visible
                loops: Animation.Infinite
                NumberAnimation { to: 0.65; duration: 600 }
                NumberAnimation { to: 1.0;  duration: 600 }
                onRunningChanged: if (!running) banner.opacity = 1.0
            }

            ColumnLayout {
                id: bannerCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 14
                spacing: 2

                Text {
                    text: win.overallLabel
                    color: win.overallLevel === win.levelMonitor ? "#1a1300" : "white"
                    font.pixelSize: 20
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    text: win.alertMessage
                    color: win.overallLevel === win.levelMonitor ? "#1a1300" : "white"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
            }
        }

        // ---------- Gauges ----------
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            // ===== Temperature card (thermometer) =====
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                color: "#171c22"
                border.color: "#2a323c"
                radius: 12

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 8

                    Text {
                        text: "TEMPERATURE"
                        color: "#9aa4b0"
                        font.pixelSize: 13
                        font.bold: true
                        font.letterSpacing: 1.5
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 10

                        Canvas {
                            id: thermo
                            Layout.preferredWidth: 150
                            Layout.fillHeight: true
                            Layout.minimumHeight: 240

                            property real value: win.temp
                            property bool active: win.hasData
                            property color fillColor: win.levelColor(win.tempLevel)

                            onValueChanged: requestPaint()
                            onActiveChanged: requestPaint()
                            onFillColorChanged: requestPaint()
                            onHeightChanged: requestPaint()
                            Component.onCompleted: requestPaint()

                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)

                                var tubeW = 28
                                var bulbR = 30
                                var cx = 70
                                var topY = 10
                                var bulbCy = height - bulbR - 6
                                var scaleTop = topY + tubeW / 2
                                var scaleBottom = bulbCy - bulbR - 4
                                var sMin = win.tempScaleMin
                                var sMax = win.tempScaleMax

                                function yOf(v) {
                                    var f = Math.max(0, Math.min(1, (v - sMin) / (sMax - sMin)))
                                    return scaleBottom - f * (scaleBottom - scaleTop)
                                }

                                // Glass body: tube + bulb, drawn as an outline layer then an inner layer
                                function body(inset, color) {
                                    var r = tubeW / 2 - inset
                                    ctx.fillStyle = color
                                    ctx.beginPath()
                                    ctx.arc(cx, topY + tubeW / 2, r, Math.PI, 0, false)
                                    ctx.lineTo(cx + r, bulbCy)
                                    ctx.lineTo(cx - r, bulbCy)
                                    ctx.closePath()
                                    ctx.fill()
                                    ctx.beginPath()
                                    ctx.arc(cx, bulbCy, bulbR - inset, 0, 2 * Math.PI)
                                    ctx.fill()
                                }
                                body(0, "#3a4450")
                                body(3, "#1d232b")

                                // Zone band (left of the tube)
                                function zone(a, b, color) {
                                    var y1 = yOf(b)
                                    var y2 = yOf(a)
                                    ctx.fillStyle = color
                                    ctx.fillRect(cx - tubeW / 2 - 18, y1, 7, y2 - y1)
                                }
                                ctx.globalAlpha = win.online ? 1.0 : 0.35
                                zone(sMin, win.tempComfortMin,  win.colorMonitor)
                                zone(win.tempComfortMin, win.tempWarning, win.colorNormal)
                                zone(win.tempWarning, win.tempCritical,   win.colorMonitor)
                                zone(win.tempCritical, sMax,    win.colorCritical)
                                ctx.globalAlpha = 1.0

                                // Liquid
                                if (active) {
                                    var rl = tubeW / 2 - 6
                                    var yv = yOf(value)
                                    ctx.fillStyle = fillColor
                                    ctx.fillRect(cx - rl, yv, 2 * rl, bulbCy - yv)
                                    ctx.beginPath()
                                    ctx.arc(cx, bulbCy, bulbR - 6, 0, 2 * Math.PI)
                                    ctx.fill()
                                }

                                // Scale ticks and labels (right of the tube)
                                ctx.strokeStyle = "#6b7684"
                                ctx.fillStyle = "#9aa4b0"
                                ctx.lineWidth = 1
                                ctx.font = "12px sans-serif"
                                ctx.textAlign = "left"
                                ctx.textBaseline = "middle"
                                for (var t = sMin; t <= sMax; t += 10) {
                                    var y = yOf(t)
                                    ctx.beginPath()
                                    ctx.moveTo(cx + tubeW / 2 + 6, y)
                                    ctx.lineTo(cx + tubeW / 2 + 14, y)
                                    ctx.stroke()
                                    ctx.fillText(t + "°", cx + tubeW / 2 + 18, y)
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 8

                            Text {
                                text: win.hasData ? win.temp.toFixed(1) + " °C" : "-- °C"
                                color: win.levelColor(win.tempLevel)
                                font.pixelSize: 40
                                font.bold: true
                            }

                            Rectangle {
                                Layout.preferredWidth: tempChip.implicitWidth + 20
                                Layout.preferredHeight: 26
                                radius: 13
                                color: win.levelColor(win.tempLevel)
                                Text {
                                    id: tempChip
                                    anchors.centerIn: parent
                                    text: win.levelLabel(win.tempLevel)
                                    color: win.tempLevel === win.levelMonitor ? "#1a1300" : "white"
                                    font.pixelSize: 12
                                    font.bold: true
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: win.hasData ? win.tempDetail(win.temp) : ""
                                color: "#9aa4b0"
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }

            // ===== Humidity card (semicircular gauge) =====
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                color: "#171c22"
                border.color: "#2a323c"
                radius: 12

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 8

                    Text {
                        text: "RELATIVE HUMIDITY"
                        color: "#9aa4b0"
                        font.pixelSize: 13
                        font.bold: true
                        font.letterSpacing: 1.5
                    }

                    Canvas {
                        id: humGauge
                        Layout.fillWidth: true
                        Layout.maximumWidth: 340
                        Layout.preferredHeight: 190
                        Layout.alignment: Qt.AlignHCenter

                        property real value: win.hum
                        property bool active: win.hasData
                        property color needleColor: win.levelColor(win.humLevel)

                        onValueChanged: requestPaint()
                        onActiveChanged: requestPaint()
                        onNeedleColorChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        Component.onCompleted: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)

                            var lw = 16
                            var cx = width / 2
                            var cy = height - 22
                            var r = Math.min(width / 2 - 34, cy - 24)

                            function angleOf(pct) {
                                return Math.PI + Math.max(0, Math.min(100, pct)) / 100 * Math.PI
                            }

                            // Colored zones along the arc
                            var zones = [
                                [0,                  win.humCriticalLow,  win.colorCritical],
                                [win.humCriticalLow, win.humWarningLow,   win.colorMonitor],
                                [win.humWarningLow,  win.humWarningHigh,  win.colorNormal],
                                [win.humWarningHigh, win.humCriticalHigh, win.colorMonitor],
                                [win.humCriticalHigh, 100,                win.colorCritical]
                            ]
                            ctx.globalAlpha = win.online ? 1.0 : 0.35
                            ctx.lineWidth = lw
                            ctx.lineCap = "butt"
                            for (var i = 0; i < zones.length; i++) {
                                ctx.strokeStyle = zones[i][2]
                                ctx.beginPath()
                                ctx.arc(cx, cy, r, angleOf(zones[i][0]) + 0.01, angleOf(zones[i][1]) - 0.01, false)
                                ctx.stroke()
                            }
                            ctx.globalAlpha = 1.0

                            // Scale labels
                            ctx.fillStyle = "#9aa4b0"
                            ctx.font = "12px sans-serif"
                            ctx.textAlign = "center"
                            ctx.textBaseline = "middle"
                            var marks = [0, 25, 50, 75, 100]
                            for (var m = 0; m < marks.length; m++) {
                                var a = angleOf(marks[m])
                                var lr = r + lw / 2 + 14
                                ctx.fillText(marks[m] + "", cx + Math.cos(a) * lr, cy + Math.sin(a) * lr)
                            }

                            // Needle
                            if (active) {
                                var na = angleOf(value)
                                ctx.strokeStyle = needleColor
                                ctx.fillStyle = needleColor
                                ctx.lineWidth = 4
                                ctx.lineCap = "round"
                                ctx.beginPath()
                                ctx.moveTo(cx, cy)
                                ctx.lineTo(cx + Math.cos(na) * (r - 6), cy + Math.sin(na) * (r - 6))
                                ctx.stroke()
                                ctx.beginPath()
                                ctx.arc(cx, cy, 8, 0, 2 * Math.PI)
                                ctx.fill()
                                ctx.fillStyle = "#171c22"
                                ctx.beginPath()
                                ctx.arc(cx, cy, 3, 0, 2 * Math.PI)
                                ctx.fill()
                            }
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: win.hasData ? win.hum.toFixed(1) + " %" : "-- %"
                        color: win.levelColor(win.humLevel)
                        font.pixelSize: 40
                        font.bold: true
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: humChip.implicitWidth + 20
                        Layout.preferredHeight: 26
                        radius: 13
                        color: win.levelColor(win.humLevel)
                        Text {
                            id: humChip
                            anchors.centerIn: parent
                            text: win.levelLabel(win.humLevel)
                            color: win.humLevel === win.levelMonitor ? "#1a1300" : "white"
                            font.pixelSize: 12
                            font.bold: true
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: win.hasData ? win.humDetail(win.hum) : ""
                        color: "#9aa4b0"
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                    }

                    Item { Layout.fillHeight: true }
                }
            }
        }

        // ---------- Threshold legend ----------
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: "#7d8793"
            font.pixelSize: 12
            lineHeight: 1.2
            text: "Temperature — Normal: " + win.tempComfortMin + "–" + win.tempWarning
                  + " °C (optimal " + win.tempComfortMin + "–" + win.tempComfortMax
                  + ")  ·  Monitor: " + win.tempWarning + "–" + win.tempCritical
                  + " °C or below " + win.tempComfortMin
                  + "  ·  Critical: above " + win.tempCritical + " °C\n"
                  + "Humidity — Normal: " + win.humWarningLow + "–" + win.humWarningHigh
                  + " %  ·  Monitor: " + win.humCriticalLow + "–" + win.humWarningLow
                  + " % or " + win.humWarningHigh + "–" + win.humCriticalHigh
                  + " %  ·  Critical: below " + win.humCriticalLow
                  + " % or above " + win.humCriticalHigh + " %"
        }
    }
}
