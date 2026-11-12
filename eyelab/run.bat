@echo off
rem EyeLab: serves this folder on localhost (camera access needs localhost or https) and opens it.
cd /d "%~dp0"
start "" http://localhost:8070/index.html
python -m http.server 8070 --bind 127.0.0.1
