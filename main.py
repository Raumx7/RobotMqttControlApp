import sys
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtCore import QObject, Slot

# Clase puente para recibir los datos de la interfaz táctil
class Backend(QObject):
    def __init__(self):
        super().__init__()

    # El decorador Slot(float, float) le dice a Qt que esta función
    # recibirá dos números con punto decimal desde QML.
    @Slot(float, float)
    def actualizar_joystick(self, x, y):
        # Redondeamos los valores para que queden como enteros limpios entre -100 y 100
        eje_x = round(x)
        eje_y = round(y)

        # ¡Aquí imprimimos en la consola de Python en tiempo real!
        print(f"[Python Backend] Datos Recibidos -> X: {eje_x:4d} | Y: {eje_y:4d}")

        # NOTA: En el futuro, aquí es donde tomarás estos valores,
        # decidirás si el robot va Forward/Backward usando condicionales,
        # armarás tu struct con struct.pack y lo mandarás por MQTT.

if __name__ == "__main__":
    app = QGuiApplication(sys.argv)
    engine = QQmlApplicationEngine()

    # Instanciamos e inyectamos el backend
    backend = Backend()
    engine.rootContext().setContextProperty("backend", backend)

    # CORRECCIÓN AQUÍ: Cargamos el archivo visual .qml, NO el archivo .py
    engine.load("RobotApp/Main.qml")

    if not engine.rootObjects():
        sys.exit(-1)

    sys.exit(app.exec())

