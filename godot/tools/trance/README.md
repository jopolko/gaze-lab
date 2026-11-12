# Ocular Trance: how to run it

**In the browser (easiest):** https://joshuaopolko.com/gaze-lab/godot/?level=trance — pick START WITH CAMERA. Nothing to install.
Look at a glowing orb for half a second to start charging, keep looking, then blink to release.
No camera: the mouse is your eyes and SPACE (or right click) is the blink.

**Desktop Godot build with the Python tracker (UDP):**
1. `pip install opencv-python mediapipe`
2. `python tools/trance/webcam_server.py` (add `--show` for a preview, `--flip` if left/right is reversed, `--gain 3.5` for more sensitivity)
3. Run the Godot project (open level 9, or `godot --path . -- --demo` and choose TRANCE). `TrackerBridge` listens on UDP 127.0.0.1:4242.
   It uses the packets while they keep arriving; after 1 s of silence it falls back to the camera (web) or the mouse.

**Comfort:** the camera sway, colour split and audio bend are strong on purpose. INTENSITY (top centre) is always visible:
`-` / `=` change it, `C` or `Esc` sets calm (0), or click the bar. At 0 the game plays the same with no motion effects.
Do not use it if you are prone to motion sickness, vertigo or photosensitive seizures.
