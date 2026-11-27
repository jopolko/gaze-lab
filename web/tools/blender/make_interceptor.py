# Interceptor Recon: black muscle car with a blower on the hood (reference sheet, #1).  blender -b -P make_interceptor.py -- out.glb
# Faces +Y. Origin on the ground at the centre. Metres.
import bpy, sys, math, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bl_common import *
argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
OUT = argv[0] if argv else 'interceptor.glb'
bpy.ops.wm.read_factory_settings(use_empty=True)

PAINT = mat('paint', 0x8a8a92, .75, .15)
RUSTM = mat('rust_brown', 0x6e3a1e, .95, .3)
SCRAP = mat('scrap', 0x5b5d63, .8, .6)
DARK = mat('dark_metal', 0x1d1d22, .6, .5)
CHROME = mat('chrome', 0xc9cdd8, .3, 1.0)
GLASS = mat('glass', 0x2a3a48, .2, .0, 0x182838, .4)
TIRE = mat('tire', 0x1a1918, .95)
SOOT = mat('soot', 0x0d0c0e, .95)
LENS = mat('headlight', 0xfff2c0, .2, .0, 0xfff2c0, 6)
TAIL = mat('taillight', 0xff2a2a, .3, .0, 0xff2020, 5)
BONE = mat('bone', 0xd6cdb0, .8)

def weather(co, m):
    """Dirt and rust by position: heavy low on the body, rust patches, scratches to bare metal. Returns a colour multiplier."""
    x, y, z = co.x, co.y, co.z
    low = max(0.0, 1.0 - z / .95)
    n = smooth_noise(x * 2.0, y * .8, z * 3.0, 3.1)
    patch = min(1.0, max(0.0, (n - .55) * 3.2)) + .6 * low * smooth_noise(y * 2.0, x, z * 2.0, 5.0)
    patch = min(1.0, patch)
    scratch = 1.0 if hnoise(math.floor(y * 7), math.floor(z * 15), math.floor(x * 3)) > .92 else 0.0
    if m is PAINT:
        base = .2 + scratch * .5                       # matte black with bare-metal scratches
        r, g, b = base, base, base * 1.03
        r, g, b = r + (1.05 - r) * patch, g + (.52 - g) * patch, b + (.26 - b) * patch   # rust
        d = .3 * low; r, g, b = r * (1 - d) + .55 * d, g * (1 - d) + .45 * d, b * (1 - d) + .36 * d   # road dust
        return (r, g, b)
    k = 1.0 - .3 * low
    return (k, k * (1.0 - .1 * patch), k * (1.0 - .3 * patch))

B = Part('car_body', weather)
WX, WYF, WYR, WR, WW = 1.0, 1.55, -1.45, .6, .55
# ---- lower body: nose, hood, cowl, deck, tail (one smooth skin)
#            y     hb    hm    ht    zb   zm    zt
S = [(-2.55, .78, .84, .74, .62, .86, 1.06),
     (-2.45, .92, .98, .88, .55, .92, 1.12),
     (-2.0, 1.0, 1.05, .98, .5, .95, 1.1),
     (-1.2, 1.0, 1.05, 1.0, .5, .95, 1.08),
     (-.2, 1.0, 1.05, .98, .5, .95, 1.06),
     (.5, 1.0, 1.05, .96, .5, .95, 1.1),
     (1.2, .98, 1.04, .94, .5, .93, 1.14),
     (1.9, .94, 1.0, .88, .5, .9, 1.08),
     (2.4, .86, .92, .78, .5, .84, .98),
     (2.72, .74, .8, .66, .48, .76, .86)]
B.loft([ring(*s) for s in S], PAINT)
# ---- cabin: glass skin with body-coloured pillars and a roof
C = [(-1.35, .84, .84, .66, 1.08, 1.12, 1.46), (-.9, .88, .88, .7, 1.08, 1.14, 1.56), (.1, .9, .9, .72, 1.08, 1.14, 1.6), (.75, .9, .9, .74, 1.08, 1.14, 1.58), (1.25, .9, .9, .84, 1.06, 1.1, 1.14)]
B.loft([ring(*s) for s in C], GLASS)
B.box((0, -.15, 1.605), (1.34, 1.9, .06), PAINT, .04, sub=2)                       # roof
for sx in (-1, 1):
    B.bar((sx * .72, .9, 1.58), (sx * .86, 1.22, 1.12), .045, PAINT)                # A pillars
    B.bar((sx * .68, -.95, 1.5), (sx * .8, -1.4, 1.1), .06, PAINT)                  # C pillars
    B.bar((sx * .72, .15, 1.58), (sx * .88, .15, 1.12), .035, PAINT)                # B pillars
    B.box((sx * 1.04, -.1, .92), (.05, 1.6, .5), SCRAP, .02, sub=2)                 # door armour plates
    B.box((sx * 1.04, -1.3, .9), (.05, .9, .45), RUSTM, .02)
    for k in range(5): B.cyl((sx * 1.07, -.75 + k * .32, .72), .03, .03, 'x', DARK, 6)   # rivets
B.box((0, -1.42, 1.34), (1.3, .05, .5), DARK, .02)                                   # rear window mesh frame
for k in range(7): B.bar((-.6 + k * .2, -1.45, 1.1), (-.6 + k * .2, -1.45, 1.58), .012, SOOT, 5)
for k in range(4): B.bar((-.62, -1.45, 1.2 + k * .11), (.62, -1.45, 1.2 + k * .11), .012, SOOT, 5)
# ---- the blower: a supercharger on the hood, with intake stacks and a belt drive
B.box((0, 1.35, 1.3), (.74, .9, .3), DARK, .05)
B.cyl((0, 1.35, 1.5), .26, .34, 'z', CHROME, 14); B.cyl((0, 1.35, 1.7), .3, .06, 'z', DARK, 14)
for k in range(2): B.cyl((-.2 + k * .4, 1.65, 1.5), .09, .3, 'z', CHROME, 10); B.cyl((-.2 + k * .4, 1.65, 1.67), .12, .04, 'z', DARK, 10)
B.box((0, 1.35, 1.4), (.3, 1.1, .08), SCRAP, .02)
for sx in (-1, 1): B.bar((sx * .5, .95, 1.3), (sx * .5, 1.85, 1.3), .03, SOOT)
B.box((0, 1.3, 1.18), (1.1, 1.2, .03), SCRAP, .01, rot=(.04, 0, 0))                  # hood scuffs / patched plate
# ---- front: cow-catcher splitter, mesh grille, caged lights
B.box((0, 2.6, .48), (1.95, .6, .12), SCRAP, .04, rot=(-.15, 0, 0))                 # splitter plate
for k in range(9): B.cyl((-.88 + k * .22, 2.9, .45), .055, .3, 'y', DARK, 6, r2=0)  # spikes
B.box((0, 2.74, .74), (1.5, .05, .3), DARK, .02)
for k in range(9): B.bar((-.7 + k * .175, 2.78, .6), (-.7 + k * .175, 2.78, .88), .015, CHROME, 5)
for sx in (-1, 1):
    B.cyl((sx * .72, 2.62, .96), .17, .08, 'y', CHROME, 16); B.cyl((sx * .72, 2.67, .96), .13, .05, 'y', LENS, 16)
    for k in range(3): B.bar((sx * .72 - .18, 2.7, .88 + k * .09), (sx * .72 + .18, 2.7, .88 + k * .09), .012, DARK, 5)
B.bar((-.9, 2.8, .5), (-.9, 2.8, 1.05), .05, SCRAP); B.bar((.9, 2.8, .5), (.9, 2.8, 1.05), .05, SCRAP); B.bar((-.9, 2.8, 1.05), (.9, 2.8, 1.05), .05, SCRAP)
# ---- roof lights, antenna
B.box((0, .75, 1.7), (1.0, .14, .1), DARK, .03)
for k in range(4): B.box((-.36 + k * .24, .83, 1.7), (.16, .04, .07), LENS if k in (0, 3) else SOOT, .01)
B.bar((-.85, -1.0, 1.5), (-.85, -1.5, 2.6), .012, DARK, 5)
# ---- side exhaust pipes, fender flares and sill
for sx in (-1, 1):
    B.bar((sx * 1.1, -.5, .46), (sx * 1.1, 1.0, .46), .07, CHROME); B.cyl((sx * 1.1, 1.02, .46), .075, .06, 'y', SOOT, 10)
    for yy, ww in ((WYF, 1.3), (WYR, 1.25)):
        B.box((sx * 1.03, yy, WR + .5), (.13, ww, .1), PAINT, .04, rot=(0, 0, 0))     # flare top
        B.box((sx * 1.1, yy + ww * .46, WR + .28), (.1, .2, .4), PAINT, .03); B.box((sx * 1.1, yy - ww * .46, WR + .28), (.1, .2, .4), PAINT, .03)
    B.box((sx * 1.0, -2.1, .62), (.05, .22, .16), TAIL, .02)                        # tail lights
# ---- rear: small spoiler, fuel cap, exhaust
B.box((0, -2.55, 1.2), (1.7, .24, .06), SCRAP, .02); B.bar((-.7, -2.5, 1.0), (-.7, -2.5, 1.2), .03, DARK); B.bar((.7, -2.5, 1.0), (.7, -2.5, 1.2), .03, DARK)
B.box((0, -2.78, .78), (1.4, .06, .18), SOOT, .02)
body = B.finish()

def wheel(name, loc, side):
    W = Part(name, None)
    W.cyl((0, 0, 0), WR, WW, 'x', TIRE, 24)
    for i in range(16):
        a = i / 16 * math.tau
        W.box((0, math.cos(a) * (WR + .015), math.sin(a) * (WR + .015)), (WW * .96, .1, .08), TIRE, .012, rot=(a - math.pi / 2, 0, 0), seg=1)
    W.cyl((side * (WW / 2 + .003), 0, 0), .36, .02, 'x', RUSTM, 20); W.cyl((side * (WW / 2 + .02), 0, 0), .15, .04, 'x', DARK, 12)
    for i in range(6): a = i / 6 * math.tau; W.cyl((side * (WW / 2 + .03), math.cos(a) * .24, math.sin(a) * .24), .03, .03, 'x', CHROME, 6)
    return W.finish(loc)
for n, loc, sd in (('wheel_FL', (-WX, WYF, WR), -1), ('wheel_FR', (WX, WYF, WR), 1), ('wheel_RL', (-WX, WYR, WR), -1), ('wheel_RR', (WX, WYR, WR), 1)): wheel(n, loc, sd)
export(OUT)
