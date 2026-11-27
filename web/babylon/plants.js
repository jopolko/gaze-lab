/* THE PLANTS behind the strains (owner 2026-11-27, v2: "simpler, comical and uniquely identifiable; great from a distance and up close").
   Read from far away by SILHOUETTE and COLOUR, close up by the face:
     cacao = a chocolate HEART (brown)            green tea = a TEACUP with a leaf (white + green)
     coffee = a BEAN split by a yellow BOLT        ginger root = a running GINGERBREAD MAN (orange)
     chamomile = a white DAISY                     peppermint = a wrapped red-and-white SWIRL CANDY (bow-tie shape)
     turmeric = a golden PYRAMID heap              chilli = a red CRESCENT with a flame
   Every shape has a thick dark outline so it holds against any sky. The old sticker set is plants.js.bak_v1.
   AGPLANTS.svg(plant) -> an <svg> string, viewBox 0 0 100 100, or '' for an unknown plant. Plant names as in molpantry.js. */
(function () {
  const W = (inner) => '<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg" stroke-linecap="round" stroke-linejoin="round">' + inner + '</svg>';
  const O = '#1a0f14';          /* the outline ink */
  const eyes = (x1, x2, y, r = 3.6) => '<circle cx="' + x1 + '" cy="' + y + '" r="' + r + '" fill="' + O + '"/><circle cx="' + x2 + '" cy="' + y + '" r="' + r + '" fill="' + O + '"/>'
    + '<circle cx="' + (x1 + 1.2) + '" cy="' + (y - 1.3) + '" r="1.2" fill="#fff"/><circle cx="' + (x2 + 1.2) + '" cy="' + (y - 1.3) + '" r="1.2" fill="#fff"/>';
  const P = {
    /* black-market cacao: a chocolate heart, a bite out of the corner, delighted with itself */
    'cacao': W('<path d="M50 88 C22 68 8 52 10 34 C12 18 30 10 42 18 C46 21 48 24 50 28 C52 24 54 21 58 18 C70 10 88 18 90 34 C92 52 78 68 50 88Z" fill="#7a3f1d" stroke="' + O + '" stroke-width="5"/>'
      + ''
      + '<path d="M22 30 C24 22 32 19 38 22" fill="none" stroke="#c98552" stroke-width="5"/>'
      + eyes(38, 62, 46) + '<path d="M40 58 Q50 68 60 58" fill="#3a1608" stroke="' + O + '" stroke-width="3"/>'
      + '<circle cx="31" cy="55" r="4" fill="#ff7aa0" opacity=".75"/><circle cx="69" cy="55" r="4" fill="#ff7aa0" opacity=".75"/>'),
    /* roadside green tea: a white teacup, a big leaf standing up out of it like a flag */
    'green tea': W('<path d="M58 40 C58 22 68 8 84 6 C86 22 78 38 58 40Z" fill="#4fd65a" stroke="' + O + '" stroke-width="4"/><path d="M60 38 C66 28 72 20 80 12" fill="none" stroke="#1f7a2a" stroke-width="2.5"/>'
      + '<path d="M14 44 L86 44 L78 82 Q76 90 66 90 L34 90 Q24 90 22 82Z" fill="#f6f2e6" stroke="' + O + '" stroke-width="5"/>'
      + '<ellipse cx="50" cy="44" rx="36" ry="6" fill="#7ee07a" stroke="' + O + '" stroke-width="4"/>'
      + '<path d="M84 52 C98 52 98 72 80 72" fill="none" stroke="' + O + '" stroke-width="5"/>'
      + eyes(40, 60, 62) + '<path d="M43 72 Q50 77 57 72" fill="none" stroke="' + O + '" stroke-width="3"/>'),
    /* contraband coffee: one fat bean, split down the middle by a lightning bolt instead of a crease; wide awake */
    'coffee': W('<g transform="rotate(-20 50 50)"><ellipse cx="50" cy="50" rx="30" ry="40" fill="#4a2a16" stroke="' + O + '" stroke-width="5"/>'
      + '<path d="M54 8 L40 46 L54 46 L42 92 L66 40 L52 40 L62 8Z" fill="#ffd23a" stroke="' + O + '" stroke-width="3"/></g>'
      + '<circle cx="28" cy="40" r="6.5" fill="#fff" stroke="' + O + '" stroke-width="2.5"/><circle cx="29" cy="40" r="2.8" fill="' + O + '"/>'
      + '<circle cx="70" cy="58" r="6.5" fill="#fff" stroke="' + O + '" stroke-width="2.5"/><circle cx="71" cy="58" r="2.8" fill="' + O + '"/>'),
    /* feral ginger root: escaped as a gingerbread man, mid-sprint */
    'ginger root': W('<g transform="rotate(10 50 50)"><circle cx="50" cy="20" r="14" fill="#e08a3a" stroke="' + O + '" stroke-width="5"/>'
      + '<path d="M38 34 L62 34 L64 60 L80 86 L66 92 L52 70 L46 70 L30 90 L18 82 L36 60 L34 46 L14 52 L10 40 L34 34Z" fill="#e08a3a" stroke="' + O + '" stroke-width="5"/>'
      + '<path d="M66 38 L88 30 L92 42 L64 48" fill="#e08a3a" stroke="' + O + '" stroke-width="5"/>'
      + '<circle cx="50" cy="44" r="2.8" fill="#fff"/><circle cx="50" cy="54" r="2.8" fill="#fff"/>'
      + eyes(45, 56, 18, 2.8) + '<path d="M43 25 Q50 30 57 25" fill="none" stroke="#fff" stroke-width="2.6"/></g>'
      + '<path d="M6 60 L18 60 M4 70 L14 70 M8 50 L16 50" stroke="#ffd9a8" stroke-width="3"/>'),
    /* chamomile: a fat white daisy, dozing */
    'chamomile': W([0, 40, 80, 120, 160, 200, 240, 280, 320].map((a) => '<ellipse cx="50" cy="22" rx="10" ry="17" fill="#fbfaf2" stroke="' + O + '" stroke-width="3.5" transform="rotate(' + a + ' 50 50)"/>').join('')
      + '<circle cx="50" cy="50" r="17" fill="#ffc928" stroke="' + O + '" stroke-width="4"/>'
      + '<path d="M40 48 Q44 52 48 48 M52 48 Q56 52 60 48" fill="none" stroke="' + O + '" stroke-width="2.8"/><path d="M45 57 Q50 60 55 57" fill="none" stroke="' + O + '" stroke-width="2.6"/>'
      + '<text x="76" y="22" font-family="Arial Black,Impact,sans-serif" font-size="13" fill="#b9a6ff" stroke="' + O + '" stroke-width="1">z</text>'),
    /* glacier peppermint: a wrapped swirl candy, red and white, frosty; the wrapper makes a bow tie you can see from a mile off */
    'peppermint': W('<path d="M24 50 L4 34 L8 50 L4 66Z" fill="#d9f6ff" stroke="' + O + '" stroke-width="4"/><path d="M76 50 L96 34 L92 50 L96 66Z" fill="#d9f6ff" stroke="' + O + '" stroke-width="4"/>'
      + '<circle cx="50" cy="50" r="28" fill="#fff" stroke="' + O + '" stroke-width="5"/>'
      + [0, 60, 120, 180, 240, 300].map((a) => '<path d="M50 50 C46 40 44 30 50 22 A28 28 0 0 1 64 25.8 C58 32 54 40 50 50Z" fill="#e8202a" transform="rotate(' + a + ' 50 50)"/>').join('')
      + '<circle cx="50" cy="50" r="28" fill="none" stroke="' + O + '" stroke-width="5"/>'
      + '<circle cx="50" cy="50" r="11" fill="#fff" stroke="' + O + '" stroke-width="3"/>' + eyes(46, 55, 49, 2.2)
      + '<path d="M38 30 Q44 26 50 27" fill="none" stroke="#fff" stroke-width="3.5" opacity=".9"/>'),
    /* tomb-dust turmeric: a golden pyramid of powder (it is from the Tomb), smug */
    'turmeric': W('<path d="M50 10 L92 86 L8 86Z" fill="#ffb81c" stroke="' + O + '" stroke-width="5"/>'
      + '<path d="M50 10 L60 86" stroke="#d98a00" stroke-width="3" fill="none"/><path d="M26 64 L74 64 M36 46 L64 46" stroke="#e8a000" stroke-width="2.5" fill="none"/>'
      + eyes(42, 58, 56, 3.2) + '<path d="M44 70 Q50 74 56 70" fill="none" stroke="' + O + '" stroke-width="3"/>'
      + '<path d="M84 18 L86 24 L92 26 L86 28 L84 34 L82 28 L76 26 L82 24Z" fill="#fff6a8" stroke="' + O + '" stroke-width="1.5"/>'),
    /* server-rack chilli: a red crescent with a green cap, a flame out of the tip, furious */
    'chilli': W('<path d="M70 18 C88 34 84 74 46 90 C30 96 20 88 30 82 C58 70 66 46 56 26Z" fill="#e3201c" stroke="' + O + '" stroke-width="5"/>'
      + '<path d="M56 26 C58 16 66 12 72 16 C76 10 84 12 82 20 C78 24 72 22 70 18Z" fill="#3fd06a" stroke="' + O + '" stroke-width="4"/>'
      + '<path d="M28 84 C18 90 8 84 12 74 C16 80 20 76 18 70 C26 74 30 80 28 84Z" fill="#ffd23a" stroke="' + O + '" stroke-width="3"/>'
      + '<path d="M56 42 L64 46 M70 42 L64 48" stroke="' + O + '" stroke-width="3"/>' + eyes(60, 70, 52, 2.8)
      + '<path d="M54 66 Q62 60 70 64" fill="none" stroke="' + O + '" stroke-width="3"/>'),
  };
  window.AGPLANTS = { svg: (p) => P[String(p || '').toLowerCase()] || '', list: Object.keys(P) };
})();
