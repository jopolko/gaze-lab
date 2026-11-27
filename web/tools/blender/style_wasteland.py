# Wasteland styling pass for a downloaded model: normalise size and facing, weather the colours (rust, dust, scratches), tint the paint, add welded-on parts.
#   blender -b -P style_wasteland.py -- <in.glb> <out.glb> <kind> <length_m> <tint hex> <tint strength>      kind: pickup | gunship | glider | generic
# Output faces +Y in Blender (-Z in three.js), origin at the centre on the ground, colours live in vertex colours.
import bpy, bmesh, sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bl_common import *
a = sys.argv[sys.argv.index('--') + 1:]
IN, OUT, KIND, LEN = a[0], a[1], a[2], float(a[3]); TINT = lin(int(a[4], 16))[:3] if len(a) > 4 else (1, 1, 1); TS = float(a[5]) if len(a) > 5 else 0.0
PALS = {
    "wasteland": dict(tint=0x6a4020, ts=.55, rust=(1.0, .5, .24), a1=None, a2=None, glow1=0, glow2=0),
    "pink": dict(tint=0x1c1030, ts=.92, rust=(.15, .85, .8), a1=(1.0, .08, .5), a2=(.1, .85, 1.0), glow1=0xff2fa0, glow2=0x19e6ff),
    "cyan": dict(tint=0x0c2038, ts=.9, rust=(.85, .2, .75), a1=(.05, .9, 1.0), a2=(1.0, .15, .7), glow1=0x19e6ff, glow2=0xff2fd0),
    "acid": dict(tint=0x142418, ts=.9, rust=(.7, .15, .9), a1=(.7, 1.0, .1), a2=(1.0, .35, .05), glow1=0xb8ff1a, glow2=0xff5a0a),
}
PAL = PALS[a[6]] if len(a) > 6 else PALS["wasteland"]
if len(a) > 6: TINT = lin(PAL["tint"])[:3]; TS = PAL["ts"]
FLIP = 0 if (len(a) > 7 and a[7] == '0') else 1         # the source models face the other way
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=IN)

# ---- flatten the node tree so every mesh has identity transform
bpy.ops.object.select_all(action='DESELECT')
for o in bpy.context.scene.objects:
    if o.type == 'MESH': o.select_set(True)
bpy.context.view_layer.objects.active = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM'); bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in [o for o in bpy.context.scene.objects if o.type != 'MESH']: bpy.data.objects.remove(o)
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']

# ---- normalise: size, facing (+Y), centred, sitting on the ground
def bounds():
    lo = Vector((1e9, 1e9, 1e9)); hi = Vector((-1e9, -1e9, -1e9))
    for o in meshes:
        for v in o.data.vertices:
            for i in range(3): lo[i] = min(lo[i], v.co[i]); hi[i] = max(hi[i], v.co[i])
    return lo, hi
lo, hi = bounds(); ext = hi - lo
if KIND == "char" and ext.z < max(ext.x, ext.y) * .7:
    Rx = Matrix.Rotation(math.pi / 2, 4, "X")
    for o in meshes: o.data.transform(Rx)
    lo, hi = bounds(); n_hi = sum(1 for o in meshes for v in o.data.vertices if v.co.z > lo.z + .85 * (hi.z - lo.z)); n_lo = sum(1 for o in meshes for v in o.data.vertices if v.co.z < lo.z + .15 * (hi.z - lo.z))
    if n_lo > n_hi:
        for o in meshes: o.data.transform(Matrix.Rotation(math.pi, 4, "X"))
    lo, hi = bounds(); ext = hi - lo
s = LEN / (ext.z if KIND == "char" else max(ext.x, ext.y))
ROT = (math.pi if FLIP else 0) + (math.pi / 2 if (ext.x > ext.y * 1.2 and KIND != "char") else 0)
cx, cy = (lo.x + hi.x) / 2, (lo.y + hi.y) / 2
M = Matrix.Rotation(ROT, 4, 'Z') @ Matrix.Scale(s, 4) @ Matrix.Translation((-cx, -cy, -lo.z))
for o in meshes: o.data.transform(M)
lo, hi = bounds(); W, L, H = hi.x - lo.x, hi.y - lo.y, hi.z
if KIND == "char" and W > H * .75:
    x0, zs, t = H * .16, H * .8, math.radians(68)
    for o in meshes:
        for v in o.data.vertices:
            ax = abs(v.co.x)
            if ax > x0 and v.co.z > H * .5:
                w = min(1.0, (ax - x0) / (H * .08)); ang = t * w; dx, dz = ax - x0, v.co.z - zs; sg = 1 if v.co.x >= 0 else -1
                v.co.x = sg * (x0 + dx * math.cos(ang) + dz * math.sin(ang)); v.co.z = zs - dx * math.sin(ang) + dz * math.cos(ang)
    lo, hi = bounds(); W, L, H = hi.x - lo.x, hi.y - lo.y, hi.z

MAXF = 3500
tot = sum(len(o.data.polygons) for o in meshes)
if tot > MAXF:
    for o in meshes:
        bpy.ops.object.select_all(action="DESELECT"); o.select_set(True); bpy.context.view_layer.objects.active = o
        md = o.modifiers.new("dec", "DECIMATE"); md.ratio = max(.05, MAXF / tot); bpy.ops.object.modifier_apply(modifier="dec")
    tot = sum(len(o.data.polygons) for o in meshes)
# ---- subdivide once so the weathering has something to paint on
NOSUB = len(a) > 8 and a[8] == "nosub"
for o in (meshes if (tot < 1800 and not NOSUB) else []):
    bm = bmesh.new(); bm.from_mesh(o.data); bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=1, use_grid_fill=True); bm.to_mesh(o.data); bm.free()

RUST = PAL["rust"]
def weather(co, base):
    x, y, z = co.x, co.y, co.z
    low = max(0.0, 1.0 - z / max(H * .6, .5))
    n = smooth_noise(x * 1.7, y * .6, z * 2.2, 2.4)
    patch = min(1.0, max(0.0, (n - .38) * 4.0) + .7 * low * smooth_noise(y * 1.6, x, z * 1.3, 4.2))
    streak = max(0.0, smooth_noise(x * 5.0, y * 1.2, z * .5, 3.0) - .5) * 2.6
    scratch = 1.0 if hnoise(math.floor(y * 3.4), math.floor(z * 6.5), math.floor(x * 2.2)) > .88 else 0.0
    r, g, b = base
    lum = (r + g + b) / 3
    paint = lum > .06
    if paint:
        r, g, b = r + (TINT[0] - r) * TS, g + (TINT[1] - g) * TS, b + (TINT[2] - b) * TS
        k = .78 - .3 * low - .3 * streak
        r, g, b = r * k, g * k, b * k
        r, g, b = r + (RUST[0] * lum * 1.6 - r) * patch * .9, g + (RUST[1] * lum * 1.6 - g) * patch * .9, b + (RUST[2] * lum * 1.6 - b) * patch * .9
        d = .4 * low; r, g, b = r * (1 - d) + .5 * d, g * (1 - d) + .42 * d, b * (1 - d) + .32 * d
        r, g, b = r * (1 - scratch * .5) + .5 * scratch * .5, g * (1 - scratch * .5) + .48 * scratch * .5, b * (1 - scratch * .5) + .44 * scratch * .5
    if paint and PAL["a1"]:                                   # painted accent bands: a wide stripe and a thin line
        side = abs(x) < W * .16 if KIND == "gunship" else abs(x) > W * .28
        if H * .36 < z < H * .46 and side: r, g, b = [c * .9 for c in PAL["a1"]]
        elif H * .52 < z < H * .545 and side: r, g, b = [c * .9 for c in PAL["a2"]]
    return (r, g, b)

def mat_base(m):
    if m and m.use_nodes:
        for n in m.node_tree.nodes:
            if n.type == 'BSDF_PRINCIPLED': return tuple(n.inputs['Base Color'].default_value[:3])
    return (.6, .6, .6)
for o in meshes:
    me = o.data; oldnames = [ca.name for ca in me.color_attributes]; oldact = me.color_attributes.active_color
    new = me.color_attributes.new('Col', 'FLOAT_COLOR', 'CORNER')
    bases = [mat_base(sl.material) for sl in o.material_slots]
    for poly in me.polygons:
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            if oldact is not None:
                c = oldact.data[li].color if oldact.domain == 'CORNER' else oldact.data[vi].color
                base = (c[0], c[1], c[2])
            else: base = bases[poly.material_index] if poly.material_index < len(bases) else (.6, .6, .6)
            w = weather(me.vertices[vi].co, base)
            new.data[li].color = (max(w[0], .02), max(w[1], .02), max(w[2], .02), 1.0)
    for nm in oldnames:
        ca_old = me.color_attributes.get(nm)
        if ca_old is not None: me.color_attributes.remove(ca_old)
    me.color_attributes.active_color = new
    for sl in o.material_slots:
        m = sl.material
        if m and m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type == 'BSDF_PRINCIPLED':
                    for inp in n.inputs:
                        for l in list(inp.links): m.node_tree.links.remove(l)
                    n.inputs['Base Color'].default_value = (1, 1, 1, 1); m.diffuse_color = (1, 1, 1, 1)
                    for nm in ('Emission Strength',):
                        if nm in n.inputs: n.inputs[nm].default_value = 0.0
                    if 'Emission Color' in n.inputs: n.inputs['Emission Color'].default_value = (0, 0, 0, 1)

# ---- welded-on parts
RUSTM = mat('rust_brown', 0x6e3a1e, .95, .3); SCRAP = mat('scrap', 0x5b5d63, .8, .6); DARK = mat('dark_metal', 0x1d1d22, .6, .5)
SOOT = mat('soot', 0x0d0c0e, .95); RAG = mat('rag', 0xa02818, .95); BONE = mat('bone', 0xd6cdb0, .8); CHROME = mat('chrome', 0xc9cdd8, .3, 1.0)
top = [v.co for o in meshes for v in o.data.vertices if v.co.z > H * .96]
rc = Vector((sum(v.x for v in top) / max(1, len(top)), sum(v.y for v in top) / max(1, len(top)), H))      # the highest point's centre (roof / rotor mast)
NA = mat("neon_a", PAL["glow1"] or 0xff2fa0, .2, 0, PAL["glow1"] or 0xff2fa0, 6); NB = mat("neon_b", PAL["glow2"] or 0x19e6ff, .2, 0, PAL["glow2"] or 0x19e6ff, 6); NEON = PAL["a1"] is not None
P = Part('added', lambda co, m: (1, 1, 1))
if KIND == 'pickup':
    fy = L / 2
    P.box((0, fy + .12, .62), (W * .96, .16, .2), SCRAP, .04)                                     # bumper
    for i in range(7): P.cyl((-W * .42 + i * W * .14, fy + .3, .62), .05, .28, 'y', DARK, 6, r2=0)  # bumper spikes
    for sx in (-1, 1): P.bar((sx * W * .36, fy + .2, .45), (sx * W * .36, fy + .2, 1.25), .04, SCRAP)
    P.bar((-W * .36, fy + .2, 1.25), (W * .36, fy + .2, 1.25), .04, SCRAP); P.bar((-W * .36, fy + .2, .9), (W * .36, fy + .2, .9), .035, SCRAP)
    P.sph((0, fy + .12, 1.0), .13, BONE, sc=(1, .8, 1.1)); P.sph((-.05, fy + .24, 1.03), .03, SOOT); P.sph((.05, fy + .24, 1.03), .03, SOOT)
    for sx in (-1, 1):
        P.box((sx * (W / 2 + .03), rc.y - .2, H * .55), (.05, L * .2, H * .22), RUSTM, .02); P.box((sx * (W / 2 + .03), rc.y - L * .22, H * .5), (.05, L * .16, H * .2), SCRAP, .02)
        P.bar((sx * W * .46, rc.y - L * .12, H * .6), (sx * W * .46, rc.y - L * .12, H + .5), .06, SOOT); P.cyl((sx * W * .46, rc.y - L * .12, H + .52), .08, .05, 'z', DARK, 10)   # exhaust stacks
    P.box((rc.x, rc.y - .5, H + .05), (W * .8, L * .22, .05), RUSTM, .02)                           # roof plate
    P.cyl((-.3, rc.y - .6, H + .38), .24, .5, 'z', RUSTM, 12); P.box((.35, rc.y - .55, H + .3), (.4, .3, .34), DARK, .04)   # drum + crate
    for k in range(4): P.box((-W / 2 - .02, -L * .1 + k * .3 - .3, H * .4), (.03, .1, .1), SOOT, 0)
    P.bar((W / 2 - .15, -L / 2 + .8, H * .4), (W / 2 - .15, -L / 2 + .8, H + 1.5), .012, DARK, 5); P.box((W / 2 - .15, -L / 2 + .66, H + 1.2), (.02, .3, .25), RAG, 0, rot=(0, 0, .3))
if KIND == 'pickup' and NEON:
    for sx in (-1, 1):
        P.box((sx * (W / 2 + .03), 0, H * .31), (.04, L * .62, .05), NA, .01); P.box((sx * (W / 2 + .03), 0, H * .535), (.04, L * .5, .03), NB, .01)
        P.sph((sx * W * .3, fy + .3, .85), .11, NB); P.sph((sx * .05, fy + .24, 1.03), .045, NA)
        P.box((sx * (W / 2 - .12), -L / 2 - .02, H * .38), (.4, .04, .12), NA, .01)
    P.box((0, 0, .16), (W * .62, L * .6, .03), NA, .01); P.box((rc.x, rc.y + L * .06, H + .12), (W * .7, .1, .07), NB, .01)
elif KIND == 'gunship':
    for sx in (-1, 1):
        P.box((sx * (W * .12), L * .1, H * .42), (.06, L * .18, H * .22), SCRAP, .02); P.box((sx * (W * .12), -L * .02, H * .4), (.06, L * .12, H * .2), RUSTM, .02)
        for k in range(4): P.cyl((sx * (W * .12 + .04), L * .05 + k * .35 - .4, H * .46), .03, .03, 'x', DARK, 6)   # rivets
    P.sph((0, L * .5, H * .3), .16, BONE, sc=(1, .8, 1.1)); P.sph((-.06, L * .5 + .12, H * .32), .035, SOOT); P.sph((.06, L * .5 + .12, H * .32), .035, SOOT)   # skull on the nose
    P.bar((0, -L * .48, H * .55), (0, -L * .48, H * .55 + 1.5), .012, DARK, 5); P.box((0, -L * .48 - .02, H * .55 + 1.3), (.02, .8, .5), RAG, 0, rot=(0, 0, .2))   # rag on the tail
if KIND == 'gunship' and NEON:
    P.sph((0, L * .5 + .1, H * .3), .13, NB); P.sph((-.06, L * .5 + .13, H * .32), .045, NA); P.sph((.06, L * .5 + .13, H * .32), .045, NA)
    for sx in (-1, 1): P.box((sx * (W * .06), L * .08, H * .45), (.04, L * .36, .05), NA, .01); P.box((sx * (W * .02), -L * .3, H * .4), (.04, L * .25, .04), NB, .01)
    P.box((0, -L * .3, H * .5), (.05, L * .3, .05), NA, .01); P.sph((0, -L * .48, H * .55), .08, NB)
def band(z0, z1, xlim=None):
    return [v.co.copy() for o in meshes for v in o.data.vertices if z0 <= v.co.z <= z1 and (xlim is None or abs(v.co.x) < xlim)]
def ext(vs, d=(-.5, .5, -1, 1)):
    return (min(v.x for v in vs), max(v.x for v in vs), min(v.y for v in vs), max(v.y for v in vs)) if vs else d
if KIND in ('generic', 'bus') and NEON:
    lx0, lx1, ly0, ly1 = ext(band(0, H * .3)); mx0, mx1, my0, my1 = ext(band(H * .25, H * .45)); fv = band(H * .2, H * .6); fy = max(v.y for v in fv) if fv else L / 2; cx = (mx0 + mx1) / 2
    for sx, xe in ((-1, mx0), (1, mx1)):
        P.box((xe + sx * .02, (my0 + my1) / 2, H * .3), (.04, (my1 - my0) * .55, .05), NA, .01); P.box((xe + sx * .02, (my0 + my1) / 2, H * .42), (.04, (my1 - my0) * .35, .03), NB, .01)
        P.sph((cx + sx * (mx1 - mx0) * .3, fy + .03, H * .38), .07, NB); P.sph((cx + sx * (mx1 - mx0) * .3, my0 - .02, H * .36), .05, NA)
    P.box(((lx0 + lx1) / 2, (ly0 + ly1) / 2, .1), ((lx1 - lx0) * .6, (ly1 - ly0) * .58, .03), NA, .01)
if KIND == 'bike' and NEON:
    lx0, lx1, ly0, ly1 = ext(band(0, H * .35), (-.3, .3, -1, 1)); fv = band(H * .2, H * .7); fy = max(v.y for v in fv) if fv else L / 2; ry = min(v.y for v in fv) if fv else -L / 2; cx = (lx0 + lx1) / 2
    P.box((cx, (ly0 + ly1) / 2, H * .5), (.03, (ly1 - ly0) * .4, .03), NA, .01); P.box((cx, (ly0 + ly1) / 2, H * .66), (.02, (ly1 - ly0) * .25, .02), NB, .01); P.box((cx, (ly0 + ly1) / 2, .07), (.16, (ly1 - ly0) * .5, .02), NA, .01)
if KIND == 'char' and NEON:
    hx0, hx1, hy0, hy1 = ext(band(H * .82, H)); tx0, tx1, ty0, ty1 = ext(band(H * .42, H * .58, .35)); cx = (hx0 + hx1) / 2
    P.box((cx, hy1 + .012, H * .93), ((hx1 - hx0) * .9, .03, .06), NB, .01); P.box(((tx0 + tx1) / 2, (ty0 + ty1) / 2, H * .5), ((tx1 - tx0) * 1.05, (ty1 - ty0) * 1.08, .04), NA, .01)
    P.box(((tx0 + tx1) / 2, ty1 + .012, H * .62), (.05, .02, .28), NB, .01); P.box(((tx0 + tx1) / 2, ty0 - .012, H * .62), (.05, .02, .28), NB, .01)
elif KIND == 'glider':
    P.box((0, 0, H * .5), (.001, .001, .001), DARK, 0)
P.finish()
for m in bpy.data.materials:
    if m.use_nodes:
        for n in [n for n in m.node_tree.nodes if n.type == 'TEX_IMAGE']: m.node_tree.nodes.remove(n)
for im in list(bpy.data.images): bpy.data.images.remove(im)
for o in bpy.context.scene.objects:
    if o.type == 'MESH': print('ATTRS', o.name, [(c.name, c.domain) for c in o.data.color_attributes], o.data.color_attributes.active_color_name if hasattr(o.data.color_attributes,'active_color_name') else '')
bpy.ops.object.select_all(action='SELECT')
kw = dict(filepath=OUT, export_format='GLB', export_apply=True, export_yup=True, export_materials='EXPORT', export_cameras=False, export_lights=False, export_animations=False)
try: bpy.ops.export_scene.gltf(export_vertex_color='ACTIVE', **kw)
except TypeError: bpy.ops.export_scene.gltf(**kw)
print('STYLED', OUT, 'size', round(W, 2), round(L, 2), round(H, 2))
