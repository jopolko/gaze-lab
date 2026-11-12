#!/usr/bin/env python3
"""
webcam_server.py - companion for "Ocular Trance" (desktop Godot builds).

Reads your webcam with OpenCV, finds your eyes with MediaPipe Face Mesh, and streams one JSON packet per frame over
UDP to 127.0.0.1:4242 for TrackerBridge.gd:

    {"gaze_pos": [x, y], "ear": 0.27, "is_blinking": false, "head_pitch_yaw": [pitch, yaw]}

    gaze_pos        0..1 across the screen (0.5, 0.5 = looking straight ahead). Rough: see the notes below.
    ear             Eye Aspect Ratio (about 0.25-0.35 open, below 0.18 closed).
    is_blinking     True while the eyes are closed. Godot treats the moment they re-open as the "release".
    head_pitch_yaw  radians, from the nose position relative to the eyes (approximate).

Run:
    pip install opencv-python mediapipe
    python tools/trance/webcam_server.py            # then start the Godot project
    python tools/trance/webcam_server.py --show     # preview window with the tracking drawn (q to quit)
    python tools/trance/webcam_server.py --camera 1 --flip --gain 3.5

Notes
- Webcam gaze is coarse: the iris moves only a few pixels across the whole screen. Sit about an arm's length away,
  light your face evenly, and press C in this window (or restart) after you settle to re-centre.
- Everything stays on your computer; frames are never saved or sent anywhere except these small UDP packets to localhost.
"""
import argparse
import json
import socket
import sys
import time

try:
    import cv2
    import mediapipe as mp
except ImportError as exc:  # pragma: no cover
    sys.exit("Missing dependency (%s). Install with:  pip install opencv-python mediapipe" % exc)

# Face Mesh landmark indices (refine_landmarks=True adds the iris points 468-477)
LEFT_EYE = [33, 160, 158, 133, 153, 144]       # outer, upper1, upper2, inner, lower2, lower1
RIGHT_EYE = [362, 385, 387, 263, 373, 380]
LEFT_IRIS, RIGHT_IRIS = 468, 473
LEFT_LIDS = (159, 145)                          # upper, lower lid centre
RIGHT_LIDS = (386, 374)
NOSE, LEFT_EYE_OUTER, RIGHT_EYE_OUTER = 1, 33, 263


def dist(a, b):
    return ((a.x - b.x) ** 2 + (a.y - b.y) ** 2) ** 0.5


def eye_aspect_ratio(lm, idx):
    p1, p2, p3, p4, p5, p6 = (lm[i] for i in idx)
    return (dist(p2, p6) + dist(p3, p5)) / (2.0 * dist(p1, p4) + 1e-9)


def iris_ratio(lm, outer, inner, iris, upper, lower):
    """Where the iris sits across (x) and down (y) its eye, 0..1."""
    ex = (lm[iris].x - lm[outer].x) / (lm[inner].x - lm[outer].x + 1e-9)
    ey = (lm[iris].y - lm[upper].y) / (lm[lower].y - lm[upper].y + 1e-9)
    return ex, ey


def main():
    ap = argparse.ArgumentParser(description="Webcam eye tracker -> UDP JSON for Godot")
    ap.add_argument("--camera", type=int, default=0, help="camera index (default 0)")
    ap.add_argument("--port", type=int, default=4242)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--flip", action="store_true", help="mirror horizontally (use if left/right feels reversed)")
    ap.add_argument("--gain", type=float, default=3.0, help="how far the iris must move to reach the screen edge (higher = more sensitive)")
    ap.add_argument("--blink-ratio", type=float, default=0.7, help="blink when EAR drops below this fraction of your open-eye level")
    ap.add_argument("--smooth", type=float, default=0.35, help="gaze smoothing 0..1 (higher = snappier, lower = steadier)")
    ap.add_argument("--show", action="store_true", help="show a preview window")
    args = ap.parse_args()

    cap = cv2.VideoCapture(args.camera)
    if not cap.isOpened():
        sys.exit("Could not open camera %d" % args.camera)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    dest = (args.host, args.port)

    face = mp.solutions.face_mesh.FaceMesh(max_num_faces=1, refine_landmarks=True,
                                           min_detection_confidence=0.5, min_tracking_confidence=0.5)
    centre = None            # iris ratio when looking straight ahead
    gx, gy = 0.5, 0.5
    open_ear = 0.30          # running estimate of your eyes-open EAR
    head0 = None
    print("Streaming to udp://%s:%d  (Ctrl+C to stop%s)" % (args.host, args.port, ", q in the preview to quit" if args.show else ""))
    print("Look at the middle of the screen for a moment; the first second sets your centre. Press c in the preview to re-centre.")
    t_start = time.time()
    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                time.sleep(0.01)
                continue
            if args.flip:
                frame = cv2.flip(frame, 1)
            res = face.process(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
            if not res.multi_face_landmarks:
                if args.show:
                    cv2.imshow("webcam_server", frame)
                    if cv2.waitKey(1) & 0xFF == ord("q"):
                        break
                continue
            lm = res.multi_face_landmarks[0].landmark

            ear = (eye_aspect_ratio(lm, LEFT_EYE) + eye_aspect_ratio(lm, RIGHT_EYE)) / 2.0
            if ear > open_ear:
                open_ear += 0.2 * (ear - open_ear)           # follow your open level upward quickly
            else:
                open_ear += 0.002 * (ear - open_ear)         # and downward very slowly (so a blink does not drag it)
            blinking = ear < open_ear * args.blink_ratio

            if not blinking:                                 # the iris reading is garbage while the lids close
                lx, ly = iris_ratio(lm, 33, 133, LEFT_IRIS, *LEFT_LIDS)
                rx, ry = iris_ratio(lm, 362, 263, RIGHT_IRIS, *RIGHT_LIDS)
                ix, iy = (lx + rx) / 2.0, (ly + ry) / 2.0
                if centre is None and time.time() - t_start > 1.0:
                    centre = (ix, iy)
                if centre is not None:
                    tx = 0.5 + (ix - centre[0]) * args.gain
                    ty = 0.5 + (iy - centre[1]) * args.gain * 1.6   # vertical eye travel is smaller: boost it
                    gx += args.smooth * (min(max(tx, 0.0), 1.0) - gx)
                    gy += args.smooth * (min(max(ty, 0.0), 1.0) - gy)

            # head pose, approximate: the nose relative to the middle of the eyes, in face widths
            mid_x = (lm[LEFT_EYE_OUTER].x + lm[RIGHT_EYE_OUTER].x) / 2.0
            mid_y = (lm[LEFT_EYE_OUTER].y + lm[RIGHT_EYE_OUTER].y) / 2.0
            face_w = dist(lm[LEFT_EYE_OUTER], lm[RIGHT_EYE_OUTER]) + 1e-9
            yaw = (lm[NOSE].x - mid_x) / face_w
            pitch = (lm[NOSE].y - mid_y) / face_w
            if head0 is None:
                head0 = (pitch, yaw)
            packet = {
                "gaze_pos": [round(gx, 4), round(gy, 4)],
                "ear": round(ear, 4),
                "is_blinking": bool(blinking),
                "head_pitch_yaw": [round(pitch - head0[0], 4), round(yaw - head0[1], 4)],
            }
            sock.sendto(json.dumps(packet).encode("utf-8"), dest)

            if args.show:
                h, w = frame.shape[:2]
                for i in (LEFT_IRIS, RIGHT_IRIS):
                    cv2.circle(frame, (int(lm[i].x * w), int(lm[i].y * h)), 3, (0, 255, 255), -1)
                cv2.putText(frame, "EAR %.2f %s  gaze %.2f,%.2f" % (ear, "BLINK" if blinking else "", gx, gy), (10, 24),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2)
                cv2.imshow("webcam_server", frame)
                key = cv2.waitKey(1) & 0xFF
                if key == ord("q"):
                    break
                if key == ord("c"):
                    centre = None
                    t_start = time.time()
                    head0 = None
    except KeyboardInterrupt:
        pass
    finally:
        cap.release()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
