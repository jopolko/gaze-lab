/* AFTERGLOW INPUT — one mapping for every device (open-world milestone 1, 2026-11-27).
   Every frame, call AGINPUT.poll(); then read AGINPUT.state:
     steer   -1..1  (left .. right)
     throttle -1..1 (brake/reverse .. accelerate)
     lookX, lookY   camera look offsets in radians (mouse, right stick, touch drag on the right half)
     jump, boost, gear, cam, phone   true while held; *P = pressed this frame (jumpP, boostP, gearP, camP, phoneP)
     device  'keys' | 'pad' | 'touch' | 'mouse' (whichever was used last)
   Touch: a floating joystick wherever the left thumb lands (2-D: up = gas, down = brake), buttons on the right.
   The same tuning table (AGINPUT.tune) lets each device be balanced slightly differently. */
(function () {
  const S = { steer: 0, throttle: 0, lookX: 0, lookY: 0, jump: false, boost: false, gear: false, cam: false, phone: false, device: 'keys' };
  const PREV = {}; const BTN = ['jump', 'boost', 'gear', 'cam', 'phone'];
  const tune = {
    keys: { steerRise: 7, steerFall: 10 },          /* keys are digital: ease them into an analogue value */
    pad: { dead: .14, curve: 1.5 },
    touch: { radius: 58, dead: .12, curve: 1.25 },
    mouse: { sens: .0024 },
  };
  const down = new Set();
  const KEYMAP = {
    left: ['a', 'arrowleft'], right: ['d', 'arrowright'], gas: ['w', 'arrowup'], brake: ['s', 'arrowdown'],
    jump: [' '], boost: ['shift'], gear: ['e'], cam: ['c'], phone: ['escape', 'tab', 'p'],
  };
  const kd = (k) => KEYMAP[k].some((x) => down.has(x));
  addEventListener('keydown', (e) => { const k = e.key.toLowerCase(); if (k === 'tab' || k === ' ' || k.startsWith('arrow')) e.preventDefault(); down.add(k); S.device = 'keys'; });
  addEventListener('keyup', (e) => down.delete(e.key.toLowerCase()));
  addEventListener('blur', () => down.clear());

  /* mouse: hold the right button or use pointer lock to look; left click = gear */
  let mdx = 0, mdy = 0, mLook = false, mGear = false;
  addEventListener('mousemove', (e) => { if (document.pointerLockElement || mLook) { mdx += e.movementX; mdy += e.movementY; S.device = 'mouse'; } });
  addEventListener('mousedown', (e) => { if (e.pointerType === 'touch') return; if (e.button === 2) mLook = true; if (e.button === 0 && document.pointerLockElement) mGear = true; });
  addEventListener('mouseup', (e) => { if (e.button === 2) mLook = false; if (e.button === 0) mGear = false; });
  addEventListener('contextmenu', (e) => e.preventDefault());

  /* touch */
  const T = { joy: null, look: null, btn: {} }; let lookTX = 0, lookTY = 0;
  const ui = document.createElement('div'); ui.id = 'agIn';
  ui.innerHTML = '<div id="agJoy"><div id="agKnob"></div></div>'
    + '<div id="agBtns"><button data-b="jump">JUMP</button><button data-b="boost">BOOST</button><button data-b="gear">GEAR</button></div>'
    + '<button id="agCamB" data-b="cam">CAM</button>';
  const css = document.createElement('style');
  css.textContent = '#agIn{position:fixed;inset:0;pointer-events:none;z-index:20;display:none}#agIn.on{display:block}'
    + '#agJoy{position:absolute;width:116px;height:116px;margin:-58px 0 0 -58px;border-radius:50%;border:2px solid rgba(120,255,240,.45);background:radial-gradient(rgba(20,10,40,.25),rgba(20,10,40,.05));display:none}'
    + '#agKnob{position:absolute;left:50%;top:50%;width:46px;height:46px;margin:-23px 0 0 -23px;border-radius:50%;background:rgba(120,255,240,.55);box-shadow:0 0 14px rgba(120,255,240,.7)}'
    + '#agBtns{position:absolute;right:calc(18px + var(--sa-r, env(safe-area-inset-right, 0px)));bottom:calc(22px + var(--sa-b, env(safe-area-inset-bottom, 0px)));display:grid;grid-template-columns:repeat(2,64px);gap:12px;pointer-events:auto}'
    + '#agBtns button,#agCamB{width:64px;height:64px;border-radius:50%;border:2px solid rgba(255,200,90,.6);background:rgba(20,10,40,.35);color:#ffd88a;font:700 11px/1 system-ui,sans-serif;letter-spacing:.06em;touch-action:none}'
    + '#agBtns button[data-b="jump"]{grid-column:2;grid-row:1/3;height:140px;border-radius:32px}'
    + '#agBtns button.on,#agCamB.on{background:rgba(255,200,90,.45);color:#1a0f24}'
    + '#agCamB{position:absolute;right:calc(18px + var(--sa-r, env(safe-area-inset-right, 0px)));top:calc(18px + var(--sa-t, env(safe-area-inset-top, 0px)));width:48px;height:48px;pointer-events:auto}';
  const mount = () => { document.head.appendChild(css); document.body.appendChild(ui); };
  if (document.body) mount(); else addEventListener('DOMContentLoaded', mount);
  const joyEl = () => document.getElementById('agJoy'), knobEl = () => document.getElementById('agKnob');
  ui.addEventListener('pointerdown', (e) => { const b = e.target.closest && e.target.closest('[data-b]'); if (!b) return; e.preventDefault(); T.btn[b.dataset.b] = e.pointerId; b.classList.add('on'); b.setPointerCapture(e.pointerId); S.device = 'touch'; });
  const btnUp = (e) => { for (const k in T.btn) if (T.btn[k] === e.pointerId) { delete T.btn[k]; const el = ui.querySelector('[data-b="' + k + '"]'); if (el) el.classList.remove('on'); } };
  ui.addEventListener('pointerup', btnUp); ui.addEventListener('pointercancel', btnUp);
  addEventListener('pointerdown', (e) => {
    if (e.pointerType !== 'touch' || (e.target.closest && e.target.closest('[data-b],button,a,input,#agPhone'))) return;
    ui.classList.add('on'); S.device = 'touch';
    if (e.clientX < innerWidth * .5 && !T.joy) { T.joy = { id: e.pointerId, x: e.clientX, y: e.clientY, dx: 0, dy: 0 }; const j = joyEl(); j.style.display = 'block'; j.style.left = e.clientX + 'px'; j.style.top = e.clientY + 'px'; knobEl().style.transform = ''; }
    else if (!T.look) T.look = { id: e.pointerId, x: e.clientX, y: e.clientY };
  }, { passive: true });
  addEventListener('pointermove', (e) => {
    if (T.joy && e.pointerId === T.joy.id) { const R = tune.touch.radius; let dx = e.clientX - T.joy.x, dy = e.clientY - T.joy.y; const d = Math.hypot(dx, dy); if (d > R) { /* the ring follows a thumb that slides past its edge */ T.joy.x += dx * (1 - R / d); T.joy.y += dy * (1 - R / d); dx *= R / d; dy *= R / d; const j = joyEl(); j.style.left = T.joy.x + 'px'; j.style.top = T.joy.y + 'px'; } T.joy.dx = dx / R; T.joy.dy = dy / R; knobEl().style.transform = 'translate(' + dx + 'px,' + dy + 'px)'; }
    if (T.look && e.pointerId === T.look.id) { lookTX += (e.clientX - T.look.x) * .006; lookTY += (e.clientY - T.look.y) * .006; T.look.x = e.clientX; T.look.y = e.clientY; }
  }, { passive: true });
  const tUp = (e) => { if (T.joy && e.pointerId === T.joy.id) { T.joy = null; joyEl().style.display = 'none'; } if (T.look && e.pointerId === T.look.id) T.look = null; };
  addEventListener('pointerup', tUp); addEventListener('pointercancel', tUp);

  const shape = (v, dead, curve) => { const a = Math.abs(v); if (a < dead) return 0; return Math.sign(v) * Math.pow((a - dead) / (1 - dead), curve); };
  let last = performance.now(), keySteer = 0, padLookX = 0, padLookY = 0;

  function poll() {
    const now = performance.now(), dt = Math.min(.1, (now - last) / 1000); last = now;
    let steer = 0, thr = 0, jump = false, boost = false, gear = false, cam = false, phone = false;
    /* keys */
    const kx = (kd('right') ? 1 : 0) - (kd('left') ? 1 : 0); const tk = tune.keys;
    keySteer += (kx - keySteer) * Math.min(1, dt * (kx === 0 ? tk.steerFall : tk.steerRise)); if (Math.abs(keySteer) < .01 && kx === 0) keySteer = 0;
    steer = keySteer; thr = (kd('gas') ? 1 : 0) - (kd('brake') ? 1 : 0);
    jump = kd('jump'); boost = kd('boost'); gear = kd('gear') || mGear; cam = kd('cam'); phone = kd('phone');
    /* gamepad (standard mapping) */
    const pads = navigator.getGamepads ? navigator.getGamepads() : []; padLookX = 0; padLookY = 0;
    for (const p of pads) { if (!p || !p.connected) continue; const tp = tune.pad;
      const lx = shape(p.axes[0] || 0, tp.dead, tp.curve), rx = shape(p.axes[2] || 0, tp.dead, 1), ry = shape(p.axes[3] || 0, tp.dead, 1);
      const rt = p.buttons[7] ? p.buttons[7].value : 0, lt = p.buttons[6] ? p.buttons[6].value : 0, bp = (i) => !!(p.buttons[i] && p.buttons[i].pressed);
      const used = Math.abs(lx) > 0 || rt > .05 || lt > .05 || Math.abs(rx) > 0 || Math.abs(ry) > 0 || p.buttons.some((b) => b.pressed);
      if (used) S.device = 'pad';
      if (Math.abs(lx) > Math.abs(steer)) steer = lx; if (Math.abs(rt - lt) > Math.abs(thr)) thr = rt - lt;
      padLookX = rx; padLookY = ry; jump = jump || bp(0); boost = boost || bp(1) || bp(5); gear = gear || bp(2); cam = cam || bp(3); phone = phone || bp(9); }
    /* touch */
    if (T.joy) { const tt = tune.touch, sx = shape(T.joy.dx, tt.dead, tt.curve), sy = shape(-T.joy.dy, tt.dead, 1); if (Math.abs(sx) > Math.abs(steer)) steer = sx; if (Math.abs(sy) > Math.abs(thr)) thr = sy; }
    for (const k in T.btn) { if (k === 'jump') jump = true; if (k === 'boost') boost = true; if (k === 'gear') gear = true; if (k === 'cam') cam = true; }
    /* look: mouse and touch add up, a held stick sets a rate */
    S.lookX += mdx * tune.mouse.sens + lookTX + padLookX * 2.2 * dt; S.lookY += mdy * tune.mouse.sens + lookTY + padLookY * 1.6 * dt; mdx = mdy = 0; lookTX = lookTY = 0;
    S.lookY = Math.max(-.6, Math.min(.5, S.lookY));
    if (!T.look && !mLook && !document.pointerLockElement && Math.abs(padLookX) < .01 && Math.abs(padLookY) < .01) { S.lookX *= Math.exp(-dt * 2.5); S.lookY *= Math.exp(-dt * 2.5); }          /* look springs back to the road when you let go */
    S.steer = Math.max(-1, Math.min(1, steer)); S.throttle = Math.max(-1, Math.min(1, thr));
    Object.assign(S, { jump, boost, gear, cam, phone });
    for (const b of BTN) { S[b + 'P'] = S[b] && !PREV[b]; PREV[b] = S[b]; }
    return S;
  }
  window.AGINPUT = { state: S, poll, tune, showTouch: (v) => ui.classList.toggle('on', v !== false) };
})();
