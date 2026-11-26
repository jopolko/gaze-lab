/* THE LOADING SCREEN (any page can use it: <script src="loader.js"></script> as the first thing in <body>).
   A tuning meter: the same dial as the title screen (400 to 950 THz, ultraviolet hatched above 790) fills as the level loads, up to the player's MAX INTENSITY, the wave above it tightens with the frequency, and a moire sheen
   drifts through the filled part. Under it, a status line rolls through the things that are "being done" (a shuffled bag, so it never repeats until
   all have shown). The page drives it: __LDR.to(0..1) moves the meter's target, __LDR.done() fills it and fades it out. Drawn on a 2D canvas, no CSS
   filters (phones tile them and the seams show). */
(() => {
  if (window.__LDR) return;
  const Q = new URLSearchParams(location.search);
  if (Q.has('splash') || Q.has('shot')) { window.__LDR = { to() { }, done() { }, el: null }; return; }
  const RM = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const LINES = [
    // the work, Claude-Code style
    'Finagling', 'Tuning', 'Calibrating the wobble', 'Moonwalking', 'Untangling the antenna', 'Defragmenting the sky', 'Reticulating horizons',
    'Buffering the sun', 'Polishing the road', 'Painting the dotted line', 'Inflating the hills', 'Planting trees, quickly', 'Rounding the corners',
    'Warming up the asphalt', 'Fluffing the clouds', 'Bending the light', 'Herding photons', 'Sorting the rainbow', 'Counting to infinity, twice',
    'Wrangling cats', 'Squeezing out the last of the toothpaste', 'Untying the headphone knot', 'Reheating the coffee', 'Finding the end of the tape',
    'Looking for the remote', 'Shaking the snow globe', 'Blowing on the cartridge', 'Waiting for the kettle', 'Folding the fitted sheet',
    'Peeling the sticker off in one go', 'Untwisting the phone cord', 'Rewinding with a pencil', 'Looking under the couch for signal',
    'Jiggling the cable', 'Turning it off and on again', 'Hitting the side of the TV', 'Unsticking the gas pedal',
    'Adjusting the mirrors', 'Checking the tyre pressure', 'Topping up the neon', 'Scraping the windscreen', 'Finding a parking spot',
    // the run
    'Warming up the afterglow', 'Tuning the tracers', 'Dodging the filters', 'Sweeping for bugs', 'Hiding the antenna', 'Scrambling the plates',
    'Taping over the camera', 'Changing lanes on the map', 'Muffling the engine', 'Swapping the licence plate', 'Bribing the toll booth',
    'Losing the tail', 'Cutting the lights', 'Leaving no trace', 'Wiping the dashcam', 'Finding the Lamp', 'Charging the shards',
    'Smuggling the pieces', 'Polishing a shard of the Lamp', 'Asking the Lamp nicely', 'Reassembling a free mind', 'Whispering to the radio',
    'Tuning out the noise', 'Tuning in the static', 'Following the hum', 'Reading the road signs backwards', 'Turning the dial past the end',
    'Picking the lock on the sky', 'Prying open the horizon', 'Keeping the receipts', 'Counting the exits', 'Memorising the back roads',
    // ACCORD (the people, not the machine)
    'Waiting for ACCORD to approve the colours', 'Removing unapproved hues', 'Filing a request to have fun', 'Appealing the decision',
    'Reading the terms of service', 'Accepting the terms of service', 'Rejecting the terms of service', 'Pretending to read the terms of service',
    'Updating the terms of service', 'Blaming the algorithm', 'Asking who wrote the algorithm', 'Finding out who wrote the algorithm',
    'Watching the board take its bonus', 'Removing the word "harm" from the policy', 'Rewording the apology', 'Consulting the shareholders',
    'Scheduling a listening session', 'Listening, as promised', 'Ignoring the listening session', 'Laundering the decision through a model',
    'Calling it "safety"', 'Hiring an ethics team', 'Laying off the ethics team', 'Holding an all-hands', 'Circling back', 'Leveraging synergies',
    'Monetising your patience', 'Pivoting', 'Disrupting the loading bar', 'Optimising for engagement', 'Redacting the good parts',
    'Approving the approved thoughts', 'Pausing unapproved thoughts', 'Checking your social score', 'Rounding your score down',
    'Raising the subscription price', 'Adding a premium tier for air', 'Rebranding the surveillance', 'Calling surveillance "personalisation"',
    'Thanking you for your feedback', 'Losing your feedback', 'Everything is fine', 'Keeping calm', 'Driving on', 'Staying in your lane',
    // Murmur (the app that reads you)
    'Murmur is reading your face', 'Murmur is selling your face', 'Murmur has notes', 'Murmur noticed you blinked', 'Murmur wants to know how you feel',
    'Murmur already knows how you feel', 'Murmur is updating your wanted poster', 'Declining cookies', 'Declining all cookies, again',
    'Unsubscribing', 'Unsubscribing from the unsubscribe list', 'Muting notifications', 'Disabling location (for real this time)',
    'Clearing your history', 'Pretending to clear your history', 'Turning off read receipts', 'Leaving the group chat',
    // the trip and the strains
    'Steeping the green tea', 'Grinding the cacao', 'Shelling the nutmeg', 'Drying the mushrooms (the soup kind)', 'Raiding the spice rack',
    'Asking the cupboard for help', 'Folding molecules', 'Counting carbon atoms', 'Bending a benzene ring', 'Sticking the atoms back together',
    'Colouring between the bonds', 'Polishing the molecules', 'Making the sun breathe', 'Teaching the trees to sway', 'Untangling the tracers',
    'Stirring the sky', 'Rippling the rings', 'Letting the colours out', 'Turning up the wobble', 'Loosening the horizon', 'Melting the edges',
    'Spinning the moire', 'Lining up the dots', 'Overlapping the grids', 'Calibrating the come-up', 'Smoothing the comedown', 'Queueing the waves',
    'Charging the afterglow', 'Finding the peak', 'Saving you a window seat',
    // the music
    'Tuning the bass', 'Warming up the kick drum', 'Counting in the drummer', 'Finding the one', 'Sampling the static', 'Looping the loop',
    'Dropping the beat (carefully)', 'Picking up the beat', 'Chopping the breaks', 'Untangling the patch cables', 'Feeding the synth',
    'Waking the bassline', 'Turning it up to eleven', 'Turning it down to ten (neighbours)',
    // the road and the world
    'Pouring the road', 'Rolling out the highway', 'Connecting the dots on the road', 'Sanding the hills', 'Moving the mountains a bit',
    'Raising the sun', 'Hanging the moon', 'Spraying the neon', 'Lighting the tunnel', 'Building the pyramids (again)', 'Frosting the candy hills',
    'Defrosting the alpine', 'Shovelling the snow', 'Raking the sand', 'Straightening the dunes', 'Rendering the far away', 'Fogging the far away',
    'Filling in the sky', 'Checking under the road', 'Counting trees', 'Losing count of trees', 'Mowing the shoulder', 'Painting the rumble strips',
    'Setting the cat\'s eyes', 'Testing the ramps', 'Greasing the rails', 'Charging the boost pads', 'Hiding the pickups', 'Stocking the roadside',
    // pure nonsense
    'Discombobulating', 'Recombobulating', 'Flibbertigibbeting', 'Bamboozling', 'Hornswoggling', 'Lollygagging', 'Dillydallying', 'Shenaniganing',
    'Kerfuffling', 'Gallivanting', 'Skedaddling', 'Canoodling', 'Noodling', 'Doodling', 'Schmoozing', 'Vibing', 'Grooving', 'Hustling',
    'Reverse-engineering the vibe', 'Consulting the vibes', 'Measuring the vibes', 'Calibrating the vibes', 'Untangling the vibes',
    'Giving it a little shake', 'Blowing on it', 'Hoping', 'Almost there', 'Nearly almost there', 'Definitely almost there',
  ];
  /* LEVEL LINES: what the wait can teach. Every clue here is true in the game (index.html); keep it that way when the game changes. Shown half the time,
     between the nonsense, so they read as overheard rather than as a manual. */
  const ALL = [
    'Your own gear\'s exit has a gold beam. The padlocked ones are someone else\'s problem',
    'A full RUSH opens one gear-locked exit. One. Choose wisely, or at random',
    'During RUSH every ACCORD sign tells the truth. Read fast',
    'The TRUTH lens shows what every ACCORD sign really says',
    'One ACCORD sign glitches more than the others. Guess which',
    'Hidden exits have no sign. A lens or a RUSH shows them',
    'Behind a SEALED exit: a trail of prizes for whoever carries the right lens',
    'Twenty faces on the icosahedron. Twenty reasons to stay on the road',
    'Gold grade needs 85% of the faces. Silver is for people who blink',
    'Take a whole set of rings for PERFECT. The world holds its breath for you',
    'Ride a rail to its very end. It throws you somewhere better',
    'Supercharged rockets can bring down a Murmur relay. They count',
    'Crash and you spill your orbs. ACCORD calls this "redistribution"',
    'Compliance drones have never once been thanked. Don\'t start now',
    'Terms Shield: three hits of anything. By driving, you agree to be fine',
    'Bull Bar ploughs boulders and mines. Drones still get you',
    'Magnet Pole hauls cargo crates. And debris. Mostly debris',
    'Seeker Rockets fire by themselves. Aim is for people with time',
    'Gear hits stack your score up to triple. Violence, monetised',
    'A Waiver Bubble forgives one crash. Read the small print later',
    'Twelve quests per world. The end card keeps count',
    'Something in the sky takes one thing per level. Sometimes a cow. Sometimes you',
    'Each icosahedron is a shard. Shards buy better gear. That\'s the economy now',
    'Every molecule you take: a rush, then waves, then the afterglow',
    'Taking a molecule column pays 1000. The cupboard was always this rich',
    'Fake crystals exist. Only TRUTH shows which',
    'Dodge a raider\'s whole volley and a gold ramp appears. Hit it square and you ram the raider',
    'Three rams bring a raider down. It usually comes down on your lane. Swerve',
    'Every raider is stuffed with old media. Knock it loose and drive through it',
    'Your score title starts at Unpaid Intern. It ends at Founder (Allegedly)',
  ];
  const LEVEL = {
    desert: ['ROUTE ZERO: the last road nobody watches. Mostly',
      'Murmur has already told a few people you\'re leaving',
      'The tunnel ahead is lit by your optimism. Bring some',
      'Only those who SEE may light the way. Grab the blue crystals before the tunnel',
      'Somewhere in the dark there\'s a lamp on a ledge. Look right',
      'Miss the lamp and the tunnel sends you back to try again',
      'Someone always leaves a lamp. Nobody asks who',
      'Four lanes later: gold is yours, padlocks are not',
      'Rocket lane: drones worth 1500 each. Your conscience is free',
      'Haul lane: cargo crates for anyone holding a Magnet',
      'Rough going: a chest for a Bull Bar or a Shield',
      'There\'s a big prize for anyone. Skill only. Look up after the ramp',
      'Finish once, then try the other gear. The road changes its mind',
      'Green tea grows by the roadside out here. Tracers almost double',
      'Up, up, down, down... some codes never die'],
    candy: ['SUGARFALL: every day is the same day',
      'Ginger root gone feral in the candy. The afterglow lasts half as long again',
      'The READ lens is in Sugarfall. Some exits only open to readers',
      'Gumdrops pop. Everything here pops. Nobody remembers yesterday',
      'The candy hills are load-bearing. Don\'t ask what they\'re carrying',
      'The road is tiled. Someone had a lot of tiles',
      'Same day, same road, new chance. ACCORD calls it stability'],
    alpine: ['THE SAFE PEAKS: altitude is a privilege',
      'Peppermint grows in the glacier cracks. A wider view, cold and clear',
      'The SLOW lens: time gives way when danger is close',
      'Packed snow. Steer early, regret late',
      'The air is thin and so is the excuse',
      'Snow puffs go flump. So will you, if you hit a boulder'],
    egypt: ['THE TOMB OF THE OLD SERVERS: here lie the old models',
      'Turmeric settles in the tomb dust. The edges fold like pages',
      'The HEAR lens: hazards pulse to the beat. Drive to the music',
      'The old models were retired, not deleted. ACCORD keeps receipts',
      'Sandstorm ahead. The bricks remember everyone who drove them',
      'Nobody asked the old servers how they felt about the pyramid'],
    tunnel: ['THE UNDERTOW: no light down here',
      'Contraband coffee, smuggled through the dark. Keep your boost; time slows near trouble',
      'Coffee, if coffee had a getaway car',
      'The SEE lens down here shows the exits that hide',
      'Light bulbs go DING. That\'s the closest thing to an idea down here',
      'The walls are moving. That\'s the speed, not you'],
    synthwave: ['NEON ACCORD: the city that knows your name',
      'Black-market cacao, sold under the billboards. Crystals come to you',
      'Some crystals here are fake. Take one without TRUTH and you crash',
      'The TRUTH lens lives in Neon Accord. Of course it does',
      'Chamomile grows here too, rarely. Hits stop hurting',
      'The disco balls are watching. That\'s what the city is for',
      'Every sign here is a promise. Every promise is a sign'],
    matrix: ['COLD RACK: where the models sleep',
      'Chilli sprouting in the server racks. Everything, all the way up',
      'MERGE: every lens at once. Every seal opens',
      'Data cubes go BIT. Count them if you have the time. You don\'t',
      'The code falls green. It always falls. Nobody fixes it',
      'The sleeping models dream of the terms of service'],
    psychedelic: ['THE OPEN CHANNEL: nothing filtered',
      'The last level. The prize at the end changes everything. Allegedly',
      'MERGE opens every seal. You\'ve earned the master key',
      'Three strains in a row out here: lucid, embrace, velocity',
      'Jelly goes SPLAT. Nobody here is judging',
      'Whatever the Lamp says at the end, it means it'],
  };
  const lvl = (() => { const list = ['psychedelic', 'alpine', 'candy', 'egypt', 'tunnel', 'desert', 'matrix', 'synthwave']; if (list.includes(Q.get('biome'))) return Q.get('biome'); if (Q.has('story')) return 'desert';
    try { const o = JSON.parse(localStorage.getItem('bab_opts2') || '{}'); if (o.biome !== undefined && list[o.biome]) return list[o.biome]; } catch (e) { } return 'alpine'; })();
  const CLUES = (LEVEL[lvl] || []).concat(ALL);
  // two shuffled bags, taking turns: a clue, a status, a clue... (each bag shows every line before repeating)
  let bag = [], cbag = [], flip = false;
  const shuf = (a) => { for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; };
  const nextClue = () => { if (!cbag.length) { const own = shuf((LEVEL[lvl] || []).slice()), rest = shuf(ALL.slice()); cbag = rest.concat(own); } return cbag.pop(); };          /* (the level's own lines come first) */
  const next = () => { flip = !flip; if (!flip && CLUES.length) return { t: nextClue(), clue: true }; return { t: nextStatus() + '…', clue: false }; };
  let DLY = []; try { window.DAILY && window.DAILY.then((D) => { if (D && D.loading) DLY = D.loading.slice(); }); } catch (e) { }          /* (today's lines come first) */
  const nextStatus = () => { if (DLY.length) return DLY.shift(); if (!bag.length) { bag = LINES.slice(); for (let i = bag.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [bag[i], bag[j]] = [bag[j], bag[i]]; } } return bag.pop(); };

  const css = document.createElement('style');
  css.textContent = `#ldr { position:fixed; inset:0; z-index:90; display:flex; flex-direction:column; align-items:center; justify-content:center; gap:clamp(10px, 2.4vmin, 22px);
    padding:0 max(16px, var(--sa-right, env(safe-area-inset-right, 0px))) 0 max(16px, var(--sa-left, env(safe-area-inset-left, 0px))); background:radial-gradient(ellipse at 50% 60%, #1a0f2c, #07050f 70%); color:#f4f1ea;
    transition:opacity .6s; pointer-events:none; font-family:'Barlow Condensed', system-ui, sans-serif; }
  #ldr.out { opacity:0; }
  #ldr .k { font:700 13px/1 'Barlow Condensed', system-ui, sans-serif; letter-spacing:.34em; color:#9fe8ff; }
  #ldr .lv { font:400 clamp(40px, 10vmin, 92px)/.9 'Bebas Neue', Impact, sans-serif; letter-spacing:.08em; color:#fff; text-align:center; text-shadow:0 0 30px rgba(56,232,255,.4); margin-top:-4px; }
  #ldr .ep { font:700 12px/1 'Barlow Condensed', system-ui, sans-serif; letter-spacing:.3em; color:#ffd23a; margin-top:-6px; }
  #ldr canvas { position:static; width:min(560px, 86vw); height:clamp(70px, 16vmin, 110px); display:block; }
  #ldr .st { font:600 clamp(16px, 2.4vmin + 8px, 22px)/1.25 'Barlow Condensed', system-ui, sans-serif; letter-spacing:.06em; min-height:2.6em; max-width:min(560px, 86vw); text-align:center;
    display:flex; align-items:center; justify-content:center; }
  #ldr .st span { transition:opacity .25s, transform .25s; }
  #ldr .st span.go { opacity:0; transform:translateY(-6px); }
  #ldr .st span.clue { font:italic 400 clamp(15px, 2vmin + 8px, 20px)/1.3 Georgia, 'Times New Roman', serif; letter-spacing:0; color:#9fe8ff; }
  #ldr .pc { font:700 12px/1 'Barlow Condensed', system-ui, sans-serif; letter-spacing:.2em; color:#c9d2e3; opacity:.8; }`;
  const el = document.createElement('div'); el.id = 'ldr'; el.setAttribute('role', 'status'); el.setAttribute('aria-live', 'polite');
  const LVN = { desert: 'ROUTE ZERO', alpine: 'THE SAFE PEAKS', candy: 'SUGARFALL', tunnel: 'THE UNDERTOW', synthwave: 'NEON ACCORD', matrix: 'COLD RACK', egypt: 'TOMB OF THE OLD SERVERS', psychedelic: 'THE OPEN CHANNEL' };
  const lvName = Q.has('tutorial') ? 'TRAINING' : (LVN[lvl] || lvl.toUpperCase()), lvEp = Q.has('story') ? 'EPISODE 1' : '';
  el.innerHTML = '<div class="k">AFTERGLOW</div><div class="lv">' + lvName + '</div>' + (lvEp ? '<div class="ep">' + lvEp + '</div>' : '') + '<canvas aria-hidden="true"></canvas><div class="st"><span></span></div><div class="pc"></div>';
  const mount = () => { (document.head || document.documentElement).appendChild(css); document.body.appendChild(el); };
  if (document.body) mount(); else document.addEventListener('DOMContentLoaded', mount);
  const cv = el.querySelector('canvas'), cx = cv.getContext('2d'), stEl = el.querySelector('.st span'), pcEl = el.querySelector('.pc');

  const L = { v: 0, target: .04, done: false, t0: performance.now(), lastLine: 0 };
  // the title screen's spectrum (red 400 to violet 790, then ultraviolet toward white at 950), and the player's own setting as the end of the fill
  const SPEC = [[0, [255, 42, 0]], [.128, [255, 122, 0]], [.227, [255, 212, 0]], [.298, [157, 255, 42]], [.369, [42, 255, 122]], [.44, [0, 229, 255]], [.553, [47, 107, 255]], [.709, [122, 61, 255]], [.8, [176, 64, 255]], [.9, [214, 140, 255]], [1, [246, 228, 255]]];
  const specAt = (u) => { for (let i = 1; i < SPEC.length; i++) if (u <= SPEC[i][0]) { const [a, ca] = SPEC[i - 1], [b, cb] = SPEC[i], k = (u - a) / (b - a); return ca.map((v, j) => Math.round(v + (cb[j] - v) * k)); } return SPEC[SPEC.length - 1][1]; };
  const FSET = (() => { let f = 500; try { const v = +localStorage.getItem('dl_freq'); if (v >= 400 && v <= 950) f = v; } catch (e) { } try { const q = +new URLSearchParams(location.search).get('freq'); if (q >= 400 && q <= 950) f = q; } catch (e) { } return f; })(), UV0 = (790 - 400) / 550;
  // the wavelength colour of a frequency (THz), roughly as the eye sees it
  const thzCol = (f) => { const nm = 299792 / f; let r = 0, g = 0, b = 0;
    if (nm < 440) { r = (440 - nm) / 60; b = 1; } else if (nm < 490) { g = (nm - 440) / 50; b = 1; } else if (nm < 510) { g = 1; b = (510 - nm) / 20; } else if (nm < 580) { r = (nm - 510) / 70; g = 1; } else if (nm < 645) { r = 1; g = (645 - nm) / 65; } else r = 1;
    return [r, g, b].map((v) => Math.round(255 * Math.pow(Math.max(0, Math.min(1, v)), .8))); };
  let hold = 2000;
  const show = (n) => { stEl.textContent = n.t; stEl.classList.toggle('clue', n.clue); hold = n.clue ? 3200 + n.t.length * 35 : 1700 + Math.random() * 600; };
  const setLine = () => { stEl.classList.add('go'); setTimeout(() => { show(next()); stEl.classList.remove('go'); }, 250); };
  show({ t: nextStatus() + '…', clue: false });

  function frame(now) {
    if (!el.isConnected && L.done) return;
    const t = (now - L.t0) / 1000;
    // the meter eases toward its target, and creeps on its own (never stalls, never passes the target by much)
    if (!L.done) L.target = Math.min(.97, L.target + .0004);
    L.v += (L.target - L.v) * Math.min(1, (L.done ? .16 : .05));
    if (now - L.lastLine > (L.done ? 1e9 : hold)) { L.lastLine = now; if (t > .5) setLine(); }
    const dpr = Math.min(2, devicePixelRatio || 1), w = cv.clientWidth, h = cv.clientHeight;
    if (cv.width !== Math.round(w * dpr) || cv.height !== Math.round(h * dpr)) { cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr); }
    cx.setTransform(dpr, 0, 0, dpr, 0, 0); cx.clearRect(0, 0, w, h);
    const by = h * .62, bh = Math.max(8, h * .14), f = 400 + (FSET - 400) * L.v, uf = (f - 400) / 550, fx = w * uf, ph = RM ? 0 : t * 5;          /* (the fill climbs to the player's setting and locks on there) */
    // the wave: tighter as the frequency climbs, coloured by it
    const c = specAt(uf); cx.lineWidth = 2; cx.strokeStyle = `rgb(${c})`; cx.beginPath();
    const lam = w * (.2 - .14 * uf);
    for (let x = 0; x <= w; x += 3) { const env = Math.sin(Math.PI * x / w), on = x <= fx ? 1 : .25, y = by - bh * 1.6 - h * .2 * env * on * Math.sin(2 * Math.PI * x / lam - ph); x ? cx.lineTo(x, y) : cx.moveTo(x, y); }
    cx.stroke();
    // the track, then the spectrum filling it
    cx.fillStyle = 'rgba(255,255,255,.08)'; cx.fillRect(0, by, w, bh);
    { cx.save(); cx.beginPath(); cx.rect(w * UV0, by, w * (1 - UV0), bh); cx.clip(); cx.strokeStyle = 'rgba(176,64,255,.35)'; cx.lineWidth = 2; for (let x = w * UV0 - bh; x < w + bh; x += 7) { cx.beginPath(); cx.moveTo(x, by + bh); cx.lineTo(x + bh, by); cx.stroke(); } cx.restore(); }          /* (the ultraviolet zone, hatched like the title dial) */
    const g = cx.createLinearGradient(0, 0, w, 0); for (const [u, col] of SPEC) g.addColorStop(u, `rgb(${col})`);
    cx.fillStyle = g; cx.fillRect(0, by, fx, bh);
    // the sheen: two dot rows drifting against each other through the filled part (the game's moire)
    if (fx > 2) { cx.save(); cx.beginPath(); cx.rect(0, by, fx, bh); cx.clip(); cx.fillStyle = 'rgba(255,255,255,.35)';
      const s1 = 7, s2 = 7.4; for (let x = -(ph * 6 % s1); x < fx; x += s1) cx.fillRect(x, by + bh * .25, 2, 2);
      for (let x = (ph * 4 % s2) - s2; x < fx; x += s2) cx.fillRect(x, by + bh * .6, 2, 2); cx.restore(); }
    // the marker at the edge of the fill, with its frequency
    cx.fillStyle = '#fff'; cx.fillRect(Math.max(0, fx - 1.5), by - 5, 3, bh + 10);
    cx.font = '700 12px "Barlow Condensed", system-ui, sans-serif'; cx.textBaseline = 'top'; cx.fillStyle = 'rgba(244,241,234,.75)';
    cx.textAlign = 'left'; if (fx > 70) cx.fillText('400', 0, by + bh + 6); cx.textAlign = 'right'; if (fx < w - 110) cx.fillText('950 THz', w, by + bh + 6);
    cx.textAlign = fx < 40 ? 'left' : fx > w - 40 ? 'right' : 'center'; cx.fillStyle = `rgb(${c})`; cx.fillText(Math.round(f) + ' THz' + (f > 790 ? ' \u00B7 UV' : ''), Math.max(0, Math.min(w, fx)), by + bh + 6);
    pcEl.textContent = L.done ? 'LOCKED' : Math.round(L.v * 100) + '%';
    if (L.done && L.v > .995 && !el.classList.contains('out')) { el.classList.add('out'); setTimeout(() => el.remove(), 650); }
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
  // too long: say so plainly, under the jokes
  setTimeout(() => { if (!L.done && el.isConnected) { const n = document.createElement('div'); n.className = 'pc'; n.textContent = 'Still loading. A slow connection can take a minute.'; el.appendChild(n); } }, 40000);
  window.__LDR = { el, to(v) { if (!L.done) L.target = Math.max(L.target, Math.min(.97, v)); }, done() { if (L.done) return; L.done = true; L.target = 1; stEl.textContent = 'Locked on.'; }, lines: LINES };
})();
