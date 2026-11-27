/* THE PLANTS behind the strains (owner 2026-11-26: "cool and funny, fitting the theme, not the same leaf in different colours").
   Each strain's plant as a small neon icon, one joke each. Used beside the molecule on strain cards (the intro's tags, the game's strain cards).
   AGPLANTS.svg(plant) -> an <svg> string, viewBox 0 0 100 100, or '' for an unknown plant. Plant names as in molpantry.js. */
(function () {
  const W = (inner) => '<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg" stroke-linecap="round" stroke-linejoin="round">' + inner + '</svg>';
  const P = {
    /* black-market cacao: a ribbed pod, sealed with evidence tape, barcoded */
    'cacao': W('<ellipse cx="50" cy="50" rx="22" ry="36" fill="#3a1d10" stroke="#d98b3a" stroke-width="3"/>'
      + '<path d="M50 15 Q41 50 50 85 M50 15 Q59 50 50 85 M37 22 Q30 50 37 78 M63 22 Q70 50 63 78" fill="none" stroke="#8a4a1e" stroke-width="2.2"/>'
      + '<g transform="rotate(-24 50 50)"><rect x="18" y="43" width="64" height="12" fill="#ffd23a"/><text x="50" y="52.5" font-family="Arial Black,Impact,sans-serif" font-size="8.5" text-anchor="middle" fill="#120a04" letter-spacing="1">SEIZED</text></g>'
      + '<g fill="#e8e2d6">' + [0, 3, 5, 6, 9, 11, 12, 15].map((x, i) => '<rect x="' + (38 + x * 1.5) + '" y="74" width="' + (i % 3 ? 1 : 2) + '" height="7"/>').join('') + '</g>'),
    /* roadside green tea: leaves breaking up through cracked asphalt, a traffic cone beside them */
    'green tea': W('<rect x="6" y="70" width="88" height="22" rx="2" fill="#2a2730"/><rect x="58" y="80" width="18" height="3" fill="#ffd23a"/>'
      + '<path d="M38 70 L44 78 L40 86 M44 78 L52 74" fill="none" stroke="#0d0c10" stroke-width="2.5"/>'
      + '<path d="M44 72 C30 60 26 42 36 28 C44 40 48 56 44 72Z" fill="#1f5a2a" stroke="#6dff8a" stroke-width="2.5"/><path d="M44 72 C56 58 66 46 64 30 C52 38 46 54 44 72Z" fill="#1f5a2a" stroke="#6dff8a" stroke-width="2.5"/>'
      + '<path d="M44 70 L37 34 M44 70 L61 36" fill="none" stroke="#6dff8a" stroke-width="1.3" opacity=".7"/>'
      + '<path d="M74 70 L80 44 L86 70Z" fill="#ff7a1a" stroke="#ffb14a" stroke-width="1.5"/><path d="M76.5 60 L83.5 60" stroke="#f2efe6" stroke-width="3"/><rect x="70" y="68" width="20" height="4" fill="#ff7a1a"/>'),
    /* coffee: a branch of cherries on jumper cables to a car battery */
    'coffee': W('<path d="M14 30 Q36 22 58 30" fill="none" stroke="#7a4a22" stroke-width="4"/><path d="M26 27 C20 16 30 12 34 22Z M46 25 C46 13 56 13 54 25Z" fill="#1f5a2a" stroke="#6dff8a" stroke-width="2"/>'
      + '<circle cx="30" cy="40" r="7" fill="#c8202a" stroke="#ff6a5a" stroke-width="2"/><circle cx="44" cy="42" r="7" fill="#c8202a" stroke="#ff6a5a" stroke-width="2"/>'
      + '<path d="M30 47 Q32 66 52 70 M44 49 Q50 60 70 66" fill="none" stroke-width="2.5" stroke="#e8283a"/><path d="M44 49 Q50 60 70 66" fill="none" stroke-width="2.5" stroke="#15151a"/>'
      + '<rect x="50" y="64" width="40" height="26" rx="3" fill="#1d1f29" stroke="#8a90a6" stroke-width="2"/><rect x="54" y="60" width="7" height="5" fill="#e8283a"/><rect x="78" y="60" width="7" height="5" fill="#8a90a6"/>'
      + '<path d="M71 68 L64 78 L70 78 L66 87 L76 75 L70 75 L74 68Z" fill="#ffd23a"/>'),
    /* ginger root, unsettled: a knobbly root that has grown legs and is running, sweating */
    'ginger root': W('<path d="M30 52 C24 40 34 30 44 36 C48 26 62 26 64 38 C74 36 80 48 70 54 C72 64 58 68 52 60 C44 68 30 64 30 52Z" fill="#c9954a" stroke="#ffd27a" stroke-width="2.5"/>'
      + '<path d="M42 40 C44 44 48 44 50 40 M58 40 L62 44" fill="none" stroke="#7a5420" stroke-width="1.6"/>'
      + '<circle cx="47" cy="47" r="2.4" fill="#120a04"/><circle cx="57" cy="47" r="2.4" fill="#120a04"/><path d="M48 55 Q52 52 56 55" fill="none" stroke="#120a04" stroke-width="2"/>'
      + '<path d="M44 62 L36 76 L28 74 M58 62 L64 78 L72 76" fill="none" stroke="#c9954a" stroke-width="4"/><path d="M30 50 L18 44 M72 50 L84 40" fill="none" stroke="#c9954a" stroke-width="3.5"/>'
      + '<path d="M78 28 Q80 32 78 34 Q76 32 78 28Z M84 34 Q86 38 84 40 Q82 38 84 34Z" fill="#9fe8ff"/><path d="M8 60 L16 60 M6 68 L16 67 M10 76 L20 74" stroke="#9fe8ff" stroke-width="2" opacity=".7"/>'),
    /* chamomile, but it means it: a daisy dozing off */
    'chamomile': W('<path d="M50 66 Q48 82 52 94" fill="none" stroke="#6dff8a" stroke-width="3"/>'
      + Array.from({ length: 12 }, (_, i) => '<ellipse cx="50" cy="22" rx="6" ry="14" fill="#f4f1ea" stroke="#c9c4d6" stroke-width="1" transform="rotate(' + i * 30 + ' 50 44)"/>').join('')
      + '<circle cx="50" cy="44" r="13" fill="#ffc72a" stroke="#ffe48a" stroke-width="2"/><path d="M43 43 Q45.5 46 48 43 M52 43 Q54.5 46 57 43" fill="none" stroke="#5a3a0a" stroke-width="2"/><path d="M47 50 Q50 52 53 50" fill="none" stroke="#5a3a0a" stroke-width="1.6"/>'
      + '<text x="72" y="20" font-family="Arial Black,Impact,sans-serif" font-size="11" fill="#b48cff">z</text><text x="80" y="11" font-family="Arial Black,Impact,sans-serif" font-size="8" fill="#b48cff">z</text>'),
    /* peppermint, cold enough to see through: a mint leaf in sunglasses, frost sparkling */
    'peppermint': W('<path d="M50 90 C20 72 18 34 50 10 C82 34 80 72 50 90Z" fill="#1f6a4a" stroke="#7dffc8" stroke-width="2.5"/>'
      + '<path d="M50 88 L50 16 M50 64 L34 52 M50 64 L66 52 M50 44 L38 34 M50 44 L62 34" fill="none" stroke="#7dffc8" stroke-width="1.4" opacity=".8"/>'
      + '<path d="M30 42 L70 42 L67 52 Q60 56 54 50 L46 50 Q40 56 33 52Z" fill="#0b0b12" stroke="#9fe8ff" stroke-width="1.5"/><path d="M36 45 L42 45" stroke="#9fe8ff" stroke-width="1.5"/>'
      + '<path d="M80 18 L80 30 M74 24 L86 24 M76 20 L84 28 M84 20 L76 28" stroke="#e8f8ff" stroke-width="1.8"/><path d="M16 64 L16 72 M12 68 L20 68" stroke="#e8f8ff" stroke-width="1.6"/>'),
    /* turmeric: a golden root glowing like a reactor rod */
    'turmeric': W('<circle cx="50" cy="50" r="40" fill="#ffb81f" opacity=".12"/>'
      + '<path d="M22 66 C18 54 30 46 40 50 C44 38 62 36 66 48 C78 44 86 58 76 66 C70 74 30 76 22 66Z" fill="#e89a10" stroke="#ffd23a" stroke-width="3"/>'
      + '<path d="M34 58 C38 56 42 58 46 56 M58 54 C62 56 66 54 70 56" fill="none" stroke="#a86a08" stroke-width="2"/>'
      + '<g transform="translate(50 28)"><circle r="12" fill="#ffd23a" stroke="#120a04" stroke-width="2"/><circle r="2.6" fill="#120a04"/>'
      + [0, 120, 240].map((a) => '<path d="M0 -4 L-5 -10.5 A11 11 0 0 1 5 -10.5Z" fill="#120a04" transform="rotate(' + a + ')"/>').join('') + '</g>'),
    /* chilli that bites from the inside: a chilli pepper as a rocket */
    'chilli': W('<g transform="rotate(-38 50 50)"><path d="M50 8 C62 20 62 60 52 80 C48 84 44 80 46 74 C40 50 40 22 50 8Z" fill="#d8201a" stroke="#ff6a4a" stroke-width="2.5"/>'
      + '<path d="M47 10 C46 4 52 2 54 6" fill="none" stroke="#3fd06a" stroke-width="4"/><path d="M42 62 L34 74 L44 70Z M56 62 L64 72 L54 70Z" fill="#8a8f9e"/>'
      + '<path d="M44 84 Q49 104 54 84 Q49 92 44 84Z" fill="#ffd23a"/><path d="M46 84 Q49 96 52 84Z" fill="#ff7a1a"/><circle cx="51" cy="30" r="4" fill="#9fe8ff" stroke="#f4f1ea" stroke-width="1.5"/></g>'),
  };
  window.AGPLANTS = { svg: (p) => P[String(p || '').toLowerCase()] || '', list: Object.keys(P) };
})();
