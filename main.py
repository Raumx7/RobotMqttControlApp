import sys
import json
import threading
import paho.mqtt.client as mqtt
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtCore import QObject, Slot, Signal, Property

# --- MQTT Configuration ---
MQTT_BROKER   = "localhost"
MQTT_PORT     = 1883
MQTT_SUB_RESP = "robot/response"
MQTT_SUB_STAT = "robot/status"
MQTT_PUB      = "robot/command"
CLIENT_ID     = "qt-robot-panel"


class Backend(QObject):
    connectionChanged = Signal(bool)
    responsesChanged  = Signal()

    # Robot status signals (from robot/status topic)
    leftChanged      = Signal(int)
    rightChanged     = Signal(int)
    modeChanged      = Signal(str)
    brakeModeChanged = Signal(str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._connected = False

        # Last robot responses, newest first (one compact line each)
        self._responses     = []
        self._max_responses = 10

        # Internal status
        self._left       = 0
        self._right      = 0
        self._mode       = "manual"
        self._brake_mode = "coast"

        # Synchronization - MUST be created before starting threads
        self._stop_event      = threading.Event()
        self._publish_lock    = threading.Lock()
        self._pending_publish = None

        # --- MQTT Client ---
        self._client = mqtt.Client(
            callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
            client_id=CLIENT_ID,
            protocol=mqtt.MQTTv311,
        )
        self._client.on_connect    = self._on_connect
        self._client.on_disconnect = self._on_disconnect
        self._client.on_message    = self._on_message

        # --- Threads ---
        self._publish_thread = threading.Thread(
            target=self._publish_worker, name="publish_worker", daemon=True)
        self._publish_thread.start()

        self._connection_thread = threading.Thread(
            target=self._connection_loop, name="connection_loop", daemon=True)
        self._connection_thread.start()

    # ------------------------------------------------------------------
    # Automatic reconnection
    # ------------------------------------------------------------------

    def _connection_loop(self):
        backoff = 1.0
        max_backoff = 30.0
        while not self._stop_event.is_set():
            if not self._client.is_connected():
                try:
                    print(f"[MQTT] Connecting to {MQTT_BROKER}:{MQTT_PORT}...")
                    self._client.connect(MQTT_BROKER, MQTT_PORT, keepalive=30)
                    self._client.loop_start()
                    backoff = 1.0
                except Exception as e:
                    print(f"[MQTT] Error: {e}. Retrying in {backoff:.1f}s")
                    self._stop_event.wait(backoff)
                    backoff = min(backoff * 2.0, max_backoff)
            self._stop_event.wait(1.0)

    def stop(self):
        self._stop_event.set()
        try:
            self._client.loop_stop()
            self._client.disconnect()
        except Exception:
            pass

    # ------------------------------------------------------------------
    # Async publishing
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
                    print(f"[MQTT] Publish error: {e}")
            else:
                self._stop_event.wait(0.05)

    def _enqueue(self, payload: str):
        with self._publish_lock:
            self._pending_publish = payload

    # ------------------------------------------------------------------
    # MQTT Callbacks
    # ------------------------------------------------------------------

    def _on_connect(self, client, userdata, flags, rc, properties=None):
        if rc == 0:
            print("[MQTT] Connected to broker")
            client.subscribe(MQTT_SUB_RESP)
            client.subscribe(MQTT_SUB_STAT)
            self._connected = True
            self.connectionChanged.emit(True)
        else:
            print(f"[MQTT] Connection failed, rc={rc}")
            self._connected = False
            self.connectionChanged.emit(False)

    def _on_disconnect(self, client, userdata, flags, rc, properties=None):
        print("[MQTT] Disconnected")
        self._connected = False
        self.connectionChanged.emit(False)

    def _on_message(self, client, userdata, msg):
        try:
            payload = msg.payload.decode("utf-8", errors="replace")
        except Exception:
            payload = "<decode error>"

        # Tolerant parsing
        try:
            parsed = json.loads(payload)
        except Exception:
            parsed = None

        if msg.topic == MQTT_SUB_STAT and isinstance(parsed, dict):
            self._handle_status(parsed)
        elif msg.topic == MQTT_SUB_RESP:
            self._handle_response(payload, parsed)

    def _handle_status(self, obj: dict):
        # left / right
        l = obj.get("left")
        r = obj.get("right")
        if isinstance(l, int) and l != self._left:
            self._left = l
            self.leftChanged.emit(l)
        if isinstance(r, int) and r != self._right:
            self._right = r
            self.rightChanged.emit(r)

        # mode
        m = obj.get("mode")
        if isinstance(m, str) and m != self._mode:
            self._mode = m
            self.modeChanged.emit(m)

        # brake_mode
        b = obj.get("brake_mode")
        if isinstance(b, str) and b != self._brake_mode:
            self._brake_mode = b
            self.brakeModeChanged.emit(b)

    def _handle_response(self, raw: str, parsed):
        # Keep each response on a single line so the log never needs scrolling
        if parsed is not None:
            line = json.dumps(parsed, ensure_ascii=False)
        else:
            line = " ".join(raw.split())

        print(f"[MQTT] response: {line}")

        # Newest first, keep only the last N responses
        self._responses.insert(0, line)
        del self._responses[self._max_responses:]
        self.responsesChanged.emit()

    # ------------------------------------------------------------------
    # QML Properties
    # ------------------------------------------------------------------

    @Property(bool, notify=connectionChanged)
    def connected(self):
        return self._connected

    @Property(list, notify=responsesChanged)
    def lastResponses(self):
        return list(self._responses)

    @Property(int, notify=leftChanged)
    def leftPower(self):
        return self._left

    @Property(int, notify=rightChanged)
    def rightPower(self):
        return self._right

    @Property(str, notify=modeChanged)
    def mode(self):
        return self._mode

    @Property(str, notify=brakeModeChanged)
    def brakeMode(self):
        return self._brake_mode

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
            print(f"[TX] Unknown brake mode: {mode}")
            return
        print(f"[TX] {cmd}")
        self._enqueue(cmd)

    @Slot()
    def clear_response(self):
        self._responses.clear()
        self.responsesChanged.emit()


if __name__ == "__main__":
    app = QGuiApplication(sys.argv)
    engine = QQmlApplicationEngine()

    backend = Backend()
    engine.rootContext().setContextProperty("backend", backend)

    engine.load("RobotApp/Main.qml")

    if not engine.rootObjects():
        sys.exit(-1)

    app.backend = backend
    exit_code = app.exec()
    backend.stop()
    sys.exit(exit_code)