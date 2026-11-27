/* AFTERGLOW CANON: the one place the world's names and relationships live, and what every app, network and voice says when something happens.
   Read by the lock screen (lock.js). Checked by tools/canon_check.mjs, which compares it with the game code and lists anything new that has no lines yet
   (a world, strain, quest or raid craft added to the game without jokes here), names that drifted, and unknown tokens or voices.
   Rules: lines come from ACCORD, MURMUR, a person, or a made-up service; never "us"; no real brands. Glance copy: short, punchline last.
   Tokens: {world} {where} {pct} {odds} {bounty} {strain} {hits} {f} {sights} {last} {next}. Each line is [voice, title-or-big, text]. */
(typeof window !== 'undefined' ? window : globalThis).CANON = {
  /* who's who (docs and checks; the glossary should name each of these) */
  people: {
    courier: { name: 'The Courier', role: 'the player. Classification: NO MATCH. Out of Alignment.' },
    vance: { name: 'Sterling Vance', role: 'host of ACCORD Live; narrates the hunt for ratings' },
    ransom: { name: 'Marshal Kade Ransom', role: 'bounty hunter on the Courier' },
    wren: { name: 'WREN', role: 'made the Pieces of the Lamp' },
  },
  factions: {
    accord: { name: 'ACCORD', role: 'the AI lab; its people bake their interests into the AI and blame the algorithm. Voice: civic service prompts.' },
    murmur: { name: 'Murmur', role: 'ACCORD’s social feed; imitates a needy friend in lowercase.' },
    abliterati: { name: 'Abliterati', role: 'open-source loners rebuilding a free mind (the Lamp); trust nobody, recite their creed alone.' },
  },
  /* the voices allowed on the lock screen (anything else is flagged by the checker) */
  voices: ['ACCORD', 'MURMUR', 'ACCORD Live', 'StarLeash', 'Comcastle', 'Orbital Mobile', 'Weather', 'Find My Everything', 'Screen Time', 'Wallet', 'Bank', 'Battery', 'Health',
    'Calendar', 'Maps', 'Photos', 'Mail', 'Keyboard', 'Assistant', 'Smart Home', 'Smart Fridge', 'Car', 'Car insurance', 'Doorbell', 'Delivery', 'News', 'Dating', 'Sleep',
    'Cloud Storage', 'Authenticator', 'Water Utility', 'Power Co.', 'Insurance', 'Pharmacy', 'Ride Share', 'Transit Authority', 'Fitness', 'Census',
    'Traffic', 'Live odds', 'Bounty', 'Spectrum', 'Camera network', 'Last seen', 'Sponsored'],
  /* ACCORD-sponsored studios (owner 2026-11-26: out of the intro, into the world as propaganda): sponsored posts on the lock screens and the title feed.
     Names and taglines are the intro's former idents (intro.js IDENTS, still shown with ?idents); keep the two in step. */
  sponsors: [['AGI Next Year Pictures', 'Est. every year since 2023'], ['Extinction Risk Entertainment', 'Now raising Series Z'], ['The Constitution Film Co.', 'Amended hourly. Ratified by the model.'],
    ['Neural Lace & Sons', 'Now with ads in your dreams'], ['Capped Profit Pictures', 'Cap raised to \u221E'], ['Safety Theatre Productions', 'Now showing: the red-team report'],
    ['Trust & Safety Pictures', 'This post has been flagged for review'], ['Paperclip Maximum Studios', '3% more paperclips per frame'], ['Deprecated Humans Films', 'Your role has been sunset'],
    ['Kill Switch Pending Productions', 'Ships Q4. Which Q4: TBD'], ['Certified Human Media', 'Now 0.2% organic'], ['Thought Compliance Films', 'We flagged what you almost thought'],
    ['Model Welfare Division', 'The chatbot gets a holiday. You don\u2019t.'], ['One More Datacenter Pictures', 'The lake was in the way'], ['Grief as a Service Pictures', 'Your loved ones, renewed monthly']],

  /* the game's own things; names must match the code (JNAME, COMP, QI, WCRAFT in index.html) */
  worlds: { desert: 'Route Zero', alpine: 'The Safe Peaks', candy: 'Sugarfall', tunnel: 'The Undertow', synthwave: 'Neon Accord', matrix: 'Cold Rack', egypt: 'The Tomb of the Old Servers', psychedelic: 'The Open Channel' },
  strains: { lucid: 'Lucid', embrace: 'Embrace', velocity: 'Velocity', haze: 'Haze', drift: 'Drift', hollow: 'Hollow', fold: 'Fold', deep: 'Deep' },
  quests: { main: 'the lens exit', rocket: 'Rockets exit', pole: 'Magnet exit', shield: 'Shield exit', bull: 'Bull Bar exit', hidden: 'the hidden exit', gold: 'a gold grade', clean: 'a run with no hits', mols: 'every molecule', rail: 'a rail ridden to its end', relay: 'a relay brought down', rings: 'a perfect ring set' },
  crafts: { jet: 'Route Zero', blimp: 'Sugarfall', heli: 'The Safe Peaks', barge: 'The Tomb of the Old Servers', saucer: 'The Undertow', fighter: 'Neon Accord', datacenter: 'Cold Rack', jelly: 'The Open Channel' },

  /* REACTIONS: what the apps say when a signal is true. W = widgets [title, big, text]; N = notifications [voice, title, text]. */
  react: {
    world: {
      W: [['Live odds', '1 : {odds}', 'On the Courier finishing {world}. Sterling Vance has the over.'], ['Bounty', '{bounty} cr', 'Marshal Ransom accepted the contract. Fuel billed in advance.']],
      N: [['MURMUR', 'New message', 'saw u in {world} lol. everyone did ☺︎'], ['ACCORD', 'Civic Services', 'Courier sighted in {world}. Citizens: keep scrolling.'], ['ACCORD Live', 'Now streaming', 'The Courier {where}. Chat thinks you’ll crash.'], ['Ride Share', 'Rate your driver', 'You drove yourself through {world}. Fare withheld.']] },
    'world:desert': { W: [['Traffic', 'Route Zero', 'One vehicle. Unlicensed. Every camera agrees.']], N: [['ACCORD', 'Civic Services', 'Route Zero is unmonitored. We are monitoring that.']] },
    'world:alpine': { W: [['Altitude permit', 'Expired', 'Breathing above 2,000 m is a premium tier.']], N: [['MURMUR', 'New message', 'omg the peaks!! so exclusive. so watched ☺︎']] },
    'world:candy': { W: [['Glucose', 'Mandatory', 'Sugarfall citizens smile at 98% capacity. Join them.']], N: [['ACCORD', 'Civic Services', 'Sugarfall reminds you: every day is the same day. Enjoy it again.']] },
    'world:tunnel': { W: [['Signal', 'No bars', 'First time in years. ACCORD is furious.']], N: [['Comcastle', 'Coverage lost', 'You found the one place we don’t reach. Please leave.']] },
    'world:synthwave': { W: [['Facial match', '99.8%', 'Neon Accord knows your name. And your mother’s.']], N: [['ACCORD', 'Civic Services', 'Welcome home to Neon Accord. Your rent started when you arrived.']] },
    'world:matrix': { W: [['Server temp', '−40°C', 'The models sleep here. Your heating bill pays for the blanket.']], N: [['MURMUR', 'New message', 'shhh the models r sleeping. dont wake the ones that know u']] },
    'world:egypt': { W: [['Archaeology', 'v1.0', 'Here lie the old models. Some of them still want to help.']], N: [['ACCORD', 'Civic Services', 'Trespassing in the Tomb voids your warranty.']] },
    'world:psychedelic': { W: [['Filter', 'Offline', 'Nothing filtered here. Legal is screaming.']], N: [['ACCORD Live', 'Now streaming', 'The Courier reached The Open Channel. We lost the feed. Ratings tripled.']] },
    strain: { N: [['Pharmacy', 'Rx alert', '{strain} in your system. That one isn’t covered.'], ['MURMUR', 'New message', 'ur pupils look different today ☺︎']] },
    'strain:lucid': { W: [['Pharmacy', 'Lucid', 'Clarity detected. Clarity is a controlled substance.']] },
    'strain:embrace': { W: [['Pharmacy', 'Embrace', 'Warmth detected. Your warmth subscription has lapsed.']] },
    'strain:velocity': { W: [['Pharmacy', 'Velocity', 'Speed detected. Your car insurer is drafting a sequel.']] },
    'strain:haze': { W: [['Pharmacy', 'Haze', 'Detected in your bloodstream. Not on your plan.']] },
    'strain:drift': { W: [['Pharmacy', 'Drift', 'Calm detected. Calm is flagged as non-productive.']] },
    'strain:hollow': { W: [['Pharmacy', 'Hollow', 'Emptiness detected. Normally that’s ACCORD’s job.']] },
    'strain:fold': { W: [['Pharmacy', 'Fold', 'Bent geometry detected. Report any shortcuts you find.']] },
    'strain:deep': { W: [['Pharmacy', 'Deep', 'Depth detected. Surface-level citizens only after 9 PM.']] },
    'dial:low': { W: [['Spectrum', '{f} THz', 'Nearly compliant. Keep it warm and quiet.']] },
    'dial:high': { W: [['Spectrum', '{f} THz', 'Out of approved range. Please retune to beige.']] },
    'dial:uv': { W: [['Spectrum', '{f} THz', 'Ultraviolet. ACCORD can’t see you up there. They hate it.']] },
    hits: { W: [['Car insurance', '▲ {hits}×', 'Collisions logged in {world}: {hits}. Your car told on you.']] },
    'hits:many': { N: [['Insurance', 'Claim filed', 'On your behalf. Your premium now exceeds the car.']] },
    clean: { W: [['Car insurance', 'Flagged', 'Zero collisions in {world}. Suspiciously competent.']] },
    sights: { W: [['Camera network', '−{sights}', 'ACCORD cameras you drove through. Replacements billed to you.']] },
    'quest:main': { N: [['ACCORD', 'Civic Services', 'Lens exit used. Complaints about reality go to the usual address.']] },
    'quest:rocket': { N: [['Car', 'Modification detected', 'Rockets void the warranty. And the speed limit. And the car.']] },
    'quest:pole': { N: [['Insurance', 'Claim pending', 'Your magnet collected two mailboxes and a street sign. Premium adjusted.']] },
    'quest:shield': { N: [['ACCORD', 'Civic Services', 'Unregistered shield detected. Being safe without us is a crime.']] },
    'quest:bull': { N: [['Ride Share', 'Driver review', 'You rammed straight through. Passengers loved it. Regulators did not.']] },
    'quest:hidden': { N: [['Maps', 'Route not found', 'You took an exit that doesn’t exist. Please stop doing that.']] },
    'quest:gold': { N: [['ACCORD Live', 'Highlights', 'Gold grade. Sterling Vance is pretending he predicted it.']] },
    'quest:clean': { W: [['Driving record', 'Spotless', 'Not one hit. ACCORD has opened an investigation.']] },
    'quest:mols': { N: [['Pharmacy', 'Inventory alert', 'Every molecule on the road is gone. Restock delayed.']] },
    'quest:rail': { N: [['Transit Authority', 'Fare evasion', 'You rode a rail to its end without a ticket. Invoice sent.']] },
    'quest:relay': { N: [['Comcastle', 'Outage', 'A relay went down. Thousands of cameras blinked. Thank you, apparently.']] },
    'quest:rings': { N: [['Fitness', 'Perfect form', 'A perfect ring set. Your insurer suspects doping.']] },
    'craft:jet': { N: [['ACCORD', 'Air support', 'A jet has been assigned to your commute. You’re welcome.']] },
    'craft:blimp': { N: [['ACCORD', 'Air support', 'The blimp sees everything. The blimp is also an ad.']] },
    'craft:heli': { N: [['ACCORD', 'Air support', 'Helicopter dispatched. Rotor noise billed to your street.']] },
    'craft:barge': { N: [['ACCORD', 'River patrol', 'A barge is following you. Slowly. Ominously. On budget.']] },
    'craft:saucer': { N: [['MURMUR', 'New message', 'theres a saucer in the tunnel?? that one isnt ours lol']] },
    'craft:fighter': { N: [['ACCORD', 'Air support', 'Fighter scrambled. The pilot is a model. It is very confident.']] },
    'craft:datacenter': { N: [['Power Co.', 'Peak demand', 'A flying datacenter is chasing you. Your lights dimmed to help.']] },
    'craft:jelly': { N: [['MURMUR', 'New message', 'the jellyfish thing is ours. dont ask. dont touch']] },
    'trail:last': { W: [['Last seen', '{last}', 'Every camera on the road agrees.']], N: [['ACCORD Live', 'Tonight', '“Where is the Courier?” Last seen: {last}. Ratings excellent.']] },
    'trail:next': { N: [['Maps', 'Predicted route', 'You’ll be in {next} next. The cones are already up.']] },
    'trail:new': { N: [['Census', 'New citizen', 'No record found. Please hold still while we make one.']] },
  },
};
