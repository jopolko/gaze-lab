# physics + compaction for already-split courses (data/long_s101..)
$root = Split-Path -Parent $PSScriptRoot
foreach ($d in Get-ChildItem (Join-Path $root 'web\downhill-three\data') -Directory -Filter 'long_s1??') {
  if (Test-Path (Join-Path $d.FullName 'physics.json')) { continue }
  python (Join-Path $root 'web\tools\make_physics.py') $d.FullName *> $null
  python (Join-Path $root 'web\tools\compact_level.py') $d.FullName ($d.FullName + '_c') *> $null
  if (Test-Path (Join-Path ($d.FullName + '_c') 'meta.json')) { Remove-Item -Recurse -Force $d.FullName; Rename-Item ($d.FullName + '_c') $d.Name; Write-Output "$($d.Name) ok" } else { Write-Output "$($d.Name) FAILED" }
}
Write-Output 'FINISH DONE'
