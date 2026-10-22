"""Real inference smoke test with official OpenCV public sample images, not user photos."""
from pathlib import Path
import sys
from urllib.request import urlopen
import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "WebAPI_TongNhatBaoAn" / "face_worker"))
from worker import Engine, decode_image


def run():
    engine = Engine(ROOT / "WebAPI_TongNhatBaoAn" / "face_worker" / "models")
    checks = 0

    def check(value, label):
        nonlocal checks
        if not value:
            raise AssertionError(label)
        checks += 1
        print("PASS", label)

    def rejected(data):
        try:
            engine.extract(data)
        except ValueError:
            return True
        return False

    def jpeg(image):
        return cv2.imencode(".jpg", image)[1].tobytes()

    def sample(name):
        with urlopen("https://raw.githubusercontent.com/opencv/opencv/master/samples/data/" + name, timeout=60) as response:
            return response.read()

    lena = sample("lena.jpg")
    vector = np.array(engine.extract(lena))
    check(len(vector) == 128 and abs(np.linalg.norm(vector) - 1) < 0.001, "Real SFace 128-dimensional normalized template")
    again = np.array(engine.extract(lena))
    check(float(vector @ again) > 0.99, "Same person matches")
    image = decode_image(lena)
    flipped = np.array(engine.extract(jpeg(cv2.flip(image, 1))))
    check(float(vector @ flipped) >= 0.45, "Mirrored camera image matches")
    check(rejected(jpeg(np.full((512, 512, 3), 100, np.uint8))), "No face rejected")
    check(rejected(jpeg(np.hstack([image, image]))), "Multiple faces rejected")
    check(rejected(b"invalid"), "Invalid image rejected")
    check(rejected(b"x" * (3 * 1024 * 1024 + 1)), "Oversized image rejected")

    # Crop around the detected face in a second official sample, without assuming its location.
    messi = cv2.imdecode(np.frombuffer(sample("messi5.jpg"), np.uint8), cv2.IMREAD_COLOR)
    engine.detector.setInputSize((messi.shape[1], messi.shape[0]))
    _, faces = engine.detector.detect(messi)
    if faces is None or len(faces) != 1:
        raise AssertionError("Second official sample must contain one detected face")
    x, y, w, h = faces[0][:4].astype(int)
    crop = messi[max(0, y - h):min(messi.shape[0], y + 2*h), max(0, x - w):min(messi.shape[1], x + 2*w)]
    crop = cv2.resize(crop, (600, 600))
    check(rejected(jpeg(crop)), "Low-resolution enlarged face rejected as blurry")
    # Exercise the real recognizer independently of the intentionally strict
    # quality gate: this second source is too small for production enrollment.
    aligned = engine.recognizer.alignCrop(messi, faces[0])
    other = engine.recognizer.feature(aligned).flatten().astype(float)
    other /= np.linalg.norm(other)
    check(float(vector @ other) < 0.45, "Different person's real SFace features do not match")
    print(checks, "checks passed")


if __name__ == "__main__":
    run()
