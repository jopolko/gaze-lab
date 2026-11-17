"""Builds 3D ball-and-stick coordinates for six phenethylamines from Alexander Shulgin's PiHKAL (mescaline, DOM, 2C-B, 2C-E, 2C-T-2, 2C-T-7) with standard bond
lengths and angles, no chemistry packages needed.   python tools/mol_gen.py   ->   scripts/MolData.gd

Each molecule is checked against its known formula and for atoms sitting on top of each other, so a mistake in the builder shows up here, not in the game.
"""
import math
import os

D2R = math.pi / 180.0


def add(a, b): return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def mul(a, s): return (a[0] * s, a[1] * s, a[2] * s)
def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def ln(a): return math.sqrt(dot(a, a))
def unit(a):
    l = ln(a)
    return (a[0] / l, a[1] / l, a[2] / l)


def place(a, b, c, bond, angle, tors):
    """The next atom d after a-b-c: bond length c-d, angle b-c-d, torsion a-b-c-d (degrees)."""
    bc = unit(sub(c, b))
    n = unit(cross(sub(b, a), bc))
    m = cross(n, bc)
    ang = angle * D2R
    t = tors * D2R
    d2 = (-bond * math.cos(ang), bond * math.sin(ang) * math.cos(t), bond * math.sin(ang) * math.sin(t))
    return add(c, add(add(mul(bc, d2[0]), mul(m, d2[1])), mul(n, d2[2])))


def subst3(d, p):
    """The three unit directions of the other bonds of a tetrahedral atom whose fourth bond lies behind, d being the direction from that fourth neighbour to the atom."""
    e1 = unit(sub(p, mul(d, dot(p, d))))
    e2 = cross(d, e1)
    out = []
    for k in range(3):
        phi = k * 120.0 * D2R
        out.append(add(mul(d, 0.334), mul(add(mul(e1, math.cos(phi)), mul(e2, math.sin(phi))), 0.943)))
    return out


def two_hs(c, p, n):
    b1 = unit(sub(p, c))
    b2 = unit(sub(n, c))
    m = unit(mul(add(b1, b2), -1.0))
    k = unit(cross(b1, b2))
    h = 54.75 * D2R
    return [add(mul(m, math.cos(h)), mul(k, math.sin(h))), add(mul(m, math.cos(h)), mul(k, -math.sin(h)))]


class Mol:
    def __init__(self):
        self.atoms = []
        self.bonds = []

    def a(self, el, pos, bonded_to=None, order=1):
        self.atoms.append([el, pos])
        i = len(self.atoms) - 1
        if bonded_to is not None:
            self.bonds.append([bonded_to, i, order])
        return i

    def pos(self, i): return self.atoms[i][1]

    def methyl(self, parent, d, p):
        first = len(self.atoms)
        self.hs(parent, subst3(d, p))
        self.meths = getattr(self, "meths", [])
        self.meths.append((parent, list(range(first, first + 3)), d))

    def hs(self, parent, dirs, length=1.09):
        for d in dirs:
            self.a("H", add(self.pos(parent), mul(d, length)), parent)


def rot_about(v, axis, ang):
    k = unit(axis)
    c, s_ = math.cos(ang), math.sin(ang)
    return add(add(mul(v, c), mul(cross(k, v), s_)), mul(k, dot(k, v) * (1 - c)))


def relax(m):
    """Each methyl group is turned (in steps) to the position where its hydrogens are furthest from every other atom."""
    for _ in range(2):
        for parent, hidx, d in getattr(m, "meths", []):
            pc = m.pos(parent)
            base = [sub(m.pos(h), pc) for h in hidx]
            best, best_a = -1.0, 0.0
            for step in range(0, 120, 6):
                a = step * D2R
                worst = 99.0
                for v in base:
                    hp = add(pc, rot_about(v, d, a))
                    for j in range(len(m.atoms)):
                        if j == parent or j in hidx:
                            continue
                        dd = ln(sub(hp, m.pos(j)))
                        if dd < 2.0 and any(b[0] == parent and b[1] == j or b[1] == parent and b[0] == j for b in m.bonds):
                            continue
                        worst = min(worst, dd)
                if worst > best:
                    best, best_a = worst, a
            for h, v in zip(hidx, base):
                m.atoms[h][1] = add(pc, rot_about(v, d, best_a))


def build(kind):
    m = Mol()
    R = 1.40
    ring = []
    us = []
    for k in range(6):
        th = (180.0 - 60.0 * k) * D2R
        u = (math.cos(th), math.sin(th), 0.0)
        us.append(u)
        ring.append(m.a("C", mul(u, R)))
    for k in range(6):
        m.bonds.append([ring[k], ring[(k + 1) % 6], 2 if k % 2 == 0 else 1])
    N = (0.0, 0.0, 1.0)
    # ring positions 1..6 are ring[0..5]; position 1 carries the chain

    def toward(k, nb):
        w = sub(m.pos(ring[nb]), m.pos(ring[k]))
        w = sub(w, mul(us[k], dot(w, us[k])))
        return unit(w)

    def methoxy(k, nb):
        o = m.a("O", add(m.pos(ring[k]), mul(us[k], 1.36)), ring[k])
        w = N if nb is None else toward(k, nb)
        d = add(mul(us[k], math.cos(63 * D2R)), mul(w, math.sin(63 * D2R)))
        c = m.a("C", add(m.pos(o), mul(d, 1.43)), o)
        m.methyl(c, d, N if nb is not None else us[k])

    def ring_h(k):
        m.a("H", add(m.pos(ring[k]), mul(us[k], 1.08)), ring[k])

    # the side chain on position 1
    ca = m.a("C", add(m.pos(ring[0]), mul(us[0], 1.51)), ring[0])
    cb = m.a("C", place(m.pos(ring[1]), m.pos(ring[0]), m.pos(ca), 1.53, 112.0, 90.0), ca)
    nn = m.a("N", place(m.pos(ring[0]), m.pos(ca), m.pos(cb), 1.47, 111.0, 180.0), cb)
    if kind == "dom":
        cm = m.a("C", place(m.pos(ring[0]), m.pos(ca), m.pos(cb), 1.53, 111.0, 60.0), cb)
        m.a("H", place(m.pos(ring[0]), m.pos(ca), m.pos(cb), 1.09, 109.0, -60.0), cb)
        dm = unit(sub(m.pos(cm), m.pos(cb)))
        m.methyl(cm, dm, unit(sub(m.pos(ca), m.pos(cb))))
    else:
        m.a("H", place(m.pos(ring[0]), m.pos(ca), m.pos(cb), 1.09, 109.0, 60.0), cb)
        m.a("H", place(m.pos(ring[0]), m.pos(ca), m.pos(cb), 1.09, 109.0, -60.0), cb)
    m.hs(ca, two_hs(m.pos(ca), m.pos(ring[0]), m.pos(cb)))
    m.a("H", place(m.pos(ca), m.pos(cb), m.pos(nn), 1.01, 109.0, 60.0), nn)
    m.a("H", place(m.pos(ca), m.pos(cb), m.pos(nn), 1.01, 109.0, -60.0), nn)

    if kind == "mescaline":
        ring_h(1)
        methoxy(2, 1)
        methoxy(3, None)
        methoxy(4, 5)
        ring_h(5)
    else:
        methoxy(1, 2)
        ring_h(2)
        c4 = ring[3]
        u4 = us[3]
        if kind == "2cb":
            m.a("Br", add(m.pos(c4), mul(u4, 1.90)), c4)
        elif kind == "dom":
            cm4 = m.a("C", add(m.pos(c4), mul(u4, 1.51)), c4)
            m.methyl(cm4, u4, N)
        elif kind == "2ce":
            c_a = m.a("C", add(m.pos(c4), mul(u4, 1.51)), c4)
            c_b = m.a("C", place(m.pos(ring[2]), m.pos(c4), m.pos(c_a), 1.53, 112.0, 90.0), c_a)
            m.hs(c_a, two_hs(m.pos(c_a), m.pos(c4), m.pos(c_b)))
            m.methyl(c_b, unit(sub(m.pos(c_b), m.pos(c_a))), unit(sub(m.pos(c4), m.pos(c_a))))
        elif kind in ("2ct2", "2ct7"):
            s = m.a("S", add(m.pos(c4), mul(u4, 1.76)), c4)
            c_a = m.a("C", place(m.pos(ring[2]), m.pos(c4), m.pos(s), 1.82, 103.0, 0.0), s)
            if kind == "2ct2":
                c_b = m.a("C", place(m.pos(c4), m.pos(s), m.pos(c_a), 1.53, 108.0, 180.0), c_a)
                m.hs(c_a, two_hs(m.pos(c_a), m.pos(s), m.pos(c_b)))
                m.methyl(c_b, unit(sub(m.pos(c_b), m.pos(c_a))), unit(sub(m.pos(s), m.pos(c_a))))
            else:
                c_b = m.a("C", place(m.pos(c4), m.pos(s), m.pos(c_a), 1.53, 109.0, 180.0), c_a)
                c_g = m.a("C", place(m.pos(s), m.pos(c_a), m.pos(c_b), 1.53, 112.0, 180.0), c_b)
                m.hs(c_a, two_hs(m.pos(c_a), m.pos(s), m.pos(c_b)))
                m.hs(c_b, two_hs(m.pos(c_b), m.pos(c_a), m.pos(c_g)))
                m.methyl(c_g, unit(sub(m.pos(c_g), m.pos(c_b))), unit(sub(m.pos(c_a), m.pos(c_b))))
        ring_h(4 + 1)
        methoxy(4, 5)
    relax(m)
    return m


# ring_h(4+1) above is position 6 (index 5); position 5 (index 4) carries the second methoxy, put on after position 4's group

SPECS = [
    ("mescaline", "mescaline", "C11H17NO3", (0.68, 0.48, 1.00)),
    ("dom", "DOM", "C12H19NO2", (1.00, 0.38, 0.68)),
    ("2cb", "2C-B", "C10H14BrNO2", (0.30, 0.90, 1.00)),
    ("2ce", "2C-E", "C12H19NO2", (1.00, 0.85, 0.25)),
    ("2ct2", "2C-T-2", "C12H19NO2S", (0.40, 1.00, 0.55)),
    ("2ct7", "2C-T-7", "C13H21NO2S", (1.00, 0.55, 0.25)),
]


def formula(m):
    cnt = {}
    for el, _ in m.atoms:
        cnt[el] = cnt.get(el, 0) + 1
    s = ""
    for el in ["C", "H", "Br", "N", "O", "S"]:
        if el in cnt:
            s += el + (str(cnt[el]) if cnt[el] > 1 else "")
    return s


def main():
    out = ["class_name MolData", "extends RefCounted",
           "## Ball-and-stick coordinates (angstroms, centred, long axis along x) for six phenethylamines from Alexander Shulgin's PiHKAL. Made by tools/mol_gen.py: do not edit by hand.",
           "", "const MOLS := {"]
    for kid, label, want, col in SPECS:
        m = build(kid)
        got = formula(m)
        assert got == want, (kid, got, want)
        # nothing sits on top of anything else: every pair that is not bonded is at least 1.6 A apart (hydrogens 1.7 from non-bonded heavy atoms)
        bonded = set()
        for a, b, _ in m.bonds:
            bonded.add((a, b))
            bonded.add((b, a))
        nb_of = {}
        for a, b, _ in m.bonds:
            nb_of.setdefault(a, set()).add(b)
            nb_of.setdefault(b, set()).add(a)
        worst = 99.0
        for i in range(len(m.atoms)):
            for j in range(i + 1, len(m.atoms)):
                if (i, j) in bonded:
                    continue
                if j in nb_of.get(i, set()) or any(j in nb_of.get(k, set()) for k in nb_of.get(i, set())):
                    continue          # 1-3 pairs are close by construction
                d = ln(sub(m.pos(i), m.pos(j)))
                if d < 1.95:
                    print('   close', kid, i, m.atoms[i][0], j, m.atoms[j][0], round(d, 2))
                worst = min(worst, d)
        assert worst > 1.9, (kid, "atoms too close", worst)
        cx = sum(p[0] for _, p in m.atoms) / len(m.atoms)
        cy = sum(p[1] for _, p in m.atoms) / len(m.atoms)
        cz = sum(p[2] for _, p in m.atoms) / len(m.atoms)
        atoms = ", ".join('["%s", %.2f, %.2f, %.2f]' % (el, p[0] - cx, p[1] - cy, p[2] - cz) for el, p in m.atoms)
        bonds = ", ".join("[%d, %d, %d]" % (a, b, o) for a, b, o in m.bonds)
        out.append('\t"%s": {"name": "%s", "c": Color(%.2f, %.2f, %.2f), "atoms": [%s], "bonds": [%s]},' % (kid, label, col[0], col[1], col[2], atoms, bonds))
        print("%-10s %-12s atoms %d bonds %d  closest non-bonded %.2f A" % (label, got, len(m.atoms), len(m.bonds), worst))
    out.append("}")
    out.append("const ORDER := [\"mescaline\", \"dom\", \"2cb\", \"2ce\", \"2ct2\", \"2ct7\"]")
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts", "MolData.gd")
    open(path, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
    print("written", os.path.normpath(path))


main()
