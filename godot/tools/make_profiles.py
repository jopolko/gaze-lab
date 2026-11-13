"""Builds profiles.json, the "start here" table for each class of hardware, from what everybody's devices found when they tuned themselves.

    python tools/make_profiles.py [logs folder] [out file]       (defaults: tools/logs-vps  ->  tools/profiles.json)
    then upload it to the web server as /gaze-lab/profiles.json (the game fetches it at load and uses it as a starting point for a device class it matches).

Reads the "tuner" records with event "done": per hardware class, the most common kept value of each knob (camera resolution, tracker rate, camera exposure), needing at least MIN devices
to agree before a class is written (one lucky device should not decide for everybody).
"""
import collections
import glob
import json
import os
import sys

MIN = 3
here = os.path.dirname(os.path.abspath(__file__))
root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "logs-vps")
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, "profiles.json")
votes = collections.defaultdict(lambda: collections.defaultdict(collections.Counter))
devices = collections.defaultdict(set)
for path in glob.glob(os.path.join(root, "*", "*.jsonl")):
    for line in open(path, encoding="utf-8", errors="replace"):
        try:
            d = json.loads(line)
        except Exception:
            continue
        if d.get("kind") != "tuner" or d.get("event") != "done" or not isinstance(d.get("chosen"), dict):
            continue
        cls = d.get("class")
        who = (d.get("who"), d.get("sid"))
        if not cls or who in devices[cls]:
            continue
        devices[cls].add(who)
        for k, v in d["chosen"].items():
            votes[cls][k][json.dumps(v)] += 1
table = {}
for cls, ks in votes.items():
    if len(devices[cls]) < MIN:
        continue
    table[cls] = {k: json.loads(c.most_common(1)[0][0]) for k, c in ks.items()}
json.dump(table, open(out, "w"), indent=1)
print("%d hardware classes written to %s (%d seen, %d had enough devices)" % (len(table), out, len(votes), len(table)))
