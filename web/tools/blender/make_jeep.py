# Builds the hero jeep for The Last Copy and exports a .glb.   Run:  blender -b -P make_jeep.py -- <out.glb> [preview_prefix]
# Car faces +Y in Blender (-Z in three.js). Origin is on the ground at the car's centre. Units are metres.
import bpy, bmesh, sys, math
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
OUT = argv[0] if argv else 'jeep.glb'
PREVIEW = argv[1] if len(argv) > 1 else None

bpy.ops.wm.read_factory_settings(use_empty=True)

def lin(h):  # sRGB hex -> linear tuple
    r, g, b = ((h >> 16) & 255) / 255, ((h >> 8) & 255) / 255, (h & 255) / 255
    f = lambda c: c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4
    return (f(r), f(g), f(b), 1)

MATS = {}
def mat(name, hexc, rough=.6, metal=0.0, emit=None, emit_k=0.0):
    if name in MATS: return MATS[name]
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = lin(hexc); b.inputs['Roughness'].default_value = rough; b.inputs['Metallic'].default_value = metal
    if emit is not None:
        b.inputs['Emission Color'].default_value = lin(emit); b.inputs['Emission Strength'].default_value = emit_k
    m.diffuse_color = lin(hexc)
    MATS[name] = m; return m

PAINT = mat('paint', 0xa8894e, .9, .1)
RUSTM = mat('rust_brown', 0x6b3a22, .95, .3)
RUSTO = mat('rust_orange', 0x9a4a1e, .9, .2)
SCRAP = mat('scrap', 0x5d5f66, .8, .6)
PRIMER = mat('primer', 0x8a8a84, .95)
OLIVE = mat('olive', 0x4a5532, .9)
BONE = mat('bone', 0xd6cdb0, .8)
SOOT = mat('soot', 0x0f0e10, .95)
RAG = mat('rag', 0xa02818, .95)
BAND = mat('bandolier', 0x5b4326, .9)
TIRE = mat('tire', 0x1c1a19, .95)
DARK = mat('dark_metal', 0x23232b, .6, .5)
RUBBER = mat('rubber', 0x141416, .9)
CHROME = mat('chrome', 0xd8dce8, .25, 1.0)
GLASS = mat('glass', 0x4a6a80, .2, .0, 0x305070, .5)
LENS = mat('headlight', 0xfff2c0, .2, .0, 0xfff2c0, 6)
TAIL = mat('taillight', 0xff2a2a, .3, .0, 0xff2020, 5)
CANVAS = mat('canvas', 0x4b4036, .95)
CLOAK = mat('cloak', 0x2a2420, .9)
SKIN = mat('skin', 0xc9a07a, .8)
GOGGLE = mat('goggles', 0xffb030, .2, .0, 0xffa020, 4)
CYAN = mat('cyan_glow', 0x7af4ff, .2, .0, 0x30e8ff, 8)

class Part:
    def __init__(self, name):
        self.name = name; self.bm = bmesh.new(); self.mats = []
    def mi(self, m):
        if m not in self.mats: self.mats.append(m)
        return self.mats.index(m)
    def _add(self, tmp, m, smooth):
        bm = self.bm; idx = self.mi(m); mp = {}
        for v in tmp.verts: mp[v] = bm.verts.new(v.co)
        for f in tmp.faces:
            nf = bm.faces.new([mp[v] for v in f.verts]); nf.material_index = idx; nf.smooth = smooth
        tmp.free()
    def box(self, c, size, m, bevel=.03, rot=(0, 0, 0), seg=2):
        t = bmesh.new(); bmesh.ops.create_cube(t, size=1.0)
        bmesh.ops.transform(t, matrix=Matrix.Diagonal((size[0], size[1], size[2], 1.0)), verts=t.verts)
        if bevel > 0:
            b = min(bevel, min(size) * .45)
            bmesh.ops.bevel(t, geom=list(t.edges), offset=b, segments=seg, affect='EDGES')
        R = Matrix.Rotation(rot[2], 4, 'Z') @ Matrix.Rotation(rot[1], 4, 'Y') @ Matrix.Rotation(rot[0], 4, 'X')
        bmesh.ops.transform(t, matrix=Matrix.Translation(c) @ R, verts=t.verts)
        bmesh.ops.recalc_face_normals(t, faces=t.faces); self._add(t, m, False)
    def cyl(self, c, r, h, axis, m, seg=16, r2=None, smooth=True, caps=True):
        t = bmesh.new(); bmesh.ops.create_cone(t, cap_ends=caps, cap_tris=False, segments=seg, radius1=r, radius2=(r if r2 is None else r2), depth=h)
        rot = {'z': Matrix.Identity(4), 'x': Matrix.Rotation(math.pi / 2, 4, 'Y'), 'y': Matrix.Rotation(-math.pi / 2, 4, 'X')}[axis]
        bmesh.ops.transform(t, matrix=Matrix.Translation(c) @ rot, verts=t.verts)
        bmesh.ops.recalc_face_normals(t, faces=t.faces); self._add(t, m, smooth)
    def sph(self, c, r, m, sc=(1, 1, 1), seg=12):
        t = bmesh.new(); bmesh.ops.create_uvsphere(t, u_segments=seg, v_segments=max(6, seg // 2), radius=r)
        bmesh.ops.transform(t, matrix=Matrix.Translation(c) @ Matrix.Diagonal((sc[0], sc[1], sc[2], 1.0)), verts=t.verts)
        bmesh.ops.recalc_face_normals(t, faces=t.faces); self._add(t, m, True)
    def bar(self, p1, p2, r, m, seg=8):  # a tube between two points
        p1, p2 = Vector(p1), Vector(p2); d = p2 - p1; L = d.length
        t = bmesh.new(); bmesh.ops.create_cone(t, cap_ends=True, cap_tris=False, segments=seg, radius1=r, radius2=r, depth=L)
        q = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        bmesh.ops.transform(t, matrix=Matrix.Translation((p1 + p2) / 2) @ q, verts=t.verts)
        bmesh.ops.recalc_face_normals(t, faces=t.faces); self._add(t, m, True)
    def finish(self, loc=(0, 0, 0)):
        me = bpy.data.meshes.new(self.name); self.bm.to_mesh(me); self.bm.free()
        for m in self.mats: me.materials.append(m)
        ob = bpy.data.objects.new(self.name, me); ob.location = loc; bpy.context.scene.collection.objects.link(ob); return ob

# ---------------------------------------------------------------- the body: a wrecked-and-rebuilt wasteland jeep
B = Part('jeep_body')
WX, WY, WR, WW = 1.06, 1.45, .58, .5
# chassis, rails, skid plate
B.box((0, -.3, .42), (1.5, 3.7, .18), DARK, .03)
B.box((-.62, -.2, .38), (.12, 3.8, .22), RUSTM, .02); B.box((.62, -.2, .38), (.12, 3.8, .22), RUSTM, .02)
B.box((0, 1.6, .3), (1.2, 1.2, .08), SCRAP, .02)
# tub: floor, mismatched sides (tan driver side, olive passenger side), scrap rear
B.box((0, -.55, .62), (1.9, 3.1, .1), RUSTM, .03)
B.box((-.93, -.55, .93), (.14, 3.1, .62), PAINT, .05)
B.box((.93, -.55, .93), (.14, 3.1, .62), OLIVE, .05)
B.box((0, -2.08, .95), (1.9, .14, .66), SCRAP, .05)
B.box((0, -1.45, .74), (1.7, .1, .22), RUSTM, .03)
# patched door panels, welded on at slightly wrong angles
B.box((-.99, -.2, 1.0), (.05, 1.0, .5), RUSTM, .02, rot=(0, 0, .03)); B.box((.99, -.5, 1.0), (.05, .9, .46), SCRAP, .02, rot=(0, 0, -.04))
B.box((-.99, -1.4, .98), (.05, .7, .5), SCRAP, .02); B.box((.99, .15, .88), (.05, .6, .35), PAINT, .02)
for (x, y, z) in ((-1.03, -.2, 1.15), (-1.03, -.2, .85), (1.03, -.5, 1.12), (1.03, -.5, .82), (1.03, -1.3, 1.0), (-1.03, -1.4, 1.1)):
    B.cyl((x, y, z), .035, .03, 'x', DARK, 6)               # bolt heads
for (x, y, z) in ((-1.0, 0.35, 1.05), (1.0, -.9, 1.2), (-1.0, -1.1, .85), (1.0, .4, 1.15)):
    B.cyl((x, y, z), .04, .02, 'x', SOOT, 8)                # bullet holes
# hood, cowl, fenders (each a different colour, none flush)
B.box((0, 1.52, 1.0), (1.56, 1.15, .42), RUSTO, .08, seg=3)
B.box((.25, 1.4, 1.22), (.7, .6, .04), PRIMER, .02, rot=(0, 0, .15))   # primer patch
B.box((0, .85, 1.12), (1.9, .3, .46), PAINT, .06)
B.box((-WX, WY, WR + .52), (.66, 1.18, .13), RUSTM, .05, rot=(0, .04, 0)); B.box((WX, WY, WR + .52), (.66, 1.18, .13), PAINT, .05)
B.box((-WX, -WY, WR + .52), (.66, 1.0, .13), SCRAP, .05); B.box((WX, -WY, WR + .5), (.66, 1.0, .13), RUSTO, .05, rot=(.05, 0, 0))
for sx in (-1, 1):
    for yy in (WY, -WY):
        B.box((sx * (WX + .3), yy, WR + .34), (.07, 1.18 if yy > 0 else 1.0, .38), DARK, .03)
        for k in range(3): B.cyl((sx * (WX + .05), yy + (k - 1) * .35, WR + .62), .05, .16, 'z', DARK, 6, r2=0)      # fender spikes
# front: grille with a skull, one lit headlight and one smashed, spiked bull bar
B.box((0, 2.12, .92), (1.34, .08, .5), DARK, .03)
for i in range(7): B.box((-.54 + i * .18, 2.17, .92), (.07, .06, .44), RUSTM, .015)
B.sph((0, 2.26, .95), .15, BONE, sc=(1, .8, 1.1)); B.box((0, 2.3, .8), (.18, .08, .1), BONE, .02)
B.sph((-.06, 2.38, .98), .035, SOOT); B.sph((.06, 2.38, .98), .035, SOOT)
B.cyl((-.74, 2.14, .98), .2, .1, 'y', DARK, 18); B.cyl((-.74, 2.2, .98), .15, .06, 'y', SOOT, 18)
B.cyl((.74, 2.14, .98), .2, .1, 'y', DARK, 18); B.cyl((.74, 2.2, .98), .15, .06, 'y', LENS, 18)
for sx in (-1, 1):
    for k in range(3): B.bar((sx * .74, 2.3, .8 + k * .18), (sx * .74, 2.36, .8 + k * .18), .015, DARK, 5)   # light cage bars
B.box((0, 2.24, .5), (1.98, .2, .22), SCRAP, .06)
for i in range(9): B.cyl((-.88 + i * .22, 2.4, .5), .06, .22, 'y', DARK, 6, r2=0)             # bumper spikes
B.bar((-.7, 2.3, .55), (-.7, 2.3, 1.25), .045, SCRAP); B.bar((.7, 2.3, .55), (.7, 2.3, 1.25), .045, SCRAP); B.bar((-.7, 2.3, 1.25), (.7, 2.3, 1.25), .045, SCRAP)
B.bar((-.7, 2.3, .85), (.7, 2.3, .85), .04, SCRAP)
# armoured windshield: steel plate with a narrow slit, no glass to speak of
for sx in (-1, 1): B.bar((sx * .86, .78, 1.3), (sx * .84, .42, 1.98), .04, DARK)
B.bar((-.84, .42, 1.98), (.84, .42, 1.98), .04, DARK)
B.box((0, .67, 1.45), (1.64, .05, .34), SCRAP, .02, rot=(.49, 0, 0))                  # lower plate
B.box((0, .51, 1.83), (1.64, .05, .3), SCRAP, .02, rot=(.49, 0, 0))                   # upper plate
B.box((0, .59, 1.64), (1.58, .02, .12), GLASS, 0, rot=(.49, 0, 0))                    # the slit
# roll cage with a plated roof, junk on top
for sx in (-1, 1):
    B.bar((sx * .86, -.7, 1.0), (sx * .86, -.7, 2.12), .045, DARK)
    B.bar((sx * .86, -.7, 2.12), (sx * .84, .42, 1.98), .045, DARK)
    B.bar((sx * .86, -.7, 2.12), (sx * .88, -1.95, 1.2), .04, DARK)
    B.bar((sx * .86, -.7, 1.7), (sx * .88, -1.95, 1.2), .035, DARK)
B.bar((-.86, -.7, 2.12), (.86, -.7, 2.12), .045, DARK); B.bar((-.86, -.7, 1.55), (.86, -.7, 1.55), .035, DARK)
B.box((0, -.15, 2.16), (1.8, 1.3, .05), RUSTM, .02, rot=(.04, 0, 0))               # roof plate
for i in range(5): B.box((-.7 + i * .35, -.15, 2.2), (.12, 1.3, .03), SCRAP, 0)    # corrugation
B.cyl((-.45, -.4, 2.42), .24, .5, 'z', RUSTO, 14); B.cyl((.1, -.45, 2.42), .24, .5, 'z', OLIVE, 14)   # drums
B.box((.6, -.35, 2.35), (.36, .2, .36), OLIVE, .04); B.cyl((0, .15, 2.28), .1, 1.2, 'x', CANVAS, 10)  # jerry can, bedroll
B.bar((-.5, -.4, 2.2), (.5, -.4, 2.5), .012, DARK, 4); B.bar((.5, -.4, 2.2), (-.5, -.4, 2.5), .012, DARK, 4)  # tie-down cords
# roof light bar: two lights dead, two lit
B.box((0, .4, 2.06), (1.3, .12, .1), DARK, .03)
for i in range(4): B.box((-.45 + i * .3, .47, 2.06), (.2, .04, .07), LENS if i in (0, 3) else SOOT, .01)
# seats (torn), dash, wheel
for sx in (-1, 1):
    B.box((sx * .45, -.15, .72), (.55, .55, .16), CANVAS, .05)
    B.box((sx * .45, -.45, 1.04), (.55, .16, .62), CANVAS, .06, rot=(0, 0, sx * .05))
B.box((0, .72, 1.12), (1.7, .32, .14), DARK, .04)
B.cyl((-.45, .46, 1.22), .22, .03, 'y', DARK, 18); B.bar((-.45, .52, 1.2), (-.45, .7, 1.1), .02, DARK)
B.bar((-.67, .46, 1.22), (-.23, .46, 1.22), .02, DARK); B.bar((-.45, .46, 1.0), (-.45, .46, 1.44), .02, DARK)
# the Last Copy's mount: a clamped bracket on the passenger side
B.cyl((.45, .05, 0.85), .17, .14, 'z', DARK, 6); B.cyl((.45, .05, 0.93), .1, .02, 'z', CYAN, 6)
for a in (0, 2.1, 4.2): B.bar((.45 + math.cos(a) * .2, .05 + math.sin(a) * .2, .85), (.45 + math.cos(a) * .12, .05 + math.sin(a) * .12, 1.0), .015, DARK, 5)
# rear: spare tyre, mismatched tail lights, exhaust stacks, antenna with rags
B.cyl((0, -2.3, 1.08), .52, .3, 'y', RUBBER, 24); B.cyl((0, -2.46, 1.08), .27, .04, 'y', SCRAP, 16); B.cyl((0, -2.46, 1.08), .12, .06, 'y', DARK, 12)
B.box((-.78, -2.17, .86), (.22, .06, .16), TAIL, .02); B.box((.78, -2.17, .86), (.22, .06, .16), SOOT, .02)
B.box((-.55, -1.82, 1.2), (.4, .22, .46), RUSTO, .04); B.box((-.55, -1.82, 1.46), (.14, .1, .06), DARK, .01)
for sx in (-1, 1): B.bar((sx * .9, -1.5, 1.0), (sx * .9, -1.5, 2.3), .07, SOOT); B.cyl((sx * .9, -1.5, 2.32), .09, .06, 'z', DARK, 10)
B.bar((1.0, 1.1, 1.0), (1.0, 1.1, 2.1), .05, SCRAP); B.cyl((1.0, 1.1, 2.12), .08, .05, 'z', DARK, 10)
B.bar((-.98, -2.0, 1.0), (-.98, -2.0, 2.9), .012, DARK, 6); B.sph((-.98, -2.0, 2.92), .06, CYAN)
B.box((-.98, -2.06, 2.55), (.02, .3, .3), RAG, 0, rot=(0, 0, .3)); B.box((-.98, -2.2, 2.35), (.02, .28, .22), RAG, 0, rot=(0, 0, -.2))
# rust streaks and grime on the sides
for (x, y, z, h) in ((-1.0, -.9, .9, .4), (-1.0, .3, .85, .3), (1.0, -1.5, .9, .35), (1.0, .0, .9, .3)):
    B.box((x * 1.002, y, z), (.02, .08, h), RUSTM, 0)
body = B.finish()

# ---------------------------------------------------------------- wheels: fat, dusty, spiked hubs
def make_wheel(name, loc, side):
    W = Part(name)
    W.cyl((0, 0, 0), WR, WW, 'x', TIRE, 28)
    n = 20
    for i in range(n):
        a = i / n * math.tau
        W.box((0, math.cos(a) * (WR + .02), math.sin(a) * (WR + .02)), (WW * .96, .1, .08), TIRE, .015, rot=(a - math.pi / 2, 0, 0), seg=1)
    W.cyl((side * (WW / 2 + .004), 0, 0), .33, .02, 'x', SCRAP, 20)
    W.cyl((side * (WW / 2 + .02), 0, 0), .14, .04, 'x', DARK, 12)
    for i in range(6):
        a = i / 6 * math.tau
        W.cyl((side * (WW / 2 + .06), math.cos(a) * .22, math.sin(a) * .22), .035, .12, 'x', DARK, 6, r2=0)   # spikes
    return W.finish(loc)
wheels = [make_wheel('wheel_FL', (-WX, WY, WR), -1), make_wheel('wheel_FR', (WX, WY, WR), 1), make_wheel('wheel_RL', (-WX, -WY, WR), -1), make_wheel('wheel_RR', (WX, -WY, WR), 1)]

# ---------------------------------------------------------------- the Runner: hooded, goggled, masked, bandolier
D = Part('driver')
D.box((-.45, -.3, 1.2), (.5, .32, .55), CLOAK, .08)
D.cyl((-.45, -.5, 1.28), .28, .7, 'z', CLOAK, 10, r2=.12)
D.box((-.45, -.18, 1.3), (.1, .34, .62), BAND, .02, rot=(0, 0, .6))                  # bandolier
D.sph((-.45, -.18, 1.78), .19, SKIN)
D.box((-.45, -.04, 1.7), (.3, .1, .14), CLOAK, .03)                                  # face wrap
D.sph((-.45, -.24, 1.82), .23, CLOAK, sc=(1, 1.05, 1.0))
D.box((-.45, -.02, 1.82), (.32, .06, .1), GOGGLE, .02)
D.bar((-.6, -.05, 1.35), (-.5, .42, 1.22), .04, CLOAK); D.bar((-.3, -.05, 1.35), (-.4, .42, 1.22), .04, CLOAK)
D.box((-.45, -.62, 1.62), (.5, .5, .06), RAG, .03, rot=(.25, 0, 0))                  # scarf
driver = D.finish()

# ---------------------------------------------------------------- export
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_apply=True, export_yup=True, export_materials='EXPORT', export_cameras=False, export_lights=False)
print('EXPORTED', OUT)

# ---------------------------------------------------------------- a quick look (Workbench, no GPU needed)
if PREVIEW:
    sc = bpy.context.scene; sc.render.engine = 'BLENDER_WORKBENCH'; sc.render.resolution_x = 900; sc.render.resolution_y = 560
    sh = sc.display.shading; sh.light = 'STUDIO'; sh.color_type = 'MATERIAL'; sh.show_cavity = True
    try: sc.world = bpy.data.worlds.new('w'); sc.world.color = (.1, .06, .16)
    except Exception: pass
    cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); sc.collection.objects.link(cam); sc.camera = cam
    for name, loc in (('front34', (5.2, 5.6, 2.8)), ('rear34', (-5.0, -5.8, 3.0)), ('side', (7.2, .2, 1.6))):
        cam.location = loc; d = Vector((0, 0, 1.0)) - Vector(loc); cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = PREVIEW + '_' + name + '.png'; bpy.ops.render.render(write_still=True)
