# BAKE ROADS: generates wide courses in headless Godot (godot/tests/dump_long.gd) and splits each into web/downhill-three/data/long_s<seed>/.
#   powershell -File tools/bake_roads.ps1 -Seeds 102,103 [-TurnAmps 9,13,17]
# Each seed takes ~20 s to bake and ~20 s to split; the raw dump (~35 MB) is deleted after splitting. Then run: node web/tools/build_bank2.mjs
param([int[]]$Seeds = @(102..121), [double[]]$TurnAmps = @(9, 13, 17))
$root = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $root 'tools\godot\Godot_v4.7.2-stable_win64_console.exe'
$bake = Join-Path $root 'tools\bake'; New-Item -ItemType Directory -Force $bake | Out-Null
$i = 0
foreach ($s in $Seeds) {
  $amp = $TurnAmps[$i % $TurnAmps.Count]; $i++
  $out = Join-Path $bake "long_s$s.json"; $dir = Join-Path $root "web\downhill-three\data\long_s$s"
  if (Test-Path (Join-Path $dir 'meta.json')) { Write-Output "skip s$s (already baked)"; continue }
  $env:OUT = $out -replace '\\', '/'; $env:SEED = "$s"; $env:THEME = 'psychedelic'; $env:SEGS = '64'; $env:TURN_AMP = "$amp"
  $t0 = Get-Date
  & $godot --headless --path (Join-Path $root 'godot') res://tests/dump_long.tscn *> $null
  if (-not (Test-Path $out)) { Write-Output "FAILED s$s (no dump)"; continue }
  python (Join-Path $root 'web\tools\split_level.py') $out $dir *> $null
  python (Join-Path $root 'web\tools\make_physics.py') $dir *> $null
  python (Join-Path $root 'web\tools\compact_level.py') $dir ($dir + '_c') *> $null; if (Test-Path (Join-Path ($dir + '_c') 'meta.json')) { Remove-Item -Recurse -Force $dir; Rename-Item ($dir + '_c') (Split-Path $dir -Leaf) }
  Remove-Item $out -Force
  Write-Output ("s{0} turn {1}: {2} s" -f $s, $amp, [int]((Get-Date) - $t0).TotalSeconds)
}
Remove-Item Env:TURN_AMP -ErrorAction SilentlyContinue
Write-Output 'BAKE DONE'

