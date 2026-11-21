<?php
// THE ROCKET CERTIFICATE (a joke). POST: the game reports an earned rocket {b: biome 0..6, s: seconds riding, m: difficulty multiplier, p: pity 0..4, ch: best chain} and gets back a code and a serial number.
// GET ?c=RKT-XXXX-XXXX shows the certificate for that code. It proves only that this server was told about a rocket, which is the joke. Nothing about the player is stored: no name, no address, only these numbers.
// Records: /var/lib/gaze-lab-logs/three/certs.jsonl, one JSON object per line (outside the web root).
const ROOT = '/var/lib/gaze-lab-logs/three';
const CERTS = ROOT . '/certs.jsonl';
const BIOMES = ['Alps', 'Candy Land', 'Desert', 'Tunnel', 'Matrix', 'Synthwave', 'Trip'];
$method = $_SERVER['REQUEST_METHOD'] ?? '';
function esc($s) { return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8'); }

if ($method === 'POST') {
  $len = (int)($_SERVER['CONTENT_LENGTH'] ?? 0);
  if ($len <= 0 || $len > 512) { http_response_code(413); exit; }
  $d = json_decode((string)file_get_contents('php://input', false, null, 0, 513), true);
  if (!is_array($d)) { http_response_code(400); exit; }
  $b = isset($d['b']) && is_numeric($d['b']) ? (int)$d['b'] : -1; $s = isset($d['s']) && is_numeric($d['s']) ? (int)round($d['s']) : -1;
  $m = isset($d['m']) && is_numeric($d['m']) ? round((float)$d['m'], 3) : -1; $p = isset($d['p']) && is_numeric($d['p']) ? (int)$d['p'] : -1; $ch = isset($d['ch']) && is_numeric($d['ch']) ? (int)$d['ch'] : -1;
  if ($b < 0 || $b > 6 || $s < 0 || $s > 14400 || $m < 0 || $m > 10 || $p < 0 || $p > 4 || $ch < 0 || $ch > 200) { http_response_code(400); exit; }
  $rl = sys_get_temp_dir() . '/three_cert_rl_' . md5($_SERVER['REMOTE_ADDR'] ?? '0') . '_' . date('YmdHi');
  $n = is_file($rl) ? (int)file_get_contents($rl) : 0;
  if ($n >= 6) { http_response_code(429); exit; }
  @file_put_contents($rl, (string)($n + 1), LOCK_EX);
  if (!is_dir(ROOT) && !@mkdir(ROOT, 0770, true)) { http_response_code(500); exit; }
  $fp = @fopen(CERTS, 'c+');
  if (!$fp) { http_response_code(500); exit; }
  flock($fp, LOCK_EX);
  $count = 0; $used = [];
  while (($line = fgets($fp)) !== false) { $count++; $r0 = json_decode($line, true); if (is_array($r0) && isset($r0['code'])) $used[$r0['code']] = true; }   // the serial number is the line count + 1, under the lock; the codes already issued are remembered so a repeat can never happen
  $alpha = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  do { $code = 'RKT-'; for ($i = 0; $i < 8; $i++) { if ($i === 4) $code .= '-'; $code .= $alpha[random_int(0, strlen($alpha) - 1)]; } } while (isset($used[$code]));
  $rec = ['code' => $code, 'n' => $count + 1, 't' => time(), 'b' => $b, 's' => $s, 'm' => $m, 'p' => $p, 'ch' => $ch];
  fseek($fp, 0, SEEK_END); fwrite($fp, json_encode($rec) . "\n"); fflush($fp); flock($fp, LOCK_UN); fclose($fp);
  header('Content-Type: application/json'); header('Cache-Control: no-store');
  echo json_encode(['code' => $code, 'n' => $count + 1]);
  exit;
}
if ($method !== 'GET') { http_response_code(405); exit; }

$code = strtoupper(trim((string)($_GET['c'] ?? '')));
$rec = null; $total = 0;
if (is_file(CERTS)) { foreach (file(CERTS, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) { $r = json_decode($line, true); if (!is_array($r)) continue; $total++; if (($r['code'] ?? '') === $code) $rec = $r; } }
header('Content-Type: text/html; charset=utf-8'); header('Cache-Control: no-store');
$ok = $rec !== null && preg_match('/^RKT-[A-Z2-9]{4}-[A-Z2-9]{4}$/', $code);
$when = $ok ? gmdate('j F Y, H:i', (int)$rec['t']) . ' UTC' : '';
$mins = $ok ? sprintf('%d min %02d s', intdiv($rec['s'], 60), $rec['s'] % 60) : '';
$grade = $ok ? ($rec['m'] >= 3 ? 'Common' : ($rec['m'] >= 1.5 ? 'Uncommon' : ($rec['m'] >= 0.7 ? 'Rare' : ($rec['m'] >= 0.35 ? 'Very Rare' : 'Legendary')))) : '';
$host = preg_match('/^[A-Za-z0-9.-]+(:d+)?$/', $_SERVER['HTTP_HOST'] ?? '') ? $_SERVER['HTTP_HOST'] : 'localhost';
$base = 'https://' . $host . rtrim(dirname($_SERVER['SCRIPT_NAME'] ?? '/'), '/') . '/';
$pageUrl = $base . 'cert.php' . ($ok ? '?c=' . $code : '');
$ogTitle = $ok ? 'Rocket ' . $code . ' - Certificate of Authentic Rocket' : 'Certificate of Authentic Rocket';
$ogDesc = $ok ? 'Earned in ' . (BIOMES[$rec['b']] ?? '?') . ', ' . $mins . ' into a journey. Rarity: ' . $grade . '. Certified genuine by us, valid nowhere.' : 'Earn a rocket in Downhill, get a very official certificate.';
?><!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title><?= esc($ogTitle) ?></title>
<meta name="description" content="<?= esc($ogDesc) ?>">
<meta property="og:type" content="website"><meta property="og:title" content="<?= esc($ogTitle) ?>"><meta property="og:description" content="<?= esc($ogDesc) ?>"><meta property="og:url" content="<?= esc($pageUrl) ?>">
<meta property="og:image" content="<?= esc($base) ?>cert_share.png"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630"><meta property="og:image:alt" content="A very official looking certificate with a rocket and a molecule of unknown origin">
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="<?= esc($ogTitle) ?>"><meta name="twitter:description" content="<?= esc($ogDesc) ?>"><meta name="twitter:image" content="<?= esc($base) ?>cert_share.png">
<style>
:root{color-scheme:light dark;--ink:#2a1f0c;--gold:#b8892b;--gold2:#f1d37a;--paper:#fbf3dc;--red:#a3201c}
html,body{margin:0;background:#1b1530;font-family:Georgia,'Times New Roman',serif;color:var(--ink)}
body{min-height:100vh;display:flex;align-items:center;justify-content:center;padding:16px;box-sizing:border-box}
.cert{position:relative;width:min(720px,100%);box-sizing:border-box;padding:clamp(14px,4vw,34px);background:var(--paper);
 background-image:repeating-linear-gradient(45deg,#0000 0 6px,#b8892b12 6px 7px),radial-gradient(circle at 50% 0,#fff8 0,#0000 60%);
 border:3px solid var(--gold);outline:2px solid var(--gold2);outline-offset:-12px;box-shadow:0 10px 50px #000a;text-align:center}
.cert:before{content:"";position:absolute;inset:10px;border:1px dashed #b8892b88;pointer-events:none}
.bureau{font:700 clamp(10px,2.6vw,13px) system-ui,sans-serif;letter-spacing:.32em;text-transform:uppercase;color:var(--gold)}
h1{margin:6px 0 2px;font-size:clamp(22px,6.4vw,40px);letter-spacing:.06em;font-variant:small-caps;line-height:1.05}
.sub{font-style:italic;font-size:clamp(12px,3vw,15px);margin-bottom:10px}
.big{font-size:clamp(17px,4.6vw,26px);margin:10px 0 4px}
.serial{font:800 clamp(18px,5vw,28px) ui-monospace,Consolas,monospace;letter-spacing:.12em;color:var(--red);border:2px solid var(--red);display:inline-block;padding:2px 12px;transform:rotate(-1.5deg);margin:6px 0}
table{margin:12px auto 6px;border-collapse:collapse;width:min(520px,100%);font-size:clamp(12px,3.2vw,15px)}
td{padding:5px 8px;border-bottom:1px dotted #b8892b99;text-align:left}td:first-child{font-weight:700;width:46%}
.seals{display:flex;align-items:center;justify-content:space-between;gap:8px;margin-top:10px}
.stamp{flex:none;width:clamp(78px,20vw,116px);height:clamp(78px,20vw,116px);border-radius:50%;border:4px double var(--red);color:var(--red);display:flex;align-items:center;justify-content:center;text-align:center;font:900 clamp(9px,2.3vw,13px)/1.1 system-ui,sans-serif;letter-spacing:.08em;transform:rotate(-14deg);opacity:.85;text-transform:uppercase}
.holo{flex:none;width:clamp(54px,14vw,84px);height:clamp(54px,14vw,84px);border-radius:50%;background:conic-gradient(#f0f,#0ff,#ff0,#0f8,#f0f);opacity:.7;display:flex;align-items:center;justify-content:center;font:700 7px system-ui,sans-serif;color:#000a;text-align:center;filter:saturate(1.3)}
.verdict{margin-top:0;font:800 clamp(13px,3.6vw,17px) system-ui,sans-serif;letter-spacing:.1em;color:#0d6b2b}
.bad .verdict{color:var(--red)}
.fine{margin-top:12px;font:italic clamp(9px,2.3vw,11px) system-ui,sans-serif;color:#6b5a30;line-height:1.35}
.micro{font:6px/1 system-ui,sans-serif;color:#b8892b;letter-spacing:.04em;margin-top:6px;overflow:hidden;white-space:nowrap}
.plate{display:flex;align-items:center;justify-content:center;gap:clamp(6px,2.4vw,22px);flex-wrap:wrap;margin:6px 0 2px}
.fig{flex:none;width:clamp(74px,18vw,118px);text-align:center;font:italic clamp(8px,2vw,10px)/1.15 Georgia,serif;color:#6b5a30}
.fig svg{display:block;width:100%;height:auto}
.edition{font:700 clamp(10px,2.6vw,13px) system-ui,sans-serif;letter-spacing:.12em;color:var(--ink);margin-top:2px}
.limit{font:italic clamp(9px,2.3vw,12px) Georgia,serif;color:#6b5a30;margin:2px 0 0}
.share{display:block;margin:12px auto 0;min-height:44px;padding:8px 22px;border-radius:30px;border:2px solid var(--red);background:var(--paper);color:var(--red);font:900 clamp(12px,3.2vw,15px) system-ui,sans-serif;letter-spacing:.12em;text-transform:uppercase;cursor:pointer;touch-action:manipulation}
.share:active{transform:scale(.98)}
.mill{display:flex;align-items:flex-end;justify-content:space-between;gap:12px;margin-top:10px;text-align:left}
.acc{flex:1;font:700 clamp(8px,2vw,10px)/1.3 system-ui,sans-serif;letter-spacing:.05em;color:#6b5a30;text-transform:uppercase}
.sig{flex:none;text-align:center;border-top:1px solid #2a1f0c;padding-top:2px;min-width:clamp(120px,32vw,190px)}
.luke{display:block;font:normal clamp(22px,6vw,32px)/.9 'Brush Script MT','Segoe Script','Lucida Handwriting',cursive;color:#16306b;transform:rotate(-4deg);margin-bottom:2px}
.ttl{display:block;font:italic clamp(8px,2vw,10px) system-ui,sans-serif;color:#6b5a30}
a{color:var(--red)}
@media (prefers-color-scheme:dark){.cert{box-shadow:0 10px 50px #000c}}
</style></head><body>
<?php if ($ok): ?>
<div class="cert">
  <div class="bureau">The International Bureau of Downhill Rocketry</div>
  <h1>Certificate of Authentic Rocket</h1>
  <div class="sub">A genuine, officially unofficial document</div>
  <div class="big">This is to certify that a rocket was earned,<br>and was reported to a PHP script.</div>
  <div class="plate"><div class="fig"><svg viewBox="0 0 150 130" aria-label="molecule of unknown origin"><g stroke="#2a1f0c" stroke-width="4" stroke-linecap="round" opacity=".8"><line x1="62" y1="52" x2="22" y2="28"/><line x1="62" y1="52" x2="104" y2="24"/><line x1="62" y1="52" x2="72" y2="108"/><line x1="104" y1="24" x2="140" y2="48"/></g><circle cx="62" cy="52" r="24" fill="#19e6ff" stroke="#2a1f0c" stroke-width="3"/><circle cx="22" cy="28" r="15" fill="#ff4fd8" stroke="#2a1f0c" stroke-width="3"/><circle cx="104" cy="24" r="17" fill="#ffe14a" stroke="#2a1f0c" stroke-width="3"/><circle cx="72" cy="108" r="12" fill="#8a2dff" stroke="#2a1f0c" stroke-width="3"/><circle cx="140" cy="48" r="9" fill="#c8c8c8" stroke="#2a1f0c" stroke-width="3"/><text x="140" y="52" text-anchor="middle" font-family="sans-serif" font-weight="bold" font-size="11" fill="#2a1f0c">?</text><ellipse cx="54" cy="42" rx="8" ry="5" fill="#fff" opacity=".6" transform="rotate(-30 54 42)"/></svg>fig. 1: specimen of<br>undetermined provenance</div><div><div class="serial"><?= esc($code) ?></div></div><div class="fig"><svg viewBox="0 0 150 130" aria-label="a rocket, speeding by"><defs><linearGradient id="fl" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff2a8"/><stop offset=".5" stop-color="#ffb400"/><stop offset="1" stop-color="#ff4d6a" stop-opacity="0"/></linearGradient></defs><g transform="translate(78 62) rotate(38) scale(.62)"><g stroke="#b8892b" stroke-width="5" stroke-linecap="round" opacity=".55"><line x1="-6" y1="62" x2="-6" y2="128"/><line x1="-26" y1="70" x2="-26" y2="150"/><line x1="14" y1="70" x2="14" y2="140"/></g><path d="M-12 62 Q0 150 12 62Z" fill="url(#fl)"/><path d="M0 -70 C26 -40 26 20 18 54 H-18 C-26 20 -26 -40 0 -70Z" fill="#fff" stroke="#2a1f0c" stroke-width="5"/><circle cx="0" cy="-18" r="11" fill="#19e6ff" stroke="#2a1f0c" stroke-width="4"/><path d="M-18 26 L-46 62 L-18 54Z M18 26 L46 62 L18 54Z" fill="#ff4d6a" stroke="#2a1f0c" stroke-width="4" stroke-linejoin="round"/><path d="M0 -70 C10 -62 16 -52 18 -44 H-18 C-16 -52 -10 -62 0 -70Z" fill="#ff4d6a"/></g></svg>fig. 2: rocket,<br>speeding by</div></div>
  <div class="edition">No. <?= str_pad((string)$rec['n'], 6, '0', STR_PAD_LEFT) ?> / 009,999 &middot; COLLECTOR'S SERIES IX &middot; RUN &Omega;</div>
  <div class="limit">Limited to 9,999 (give or take 9,990,000). Actually issued so far: <?= (int)$total ?>.</div>
  <table>
    <tr><td>Issued on</td><td><?= esc($when) ?></td></tr>
    <tr><td>Earned in</td><td><?= esc(BIOMES[$rec['b']] ?? '?') ?></td></tr>
    <tr><td>Time into the journey</td><td><?= esc($mins) ?></td></tr>
    <tr><td>Best chain</td><td><?= (int)$rec['ch'] ?></td></tr>
    <tr><td>Series</td><td>Collector's Series IX (not a real series)</td></tr>
    <tr><td>Condition</td><td>Mint (it is a webpage)</td></tr>
    <tr><td>Rarity grade</td><td><?= esc($grade) ?> (difficulty <?= esc($rec['m']) ?>&times;<?= $rec['p'] > 0 ? ', pity ' . (int)$rec['p'] : '' ?>)</td></tr>
  </table>
  <div class="seals"><div class="holo">HOLOGRAM<br>(imitation)</div><div class="verdict">&#10003; VERIFIED &mdash; by us, just now</div><div class="stamp">Totally<br>Legit<br>&bull; 100% &bull;<br>Approved</div></div>
  <button class="share" id="sh" type="button">Share this rocket</button>
  <div class="fine">This certificate certifies nothing in particular. Not valid as proof of anything, anywhere. Void where prohibited, where forbidden and where nobody cares. The Bureau is a certificate mill.</div>
  <div class="mill"><div class="acc">Fully accredited by the Accreditation Accreditation Board (accredited by us). Life experience credit applied. Per rocketa ad astra (approximately).</div><div class="sig"><span class="luke">Luke</span><span class="ttl">Luke, Registrar &middot; Certificate Mill &middot; Est. last Tuesday</span></div></div>
  <div class="micro">THIS IS A GAME THIS IS A GAME THIS IS A GAME THIS IS A GAME THIS IS A GAME THIS IS A GAME THIS IS A GAME THIS IS A GAME THIS IS A GAME THIS IS A GAME THIS IS A GAME THIS IS A GAME</div>
</div>
<?php else: ?>
<div class="cert bad">
  <div class="bureau">The International Bureau of Downhill Rocketry</div>
  <h1>No Such Certificate</h1>
  <div class="sub">The Bureau has no record of that rocket</div>
  <div class="big">Code: <span class="serial"><?= esc($code !== '' ? $code : '(none)') ?></span></div>
  <div class="verdict">&#10007; NOT VERIFIED &mdash; suspicious</div>
  <div class="fine">Either the code was typed wrong, or the rocket was never earned. Rockets are earned in the game, one per journey. Nice try, though.</div>
</div>
<?php endif; ?>
<?php if ($ok): ?>
<script>
document.getElementById('sh').onclick = async function () {
  var d = { title: <?= json_encode($ogTitle) ?>, text: <?= json_encode($ogDesc) ?>, url: <?= json_encode($pageUrl) ?> };
  try { if (navigator.share) { await navigator.share(d); return; } } catch (e) { if (e && e.name === 'AbortError') return; }
  try { await navigator.clipboard.writeText(d.url); this.textContent = 'Link copied'; setTimeout(function () { this.textContent = 'Share this rocket'; }.bind(this), 2000); } catch (e) { window.prompt('Copy this link', d.url); }
};
</script>
<?php endif; ?>
</body></html>
