import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: camWin
    visible: false
    width: 720
    height: 620
    minimumWidth: 640
    minimumHeight: 540
    title: "ESP32-CAM Vision & Color Detection"
    transientParent: null

    background: Rectangle { color: "#141419" }

    // Activa o detiene el hilo de lectura de cámara al abrir/cerrar la ventana
    onVisibleChanged: {
        backend.set_camera_active(visible)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // ---------- Barra Superior: IP Cámara y Estado ----------
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                width: 12; height: 12; radius: 6
                color: backend.cameraConnected ? "#2ECC71" : "#E74C3C"
            }

            Text {
                text: backend.cameraConnected ? "Stream Online" : "Disconnected"
                color: "white"
                font.pixelSize: 13
            }

            TextField {
                id: camUrlInput
                text: backend.cameraUrl
                placeholderText: "http://IP/stream"
                font.pixelSize: 13
                color: "white"
                background: Rectangle {
                    color: "#1b1b22"
                    border.color: "#393e46"
                    radius: 4
                }
                Layout.fillWidth: true
                Layout.preferredHeight: 30
            }

            Button {
                text: "Update URL"
                Layout.preferredHeight: 30
                onClicked: backend.set_camera_url(camUrlInput.text)
            }
        }

        // ---------- Visor de Video ----------
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#0d0d11"
            border.color: "#393e46"
            border.width: 2
            radius: 8
            clip: true

            Image {
                id: videoFeed
                anchors.fill: parent
                anchors.margins: 4
                fillMode: Image.PreserveAspectFit
                cache: false
                smooth: false // Mantiene nitidez en resolución 160x120
                source: "image://camera/frame?0"

                property int frameCounter: 0
            }

            Connections {
                target: backend
                function onCameraFrameReady() {
                    videoFeed.frameCounter++
                    videoFeed.source = "image://camera/frame?" + videoFeed.frameCounter
                }
            }

            Text {
                anchors.centerIn: parent
                visible: !backend.cameraConnected
                text: "Waiting for ESP32-CAM RGB565 stream..."
                color: "#7F8C8D"
                font.pixelSize: 15
            }
        }

        // ---------- Controles de Detección de Color ----------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: hsvControls.visible ? 165 : 64
            color: "#1b1b22"
            border.color: "#393e46"
            border.width: 1
            radius: 8

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    // Botón principal para activar/desactivar detección
                    Button {
                        text: backend.colorDetectionEnabled ? "Color Detection: ON" : "Color Detection: OFF"
                        Layout.preferredWidth: 210
                        Layout.preferredHeight: 38
                        highlighted: backend.colorDetectionEnabled
                        onClicked: backend.toggle_color_detection()
                    }

                    Text {
                        text: backend.colorDetected
                              ? "Target: BLUE DETECTED (Area: " + backend.detectedArea + ")"
                              : "Target: Searching..."
                        color: backend.colorDetected ? "#2ECC71" : "#95A5A6"
                        font.pixelSize: 13
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    Button {
                        text: hsvControls.visible ? "Hide HSV" : "Calibrate HSV"
                        Layout.preferredHeight: 34
                        onClicked: hsvControls.visible = !hsvControls.visible
                    }
                }

                // Sliders HSV opcionales (reemplazan cv2.createTrackbar)
                GridLayout {
                    id: hsvControls
                    visible: false
                    columns: 4
                    rowSpacing: 4
                    columnSpacing: 12
                    Layout.fillWidth: true

                    Text { text: "H Min (" + Math.round(hMinSlider.value) + ")"; color: "#aaa"; font.pixelSize: 12 }
                    Slider { id: hMinSlider; from: 0; to: 179; value: 100; Layout.fillWidth: true; onMoved: updateHsv() }

                    Text { text: "H Max (" + Math.round(hMaxSlider.value) + ")"; color: "#aaa"; font.pixelSize: 12 }
                    Slider { id: hMaxSlider; from: 0; to: 179; value: 130; Layout.fillWidth: true; onMoved: updateHsv() }

                    Text { text: "S Min (" + Math.round(sMinSlider.value) + ")"; color: "#aaa"; font.pixelSize: 12 }
                    Slider { id: sMinSlider; from: 0; to: 255; value: 100; Layout.fillWidth: true; onMoved: updateHsv() }

                    Text { text: "V Min (" + Math.round(vMinSlider.value) + ")"; color: "#aaa"; font.pixelSize: 12 }
                    Slider { id: vMinSlider; from: 0; to: 255; value: 50; Layout.fillWidth: true; onMoved: updateHsv() }

                    function updateHsv() {
                        backend.set_hsv_bounds(
                            Math.round(hMinSlider.value),
                            Math.round(hMaxSlider.value),
                            Math.round(sMinSlider.value),
                            Math.round(vMinSlider.value)
                        )
                    }
                }
            }
        }
    }
}