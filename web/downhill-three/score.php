<?php
// THE CROWD TOTAL: the points every player has scored together over the last DAYS days, and the averages of every finished journey. The game reads it (GET) to set how hard the rocket is to earn and what counts as a good run, and adds to it (POST).
// It stores nothing about people: no names, no addresses, just numbers per day in /var/lib/gaze-lab-logs/three/score_total.json (outside the web root).
// TUNING (edit here, no game update needed): the rocket fills M0 times as fast as normal when the recent total is 0 and slows as it grows: mult = M0 / (1 + recent / K), never below FLOOR.
// A journey scores roughly 20,000 to 50,000 points, so K = 1,750,000 is about 50 journeys: normal difficulty (1x) at about 150 journeys in the window, about 0.5x at 350, the floor at about 1,000.
const ROOT = '/var/lib/gaze-lab-logs/three';
const FILE = ROOT . '/score_total.json';
const M0 = 4.0;          // multiplier when nobody has scored recently (nearly free)
const K = 1750000;       // recent points at which the multiplier has halved
const FLOOR = 0.2;       // never harder than this multiplier
const DAYS = 30;         // only the last 30 days count, so new players are not locked into the hardest setting and the game recovers when it goes quiet
const MAXPOST = 100000;  // the most one post can add (a whole journey is far below this)
header('Cache-Control: no-store');
$method = $_SERVER['REQUEST_METHOD'] ?? '';
$today = date('Y-m-d');

// the state: days = points per day, all = points ever, runs = per day sums of finished journeys {n, ch (best chain), cl (clean %), sp (speed %)}
function parse_state($raw, $today) {
  $days = []; $all = 0; $runs = [];
  $j = json_decode((string)$raw, true);
  if (is_array($j)) {
    if (isset($j['days']) && is_array($j['days'])) {
      foreach ($j['days'] as $d => $v) if (preg_match('/^\d{4}-\d{2}-\d{2}$/', (string)$d)) $days[$d] = max(0, (int)$v);
      $all = max(0, (int)($j['all'] ?? array_sum($days)));
      if (isset($j['runs']) && is_array($j['runs'])) $runs = $j['runs'];
    } elseif (isset($j['total'])) { $t = max(0, (int)$j['total']); $days[$today] = $t; $all = $t; }   // the first file format: one running total
  }
  return [$days, $all, $runs];
}
function window_cut($today) { return date('Y-m-d', strtotime($today . ' -' . (DAYS - 1) . ' days')); }
function recent_total($days, $today) { $cut = window_cut($today); $s = 0; foreach ($days as $d => $v) if ($d >= $cut) $s += $v; return $s; }
function recent_runs($runs, $today) {
  $cut = window_cut($today); $n = 0; $ch = 0; $cl = 0; $sp = 0;
  foreach ($runs as $d => $r) if ($d >= $cut && is_array($r)) { $n += (int)($r['n'] ?? 0); $ch += (int)($r['ch'] ?? 0); $cl += (int)($r['cl'] ?? 0); $sp += (int)($r['sp'] ?? 0); }
  if ($n < 1) return ['runs' => 0, 'avg' => null];
  return ['runs' => $n, 'avg' => ['chain' => round($ch / $n, 1), 'clean' => round($cl / $n, 1), 'speed' => round($sp / $n, 1)]];
}

if ($method === 'GET') {
  [$days, $all, $runs] = parse_state(is_file(FILE) ? @file_get_contents(FILE) : '', $today);
  $recent = recent_total($days, $today);
  $rr = recent_runs($runs, $today);
  $mult = max(FLOOR, M0 / (1 + $recent / K));
  header('Content-Type: application/json');
  echo json_encode(['total' => $recent, 'all' => $all, 'mult' => round($mult, 3), 'runs' => $rr['runs'], 'avg' => $rr['avg']]);
  exit;
}
if ($method !== 'POST') { http_response_code(405); exit; }
$len = (int)($_SERVER['CONTENT_LENGTH'] ?? 0);
if ($len <= 0 || $len > 512) { http_response_code(413); exit; }
$d = json_decode((string)file_get_contents('php://input', false, null, 0, 513), true);
if (!is_array($d)) { http_response_code(400); exit; }
// two kinds of post: {"d": points} adds to the crowd total; {"run": {"ch": best chain, "cl": clean percent, "sp": speed percent}} adds one finished journey to the averages
$add = 0; $run = null;
if (isset($d['run']) && is_array($d['run'])) {
  $r = $d['run'];
  foreach (['ch' => 200, 'cl' => 100, 'sp' => 100] as $k => $mx) {
    if (!isset($r[$k]) || !is_numeric($r[$k])) { http_response_code(400); exit; }
    $r[$k] = (int)round($r[$k]);
    if ($r[$k] < 0 || $r[$k] > $mx) { http_response_code(400); exit; }
  }
  $run = $r;
} elseif (isset($d['d']) && is_numeric($d['d'])) {
  $add = (int)$d['d'];
  if ($add < 1 || $add > MAXPOST) { http_response_code(400); exit; }
} else { http_response_code(400); exit; }
$rl = sys_get_temp_dir() . '/three_score_rl_' . md5($_SERVER['REMOTE_ADDR'] ?? '0') . '_' . date('YmdHi');
$n = is_file($rl) ? (int)file_get_contents($rl) : 0;
if ($n >= 20) { http_response_code(429); exit; }
@file_put_contents($rl, (string)($n + 1), LOCK_EX);
if (!is_dir(ROOT) && !@mkdir(ROOT, 0770, true)) { http_response_code(500); exit; }
$fp = @fopen(FILE, 'c+');
if (!$fp) { http_response_code(500); exit; }
flock($fp, LOCK_EX);
[$days, $all, $runs] = parse_state(stream_get_contents($fp), $today);
if ($run) {
  $q = $runs[$today] ?? ['n' => 0, 'ch' => 0, 'cl' => 0, 'sp' => 0];
  $q['n'] = (int)$q['n'] + 1; $q['ch'] = (int)$q['ch'] + $run['ch']; $q['cl'] = (int)$q['cl'] + $run['cl']; $q['sp'] = (int)$q['sp'] + $run['sp'];
  $runs[$today] = $q;
} else {
  $days[$today] = ($days[$today] ?? 0) + $add; $all += $add;
}
$keep = date('Y-m-d', strtotime($today . ' -' . (DAYS + 5) . ' days'));   // old days drop out of the file (the all-time number stays)
foreach ($days as $dd => $v) if ($dd < $keep) unset($days[$dd]);
foreach ($runs as $dd => $v) if ($dd < $keep) unset($runs[$dd]);
ftruncate($fp, 0); rewind($fp); fwrite($fp, json_encode(['days' => $days, 'all' => $all, 'runs' => $runs])); fflush($fp); flock($fp, LOCK_UN); fclose($fp);
http_response_code(204);
