import QtQuick
import QtQuick.Controls

ApplicationWindow {
    id: window
    visible: true
    width: 800
    height: 480
    title: "Panel Táctil - Robot Control"

    background: Rectangle { color: "#141419" }

    // ETIQUETAS DE TEXTO DINÁMICAS (Muestran los datos del Joystick)
    Column {
        anchors.top: parent.top
        anchors.topMargin: 20
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 5

        Text {
            text: "CONTROL DE DESPLAZAMIENTO"
            color: "#00adb5"
            font.pixelSize: 22
            font.bold: true
        }

        Text {
            // Vinculamos el texto dinámicamente usando las propiedades personalizadas del Joystick
            text: "Joystick X: " + Math.round(joystickBase.outputX) + " | Y: " + Math.round(joystickBase.outputY)
            color: "white"
            font.pixelSize: 16
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    // CONTENEDOR DEL JOYSTICK (La base gris externa)
    Rectangle {
        id: joystickBase
        width: 200
        height: 200
        radius: width / 2
        color: "#222831"
        border.color: "#393e46"
        border.width: 4

        anchors.bottom: parent.bottom
        anchors.bottomMargin: 50
        anchors.horizontalCenter: parent.horizontalCenter

        // Propiedades personalizadas para almacenar los valores listos para el robot (-100 a 100)
        property real outputX: 0
        property real outputY: 0

        // LA PALANCA (Ya no usa anchors, usa coordenadas x e y manuales)
        Rectangle {
            id: joystickStick
            width: 80
            height: 80
            radius: width / 2
            color: "#00adb5"

            // Centrado inicial de manera matemática: (AnchoBase / 2) - (AnchoStick / 2)
            x: (joystickBase.width / 2) - (width / 2)
            y: (joystickBase.height / 2) - (height / 2)

            // Animación suave cuando regresa al centro
            Behavior on x { NumberAnimation { duration: 50; easing.type: Easing.OutQuad } }
            Behavior on y { NumberAnimation { duration: 50; easing.type: Easing.OutQuad } }
        }

        MouseArea {
            anchors.fill: parent
            preventStealing: true

            function updateJoystickPosition(mouseX, mouseY) {
                let centerX = joystickBase.width / 2;
                let centerY = joystickBase.height / 2;

                let dx = mouseX - centerX;
                let dy = mouseY - centerY;
                let distance = Math.sqrt(dx * dx + dy * dy);

                let maxDistance = (joystickBase.width / 2) - (joystickStick.width / 2);

                if (distance > maxDistance) {
                    let angle = Math.atan2(dy, dx);
                    joystickStick.x = centerX + Math.cos(angle) * maxDistance - (joystickStick.width / 2);
                    joystickStick.y = centerY + Math.sin(angle) * maxDistance - (joystickStick.height / 2);

                    // Almacenamos el valor mapeado al límite máximo (-100 a 100)
                    joystickBase.outputX = Math.cos(angle) * 100;
                    joystickBase.outputY = -Math.sin(angle) * 100; // Invertido para que "Arriba" sea positivo
                } else {
                    joystickStick.x = mouseX - (joystickStick.width / 2);
                    joystickStick.y = mouseY - (joystickStick.height / 2);

                    // Almacenamos el valor proporcional actual
                    joystickBase.outputX = (dx / maxDistance) * 100;
                    joystickBase.outputY = -(dy / maxDistance) * 100;
                }

                backend.actualizar_joystick(joystickBase.outputX, joystickBase.outputY);
            }

            onPositionChanged: (mouse) => updateJoystickPosition(mouse.x, mouse.y)
            onPressed: (mouse) => updateJoystickPosition(mouse.x, mouse.y)

            onReleased: {
                // Al soltar, regresa al centro matemático
                joystickStick.x = (joystickBase.width / 2) - (joystickStick.width / 2);
                joystickStick.y = (joystickBase.height / 2) - (joystickStick.height / 2);

                // Reseteamos las salidas a cero
                joystickBase.outputX = 0;
                joystickBase.outputY = 0;

                backend.actualizar_joystick(0, 0);
            }
        }
    }
}
