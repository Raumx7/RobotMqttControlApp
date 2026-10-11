import sys
import json
import threading
import paho.mqtt.client as mqtt
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtCore import QObject, Slot, Signal, Property

# --- Configuración MQTT ---
MQTT_BROKER = "localhost"
MQTT_PORT   = 1883
MQTT_SUB    = "robot/response"
MQTT_PUB    = "robot/command"
CLIENT_ID   = "qt-robot-panel"


class Backend(QObject):
    # Señales que QML puede observar para actualizar la UI
    connectionChanged = Signal(bool)
    lastResponseChanged = Signal(str)

    def __init__(self, parent=None):
        super().__init__(parent)

        self._connected = False
        self._last_response = ""

        # --- Cliente MQTT ---
        self._client = mqtt.Client(
            callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
            client_id=CLIENT_ID,
            protocol=mqtt.MQTTv311,
        )
        self._client.on_connect    = self._on_connect
        self._client.on_disconnect = self._on_disconnect
        self._client.on_message    = self._on_message

        # Publicamos desde un hilo dedicado para no bloquear la UI
        self._publish_lock = threading.Lock()
        self._pending_publish: str | None = None
        self._publish_thread = threading.Thread(
            target=self._publish_worker, daemon=True
        )
        self._publish_thread.start()

        # Conectamos en un hilo aparte
        threading.Thread(target=self._connect_worker, daemon=True).start()

    # ------------------------------------------------------------------
    # Hilos de red
    # ------------------------------------------------------------------

    def _connect_worker(self):
        try:
            self._client.connect(MQTT_BROKER, MQTT_PORT, keepalive=30)
            self._client.loop_forever()
        except Exception as e:
            print(f"[MQTT] Error de conexión: {e}")

    def _publish_worker(self):
        """Hilo que consume comandos encolados y los publica."""
        while True:
            with self._publish_lock:
                payload = self._pending_publish
                self._pending_publish = None
            if payload is not None:
                try:
                    self._client.publish(MQTT_PUB, payload)
                except Exception as e:
                    print(f"[MQTT] Error al publicar: {e}")
            else:
                threading.Event().wait(0.05)   # 50 ms de espera

    def _enqueue(self, payload: str):
        """Encola un mensaje para publicar."""
        with self._publish_lock:
            self._pending_publish = payload

    # ------------------------------------------------------------------
    # Callbacks MQTT
    # ------------------------------------------------------------------

    def _on_connect(self, client, userdata, flags, rc, properties=None):
        if rc == 0:
            print("[MQTT] Conectado al broker")
            client.subscribe(MQTT_SUB)
            self._connected = True
            self.connectionChanged.emit(True)
        else:
            print(f"[MQTT] Fallo de conexión, rc={rc}")

    def _on_disconnect(self, client, userdata, flags, rc, properties=None):
        print("[MQTT] Desconectado")
        self._connected = False
        self.connectionChanged.emit(False)

    def _on_message(self, client, userdata, msg):
        try:
            payload = msg.payload.decode("utf-8", errors="replace")
        except Exception:
            payload = "<decode error>"

        # Formateamos el JSON si es válido
        try:
            parsed = json.loads(payload)
            pretty = json.dumps(parsed, indent=2, ensure_ascii=False)
        except Exception:
            pretty = payload

        self._last_response = pretty
        print(f"[MQTT] {msg.topic}: {pretty}")
        self.lastResponseChanged.emit(pretty)

    # ------------------------------------------------------------------
    # Propiedades expuestas a QML
    # ------------------------------------------------------------------

    @Property(bool, notify=connectionChanged)
    def connected(self):
        return self._connected

    @Property(str, notify=lastResponseChanged)
    def lastResponse(self):
        return self._last_response

    # ------------------------------------------------------------------
    # Slots invocables desde QML
    # ------------------------------------------------------------------

    @Slot(str)
    def send_command(self, command: str):
        """Envía un comando de texto crudo (fw, bw, st, etc.)."""
        if not command:
            return
        print(f"[TX] {command}")
        self._enqueue(command)

    @Slot(float, float)
    def actualizar_joystick(self, x, y):
        """Envía comando de joystick como A x y."""
        xi = int(round(x))
        yi = int(round(y))

        # Comando en formato arcade: A <x> <y>
        cmd = f"A {xi} {yi}"
        print(f"[TX] {cmd}")
        self._enqueue(cmd)


if __name__ == "__main__":
    app = QGuiApplication(sys.argv)
    engine = QQmlApplicationEngine()

    backend = Backend()
    engine.rootContext().setContextProperty("backend", backend)

    engine.load("RobotApp/Main.qml")

    if not engine.rootObjects():
        sys.exit(-1)

    sys.exit(app.exec())