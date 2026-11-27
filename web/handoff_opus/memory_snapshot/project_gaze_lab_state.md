---
name: gaze-lab-downhill-state
description: "Where Downhill stands (2026-11-13): systems built, how to test/deploy, open problems, last commit"
metadata:
  node_type: memory
  type: project
  originSessionId: 1804e927-9051-4067-9f2d-f1c299a3cedd
  modified: 2026-11-13T01:46:23.296Z
---

Downhill (class RunRig, scripts/RunRig.gd over DownhillRig.gd) at github.com/jopolko/gaze-lab, last commit 7eef287 on main; after it uncommitted: MENU button, pixel cap + start-one-tier-down in Lighting.gd, metrics files. Test build: joshuaopolko.com/gaze-lab/godot-dev/?level=downhill (add &nosplash, &theme=candy|egypt|psychedelic|matrix|synthwave, &nopm, &nopost, &pmview=0.3).

Built: zones (rush/flat/tunnel/bend/air/forest/drop) with lazy generation behind gates, regions, presets/seed/endless; splash (SplashView.gd) then settings menu (DownhillMenu.gd, saved to user://downhill_menu.cfg); themes (Themes.gd, ThemeFX.gd, ThemeBackdrop.gd, Lighting.gd = day cycle, snow, rider/gate lights, speed governor tiers 0-3); face challenges in the air + cinematic cutaway; phone motion (PhoneMotion.gd), frame rotation (GazeCamJS.gd), RunLog.gd run reports in localStorage (menu card: copy/download); Saccades.gd real-look detector + tentative intent; earned help (assist_level, _engage), agency numbers; pause screen with RETURN TO MENU.

Test: `Godot_..._console.exe --headless --path godot res://tests/run_test.tscn` (~5 min); it writes godot/tests/metrics_latest.json + metrics_history.csv. The simulated-player crash-total check is flaky (wall-clock timing), not a regression by itself. Dev probes: tests/eyes_probe*.gd, osc_probe, fps_bench, menu_probe, shader_lab (+ AppData/Local/Temp/claude/lab.sh).

Open: hands-off board still passes gates (course follows the line taken); theme-specific mechanics are thin (only Egypt sandstorm + hazard skins); party/hot-seat mode idea; multi-face needs pipeline rework; phone perf unmeasured (user reports 48 fps candy on phone, desktop was slow before the pixel cap).

**Why:** continuity after context compaction. **How to apply:** read this before touching Downhill; the user judges by feel on a real phone, so ask for the fps line and COPY ALL run report.
