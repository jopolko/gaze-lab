# Mirrors the VPS log (three.js game) into web/spike/logs/spike-<date>.jsonl so monitor.py and trace.py work on phone runs.  python pull.py   (runs until stopped)
import subprocess, os, time, datetime
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'spike', 'logs'); os.makedirs(D, exist_ok=True)
off = {}
while True:
    day = datetime.date.today().isoformat(); out = os.path.join(D, 'spike-%s.jsonl' % day); o = off.get(day, 0)
    r = subprocess.run(['ssh', 'nowservingto', 'tail -c +%d /var/lib/gaze-lab-logs/three/%s.jsonl 2>/dev/null' % (o + 1, day)], capture_output=True)
    if r.stdout:
        data = r.stdout; k = data.rfind(b'\n')
        if k >= 0:
            with open(out, 'ab') as f: f.write(data[:k + 1])
            off[day] = o + k + 1
    time.sleep(3)
