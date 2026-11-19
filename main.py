import os
import sys
import json
import math
import threading
import requests
import numpy as np
import cv2
import paho.mqtt.client as mqtt
import PySide6

# --- OS compatibility (Windows) ---
# Must run BEFORE importing any PySide6 submodule so the Qt DLLs can be found.
pyside_dir = os.path.dirname(PySide6.__file__)
if hasattr(os, "add_dll_directory"):
    os.add_dll_directory(pyside_dir)
    for folder in ["Qt/bin", "Qt/plugins", "qml"]:
        path = os.path.join(pyside_dir, folder)
        if os.path.exists(path):
            os.add_dll_directory(path)

from PySide6.QtGui import QGuiApplication, QImage
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickImageProvider
from PySide6.QtCore import QObject, Slot, Signal, Property

# --- MQTT Configuration ---
MQTT_PORT     = 1883
MQTT_SUB_RESP = "robot/response"
MQTT_SUB_STAT = "robot/status"
MQTT_SUB_TELE = "robot/telemetry"
MQTT_PUB      = "robot/command"
CLIENT_ID     = "qt-robot-panel"

# --- Camera Configuration (coincide con ESP32-CAM 160x120 RGB565) ---
DEFAULT_CAM_URL = "http://10.38.49.44/stream"
CAM_WIDTH       = 160
CAM_HEIGHT      = 120
CAM_FRAME_BYTES = CAM_WIDTH * CAM_HEIGHT * 2
MIN_COLOR_AREA  = 150


class CameraImageProvider(QQuickImageProvider):
    """Provee los frames procesados por OpenCV directamente a QML."""
    def __init__(self):
        super().__init__(QQuickImageProvider.Image)
        self._lock = threading.Lock()
        self._image = QImage(CAM_WIDTH, CAM_HEIGHT, QImage.Format_RGB888)
        self._image.fill(0)

    def update_frame(self, rgb_array: np.ndarray):
        h, w, ch = rgb_array.shape
        bytes_per_line = ch * w
        qimg = QImage(rgb_array.data, w, h, bytes_per_line, QImage.Format_RGB888).copy()
        with self._lock:
            self._image = qimg

    def requestImage(self, id, size, requestedSize):
        with self._lock:
            img = self._image.copy()
        if size is not None:
            size.setWidth(img.width())
            size.setHeight(img.height())
        return img


class Backend(QObject):
    connectionChanged = Signal(bool)
    responsesChanged  = Signal()

    # Robot status signals (from robot/status topic)
    leftChanged      = Signal(int)
    rightChanged     = Signal(int)
    modeChanged      = Signal(str)
    brakeModeChanged = Signal(str)
    frontChanged     = Signal(float)
    backChanged      = Signal(float)

    # Environmental telemetry (from robot/telemetry topic)
    telemetryChanged = Signal()
    brokerIpChanged  = Signal(str)

    # Camera & Color detection signals
    cameraFrameReady       = Signal()
    cameraConnectedChanged = Signal(bool)
    cameraUrlChanged       = Signal(str)
    colorDetectionChanged  = Signal(bool)
    detectionResultChanged = Signal()

    def __init__(self, image_provider: CameraImageProvider, parent=None):
        super().__init__(parent)
        self._image_provider = image_provider
        self._connected = False
        self._broker_ip = "localhost"

        # Last robot responses, newest first
        self._responses     = []
        self._max_responses = 10

        # Internal status
        self._left           = 0
        self._right          = 0
        self._mode           = "manual"
        self._brake_mode     = "coast"
        self._front_distance = 0.0
        self._back_distance  = 0.0

        # Internal telemetry
        self._temperature   = 0.0
        self._humidity      = 0.0
        self._eco2          = 400
        self._tvoc          = 0
        self._sensor_id     = ""
        self._has_telemetry = False

        # Camera state
        self._camera_url              = DEFAULT_CAM_URL
        self._camera_active           = False
        self._camera_connected        = False
        self._color_detection_enabled = True
        self._color_detected          = False
        self._detected_area           = 0
        self._hsv_lower               = np.array([100, 100, 50], dtype=np.uint8)
        self._hsv_upper               = np.array([130, 255, 255], dtype=np.uint8)
        self._cam_restart_event       = threading.Event()

        # Synchronization
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

        self._camera_thread = threading.Thread(
            target=self._camera_worker, name="camera_worker", daemon=True)
        self._camera_thread.start()

    # ------------------------------------------------------------------
    # Camera Stream & OpenCV Color Processing
    # ------------------------------------------------------------------

    @staticmethod
    def _read_exact(stream, count: int):
        data = bytearray()
        while len(data) < count:
            chunk = stream.read(count - len(data))
            if not chunk:
                return None
            data.extend(chunk)
        return bytes(data)

    @staticmethod
    def _rgb565_to_bgr(data: bytes) -> np.ndarray:
        image_data = np.frombuffer(data, dtype=np.uint8).reshape((CAM_HEIGHT, CAM_WIDTH, 2))
        rgb565 = (
            (image_data[:, :, 0].astype(np.uint16) << 8) |
            image_data[:, :, 1].astype(np.uint16)
        )
        r = ((rgb565 >> 11) & 0x1F) * 255 // 31
        g = ((rgb565 >> 5) & 0x3F) * 255 // 63
        b = (rgb565 & 0x1F) * 255 // 31
        return np.dstack((b, g, r)).astype(np.uint8)

    def _set_cam_connected(self, state: bool):
        if self._camera_connected != state:
            self._camera_connected = state
            self.cameraConnectedChanged.emit(state)

    def _camera_worker(self):
        kernel = np.ones((3, 3), np.uint8)

        while not self._stop_event.is_set():
            if not self._camera_active:
                self._set_cam_connected(False)
                self._stop_event.wait(0.2)
                continue

            self._cam_restart_event.clear()
            url = self._camera_url
            response = None

            try:
                print(f"[CAM] Connecting to {url}...")
                response = requests.get(url, stream=True, timeout=(3, 10))
                response.raise_for_status()
                self._set_cam_connected(True)
                print("[CAM] Stream connected")

                stream = response.raw

                while (not self._stop_event.is_set()
                       and self._camera_active
                       and not self._cam_restart_event.is_set()):

                    line = stream.readline()
                    while line and not line.startswith(b"--frame"):
                        line = stream.readline()
                    if not line:
                        raise ConnectionError("Stream closed")

                    content_length = None
                    while True:
                        header = stream.readline()
                        if not header:
                            raise ConnectionError("Header interrupted")
                        if header in (b"\r\n", b"\n"):
                            break
                        if header.lower().startswith(b"content-length:"):
                            content_length = int(header.split(b":", 1)[1].strip())

                    if content_length is None:
                        continue

                    data = self._read_exact(stream, content_length)
                    if data is None:
                        raise ConnectionError("Incomplete frame")
                    stream.read(2)

                    if len(data) != CAM_FRAME_BYTES:
                        continue

                    frame = self._rgb565_to_bgr(data)

                    # Procesamiento de color solo si está activado
                    detected = False
                    area_val = 0

                    if self._color_detection_enabled:
                        hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
                        mask = cv2.inRange(hsv, self._hsv_lower, self._hsv_upper)
                        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)

                        contours, _ = cv2.findContours(
                            mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
                        )
                        if contours:
                            largest = max(contours, key=cv2.contourArea)
                            area = cv2.contourArea(largest)
                            if area > MIN_COLOR_AREA:
                                detected = True
                                area_val = int(area)
                                x, y, w, h = cv2.boundingRect(largest)
                                cv2.drawContours(frame, [largest], -1, (0, 255, 0), 2)
                                cv2.rectangle(frame, (x, y), (x + w, y + h), (0, 0, 255), 2)
                                cv2.putText(
                                    frame,
                                    f"Blue: {area_val}",
                                    (x, max(y - 4, 10)),
                                    cv2.FONT_HERSHEY_SIMPLEX,
                                    0.38,
                                    (0, 255, 255),
                                    1
                                )

                    if detected != self._color_detected or abs(area_val - self._detected_area) > 15:
                        self._color_detected = detected
                        self._detected_area = area_val
                        self.detectionResultChanged.emit()

                    rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                    self._image_provider.update_frame(rgb_frame)
                    self.cameraFrameReady.emit()

            except Exception as e:
                print(f"[CAM] Stream error: {e}")
                self._set_cam_connected(False)
                if self._camera_active and not self._stop_event.is_set():
                    self._stop_event.wait(2.0)
            finally:
                if response is not None:
                    try:
                        response.close()
                    except Exception:
                        pass

    # ------------------------------------------------------------------
    # MQTT Connection & Workers
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
        self._camera_active = False
        self._stop_event.set()
        try:
            self._client.loop_stop()
            self._client.disconnect()
        except Exception:
            pass

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

        if self._is_number(temp) and self._is_number(hum):
            if str(obj.get("temp_unit", "C")).upper() == "F":
                temp = (temp - 32.0) * 5.0 / 9.0
            self._temperature = float(temp)
            self._humidity    = float(hum)
            updated = True

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
    def connected(self): return self._connected

    @Property(str, notify=brokerIpChanged)
    def brokerIp(self): return self._broker_ip

    @Property(list, notify=responsesChanged)
    def lastResponses(self): return list(self._responses)

    @Property(int, notify=leftChanged)
    def leftPower(self): return self._left

    @Property(int, notify=rightChanged)
    def rightPower(self): return self._right

    @Property(float, notify=frontChanged)
    def frontDistance(self): return self._front_distance

    @Property(float, notify=backChanged)
    def backDistance(self): return self._back_distance

    @Property(str, notify=modeChanged)
    def mode(self): return self._mode

    @Property(str, notify=brakeModeChanged)
    def brakeMode(self): return self._brake_mode

    @Property(float, notify=telemetryChanged)
    def temperature(self): return self._temperature

    @Property(float, notify=telemetryChanged)
    def humidity(self): return self._humidity

    @Property(int, notify=telemetryChanged)
    def eco2(self): return self._eco2

    @Property(int, notify=telemetryChanged)
    def tvoc(self): return self._tvoc

    @Property(str, notify=telemetryChanged)
    def sensorId(self): return self._sensor_id

    @Property(bool, notify=telemetryChanged)
    def hasTelemetry(self): return self._has_telemetry

    @Property(bool, notify=cameraConnectedChanged)
    def cameraConnected(self): return self._camera_connected

    @Property(str, notify=cameraUrlChanged)
    def cameraUrl(self): return self._camera_url

    @Property(bool, notify=colorDetectionChanged)
    def colorDetectionEnabled(self): return self._color_detection_enabled

    @Property(bool, notify=detectionResultChanged)
    def colorDetected(self): return self._color_detected

    @Property(int, notify=detectionResultChanged)
    def detectedArea(self): return self._detected_area

    # ------------------------------------------------------------------
    # Slots
    # ------------------------------------------------------------------

    @Slot(bool)
    def set_camera_active(self, active: bool):
        self._camera_active = active
        if not active:
            self._color_detected = False
            self._detected_area = 0
            self.detectionResultChanged.emit()

    @Slot(str)
    def set_camera_url(self, url: str):
        url = url.strip()
        if url and url != self._camera_url:
            self._camera_url = url
            self.cameraUrlChanged.emit(url)
            self._cam_restart_event.set()

    @Slot()
    def toggle_color_detection(self):
        self._color_detection_enabled = not self._color_detection_enabled
        if not self._color_detection_enabled:
            self._color_detected = False
            self._detected_area = 0
            self.detectionResultChanged.emit()
        self.colorDetectionChanged.emit(self._color_detection_enabled)

    @Slot(int, int, int, int)
    def set_hsv_bounds(self, h_min: int, h_max: int, s_min: int, v_min: int):
        self._hsv_lower = np.array([h_min, s_min, v_min], dtype=np.uint8)
        self._hsv_upper = np.array([h_max, 255, 255], dtype=np.uint8)

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

    cam_provider = CameraImageProvider()
    engine.addImageProvider("camera", cam_provider)

    backend = Backend(cam_provider)
    engine.rootContext().setContextProperty("backend", backend)

    engine.load("RobotApp/Main.qml")

    if not engine.rootObjects():
        sys.exit(-1)

    app.backend = backend
    exit_code = app.exec()
    backend.stop()
    sys.exit(exit_code)