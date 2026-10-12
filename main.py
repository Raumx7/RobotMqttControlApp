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
    connectionChanged    = Signal(bool)
    lastResponseChanged  = Signal(str)
    brakeModeChanged     = Signal(str)
    moveValuesChanged    = Signal(int, int)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._connected      = False
        self._last_response  = ""
        self._brake_mode     = "coast"
        self._l_power        = 0
        self._r_power        = 0

        # ⚠️ IMPORTANTE: crear los eventos de sincronización ANTES
        # de lanzar cualquier hilo. Si el hilo arranca primero,
        # accede a self._stop_event cuando todavía no existe.
        self._stop_event      = threading.Event()
        self._publish_lock    = threading.Lock()
        self._pending_publish = None

        # --- Cliente MQTT ---
        self._client = mqtt.Client(
            callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
            client_id=CLIENT_ID,
            protocol=mqtt.MQTTv311,
        )
        self._client.on_connect    = self._on_connect
        self._client.on_disconnect = self._on_disconnect
        self._client.on_message    = self._on_message

        # --- Hilos (después de tener todo inicializado) ---
        self._publish_thread = threading.Thread(
            target=self._publish_worker,
            name="publish_worker",
            daemon=True,
        )
        self._publish_thread.start()

        self._connection_thread = threading.Thread(
            target=self._connection_loop,
            name="connection_loop",
            daemon=True,
        )
        self._connection_thread.start()

    # ------------------------------------------------------------------
    # Reconexión automática
    # ------------------------------------------------------------------

    def _connection_loop(self):
        backoff = 1.0
        max_backoff = 30.0

        while not self._stop_event.is_set():
            if not self._client.is_connected():
                try:
                    print(f"[MQTT] Conectando a {MQTT_BROKER}:{MQTT_PORT}...")
                    self._client.connect(MQTT_BROKER, MQTT_PORT, keepalive=30)
                    self._client.loop_start()
                    backoff = 1.0
                except Exception as e:
                    print(f"[MQTT] Error: {e}. Reintentando en {backoff:.1f}s")
                    self._stop_event.wait(backoff)
                    backoff = min(backoff * 2.0, max_backoff)

            self._stop_event.wait(1.0)

    def stop(self):
        """Cierre limpio: detiene hilos y desconecta del broker."""
        self._stop_event.set()
        try:
            self._client.loop_stop()
            self._client.disconnect()
        except Exception:
            pass

    # ------------------------------------------------------------------
    # Publicación asíncrona
    # ------------------------------------------------------------------

    def _publish_worker(self):
        while not self._stop_event.is_set():
            with self._publish_lock:
                payload = self._pending_publish
                self._pending_publish = None

            if payload is not None:
                try:
                    self._client.publish(MQTT_PUB, payload)
                except Exception as e:
                    print(f"[MQTT] Error al publicar: {e}")
            else:
                self._stop_event.wait(0.05)

    def _enqueue(self, payload: str):
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
            self._connected = False
            self.connectionChanged.emit(False)

    def _on_disconnect(self, client, userdata, flags, rc, properties=None):
        print("[MQTT] Desconectado")
        self._connected = False
        self.connectionChanged.emit(False)

    def _on_message(self, client, userdata, msg):
        try:
            payload = msg.payload.decode("utf-8", errors="replace")
        except Exception:
            payload = "<decode error>"

        # Intentar parsear como JSON
        parsed = None
        try:
            parsed = json.loads(payload)
            pretty = json.dumps(parsed, indent=2, ensure_ascii=False)
        except Exception:
            pretty = payload

        # Actualizar estado interno si el JSON tiene los campos esperados
        if isinstance(parsed, dict):
            if "b" in parsed:
                self._brake_mode = str(parsed["b"])
                self.brakeModeChanged.emit(self._brake_mode)

            l = parsed.get("l")
            r = parsed.get("r")
            if isinstance(l, int) and isinstance(r, int):
                self._l_power = l
                self._r_power = r
                self.moveValuesChanged.emit(l, r)

        self._last_response = pretty
        print(f"[MQTT] {msg.topic}: {pretty}")
        self.lastResponseChanged.emit(pretty)

    # ------------------------------------------------------------------
    # Propiedades QML
    # ------------------------------------------------------------------

    @Property(bool, notify=connectionChanged)
    def connected(self):
        return self._connected

    @Property(str, notify=lastResponseChanged)
    def lastResponse(self):
        return self._last_response

    @Property(str, notify=brakeModeChanged)
    def brakeMode(self):
        return self._brake_mode

    @Property(int, notify=moveValuesChanged)
    def leftPower(self):
        return self._l_power

    @Property(int, notify=moveValuesChanged)
    def rightPower(self):
        return self._r_power

    # ------------------------------------------------------------------
    # Slots
    # ------------------------------------------------------------------

    @Slot(str)
    def send_command(self, command: str):
        if not command:
            return
        print(f"[TX] {command}")
        self._enqueue(command)

    @Slot(float, float)
    def actualizar_joystick(self, x, y):
        xi = int(round(x))
        yi = int(round(y))
        cmd = f"A {xi} {yi}"
        print(f"[TX] {cmd}")
        self._enqueue(cmd)

    @Slot(str)
    def set_brake_mode(self, mode: str):
        mode = mode.lower()
        if mode == "brake":
            cmd = "B 1"
        elif mode == "coast":
            cmd = "B 0"
        else:
            print(f"[TX] Modo de freno desconocido: {mode}")
            return
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

    # Mantener referencia viva mientras la app corre
    app.backend = backend

    exit_code = app.exec()
    backend.stop()
    sys.exit(exit_code)