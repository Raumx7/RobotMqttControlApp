import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Environmental monitoring dashboard (temperature + relative humidity).
// Place this file next to Main.qml (RobotApp/SensorWindow.qml).
ApplicationWindow {
    id: win
    visible: false
    width: 920
    height: 840
    minimumWidth: 780
    minimumHeight: 760
    title: "Environmental Monitoring"

    // Independent window (not forced on top of the control panel)
    transientParent: null

    background: Rectangle { color: "#141419" }

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
    readonly property real humWarningLow:   55   // the optimal range 55 - 65 comes from the
    readonly property real humWarningHigh:  65   // reference document
    readonly property real humCriticalHigh: 80

    // Telemetry older than this is considered stale
    readonly property int staleTimeoutMs: 10000

    // ============================================================
    // Levels and colors (aligned with the control panel palette)
    // ============================================================
    readonly property int levelNoData:   -1
    readonly property int levelNormal:    0
    readonly property int levelMonitor:   1
    readonly property int levelCritical:  2

    readonly property color colorNormal:   "#00adb5"   // panel accent
    readonly property color colorMonitor:  "#f0b429"
    readonly property color colorCritical: "#e5484d"
    readonly property color colorNoData:   "#6b7280"

    // Panel surface colors
    readonly property color surface:      "#1b1b22"
    readonly property color surfaceInner: "#101015"
    readonly property color borderColor:  "#393e46"
    readonly property color textMuted:    "#aaaaaa"

    function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

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
        if (t > tempCritical)                       return levelCritical
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

    // Absolute timestamp of the last received telemetry (depends only on lastUpdateMs,
    // so it stays fixed once the connection is lost)
    readonly property string lastUpdateText:
        Qt.formatDateTime(new Date(lastUpdateMs), "yyyy-MM-dd hh:mm:ss")

    readonly property int tempLevel: online ? tempLevelOf(temp) : levelNoData
    readonly property int humLevel:  online ? humLevelOf(hum)   : levelNoData

    // Exposed so the main window can show a summary badge
    readonly property int overallLevel: online ? Math.max(tempLevel, humLevel) : levelNoData
    readonly property string overallLabel: levelLabel(overallLevel)
    readonly property color overallColor: levelColor(overallLevel)

    readonly property string freshnessText: {
        if (!hasData) return "Waiting for data"
        if (online)   return "Live  ·  updated " + ageSec + " s ago"
        return "Last update: " + lastUpdateText
    }

    readonly property string alertMessage: {
        if (!hasData)
            return "Waiting for telemetry from the robot..."
        if (!online)
            return "No telemetry since " + lastUpdateText + ". Showing last known values."
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
    // Reusable components
    // ============================================================

    // Circular indicator frame: a ring whose color follows `tone`.
    // Children are placed inside the ring.
    component RingFrame: Item {
        id: frame
        property color tone: "#6b7280"
        default property alias content: ring.data

        Behavior on tone { ColorAnimation { duration: 300 } }

        // Soft outer halo
        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: Qt.rgba(frame.tone.r, frame.tone.g, frame.tone.b, 0.25)
        }

        // Main ring
        Rectangle {
            id: ring
            anchors.centerIn: parent
            width: parent.width - 16
            height: width
            radius: width / 2
            color: Qt.rgba(frame.tone.r, frame.tone.g, frame.tone.b, 0.07)
            border.width: Math.max(6, width * 0.03)
            border.color: frame.tone
        }
    }

    // Horizontal scale with colored zones, labeled boundaries and a value marker.
    component RangeBar: Item {
        id: bar
        property var segments: []       // [{from, to, color, dim}]
        property var marks: []          // values to label on the scale
        property real scaleMin: 0
        property real scaleMax: 100
        property real value: 0
        property bool markerVisible: false
        property color markerColor: "white"
        property bool dimmed: false
        readonly property real pad: 14

        implicitHeight: 54

        function fx(v) {
            var f = (Math.max(scaleMin, Math.min(scaleMax, v)) - scaleMin) / (scaleMax - scaleMin)
            return pad + f * (width - 2 * pad)
        }

        // Colored zones
        Repeater {
            model: bar.segments
            Rectangle {
                x: bar.fx(modelData.from) + 1
                y: 16
                width: Math.max(0, bar.fx(modelData.to) - bar.fx(modelData.from) - 2)
                height: 12
                radius: 3
                color: modelData.color
                opacity: (bar.dimmed ? 0.35 : 1.0) * (modelData.dim ? 0.55 : 1.0)
            }
        }

        // Ticks + labels
        Repeater {
            model: bar.marks
            Item {
                x: bar.fx(modelData)
                Rectangle { x: -0.5; y: 30; width: 1; height: 5; color: "#6b7684" }
                Text {
                    x: -width / 2
                    y: 36
                    text: modelData
                    color: "#9aa4b0"
                    font.pixelSize: 11
                }
            }
        }

        // Current value marker
        Rectangle {
            visible: bar.markerVisible
            width: 10
            height: 10
            radius: 2
            rotation: 45
            y: 3
            x: bar.fx(bar.value) - 5
            color: bar.markerColor
            border.color: "#141419"
            border.width: 1
            Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutQuad } }
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
                color: "#00adb5"
                font.pixelSize: 18
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            ColumnLayout {
                spacing: 2

                Text {
                    Layout.alignment: Qt.AlignRight
                    text: Qt.formatDateTime(new Date(win.nowMs), "yyyy-MM-dd   hh:mm:ss")
                    color: "white"
                    font.pixelSize: 16
                }

                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: 8

                    Rectangle {
                        width: 10; height: 10; radius: 5
                        color: win.online ? win.colorNormal : win.colorNoData
                    }

                    Text {
                        text: (backend.sensorId !== "" ? "Sensor " + backend.sensorId + "  ·  " : "")
                              + win.freshnessText
                        color: win.textMuted
                        font.pixelSize: 13
                    }
                }
            }
        }

        // ---------- Overall status banner ----------
        Rectangle {
            id: banner
            Layout.fillWidth: true
            Layout.preferredHeight: bannerCol.implicitHeight + 24
            radius: 10
            color: win.tint(win.overallColor, 0.12)
            border.color: win.overallColor
            border.width: 1

            // Pulse while critical to draw attention
            SequentialAnimation on opacity {
                running: win.overallLevel === win.levelCritical && win.visible
                loops: Animation.Infinite
                NumberAnimation { to: 0.6; duration: 600 }
                NumberAnimation { to: 1.0; duration: 600 }
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
                    color: win.overallColor
                    font.pixelSize: 18
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    text: win.alertMessage
                    color: "#cfd3d8"
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

            // ===== Temperature card =====
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                color: win.surface
                border.color: win.borderColor
                border.width: 1
                radius: 10

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 8

                    Text {
                        text: "Temperature"
                        color: "#00adb5"
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Item {
                        id: tempHolder
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 170

                        RingFrame {
                            id: tempFrame
                            anchors.centerIn: parent
                            property real d: Math.max(160, Math.min(320,
                                             Math.min(tempHolder.width, tempHolder.height) - 4))
                            width: d
                            height: d
                            tone: win.levelColor(win.tempLevel)

                            // Thermometer drawn in a 200 x 240 design space
                            Canvas {
                                id: thermo
                                anchors.fill: parent

                                property real value: win.temp
                                property bool active: win.hasData
                                property color fillColor: tempFrame.tone
                                property bool dim: !win.online

                                onValueChanged: requestPaint()
                                onActiveChanged: requestPaint()
                                onFillColorChanged: requestPaint()
                                onDimChanged: requestPaint()
                                onWidthChanged: requestPaint()
                                onHeightChanged: requestPaint()
                                Component.onCompleted: requestPaint()

                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    ctx.save()

                                    var s = Math.min(width, height) * 0.74 / 240
                                    ctx.translate(width / 2, height / 2)
                                    ctx.scale(s, s)
                                    ctx.translate(-100, -120)

                                    var tubeW = 26
                                    var bulbR = 28
                                    var cx = 88
                                    var topY = 8
                                    var bulbCy = 240 - bulbR - 6
                                    var scaleTop = topY + tubeW / 2
                                    var scaleBottom = bulbCy - bulbR - 4
                                    var sMin = win.tempScaleMin
                                    var sMax = win.tempScaleMax

                                    function yOf(v) {
                                        var f = Math.max(0, Math.min(1, (v - sMin) / (sMax - sMin)))
                                        return scaleBottom - f * (scaleBottom - scaleTop)
                                    }

                                    // Glass body: outline layer, then inner layer
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
                                    body(0, "#4a525c")
                                    body(3, "#101015")

                                    // Zone band (left of the tube)
                                    function zone(a, b, color) {
                                        var y1 = yOf(b)
                                        var y2 = yOf(a)
                                        ctx.fillStyle = color
                                        ctx.fillRect(cx - tubeW / 2 - 18, y1, 7, y2 - y1)
                                    }
                                    ctx.globalAlpha = dim ? 0.35 : 1.0
                                    zone(sMin, win.tempComfortMin,            win.colorMonitor)
                                    zone(win.tempComfortMin, win.tempWarning, win.colorNormal)
                                    zone(win.tempWarning, win.tempCritical,   win.colorMonitor)
                                    zone(win.tempCritical, sMax,              win.colorCritical)
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
                                    ctx.font = "11px sans-serif"
                                    ctx.textAlign = "left"
                                    ctx.textBaseline = "middle"
                                    for (var t = sMin; t <= sMax; t += 10) {
                                        var y = yOf(t)
                                        ctx.beginPath()
                                        ctx.moveTo(cx + tubeW / 2 + 6, y)
                                        ctx.lineTo(cx + tubeW / 2 + 14, y)
                                        ctx.stroke()
                                        ctx.fillText(t + "°", cx + tubeW / 2 + 19, y)
                                    }

                                    ctx.restore()
                                }
                            }
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        textFormat: Text.RichText
                        text: (win.hasData ? win.temp.toFixed(1) : "--")
                              + "<span style='font-size:20px; font-weight:normal;'> °C</span>"
                        color: win.levelColor(win.tempLevel)
                        font.pixelSize: 44
                        font.bold: true
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: tempChipText.implicitWidth + 28
                        Layout.preferredHeight: 26
                        radius: 13
                        color: win.tint(tempFrame.tone, 0.16)
                        border.color: tempFrame.tone
                        border.width: 1
                        Text {
                            id: tempChipText
                            anchors.centerIn: parent
                            text: win.levelLabel(win.tempLevel)
                            color: tempFrame.tone
                            font.pixelSize: 12
                            font.bold: true
                            font.letterSpacing: 1
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumHeight: 34
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignTop
                        text: win.hasData ? win.tempDetail(win.temp) : ""
                        color: win.textMuted
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // ===== Humidity card =====
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                color: win.surface
                border.color: win.borderColor
                border.width: 1
                radius: 10

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 8

                    Text {
                        text: "Relative Humidity"
                        color: "#00adb5"
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Item {
                        id: humHolder
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 170

                        RingFrame {
                            id: humFrame
                            anchors.centerIn: parent
                            property real d: Math.max(160, Math.min(320,
                                             Math.min(humHolder.width, humHolder.height) - 4))
                            width: d
                            height: d
                            tone: win.levelColor(win.humLevel)

                            // Water drop drawn in a 200 x 240 design space
                            Canvas {
                                id: drop
                                anchors.fill: parent

                                property real value: win.hum
                                property bool active: win.hasData
                                property color fillColor: humFrame.tone
                                property bool dim: !win.online
                                property real phase: 0

                                onValueChanged: requestPaint()
                                onActiveChanged: requestPaint()
                                onFillColorChanged: requestPaint()
                                onDimChanged: requestPaint()
                                onPhaseChanged: requestPaint()
                                onWidthChanged: requestPaint()
                                onHeightChanged: requestPaint()
                                Component.onCompleted: requestPaint()

                                // Slow wave motion on the water surface (only while live)
                                NumberAnimation on phase {
                                    from: 0
                                    to: 2 * Math.PI
                                    duration: 3500
                                    loops: Animation.Infinite
                                    running: win.visible && win.online
                                }

                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    ctx.save()

                                    var s = Math.min(width, height) * 0.72 / 240
                                    ctx.translate(width / 2, height / 2)
                                    ctx.scale(s, s)
                                    ctx.translate(-100, -120)

                                    var cx = 96
                                    var tipY = 12
                                    var R = 54
                                    var bottom = 232
                                    var cy = bottom - R
                                    var H = cy - tipY

                                    function yOf(pct) {
                                        var f = Math.max(0, Math.min(100, pct)) / 100
                                        return bottom - f * (bottom - tipY)
                                    }

                                    function dropPath() {
                                        ctx.beginPath()
                                        ctx.moveTo(cx, tipY)
                                        ctx.bezierCurveTo(cx + R * 0.10, tipY + H * 0.30,
                                                          cx + R, cy - H * 0.38,
                                                          cx + R, cy)
                                        ctx.arc(cx, cy, R, 0, Math.PI, false)
                                        ctx.bezierCurveTo(cx - R, cy - H * 0.38,
                                                          cx - R * 0.10, tipY + H * 0.30,
                                                          cx, tipY)
                                        ctx.closePath()
                                    }

                                    // One water-surface wave layer (filled down to the bottom)
                                    function wave(yBase, amp, shift, alpha) {
                                        ctx.globalAlpha = alpha
                                        ctx.fillStyle = fillColor
                                        ctx.beginPath()
                                        ctx.moveTo(0, 240)
                                        for (var x = 0; x <= 200; x += 4) {
                                            ctx.lineTo(x, yBase + amp * Math.sin(2 * Math.PI * x / 90 + phase + shift))
                                        }
                                        ctx.lineTo(200, 240)
                                        ctx.closePath()
                                        ctx.fill()
                                        ctx.globalAlpha = 1.0
                                    }

                                    // Zone band (left of the drop)
                                    function zone(a, b, color) {
                                        var y1 = yOf(b)
                                        var y2 = yOf(a)
                                        ctx.fillStyle = color
                                        ctx.fillRect(cx - R - 16, y1, 7, y2 - y1)
                                    }
                                    ctx.globalAlpha = dim ? 0.35 : 1.0
                                    zone(0,                  win.humCriticalLow,  win.colorCritical)
                                    zone(win.humCriticalLow, win.humWarningLow,   win.colorMonitor)
                                    zone(win.humWarningLow,  win.humWarningHigh,  win.colorNormal)
                                    zone(win.humWarningHigh, win.humCriticalHigh, win.colorMonitor)
                                    zone(win.humCriticalHigh, 100,                win.colorCritical)
                                    ctx.globalAlpha = 1.0

                                    // Drop interior
                                    dropPath()
                                    ctx.fillStyle = "#101015"
                                    ctx.fill()

                                    // Water, clipped to the drop shape
                                    var f = Math.max(0, Math.min(1, value / 100))
                                    if (active && f > 0.004) {
                                        ctx.save()
                                        dropPath()
                                        ctx.clip()

                                        var yBase = yOf(value)
                                        // Wave amplitude fades out near empty / full
                                        var amp = 4 * Math.min(1, f * 12, (1 - f) * 12)

                                        wave(yBase, amp, 1.8, 0.35)   // back wave
                                        wave(yBase, amp, 0.0, 0.95)   // front wave

                                        ctx.restore()
                                    }

                                    // Drop outline
                                    dropPath()
                                    ctx.lineWidth = 3
                                    ctx.strokeStyle = "#5a636e"
                                    ctx.stroke()

                                    // Scale ticks and labels (right of the drop)
                                    ctx.strokeStyle = "#6b7684"
                                    ctx.fillStyle = "#9aa4b0"
                                    ctx.lineWidth = 1
                                    ctx.font = "11px sans-serif"
                                    ctx.textAlign = "left"
                                    ctx.textBaseline = "middle"
                                    var marks = [0, 25, 50, 75, 100]
                                    for (var i = 0; i < marks.length; i++) {
                                        var y = yOf(marks[i])
                                        ctx.beginPath()
                                        ctx.moveTo(cx + R + 6, y)
                                        ctx.lineTo(cx + R + 14, y)
                                        ctx.stroke()
                                        ctx.fillText(marks[i] + "%", cx + R + 18, y)
                                    }

                                    ctx.restore()
                                }
                            }
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        textFormat: Text.RichText
                        text: (win.hasData ? win.hum.toFixed(1) : "--")
                              + "<span style='font-size:20px; font-weight:normal;'> %</span>"
                        color: win.levelColor(win.humLevel)
                        font.pixelSize: 44
                        font.bold: true
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: humChipText.implicitWidth + 28
                        Layout.preferredHeight: 26
                        radius: 13
                        color: win.tint(humFrame.tone, 0.16)
                        border.color: humFrame.tone
                        border.width: 1
                        Text {
                            id: humChipText
                            anchors.centerIn: parent
                            text: win.levelLabel(win.humLevel)
                            color: humFrame.tone
                            font.pixelSize: 12
                            font.bold: true
                            font.letterSpacing: 1
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumHeight: 34
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignTop
                        text: win.hasData ? win.humDetail(win.hum) : ""
                        color: win.textMuted
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        // ---------- Reference: levels and colors ----------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: refCol.implicitHeight + 28
            color: win.surface
            border.color: win.borderColor
            border.width: 1
            radius: 10

            ColumnLayout {
                id: refCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    Text {
                        text: "Reference"
                        color: "#00adb5"
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    Repeater {
                        model: [
                            { label: "Normal",   color: win.colorNormal },
                            { label: "Monitor",  color: win.colorMonitor },
                            { label: "Critical", color: win.colorCritical }
                        ]
                        RowLayout {
                            spacing: 6
                            Rectangle { width: 14; height: 14; radius: 3; color: modelData.color }
                            Text {
                                text: modelData.label
                                color: win.textMuted
                                font.pixelSize: 12
                            }
                        }
                    }
                }

                // Temperature scale
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ColumnLayout {
                        Layout.preferredWidth: 120
                        Layout.alignment: Qt.AlignTop
                        spacing: 0
                        Text {
                            text: "Temperature (°C)"
                            color: "white"
                            font.pixelSize: 12
                            font.bold: true
                        }
                        Text {
                            text: "optimal " + win.tempComfortMin + "–" + win.tempComfortMax
                            color: win.textMuted
                            font.pixelSize: 11
                        }
                    }

                    RangeBar {
                        Layout.fillWidth: true
                        scaleMin: win.tempScaleMin
                        scaleMax: win.tempScaleMax
                        marks: [win.tempScaleMin, win.tempComfortMin, win.tempComfortMax,
                                win.tempWarning, win.tempCritical, win.tempScaleMax]
                        segments: [
                            { from: win.tempScaleMin,    to: win.tempComfortMin, color: win.colorMonitor },
                            { from: win.tempComfortMin,  to: win.tempComfortMax, color: win.colorNormal },
                            { from: win.tempComfortMax,  to: win.tempWarning,    color: win.colorNormal, dim: true },
                            { from: win.tempWarning,     to: win.tempCritical,   color: win.colorMonitor },
                            { from: win.tempCritical,    to: win.tempScaleMax,   color: win.colorCritical }
                        ]
                        value: win.temp
                        markerVisible: win.hasData
                        markerColor: win.levelColor(win.tempLevel)
                        dimmed: !win.online
                    }
                }

                // Humidity scale
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ColumnLayout {
                        Layout.preferredWidth: 120
                        Layout.alignment: Qt.AlignTop
                        spacing: 0
                        Text {
                            text: "Humidity (%)"
                            color: "white"
                            font.pixelSize: 12
                            font.bold: true
                        }
                        Text {
                            text: "optimal " + win.humWarningLow + "–" + win.humWarningHigh
                            color: win.textMuted
                            font.pixelSize: 11
                        }
                    }

                    RangeBar {
                        Layout.fillWidth: true
                        scaleMin: 0
                        scaleMax: 100
                        marks: [0, win.humCriticalLow, win.humWarningLow,
                                win.humWarningHigh, win.humCriticalHigh, 100]
                        segments: [
                            { from: 0,                    to: win.humCriticalLow,  color: win.colorCritical },
                            { from: win.humCriticalLow,   to: win.humWarningLow,   color: win.colorMonitor },
                            { from: win.humWarningLow,    to: win.humWarningHigh,  color: win.colorNormal },
                            { from: win.humWarningHigh,   to: win.humCriticalHigh, color: win.colorMonitor },
                            { from: win.humCriticalHigh,  to: 100,                 color: win.colorCritical }
                        ]
                        value: win.hum
                        markerVisible: win.hasData
                        markerColor: win.levelColor(win.humLevel)
                        dimmed: !win.online
                    }
                }
            }
        }
    }
}
