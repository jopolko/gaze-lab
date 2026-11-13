# Start (or restart) the local test servers so they keep collecting while nobody is watching:
#   powershell -ExecutionPolicy Bypass -File tools/start_servers.ps1
# http://localhost:8060 (this machine) and https://<this machine's address>:8443 (phones and other machines on the network). Logs go to tools/logs/.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
foreach ($port in 8060, 8443) {
  Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
}
Start-Process python -ArgumentList "`"$here\serve.py`"" -WindowStyle Hidden
Start-Process python -ArgumentList "`"$here\serve.py`"", "--lan" -WindowStyle Hidden
Start-Sleep 3
"servers up: http://localhost:8060/  and  https://$((Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '192.168.*' } | Select-Object -First 1).IPAddress):8443/"
