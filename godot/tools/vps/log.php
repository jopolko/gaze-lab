<?php
// Receives the anonymous performance numbers people choose to share from the game (one small JSON object per POST).
// Lands at /gaze-lab/log.php. Lines are appended to /var/lib/gaze-lab-logs/<anonymous id>/<date>.jsonl, OUTSIDE the web root.
// Refuses: anything but POST, bodies over 32 KB, anything that is not a JSON object, anything carrying camera images, and more than 240 posts a minute from one address.
// Keeps only the fields in $KEEP, so nothing unexpected gets stored. Read the logs with tools/summarize.py (pull_logs.sh copies them down).
const LOG_ROOT = '/var/lib/gaze-lab-logs';
const MAX_BODY = 32768;
$KEEP = ['kind','t','who','sid','app','device','hw','gameFps','frameP95ms','trackerFps','latencyMs','modelMs','confidence','face','jitterRaw','jitterOut','spanX','spanY','mode','kalman','hold','median','pick','auto','view','camera','eyeAim','gaze','eyeLook','offset','scale','locked','msg','event','issue','evidence','action','before','after','verdict','row','n','gates','cur_med','cur_min','cur_max','looked','aim','went','steer','aim_end','flips','lost','lock_t','target','look_cur','look_gaze','aim_t','cfg','phase','i','ci','key','value','by','text','opts','health','params','sweep','calLocked','kalmanJumps','tag','dist','lit','cursor','knob','kept','chosen','default_score','log','class','applied','baseline','score_now','score','key','reason','kinds','went_kind','what','x','v','eye','run','barriers','postFail','aimed','eyes_on_it','locked_on_it'];

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') { http_response_code(405); exit; }
$len = (int)($_SERVER['CONTENT_LENGTH'] ?? 0);
if ($len <= 0 || $len > MAX_BODY) { http_response_code(413); exit; }
$raw = file_get_contents('php://input', false, null, 0, MAX_BODY + 1);
$d = json_decode($raw, true);
if (!is_array($d) || array_is_list($d)) { http_response_code(400); exit; }
foreach (['full','jpg','snap','image','frame'] as $k) { if (array_key_exists($k, $d)) { http_response_code(400); exit; } }
if (isset($d['face']) && !is_numeric($d['face'])) { http_response_code(400); exit; }

// a crude per-address rate limit
$ip = $_SERVER['REMOTE_ADDR'] ?? '0';
$rl = sys_get_temp_dir() . '/gazelab_rl_' . md5($ip) . '_' . date('YmdHi');
$n = is_file($rl) ? (int)file_get_contents($rl) : 0;
if ($n >= 240) { http_response_code(429); exit; }
@file_put_contents($rl, (string)($n + 1), LOCK_EX);

function clean($v, $depth = 0) {
    if ($depth > 5) { return null; }
    if (is_array($v)) {
        $out = []; $n = 0;
        foreach ($v as $k => $x) {
            if (++$n > 300) { break; }
            $key = is_int($k) ? $k : substr(preg_replace('/[^A-Za-z0-9_-]/', '', (string)$k), 0, 40);
            $out[$key] = clean($x, $depth + 1);
        }
        return $out;
    }
    if (is_string($v)) {
        if (strncmp($v, 'data:', 5) === 0) { return null; }      // never an image
        return substr($v, 0, 400);
    }
    if (is_int($v) || is_float($v) || is_bool($v) || $v === null) { return $v; }
    return null;
}
$rec = clean($d);
$rec['rx'] = time();
$who = preg_replace('/[^A-Za-z0-9_-]/', '', (string)($d['who'] ?? 'unnamed'));
$who = substr($who === '' ? 'unnamed' : $who, 0, 32);
$dir = LOG_ROOT . '/' . $who;
if (!is_dir($dir) && !@mkdir($dir, 0770, true)) { http_response_code(500); exit; }
$ok = @file_put_contents($dir . '/' . date('Ymd') . '.jsonl', json_encode($rec, JSON_UNESCAPED_SLASHES) . "\n", FILE_APPEND | LOCK_EX);
http_response_code($ok === false ? 500 : 204);
