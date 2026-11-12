import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes

ApplicationWindow {
    id: win
    visible: false
    width: 900
    height: 900 // Altura aumentada para la cuadrícula 2x2
    minimumWidth: 800
    minimumHeight: 850
    title: "Environmental Monitoring"
    transientParent: null

    background: Rectangle { color: "#121212" }

    // ============================================================
    // Thresholds & Colors
    // ============================================================
    readonly property real tempScaleMin:    0
    readonly property real tempScaleMax:    50
    readonly property real tempCriticalLow: 5
    readonly property real tempComfortMin:  18
    readonly property real tempComfortMax:  21
    readonly property real tempWarningHigh: 25
    readonly property real tempCritical:    27

    readonly property real humScaleMin:     0
    readonly property real humScaleMax:     100
    readonly property real humCriticalLow:  40
    readonly property real humWarningLow:   55
    readonly property real humWarningHigh:  65
    readonly property real humCriticalHigh: 80

    readonly property real eco2ScaleMin:    400
    readonly property real eco2ScaleMax:    3000
    readonly property real eco2WarningHigh: 1000
    readonly property real eco2Critical:    2000

    readonly property real tvocScaleMin:    0
    readonly property real tvocScaleMax:    2000
    readonly property real tvocWarningHigh: 250
    readonly property real tvocCritical:    1000

    readonly property int staleTimeoutMs: 10000

    readonly property int levelNoData:   -1
    readonly property int levelNormal:    0
    readonly property int levelWarning:   1
    readonly property int levelCritical:  2

    readonly property color colorAccent:   "#4A90E2"
    readonly property color colorPrimary:  "#00adb5"
    readonly property color colorNormal:   "#2ECC71"
    readonly property color colorWarning:  "#F1C40F"
    readonly property color colorCritical: "#E74C3C"
    readonly property color colorNoData:   "#7F8C8D"

    readonly property color surface:      "#1E1E24"
    readonly property color surfaceInner: "#141419"
    readonly property color textMuted:    "#95A5A6"

    function levelColor(level) {
        switch (level) {
        case levelNormal:   return colorNormal
        case levelWarning:  return colorWarning
        case levelCritical: return colorCritical
        default:            return colorNoData
        }
    }

    function levelLabel(level) {
        switch (level) {
        case levelNormal:   return "GOOD"
        case levelWarning:  return "FAIR"
        case levelCritical: return "CRITICAL"
        default:            return hasData ? "OFFLINE" : "NO DATA"
        }
    }

    function tempLevelOf(t) {
        if (t > tempCritical || t < tempCriticalLow)     return levelCritical
        if (t >= tempWarningHigh || t < tempComfortMin)  return levelWarning
        return levelNormal
    }

    function humLevelOf(h) {
        if (h < humCriticalLow || h > humCriticalHigh) return levelCritical
        if (h < humWarningLow  || h > humWarningHigh)  return levelWarning
        return levelNormal
    }

    function eco2LevelOf(c) {
        if (c > eco2Critical) return levelCritical
        if (c > eco2WarningHigh) return levelWarning
        return levelNormal
    }

    function tvocLevelOf(v) {
        if (v > tvocCritical) return levelCritical
        if (v > tvocWarningHigh) return levelWarning
        return levelNormal
    }

    function tempDetail(t) {
        if (t < tempCriticalLow) return "Critical cold (below " + tempCriticalLow + " °C)"
        if (t > tempCritical)    return "High temperature (above " + tempCritical + " °C)"
        if (t >= tempWarningHigh)return "Above recommended maximum (" + tempWarningHigh + " °C)"
        if (t < tempComfortMin)  return "Below comfort range (" + tempComfortMin + " °C)"
        if (t <= tempComfortMax) return "Optimal comfort range"
        return "Acceptable, above optimal range"
    }

    function humDetail(h) {
        if (h < humCriticalLow)  return "Very dry air (below " + humCriticalLow + " %)"
        if (h > humCriticalHigh) return "Very humid air (above " + humCriticalHigh + " %)"
        if (h < humWarningLow)   return "Air too dry (below " + humWarningLow + " %)"
        if (h > humWarningHigh)  return "Air too humid (above " + humWarningHigh + " %)"
        return "Optimal range"
    }

    function eco2Detail(c) {
        if (c > eco2Critical) return "Critical CO2 (above " + eco2Critical + " ppm)"
        if (c > eco2WarningHigh) return "Poor ventilation (above " + eco2WarningHigh + " ppm)"
        return "Optimal ventilation"
    }

    function tvocDetail(v) {
        if (v > tvocCritical) return "High VOC levels detected (above " + tvocCritical + " ppb)"
        if (v > tvocWarningHigh) return "Moderate VOC levels (above " + tvocWarningHigh + " ppb)"
        return "Clean air"
    }

    // ============================================================
    // Data State
    // ============================================================
    readonly property real temp: backend.temperature
    readonly property real hum:  backend.humidity
    readonly property real eco2: backend.eco2
    readonly property real tvoc: backend.tvoc
    readonly property bool hasData: backend.hasTelemetry

    property real nowMs: Date.now()
    property real lastUpdateMs: 0

    readonly property bool online: hasData && (nowMs - lastUpdateMs) < staleTimeoutMs
    readonly property int ageSec: Math.max(0, Math.floor((nowMs - lastUpdateMs) / 1000))

    readonly property string lastUpdateText:
        Qt.formatDateTime(new Date(lastUpdateMs), "yyyy-MM-dd hh:mm:ss")

    readonly property int tempLevel: online ? tempLevelOf(temp) : levelNoData
    readonly property int humLevel:  online ? humLevelOf(hum)   : levelNoData
    readonly property int eco2Level: online ? eco2LevelOf(eco2) : levelNoData
    readonly property int tvocLevel: online ? tvocLevelOf(tvoc) : levelNoData

    readonly property int overallLevel: online ? Math.max(tempLevel, humLevel, eco2Level, tvocLevel) : levelNoData
    readonly property string overallLabel: levelLabel(overallLevel)

    readonly property string freshnessText: {
        if (!hasData) return "Waiting for data"
        if (online)   return "Live  ·  updated " + ageSec + " s ago"
        return "Last update: " + lastUpdateText
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
    // Components: Segmented Gauge (Arc)
    // ============================================================
    component ArcGauge: Item {
        id: gauge
        property real value: 0
        property real scaleMin: 0
        property real scaleMax: 100
        property int currentLevel: win.levelNoData

        readonly property real startAngle: 150
        readonly property real sweepAngle: 240

        implicitWidth: 240
        implicitHeight: 240

        readonly property real valueAngle: startAngle + (Math.max(0, Math.min(scaleMax, value)) - scaleMin) / (scaleMax - scaleMin) * sweepAngle

        Shape {
            anchors.fill: parent
            layer.enabled: true
            ShapePath {
                strokeColor: "#2C2C35"
                strokeWidth: 16
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: gauge.width / 2
                    centerY: gauge.height / 2
                    radiusX: gauge.width / 2 - 16
                    radiusY: gauge.width / 2 - 16
                    startAngle: gauge.startAngle
                    sweepAngle: gauge.sweepAngle
                }
            }
        }

        Shape {
            anchors.fill: parent
            layer.enabled: true
            ShapePath {
                strokeColor: win.levelColor(gauge.currentLevel)
                strokeWidth: 16
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: gauge.width / 2
                    centerY: gauge.height / 2
                    radiusX: gauge.width / 2 - 16
                    radiusY: gauge.width / 2 - 16
                    startAngle: gauge.startAngle
                    sweepAngle: Math.max(0.1, gauge.valueAngle - gauge.startAngle)
                }
            }
        }
    }

    // ============================================================
    // UI Layout
    // ============================================================
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 20

        // ---------- Header ----------
        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                spacing: 2
                Text {
                    text: "HQ Robot - Environment"
                    color: win.colorPrimary
                    font.pixelSize: 24
                    font.weight: Font.Light
                }
                Text {
                    text: backend.sensorId !== "" ? "Sensor: " + backend.sensorId : "No sensor"
                    color: win.textMuted
                    font.pixelSize: 14
                }
            }

            Item { Layout.fillWidth: true }

            ColumnLayout {
                spacing: 2
                Text {
                    Layout.alignment: Qt.AlignRight
                    text: Qt.formatDateTime(new Date(win.nowMs), "hh:mm:ss")
                    color: "white"
                    font.pixelSize: 18
                    font.weight: Font.Light
                }
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: 6
                    Rectangle {
                        width: 8; height: 8; radius: 4
                        color: win.online ? win.colorNormal : win.colorNoData
                    }
                    Text {
                        text: win.freshnessText
                        color: win.textMuted
                        font.pixelSize: 12
                    }
                }
            }
        }

        // ---------- Cards Grid (2x2) ----------
        GridLayout {
            columns: 2
            rowSpacing: 20
            columnSpacing: 20
            Layout.fillWidth: true
            Layout.fillHeight: true

            // ==========================================
            // Temperature Card
            // ==========================================
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: win.surface
                radius: 16
                border.color: "#2C2C35"
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 16

                    RowLayout {
                        spacing: 8
                        Text { text: "\uD83C\uDF21"; color: win.colorPrimary; font.pixelSize: 20 }
                        Text { text: "Temperature"; color: "white"; font.pixelSize: 16; font.bold: true }
                    }

                    Item {
                        Layout.fillWidth: true; Layout.fillHeight: true

                        ArcGauge {
                            anchors.centerIn: parent
                            value: win.temp
                            scaleMin: win.tempScaleMin
                            scaleMax: win.tempScaleMax
                            currentLevel: win.tempLevel
                        }

                        ColumnLayout {
                            anchors.centerIn: parent; spacing: -8
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                textFormat: Text.RichText
                                text: (win.hasData ? win.temp.toFixed(1) : "--") + "<span style='font-size:32px; color:#95A5A6;'> °C</span>"
                                color: "white"; font.pixelSize: 64; font.weight: Font.Light
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: win.levelLabel(win.tempLevel)
                                color: win.levelColor(win.tempLevel); font.pixelSize: 18; font.bold: true; font.letterSpacing: 2
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 6
                        Text { text: win.hasData ? win.tempDetail(win.temp) : "Awaiting data..."; color: win.textMuted; font.pixelSize: 13 }
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 6; radius: 3; color: "#2C2C35"
                            Rectangle {
                                width: parent.width * Math.max(0, Math.min(1, (win.temp - win.tempScaleMin) / (win.tempScaleMax - win.tempScaleMin)))
                                height: parent.height; radius: 3; color: win.levelColor(win.tempLevel)
                                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }
            }

            // ==========================================
            // Humidity Card
            // ==========================================
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: win.surface
                radius: 16
                border.color: "#2C2C35"
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 16

                    RowLayout {
                        spacing: 8
                        Text { text: "\uD83D\uDCA7"; color: win.colorPrimary; font.pixelSize: 20 }
                        Text { text: "Humidity"; color: "white"; font.pixelSize: 16; font.bold: true }
                    }

                    Item {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        ArcGauge {
                            anchors.centerIn: parent
                            value: win.hum
                            scaleMin: win.humScaleMin
                            scaleMax: win.humScaleMax
                            currentLevel: win.humLevel
                        }
                        ColumnLayout {
                            anchors.centerIn: parent; spacing: -8
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                textFormat: Text.RichText
                                text: (win.hasData ? win.hum.toFixed(1) : "--") + "<span style='font-size:32px; color:#95A5A6;'> %</span>"
                                color: "white"; font.pixelSize: 64; font.weight: Font.Light
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: win.levelLabel(win.humLevel)
                                color: win.levelColor(win.humLevel); font.pixelSize: 18; font.bold: true; font.letterSpacing: 2
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 6
                        Text { text: win.hasData ? win.humDetail(win.hum) : "Awaiting data..."; color: win.textMuted; font.pixelSize: 13 }
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 6; radius: 3; color: "#2C2C35"
                            Rectangle {
                                width: parent.width * Math.max(0, Math.min(1, (win.hum - win.humScaleMin) / (win.humScaleMax - win.humScaleMin)))
                                height: parent.height; radius: 3; color: win.levelColor(win.humLevel)
                                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }
            }

            // ==========================================
            // eCO2 Card
            // ==========================================
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: win.surface
                radius: 16
                border.color: "#2C2C35"
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 16

                    RowLayout {
                        spacing: 8
                        Text { text: "☁️"; color: win.colorPrimary; font.pixelSize: 20 }
                        Text { text: "eCO2"; color: "white"; font.pixelSize: 16; font.bold: true }
                    }

                    Item {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        ArcGauge {
                            anchors.centerIn: parent
                            value: win.eco2
                            scaleMin: win.eco2ScaleMin
                            scaleMax: win.eco2ScaleMax
                            currentLevel: win.eco2Level
                        }
                        ColumnLayout {
                            anchors.centerIn: parent; spacing: -8
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                textFormat: Text.RichText
                                text: (win.hasData ? Math.round(win.eco2) : "--") + "<span style='font-size:32px; color:#95A5A6;'> ppm</span>"
                                color: "white"; font.pixelSize: 64; font.weight: Font.Light
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: win.levelLabel(win.eco2Level)
                                color: win.levelColor(win.eco2Level); font.pixelSize: 18; font.bold: true; font.letterSpacing: 2
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 6
                        Text { text: win.hasData ? win.eco2Detail(win.eco2) : "Awaiting data..."; color: win.textMuted; font.pixelSize: 13 }
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 6; radius: 3; color: "#2C2C35"
                            Rectangle {
                                width: parent.width * Math.max(0, Math.min(1, (win.eco2 - win.eco2ScaleMin) / (win.eco2ScaleMax - win.eco2ScaleMin)))
                                height: parent.height; radius: 3; color: win.levelColor(win.eco2Level)
                                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }
            }

            // ==========================================
            // TVOC Card
            // ==========================================
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: win.surface
                radius: 16
                border.color: "#2C2C35"
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 16

                    RowLayout {
                        spacing: 8
                        Text { text: "🧪"; color: win.colorPrimary; font.pixelSize: 20 }
                        Text { text: "TVOC"; color: "white"; font.pixelSize: 16; font.bold: true }
                    }

                    Item {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        ArcGauge {
                            anchors.centerIn: parent
                            value: win.tvoc
                            scaleMin: win.tvocScaleMin
                            scaleMax: win.tvocScaleMax
                            currentLevel: win.tvocLevel
                        }
                        ColumnLayout {
                            anchors.centerIn: parent; spacing: -8
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                textFormat: Text.RichText
                                text: (win.hasData ? Math.round(win.tvoc) : "--") + "<span style='font-size:32px; color:#95A5A6;'> ppb</span>"
                                color: "white"; font.pixelSize: 64; font.weight: Font.Light
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: win.levelLabel(win.tvocLevel)
                                color: win.levelColor(win.tvocLevel); font.pixelSize: 18; font.bold: true; font.letterSpacing: 2
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 6
                        Text { text: win.hasData ? win.tvocDetail(win.tvoc) : "Awaiting data..."; color: win.textMuted; font.pixelSize: 13 }
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 6; radius: 3; color: "#2C2C35"
                            Rectangle {
                                width: parent.width * Math.max(0, Math.min(1, (win.tvoc - win.tvocScaleMin) / (win.tvocScaleMax - win.tvocScaleMin)))
                                height: parent.height; radius: 3; color: win.levelColor(win.tvocLevel)
                                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }
            }
        }
    }
}