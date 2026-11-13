#!/bin/sh
# Copy the shared numbers from the VPS down and summarise them:   sh tools/pull_logs.sh [--since YYYYMMDD]
# (the VPS keeps them in /var/lib/gaze-lab-logs, outside the web root)
cd "$(dirname "$0")" || exit 1
mkdir -p logs-vps
ssh nowservingto 'cd /var/lib/gaze-lab-logs 2>/dev/null && tar czf - .' | tar xzf - -C logs-vps
python summarize.py logs-vps "$@"
