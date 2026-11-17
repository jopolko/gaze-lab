"""Makes the game's music files (ogg) from the source tracks and stems. Run once; the output goes to godot/music_web/ and is copied beside the web build.
    python tools/music_build.py <incoming tracks> <stems folder> [out folder]
Each track is levelled to the same loudness; the ones that loop get a blended seam; each stem is cut to a bar-aligned loop (16 bars at 128 BPM) with a blended seam, so all
nine stay locked together however long they play. Needs ffmpeg (set FFMPEG to its path) and numpy."""
import json
import os
import re
import subprocess
import sys

import numpy as np

FF = os.environ.get("FFMPEG", "ffmpeg")
incoming, stems = sys.argv[1], sys.argv[2]
out = sys.argv[3] if len(sys.argv) > 3 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "music_web")
os.makedirs(out, exist_ok=True)
SR = 44100
BAR = 4.0 * 60.0 / 128.0


def measure(src, target):
    r = subprocess.run([FF, "-hide_banner", "-nostats", "-i", src, "-af", "loudnorm=I=%g:TP=-1.5:LRA=11:print_format=json" % target, "-f", "null", "-"], capture_output=True, text=True)
    j = json.loads(re.search(r"\{[^{}]*\"input_i\"[^{}]*\}", r.stderr, re.S).group(0))
    return "loudnorm=I=%g:TP=-1.5:LRA=11:measured_I=%s:measured_TP=%s:measured_LRA=%s:measured_thresh=%s:offset=%s:linear=true" % (
        target, j["input_i"], j["input_tp"], j["input_lra"], j["input_thresh"], j["target_offset"])


def decode(src, target, ss=None, t=None):
    flt = measure(src, target)
    args = [FF, "-v", "error"]
    if ss is not None:
        args += ["-ss", "%.4f" % ss]
    if t is not None:
        args += ["-t", "%.4f" % t]
    args += ["-i", src, "-af", flt, "-ar", str(SR), "-ac", "2", "-f", "f32le", "-"]
    raw = subprocess.run(args, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2)


def seam(x, c):
    """Blend the last c samples into the first c, so the end runs on into the start: length is cut by c."""
    n = len(x)
    t = np.linspace(0.0, np.pi * 0.5, c)[:, None]
    blend = x[n - c:] * np.cos(t) + x[:c] * np.sin(t)
    return np.concatenate([blend, x[c:n - c]])


def write_ogg(x, path, q=4):
    p = subprocess.Popen([FF, "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "-", "-c:a", "libvorbis", "-q:a", str(q), path], stdin=subprocess.PIPE)
    p.communicate(np.clip(x, -1.0, 1.0).astype(np.float32).tobytes())
    print("  %-26s %5.1f s  %5.0f KB" % (os.path.basename(path), len(x) / SR, os.path.getsize(path) / 1024))


# ---------------------------------------------------------------- tracks (-16 LUFS)
TRACKS = [
    ("mechanichal", "Lemoneight_-_Mechanichal_Meaning_of_a_Peanut.mp3", False),
    ("space_echo", "space_echo.ogg", True),
    ("dnb", "Of Far Different Nature - 1 Minute DnB (CC-BY).wav", True),
    ("exodus", "Electric Exodus v1_0.wav", False),
    ("bouncer", "Of Far Different Nature - Bouncer (CC0).wav", True),
    ("moodless", "Apoxode_-_Moodless_Refrain_(ft._Quiana_Nadine).mp3", False),
]
print("tracks")
for key, f, loop in TRACKS:
    x = decode(os.path.join(incoming, f), -16.0)
    if loop:
        x = seam(x, int(2.0 * SR))
    write_ogg(x, os.path.join(out, key + ".ogg"))

# ---------------------------------------------------------------- stems: one 16-bar loop each, on the bar grid, -26 LUFS so nine together sit near -16
WIN = {"ambience": 136, "pulse": 32, "bass": 264, "drums": 88, "piano": 64, "guitar": 120, "synth": 248, "acid": 264, "fx": 232}
print("stems")
for n, bar in WIN.items():
    x = decode(os.path.join(stems, n + ".flac"), -26.0, ss=bar * BAR, t=17 * BAR)
    x = x[:int(17 * BAR * SR)]
    c = int(BAR * SR)          # a bar of blend: the 17th bar runs into the 1st, the loop is exactly 16 bars
    y = seam(x, c)
    y = y[:int(16 * BAR * SR)]
    write_ogg(y, os.path.join(out, "stem_" + n + ".ogg"), q=3)
print("done ->", os.path.normpath(out))
