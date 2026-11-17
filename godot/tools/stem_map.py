"""Prints, per stem, how loud it is in each bar of the track (a map of what plays when), so a loopable section with the right mix of parts can be chosen.
    python tools/stem_map.py <folder of stems> <bpm>
Needs ffmpeg on the path (or set FFMPEG)."""
import os
import subprocess
import sys

import numpy as np

FF = os.environ.get("FFMPEG", "ffmpeg")
folder = sys.argv[1]
bpm = float(sys.argv[2])
bar = 4.0 * 60.0 / bpm
SR = 11025
names = sorted(f[:-5] for f in os.listdir(folder) if f.endswith(".flac"))
rows = {}
n_bars = 0
for n in names:
    raw = subprocess.run([FF, "-v", "error", "-i", os.path.join(folder, n + ".flac"), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"], capture_output=True).stdout
    x = np.frombuffer(raw, dtype=np.float32)
    per = int(bar * SR)
    k = len(x) // per
    r = np.array([np.sqrt(np.mean(x[i * per:(i + 1) * per] ** 2) + 1e-12) for i in range(k)])
    rows[n] = 20 * np.log10(r + 1e-9)
    n_bars = max(n_bars, k)
    print("%-9s %.1f s   peak %.1f dBFS   mean rms %.1f dB" % (n, len(x) / SR, 20 * np.log10(np.max(np.abs(x)) + 1e-9), rows[n].mean()))
print("\nper bar (%.3f s): '#' loud, '+' present, '.' faint, ' ' silent   (one character per bar, 8 bars per group)\n" % bar)
for n in names:
    r = rows[n]
    top = r.max()
    s = ""
    for i, v in enumerate(r):
        s += "#" if v > top - 6 else ("+" if v > top - 18 else ("." if v > top - 40 else " "))
        if i % 8 == 7:
            s += "|"
    print("%-9s %s" % (n, s))
