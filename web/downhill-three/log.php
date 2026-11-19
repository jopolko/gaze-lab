<?php
// Detailed eye-vs-board samples from the three.js game (numbers only, no images). Appends to /var/lib/gaze-lab-logs/three/<date>.jsonl, outside the web root.
const ROOT = '/var/lib/gaze-lab-logs/three';
if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') { http_response_code(405); exit; }
$len = (int)($_SERVER['CONTENT_LENGTH'] ?? 0);
if ($len <= 0 || $len > 65536) { http_response_code(413); exit; }
$raw = file_get_contents('php://input', false, null, 0, 65537);
$d = json_decode($raw, true);
if (!is_array($d) || array_is_list($d)) { http_response_code(400); exit; }
foreach (['full','jpg','snap','image','frame'] as $k) { if (array_key_exists($k, $d)) { http_response_code(400); exit; } }
$rl = sys_get_temp_dir() . '/three_rl_' . md5($_SERVER['REMOTE_ADDR'] ?? '0') . '_' . date('YmdHi');
$n = is_file($rl) ? (int)file_get_contents($rl) : 0;
if ($n > 120) { http_response_code(429); exit; }
@file_put_contents($rl, (string)($n + 1), LOCK_EX);
if (!is_dir(ROOT) && !@mkdir(ROOT, 0770, true)) { http_response_code(500); exit; }
@file_put_contents(ROOT . '/' . date('Y-m-d') . '.jsonl', json_encode($d) . "\n", FILE_APPEND | LOCK_EX);
http_response_code(204);
