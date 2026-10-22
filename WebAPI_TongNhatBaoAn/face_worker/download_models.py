"""Download public pretrained models and licenses from official OpenCV Zoo."""
from pathlib import Path
from urllib.request import urlopen
import hashlib

ROOT = "https://media.githubusercontent.com/media/opencv/opencv_zoo/main/models/"
SHA256 = {
    "yunet.onnx": "8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4",
    "sface.onnx": "0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79",
}
FILES = {
    "yunet.onnx": "face_detection_yunet/face_detection_yunet_2023mar.onnx",
    "sface.onnx": "face_recognition_sface/face_recognition_sface_2021dec.onnx",
}


def download():
    directory = Path(__file__).parent / "models"
    directory.mkdir(exist_ok=True)
    for filename, source in FILES.items():
        with urlopen(ROOT + source, timeout=120) as response:
            data = response.read()
        if len(data) < 100_000 or data.startswith(b"version https://git-lfs"):
            raise RuntimeError("Model download is incomplete: " + filename)
        if hashlib.sha256(data).hexdigest() != SHA256[filename]:
            raise RuntimeError("Model checksum mismatch: " + filename)
        (directory / filename).write_bytes(data)
        print(filename, hashlib.sha256(data).hexdigest())
    for name in ("face_detection_yunet", "face_recognition_sface"):
        url = f"https://raw.githubusercontent.com/opencv/opencv_zoo/main/models/{name}/LICENSE"
        with urlopen(url, timeout=60) as response:
            (directory / (name + ".LICENSE")).write_bytes(response.read())


if __name__ == "__main__":
    download()
