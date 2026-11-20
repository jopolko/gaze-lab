# STARGAZE

A phone-browser flight you steer with your eyes (three.js + MediaPipe face landmarks, all on the device).

- **Look** to steer and to gather the lights (rest your gaze on one and its ring closes).
- **Blink** to send a pulse that sweeps in everything near your gaze.
- **Close your eyes** for a second, once the bar is full, to jump to the next world.

## Run

    python serve.py          # http://localhost:8070/   (this machine)
    python serve.py --lan    # https://<this machine's address>:8470/   (phone on the same Wi-Fi; accept the certificate warning once)

Add `?debug` for the camera preview and tracker numbers (tracker rate, calibration fit, gaze, blink levels).
"No camera? Play by touch" (or a mouse; Space = blink, hold Space = eyes closed) runs the same game without tracking.

## How the tracking works (`tracker.js`)

1. MediaPipe FaceLandmarker gives iris and eyelid landmarks, blink scores and head pose for each camera frame.
2. Seven features: iris position inside the eye opening (along the eye's own axis), upper-lid height, head yaw and pitch, face position in the frame.
3. A 10 s "follow the spark" pursuit fits a ridge regression from features to screen position. The fit searches for the eye+camera lag, drops outliers, and rescales a weak axis so it still reaches the screen edges. A poor fit is reported as a weak lock instead of being used silently.
4. In play: a One-Euro filter (heavier when the fit was noisier), gaze held through blinks, blink levels measured against the player's own resting lid level, and a slow drift correction from each light the player gathers.

Everything in the game is sized to what a phone camera can tell apart: steering is continuous, and targets accept a look within roughly a quarter of the screen.
