"""Lays the sound effects over the music at set moments, to hear them in context.   python tools/sfx_demo.py <sfx folder> <music file> <out mp3>"""
import os
import subprocess
import sys

FF = os.environ.get("FFMPEG", "ffmpeg")
sfx, music, out = sys.argv[1], sys.argv[2], sys.argv[3]
EVENTS = [(0.5, "blip"), (1.3, "blip"), (2.2, "coin"), (3.5, "pad_boost"), (5.5, "mol0"), (6.7, "mol2"), (7.9, "mol5"), (9.5, "sproing"), (11.0, "boing2"),
          (12.5, "buff_boost"), (14.0, "powerup"), (15.5, "whoosh"), (17.0, "hurt"), (18.6, "bonk"), (20.0, "explosion"), (22.5, "levelup"), (24.5, "loot"),
          (26.0, "snap"), (27.2, "splat"), (28.6, "stretch"), (31.0, "kaboom"), (34.0, "rumble"), (36.0, "mol1"), (36.8, "mol3"), (37.6, "mol4")]
LEN = 40.0
args = [FF, "-hide_banner", "-v", "error", "-y", "-i", music]
for t, n in EVENTS:
    args += ["-i", os.path.join(sfx, n + ".wav")]
flt = "[0:a]atrim=120:135,asetpts=PTS-STARTPTS,aloop=loop=3:size=2000000000,atrim=0:%g,volume=0.8[bed];" % LEN
labels = ["[bed]"]
for i, (t, n) in enumerate(EVENTS):
    ms = int(t * 1000)
    flt += "[%d:a]aformat=sample_fmts=fltp:channel_layouts=stereo,adelay=%d|%d,volume=1.41[s%d];" % (i + 1, ms, ms, i)
    labels.append("[s%d]" % i)
flt += "".join(labels) + "amix=inputs=%d:normalize=0:duration=first,alimiter=limit=0.95,loudnorm=I=-16:TP=-1.5[o]" % len(labels)
args += ["-filter_complex", flt, "-map", "[o]", "-c:a", "libmp3lame", "-q:a", "2", out]
subprocess.run(args, check=True)
print("wrote", out)
