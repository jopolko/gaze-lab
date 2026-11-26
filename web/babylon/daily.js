/* THE DAILY FREQUENCY: one fresh line a day in the places the eye already goes (title screen, the intro's Murmur message, the first ACCORD sign,
   the loading screen, the pause menu). Lines live in daily.json; the date picks them, so everyone sees the same line on the same day, and a dated
   entry for today wins. window.DAILY is a promise of { day, title, murmur, sign: [slogan, truth], loading: [..] }; it never rejects (null if offline). */
(() => {
  if (window.DAILY) return;
  const d = new Date(), ymd = d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'),
    dn = Math.floor(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) / 864e5), at = (a, k) => (a && a.length ? a[(dn * k) % a.length] : null);
  window.DAILY = fetch('daily.json?d=' + ymd, { cache: 'no-cache' }).then((r) => (r.ok ? r.json() : null)).then((J) => { if (!J) return null; const x = (J.dated && J.dated[ymd]) || {};
    const pool = J.loading || [], lo = [at(pool, 7), at(pool, 11)].filter(Boolean);
    return { day: ymd, launch: J.launch || [], dated: x.title || null, title: x.title || at(J.title, 1), murmur: x.murmur || at(J.murmur, 3), sign: x.sign || at(J.sign, 5), loading: (x.loading || []).concat(lo) }; }).catch(() => null);
})();
