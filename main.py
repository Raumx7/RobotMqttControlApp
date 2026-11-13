import os
import sys
import json
import math
import threading
import paho.mqtt.client as mqtt
import PySide6

# --- OS compatibility (Windows) ---
# Must run BEFORE importing any PySide6 submodule so the Qt DLLs can be found.
pyside_dir = os.path.dirname(PySide6.__file__)
if hasattr(os, "add_dll_directory"):
    # Register the PySide6 root and the native Qt folders
    os.add_dll_directory(pyside_dir)
    for folder in ["Qt/bin", "Qt/plugins", "qml"]:
        path = os.path.join(pyside_dir, folder)
        if os.path.exists(path):
            os.add_dll_directory(path)

from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtCore import QObject, Slot, Signal, Property

# --- MQTT Configuration ---
MQTT_PORT     = 1883
MQTT_SUB_RESP = "robot/response"
MQTT_SUB_STAT = "robot/status"
MQTT_SUB_TELE = "robot/telemetry"
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
    
    # NUEVAS SEÑALES PARA LÁSER
    frontChanged = Signal(float)
    backChanged = Signal(float)

    # Environmental telemetry (from robot/telemetry topic).
    telemetryChanged = Signal()
    brokerIpChanged  = Signal(str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._connected = False
        self._broker_ip = "localhost"

        # Last robot responses, newest first (one compact line each)
        self._responses     = []
        self._max_responses = 10

        # Internal status
        self._left       = 0
        self._right      = 0
        self._mode       = "manual"
        self._brake_mode = "coast"
        
        # NUEVAS VARIABLES PARA LÁSER
        self._front_distance = 0.0
        self._back_distance = 0.0

        # Internal telemetry
        self._temperature   = 0.0
        self._humidity      = 0.0
        self._eco2          = 400
        self._tvoc          = 0
        self._sensor_id     = ""
        self._has_telemetry = False

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
                    print(f"[MQTT] Connecting to {self._broker_ip}:{MQTT_PORT}...")
                    self._client.connect(self._broker_ip, MQTT_PORT, keepalive=30)
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
            client.subscribe(MQTT_SUB_TELE)
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

        try:
            parsed = json.loads(payload)
        except Exception:
            parsed = None

        if msg.topic == MQTT_SUB_STAT and isinstance(parsed, dict):
            self._handle_status(parsed)
        elif msg.topic == MQTT_SUB_RESP:
            self._handle_response(payload, parsed)
        elif msg.topic == MQTT_SUB_TELE and isinstance(parsed, dict):
            self._handle_telemetry(parsed)

    @staticmethod
    def _is_number(value) -> bool:
        return (isinstance(value, (int, float))
                and not isinstance(value, bool)
                and math.isfinite(value))

    def _handle_telemetry(self, obj: dict):
        updated = False
        
        temp = obj.get("temp")
        hum  = obj.get("hum")
        eco2 = obj.get("eco2")
        tvoc = obj.get("tvoc")

        # Parsear AHT21
        if self._is_number(temp) and self._is_number(hum):
            if str(obj.get("temp_unit", "C")).upper() == "F":
                temp = (temp - 32.0) * 5.0 / 9.0
            self._temperature = float(temp)
            self._humidity    = float(hum)
            updated = True

        # Parsear ENS160+
        if self._is_number(eco2) and self._is_number(tvoc):
            self._eco2 = int(eco2)
            self._tvoc = int(tvoc)
            updated = True

        sensor_id = obj.get("sensor_id")
        if isinstance(sensor_id, str):
            self._sensor_id = sensor_id

        if updated:
            self._has_telemetry = True
            self.telemetryChanged.emit()

    def _handle_status(self, obj: dict):
        l = obj.get("left")
        r = obj.get("right")
        if isinstance(l, int) and l != self._left:
            self._left = l
            self.leftChanged.emit(l)
        if isinstance(r, int) and r != self._right:
            self._right = r
            self.rightChanged.emit(r)

        # NUEVO: Extraer valores "front" y "back" del JSON del láser
        f = obj.get("front")
        if isinstance(f, (int, float)) and f != self._front_distance:
            self._front_distance = float(f)
            self.frontChanged.emit(self._front_distance)
            
        b = obj.get("back")
        if isinstance(b, (int, float)) and b != self._back_distance:
            self._back_distance = float(b)
            self.backChanged.emit(self._back_distance)

        m = obj.get("mode")
        if isinstance(m, str) and m != self._mode:
            self._mode = m
            self.modeChanged.emit(m)

        b_mode = obj.get("brake_mode")
        if isinstance(b_mode, str) and b_mode != self._brake_mode:
            self._brake_mode = b_mode
            self.brakeModeChanged.emit(b_mode)

    def _handle_response(self, raw: str, parsed):
        if parsed is not None:
            line = json.dumps(parsed, ensure_ascii=False)
        else:
            line = " ".join(raw.split())

        print(f"[MQTT] response: {line}")
        self._responses.insert(0, line)
        del self._responses[self._max_responses:]
        self.responsesChanged.emit()

    # ------------------------------------------------------------------
    # QML Properties
    # ------------------------------------------------------------------

    @Property(bool, notify=connectionChanged)
    def connected(self):
        return self._connected

    @Property(str, notify=brokerIpChanged)
    def brokerIp(self):
        return self._broker_ip

    @Property(list, notify=responsesChanged)
    def lastResponses(self):
        return list(self._responses)

    @Property(int, notify=leftChanged)
    def leftPower(self):
        return self._left

    @Property(int, notify=rightChanged)
    def rightPower(self):
        return self._right

    # NUEVO: Propiedades QML para el láser
    @Property(float, notify=frontChanged)
    def frontDistance(self):
        return self._front_distance

    @Property(float, notify=backChanged)
    def backDistance(self):
        return self._back_distance

    @Property(str, notify=modeChanged)
    def mode(self):
        return self._mode

    @Property(str, notify=brakeModeChanged)
    def brakeMode(self):
        return self._brake_mode

    @Property(float, notify=telemetryChanged)
    def temperature(self):
        return self._temperature

    @Property(float, notify=telemetryChanged)
    def humidity(self):
        return self._humidity

    @Property(int, notify=telemetryChanged)
    def eco2(self):
        return self._eco2

    @Property(int, notify=telemetryChanged)
    def tvoc(self):
        return self._tvoc

    @Property(str, notify=telemetryChanged)
    def sensorId(self):
        return self._sensor_id

    @Property(bool, notify=telemetryChanged)
    def hasTelemetry(self):
        return self._has_telemetry

    # ------------------------------------------------------------------
    # Slots
    # ------------------------------------------------------------------

    @Slot(str)
    def set_broker_ip(self, ip: str):
        ip = ip.strip()
        if ip and ip != self._broker_ip:
            print(f"[MQTT] Changing broker IP to {ip}")
            self._broker_ip = ip
            self.brokerIpChanged.emit(ip)
            if self._client.is_connected():
                self._client.disconnect()

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