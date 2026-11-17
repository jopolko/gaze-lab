"""Level-matches the tracks and builds the stem build-up preview.
    python tools/music_prep.py <incoming folder> <stems folder> <output folder>
Needs ffmpeg (set FFMPEG to its path if it is not on the path). Everything is measured, not heard: loudness (LUFS), peaks, where each stem is playing."""
import json
import os
import re
import subprocess
import sys

import numpy as np

FF = os.environ.get("FFMPEG", "ffmpeg")
incoming, stems, out = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out, exist_ok=True)
TARGET = -16.0
BPM = 128.0
BAR = 4.0 * 60.0 / BPM          # 1.875 s


def run(args):
    return subprocess.run([FF, "-hide_banner", "-nostats"] + args, capture_output=True, text=True)


def loudnorm(src, dst, extra_in=None, t_extra=None):
    """Two passes: measure, then correct to TARGET LUFS with a -1.5 dB true-peak ceiling."""
    pre = ["-i", src] + (extra_in or [])
    r = run(pre + ["-af", "loudnorm=I=%g:TP=-1.5:LRA=11:print_format=json" % TARGET, "-f", "null", "-"])
    m = re.search(r"\{[^{}]*\"input_i\"[^{}]*\}", r.stderr, re.S)
    j = json.loads(m.group(0))
    flt = "loudnorm=I=%g:TP=-1.5:LRA=11:measured_I=%s:measured_TP=%s:measured_LRA=%s:measured_thresh=%s:offset=%s:linear=true" % (
        TARGET, j["input_i"], j["input_tp"], j["input_lra"], j["input_thresh"], j["target_offset"])
    run(pre + ["-af", flt, "-ar", "44100", "-codec:a", "libmp3lame", "-q:a", "2", "-y", dst])
    return float(j["input_i"])


def slug(n):
    return re.sub(r"[^a-z0-9]+", "_", os.path.splitext(n)[0].lower()).strip("_")[:40]


# ---------------------------------------------------------------- the tracks
ORDER = {
    "mechanichal": "01_sunny_chill",
    "space_echo": "02_calm_space",
    "1_minute_dnb": "03_dreamy_lift",
    "electric_exodus": "04_rush_mid",
    "bouncer": "05_rush_hard",
    "moodless": "06_comedown",
    "drums_loop": "07_loop_tool",
}
for f in sorted(os.listdir(incoming)):
    if f.startswith("Kamihamiha") or not f.lower().endswith((".mp3", ".wav", ".ogg")):
        continue
    key = next((v for k, v in ORDER.items() if k in slug(f)), slug(f))
    dst = os.path.join(out, "preview_%s.mp3" % key)
    before = loudnorm(os.path.join(incoming, f), dst)
    print("%-48s %6.1f LUFS -> %g   %s" % (f[:48], before, TARGET, os.path.basename(dst)))

# ---------------------------------------------------------------- the stems: an 8-bar window per stem, built up one at a time
SR = 11025
names = ["ambience", "pulse", "bass", "drums", "piano", "guitar", "synth", "acid", "fx"]
win = {}
for n in names:
    raw = subprocess.run([FF, "-v", "error", "-i", os.path.join(stems, n + ".flac"), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"], capture_output=True).stdout
    x = np.frombuffer(raw, dtype=np.float32)
    per = int(BAR * SR)
    k = len(x) // per
    r = 20 * np.log10(np.array([np.sqrt(np.mean(x[i * per:(i + 1) * per] ** 2) + 1e-12) for i in range(k)]) + 1e-9)
    best, bs = -999.0, 0
    for s in range(0, k - 8, 8):          # on the 8-bar phrase grid
        seg = r[s:s + 8]
        # loud and steady: the mean level, and no gap inside the window
        sc = seg.mean() - 2.0 * max(0.0, seg.max() - seg.min() - 12.0)
        if sc > best:
            best, bs = sc, s
    win[n] = bs
    print("%-9s window starts at bar %3d (%.1f s)" % (n, bs, bs * BAR))

tmp = os.path.join(out, "_tmp")
os.makedirs(tmp, exist_ok=True)
wav = {}
for n in names:
    p = os.path.join(tmp, n + ".wav")
    subprocess.run([FF, "-v", "error", "-y", "-ss", "%.3f" % (win[n] * BAR), "-t", "%.3f" % (8 * BAR), "-i", os.path.join(stems, n + ".flac"),
                    "-af", "loudnorm=I=-24:TP=-3:LRA=7", "-ar", "44100", "-ac", "2", p], check=True)
    wav[n] = p
# each step adds one stem; a step is the same 8 bars with more parts playing
parts = []
for k in range(1, len(names) + 1):
    use = names[:k]
    inputs = []
    for n in use:
        inputs += ["-i", wav[n]]
    flt = "".join("[%d:a]" % i for i in range(len(use))) + "amix=inputs=%d:normalize=0,alimiter=limit=0.9[o]" % len(use)
    p = os.path.join(tmp, "step%d.wav" % k)
    subprocess.run([FF, "-v", "error", "-y"] + inputs + ["-filter_complex", flt, "-map", "[o]", "-ar", "44100", p], check=True)
    parts.append(p)
lst = os.path.join(tmp, "list.txt")
open(lst, "w").write("".join("file '%s'\n" % p.replace("\\", "/") for p in parts))
whole = os.path.join(tmp, "buildup.wav")
subprocess.run([FF, "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", whole], check=True)
loudnorm(whole, os.path.join(out, "alien_warfare_buildup.mp3"))
print("build-up order:", " + ".join(names), " (8 bars = 15 s each step)")
for f in os.listdir(tmp):
    os.remove(os.path.join(tmp, f))
os.rmdir(tmp)
print("done ->", out)
