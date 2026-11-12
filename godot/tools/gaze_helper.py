"""Webcam -> Godot gaze bridge (starter, UNTESTED against real hardware).

Streams JSON over UDP to the game's GazeProvider (default 127.0.0.1:5005).
Frames are processed on-device and never saved or sent anywhere.

Setup:
    pip install mediapipe opencv-python
    # download face_landmarker.task from the MediaPipe model page, put it next to this file
    python tools/gaze_helper.py [--cam 0] [--port 5005] [--gain 2.2]

In the game: F9 = hands-free on, F10 = switch to webcam backend, look at the
screen centre and press F8 to recentre.
"""
import argparse
import json
import socket
import time

import cv2
import mediapipe as mp
from mediapipe.tasks import python as mpp
from mediapipe.tasks.python import vision


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cam", type=int, default=0)
    ap.add_argument("--port", type=int, default=5005)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--model", default="face_landmarker.task")
    ap.add_argument("--gain", type=float, default=2.2, help="blendshape gaze -> screen gain")
    ap.add_argument("--preview", action="store_true")
    args = ap.parse_args()

    opts = vision.FaceLandmarkerOptions(
        base_options=mpp.BaseOptions(model_asset_path=args.model),
        running_mode=vision.RunningMode.VIDEO,
        output_face_blendshapes=True,
        num_faces=1,
    )
    landmarker = vision.FaceLandmarker.create_from_options(opts)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    cap = cv2.VideoCapture(args.cam)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    t0 = time.time()

    while cap.isOpened():
        ok, frame = cap.read()
        if not ok:
            break
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        res = landmarker.detect_for_video(img, int((time.time() - t0) * 1000))
        if res.face_blendshapes:
            bs = {c.category_name: c.score for c in res.face_blendshapes[0]}
            # Horizontal: + = user looks to THEIR right (screen right).
            h = ((bs["eyeLookInLeft"] + bs["eyeLookOutRight"]) - (bs["eyeLookOutLeft"] + bs["eyeLookInRight"])) * 0.5
            v = ((bs["eyeLookUpLeft"] + bs["eyeLookUpRight"]) - (bs["eyeLookDownLeft"] + bs["eyeLookDownRight"])) * 0.5
            nose = res.face_landmarks[0][1]
            head_x = (0.5 - nose.x) * 2.0  # mirrored camera: moving right -> +
            head_nx = 1.0 - nose.x          # lean sideways = strafe in game
            pkt = {
                "x": 0.5 + h * args.gain + head_x * 0.15,
                "y": 0.5 - v * args.gain,
                "conf": 1.0,
                "blink_l": bs["eyeBlinkLeft"],
                "blink_r": bs["eyeBlinkRight"],
                "mouth": bs["jawOpen"],
                "brows": bs["browInnerUp"],
                "yaw": head_x,
                "nx": head_nx,
                "fw": abs(res.face_landmarks[0][454].x - res.face_landmarks[0][234].x),
            }
        else:
            pkt = {"conf": 0.0}
        sock.sendto(json.dumps(pkt).encode(), (args.host, args.port))
        if args.preview:
            cv2.imshow("gaze_helper (q to quit)", frame)
            if cv2.waitKey(1) & 0xFF == ord("q"):
                break
    cap.release()


if __name__ == "__main__":
    main()
