# MAKE PANTRY: the wild strains (ball-and-stick, heavy atoms only, angstroms) -> molpantry.js
#   python tools/make_pantry.py
# Each strain is a kitchen-cupboard molecule (caffeine, theobromine, L-theanine, apigenin, gingerol, curcumin, menthol, capsaicin) drawn from its real connectivity
# with standard bond lengths, plus ONE fictional mutation (flagged atoms, drawn lit in the game). The mutated strains are made up: not real compounds.
import math, json, os
here = os.path.dirname(os.path.abspath(__file__)); OUT = os.path.join(os.path.dirname(here), 'molpantry.js')
BL = 1.4

class Mol:
    def __init__(s): s.a = []; s.b = []; s.mut = set()
    def mark(s, *ids): s.mut.update(ids); return ids[-1]
    def at(s, el, x, y, z=0.0): s.a.append([el, x, y, z]); return len(s.a) - 1
    def bond(s, i, j, o=1): s.b.append([i, j, o])
    def pos(s, i): return s.a[i][1], s.a[i][2]
    def sub(s, i, el, ang, o=1, L=BL):          # an atom bonded to i, at angle ang (degrees)
        x, y = s.pos(i); j = s.at(el, x + L * math.cos(math.radians(ang)), y + L * math.sin(math.radians(ang))); s.bond(i, j, o); return j
    def chain(s, i, els, ang0, orders=None):          # a zigzag chain from atom i
        cur, ang = i, ang0; out = []
        for k, el in enumerate(els):
            cur = s.sub(cur, el, ang, (orders or [1] * len(els))[k]); out.append(cur); ang += -60 if k % 2 == 0 else 60
        return out

def ring(m, n, cx, cy, rot, els, orders):
    r = BL / (2 * math.sin(math.pi / n)); ids = []
    for k in range(n):
        a = math.radians(rot + 360 * k / n); ids.append(m.at(els[k], cx + r * math.cos(a), cy + r * math.sin(a)))
    for k in range(n): m.bond(ids[k], ids[(k + 1) % n], orders[k])
    return ids
def outward(m, ids, k, cx, cy):          # the angle pointing away from a ring's centre at atom k
    x, y = m.pos(ids[k]); return math.degrees(math.atan2(y - cy, x - cx))
def benzene(m, cx, cy, rot=0): return ring(m, 6, cx, cy, rot, ['C'] * 6, [2, 1, 2, 1, 2, 1])
def vanillyl(m, cx, cy, rot=0):          # 4-hydroxy-3-methoxyphenyl
    r = benzene(m, cx, cy, rot); m.sub(r[3], 'O', outward(m, r, 3, cx, cy)); m2 = m.sub(r[2], 'O', outward(m, r, 2, cx, cy)); m.sub(m2, 'C', outward(m, r, 2, cx, cy) + 60); return r
def away(m, i):          # the angle pointing away from all of atom i's bonds
    x, y = m.pos(i); vs = []
    for a, b, _ in m.b:
        j = b if a == i else a if b == i else None
        if j is not None: jx, jy = m.pos(j); d = math.hypot(jx - x, jy - y) or 1; vs.append(((jx - x) / d, (jy - y) / d))
    sx, sy = sum(v[0] for v in vs), sum(v[1] for v in vs)
    return math.degrees(math.atan2(-sy, -sx)) if math.hypot(sx, sy) > 1e-3 else 90
def side(m, i, el, o=1, L=BL): return m.sub(i, el, away(m, i), o, L)          # a side group on a chain atom (the outside of the zigzag)
def spiro(m, i):          # a three-ring on atom i (the "spiro" mutation)
    ang = away(m, i); p = m.sub(i, 'C', ang + 30); q = m.sub(i, 'C', ang - 30); m.bond(p, q); return m.mark(p, q)

def theanine():          # 4R-Hydroxytheanine: an OH on the gamma carbon
    m = Mol(); c0 = m.at('C', 0, 0); ch = m.chain(c0, ['C', 'C', 'C', 'C', 'N', 'C', 'C'], 0)
    side(m, ch[0], 'N'); side(m, ch[3], 'O', 2); m.sub(c0, 'O', 150, 2); m.sub(c0, 'O', 210)
    m.mark(side(m, ch[2], 'O'))
    return m
def xanthine(methyl1, vinyl3=False, oxa8=False, prenyl7=False):          # caffeine (methyl1) / theobromine, with the strains' mutations
    m = Mol(); cx, cy = 0, 0
    six = ring(m, 6, cx, cy, 30, ['N', 'C', 'N', 'C', 'C', 'C'], [1, 1, 1, 2, 1, 1])          # N1 C2 N3 C4 C5 C6
    x4, y4 = m.pos(six[3]); x5, y5 = m.pos(six[4]); mx, my = (x4 + x5) / 2, (y4 + y5) / 2; ox, oy = mx - cx, my - cy; d = math.hypot(ox, oy); ux, uy = ox / d, oy / d
    r5 = BL / (2 * math.sin(math.pi / 5)); ap = r5 * math.cos(math.pi / 5); c5x, c5y = mx + ux * ap, my + uy * ap
    base = math.degrees(math.atan2(y4 - c5y, x4 - c5x)); ids = [six[3], six[4]]
    for k in (1, 2, 3):
        a = math.radians(base - 72 * (k + 1)); ids.append(m.at(['N', 'O' if (oxa8 and k == 2) else 'C', 'N'][k - 1], c5x + r5 * math.cos(a), c5y + r5 * math.sin(a)))
    if oxa8: m.mark(ids[3])
    m.bond(six[4], ids[2], 1); m.bond(ids[2], ids[3], 1 if oxa8 else 2); m.bond(ids[3], ids[4], 1); m.bond(ids[4], six[3], 1)
    m.sub(six[1], 'O', outward(m, six, 1, cx, cy), 2); m.sub(six[5], 'O', outward(m, six, 5, cx, cy), 2)
    if methyl1: m.sub(six[0], 'C', outward(m, six, 0, cx, cy))
    a3 = outward(m, six, 2, cx, cy); c3 = m.sub(six[2], 'C', a3)
    if vinyl3: m.mark(m.sub(c3, 'C', a3 - 60, 2))
    x7, y7 = m.pos(ids[2]); a7 = math.degrees(math.atan2(y7 - c5y, x7 - c5x)); c7 = m.sub(ids[2], 'C', a7)
    if prenyl7: p1 = m.sub(c7, 'C', a7 + 60); p2 = m.sub(p1, 'C', a7, 2); m.mark(p1, p2, m.sub(p2, 'C', a7 + 60), m.sub(p2, 'C', a7 - 60))
    return m
def apigenin():          # 3'-Ethynylapigenin: a C-C triple bond on the B ring
    m = Mol(); A = benzene(m, 0, 0, 30)
    r = BL; cx = math.sqrt(3) * BL; P = lambda a: (cx + r * math.cos(math.radians(a)), r * math.sin(math.radians(a)))
    c4 = m.at('C', *P(90)); c3 = m.at('C', *P(30)); c2 = m.at('C', *P(330)); o1 = m.at('O', *P(270))
    m.bond(A[0], c4); m.bond(c4, c3); m.bond(c3, c2, 2); m.bond(c2, o1); m.bond(o1, A[5])
    m.sub(c4, 'O', 90, 2)          # the ketone
    x2, y2 = m.pos(c2); bx, by = x2 + BL * math.cos(math.radians(-30)) + BL, y2 + BL * math.sin(math.radians(-30))          # B[3] lands one bond from C2
    B = benzene(m, bx, by, 0); m.bond(c2, B[3])
    m.sub(A[2], 'O', 150); m.sub(A[4], 'O', 270); m.sub(B[0], 'O', 0)
    e1 = m.sub(B[1], 'C', 60); e2 = m.sub(e1, 'C', 60, 3); m.mark(e1, e2)
    for i in B + [e1, e2]: m.a[i][3] = .3 * (m.a[i][2] - by)
    return m
def gingerol():          # 6-epi-Spirogingerol: a three-ring on the chain
    m = Mol(); R = vanillyl(m, 0, 0, 0); ch = m.chain(R[0], ['C'] * 10, 0)
    side(m, ch[2], 'O', 2); side(m, ch[4], 'O'); spiro(m, ch[6])
    return m
def curcumin():          # Spirocurcumin: a three-ring at the middle carbon
    m = Mol(); R1 = vanillyl(m, 0, 0, 0); ch = m.chain(R1[0], ['C'] * 7, 0, [1, 2, 1, 1, 1, 1, 2])
    side(m, ch[2], 'O', 2); side(m, ch[4], 'O', 2); spiro(m, ch[3])
    x, y = m.pos(ch[6]); R2 = vanillyl(m, x + BL * math.cos(math.radians(-30)) + BL, y + BL * math.sin(math.radians(-30)), 180)
    m.bond(ch[6], R2[0], 1)
    return m
def menthol():          # (1R)-8-Fluoromenthol: a fluorine on the isopropyl's middle carbon
    m = Mol(); R = ring(m, 6, 0, 0, 0, ['C'] * 6, [1] * 6)
    m.sub(R[0], 'O', outward(m, R, 0, 0, 0)); m.sub(R[3], 'C', outward(m, R, 3, 0, 0))
    o1 = outward(m, R, 1, 0, 0); ip = m.sub(R[1], 'C', o1); m.sub(ip, 'C', o1 + 60); m.sub(ip, 'C', o1 - 60)
    for k, i in enumerate(R): m.a[i][3] = .25 * (1 if k % 2 else -1)          # the chair
    f = m.sub(ip, 'F', o1, 1, .5); m.a[f][3] = 1.25; m.mark(f)          # pointing out of the page
    return m
def capsaicin():          # 13-Azacapsaicin: a nitrogen at the end of the tail
    m = Mol(); R = vanillyl(m, 0, 0, 0); ch = m.chain(R[0], ['C', 'N', 'C', 'C', 'C', 'C', 'C', 'C', 'C', 'N'], 0, [1, 1, 1, 1, 1, 1, 1, 2, 1, 1])
    side(m, ch[2], 'O', 2); side(m, ch[9], 'C'); m.mark(ch[9])
    return m

# compound key -> (strain, full name, shelf molecule, plant, colour, molecule)
PANTRY = {
    'lucid':    ('4R-Hydroxytheanine', '(2S,4R)-4-hydroxy-N⁵-ethyl-L-glutamine', 'L-theanine', 'green tea', [0.35, 0.85, 1.0], theanine()),
    'embrace':  ('7-Prenyltheobromine', '3-methyl-7-(3-methylbut-2-enyl)xanthine', 'theobromine', 'cacao', [1.0, 0.72, 0.25], xanthine(False, prenyl7=True)),
    'velocity': ('d-Vinylcaffeine', '1,7-dimethyl-3-vinyl-8-oxaxanthine', 'caffeine', 'coffee', [0.85, 0.95, 1.0], xanthine(True, vinyl3=True, oxa8=True)),
    'haze':     ('6-epi-Spirogingerol', '(5S)-spiro[2.4]-[6]-gingerol', 'gingerol', 'ginger root', [0.45, 1.0, 0.45], gingerol()),
    'drift':    ('3′-Ethynylapigenin', '5,7-dihydroxy-2-(3-ethynyl-4-hydroxyphenyl)chromen-4-one', 'apigenin', 'chamomile', [0.6, 0.75, 1.0], apigenin()),
    'hollow':   ('(1R)-8-Fluoromenthol', '(1R,2S,5R)-8-fluoro-p-menthan-3-ol', 'menthol', 'peppermint', [0.8, 0.85, 0.9], menthol()),
    'fold':     ('Spirocurcumin-4Z', '(4Z)-4-spirocyclopropyl-curcuminoid', 'curcumin', 'turmeric', [0.75, 1.0, 0.3], curcumin()),
    'deep':     ('13-Azacapsaicin', 'N-vanillyl-13-aza-8-methylnon-6-enamide', 'capsaicin', 'chilli', [0.55, 0.4, 1.0], capsaicin()) }
# compound key -> (effect, what it does, ACCORD's shelf version (satire), the wild strain's line)
# RULE: 'does' and the wild line must match what the game does (index.html COMP table, tripStep, LOOKNAMES). Change the words, never the effects.
TEXT = {
    'lucid':    ('LUCID', 'Tracers almost double; on the Trip level, hidden roads show in the waves', 'Shelf version: ACCORD Green Tea™, now with Focus. Focus is sold separately.', 'Patterns everywhere. The patterns have patterns.'),
    'embrace':  ('EMBRACE', 'Crystals come to you; a warm glow over everything', 'Shelf version: ACCORD Hug Blend™ cocoa. Contains trace amounts of hug.', 'You love everyone. Even the drones. Especially the drones.'),
    'velocity': ('VELOCITY', 'You keep your boost; time slows when something is right ahead', 'Shelf version: homeopathic coffee. One bean per reservoir. Feel nothing, faster.', 'Time is a suggestion. You declined it.'),
    'haze':     ('HAZE', 'The afterglow lasts half as long again; the world melts like wet paint', 'Shelf version: ACCORD ginger chews. Settles the stomach. Unsettles nothing else.', 'Everything melts. You agree with all of it.'),
    'drift':    ('DRIFT', 'Hits don’t hurt; everything slows a little', 'Shelf version: chamomile. Clinically proven to be a plant.', 'Nothing can hurt you. That’s the problem.'),
    'hollow':   ('HOLLOW', 'A wider, out-of-body view; cold and clear', 'Shelf version: ACCORD Peppermint Detachment™. Cool sensation. Slight existential draught.', 'You’re watching yourself drive. You’re doing great.'),
    'fold':     ('FOLD', 'The edges fold like pages; stained glass at the seams', 'Shelf version: turmeric. ACCORD stains everything yellow too.', 'Reality has pages. You’re reading ahead.'),
    'deep':     ('DEEP', 'Everything, all the way up: the breakthrough', 'Shelf version: ACCORD Brave™ hot sauce. Your mouth is on fire. Your mind is elsewhere.', 'Someone left the universe on. You’re alone in it.') }
out = {}
for k, (nm, sysn, shelf, plant, col, m) in PANTRY.items():
    xs = [a[1] for a in m.a]; ys = [a[2] for a in m.a]; cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    atoms = [[a[0], round(a[1] - cx, 2), round(a[2] - cy, 2), round(a[3] + .15 * math.sin(a[1] * .7), 2)] + ([1] if i in m.mut else []) for i, a in enumerate(m.a)]
    eff, does, acc, wild = TEXT[k]
    out[k] = {'name': nm, 'sys': sysn, 'shelf': shelf, 'plant': plant, 'eff': eff, 'does': does, 'acc': acc, 'wild': wild, 'c': col, 'atoms': atoms, 'bonds': m.b}
open(OUT, 'w', encoding='utf8').write('// The wild strains: kitchen-cupboard molecules, each with one fictional mutation (atoms flagged 1). Generated by tools/make_pantry.py; heavy atoms only. Made up: not real compounds.\nexport const PANTRY = ' + json.dumps(out, separators=(',', ':'), ensure_ascii=False) + ';\n')
print({k: (len(v['atoms']), sum(1 for a in v['atoms'] if len(a) > 4)) for k, v in out.items()})
