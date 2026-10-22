"""Private, CPU-only face embedding worker. Raw images exist in memory only.

Recognition is not presentation-attack detection: printed photos/replayed images
may pass. This demo must not be described as spoof-proof or certified liveness.
"""
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import json
import cv2
import numpy as np

MAX_BYTES = 3 * 1024 * 1024


def decode_image(body):
    if not body or len(body) > MAX_BYTES:
        raise ValueError("Ảnh thiếu hoặc quá lớn (tối đa 3 MB).")
    # Camera input is JPEG. Inspect dimensions before decompression to bound memory.
    if body[:2] != b"\xff\xd8":
        raise ValueError("Chỉ nhận ảnh JPEG chụp từ camera.")
    width, height = jpeg_size(body)
    if width < 160 or height < 160 or width * height > 12_000_000:
        raise ValueError("Kích thước ảnh không phù hợp. Chụp lại trong ứng dụng.")
    image = cv2.imdecode(np.frombuffer(body, np.uint8), cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError("Không đọc được ảnh. Hãy chụp lại.")
    scale = min(1.0, 1024 / max(image.shape[:2]))
    if scale < 1:
        image = cv2.resize(image, None, fx=scale, fy=scale)
    return image


def jpeg_size(data):
    i = 2
    sof = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}
    while i + 4 < len(data):
        if data[i] != 0xFF:
            raise ValueError("Ảnh JPEG không hợp lệ.")
        while i < len(data) and data[i] == 0xFF:
            i += 1
        marker = data[i]
        i += 1
        if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7:
            continue
        if i + 2 > len(data):
            break
        size = int.from_bytes(data[i:i + 2], "big")
        if size < 2 or i + size > len(data):
            break
        if marker in sof and size >= 7:
            return int.from_bytes(data[i + 5:i + 7], "big"), int.from_bytes(data[i + 3:i + 5], "big")
        i += size
    raise ValueError("Không tìm thấy kích thước ảnh JPEG.")


class Engine:
    def __init__(self, directory):
        cv2.setNumThreads(1)
        self.detector = cv2.FaceDetectorYN.create(str(directory / "yunet.onnx"), "", (320, 320), 0.9, 0.3, 5000)
        self.recognizer = cv2.FaceRecognizerSF.create(str(directory / "sface.onnx"), "")

    def extract(self, body):
        image = decode_image(body)
        self.detector.setInputSize((image.shape[1], image.shape[0]))
        _, faces = self.detector.detect(image)
        if faces is None or len(faces) != 1:
            raise ValueError("Ảnh cần có đúng một khuôn mặt, rõ và không bị che.")
        face = faces[0]
        x, y, w, h = face[:4].astype(int)
        if min(w, h) < 90 or x < 0 or y < 0 or x + w > image.shape[1] or y + h > image.shape[0]:
            raise ValueError("Đưa toàn bộ khuôn mặt gần camera hơn và nhìn thẳng.")
        crop = image[y:y + h, x:x + w]
        gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
        if not 40 <= float(gray.mean()) <= 220:
            raise ValueError("Ánh sáng quá tối hoặc quá sáng. Đổi vị trí rồi chụp lại.")
        if cv2.Laplacian(gray, cv2.CV_64F).var() < 35:
            raise ValueError("Ảnh khuôn mặt bị mờ. Giữ máy ổn định rồi chụp lại.")
        aligned = self.recognizer.alignCrop(image, face)
        vector = self.recognizer.feature(aligned).flatten().astype(float)
        norm = float(np.linalg.norm(vector))
        if len(vector) != 128 or not np.isfinite(vector).all() or norm <= 0:
            raise RuntimeError("Invalid model output")
        return (vector / norm).tolist()


def serve(engine):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass  # Never log images or embeddings.

        def do_POST(self):
            if self.path != "/embedding":
                self.send_error(404)
                return
            self.connection.settimeout(15)
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if length <= 0 or length > MAX_BYTES:
                    raise ValueError("Ảnh thiếu hoặc lớn hơn 3 MB.")
                body = self.rfile.read(length)
                if len(body) != length:
                    raise ValueError("Ảnh gửi lên chưa đầy đủ.")
                payload, status = {"vector": engine.extract(body)}, 200
            except ValueError as exc:
                payload, status = {"error": str(exc)}, 400
            except Exception:
                payload, status = {"error": "Face engine unavailable"}, 503
            encoded = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)

    HTTPServer(("127.0.0.1", 5051), Handler).serve_forever()


if __name__ == "__main__":
    serve(Engine(Path(__file__).parent / "models"))
