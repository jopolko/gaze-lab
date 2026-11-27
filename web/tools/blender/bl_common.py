# Shared helpers for the vehicle scripts: materials, a mesh builder with weathering (vertex colours) and lofted bodies, glb export.
import bpy, bmesh, sys, math
from mathutils import Matrix, Vector

def lin(h):
    r, g, b = ((h >> 16) & 255) / 255, ((h >> 8) & 255) / 255, (h & 255) / 255
    f = lambda c: c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4
    return (f(r), f(g), f(b), 1)

MATS = {}
def mat(name, hexc, rough=.7, metal=0.0, emit=None, emit_k=0.0):
    if name in MATS: return MATS[name]
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = lin(hexc); b.inputs['Roughness'].default_value = rough; b.inputs['Metallic'].default_value = metal
    if emit is not None:
        b.inputs['Emission Color'].default_value = lin(emit); b.inputs['Emission Strength'].default_value = emit_k
    m.diffuse_color = lin(hexc); MATS[name] = m; return m

def hnoise(x, y, z, k=1.0):  # cheap deterministic value noise in 0..1
    s = math.sin(x * 12.9898 * k + y * 78.233 * k + z * 37.719 * k) * 43758.5453
    return s - math.floor(s)
def smooth_noise(x, y, z, k):
    return .5 + .5 * (math.sin(x * k * 1.7 + math.sin(y * k * 1.1)) * .5 + math.sin(y * k * 1.3 - x * k * .7) * .3 + math.sin(z * k * 2.1 + x * k * .4) * .2)

class Part:
    """One exported object. weather(co, mat) -> (r,g,b) multiplier, applied per vertex."""
    def __init__(self, name, weather=None):
        self.name = name; self.bm = bmesh.new(); self.mats = []; self.weather = weather; self.cl = self.bm.loops.layers.color.new('Col')
    def mi(self, m):
        if m not in self.mats: self.mats.append(m)
        return self.mats.index(m)
    def _add(self, tmp, m, smooth):
        bm = self.bm; idx = self.mi(m); mp = {}
        for v in tmp.verts: mp[v] = bm.verts.new(v.co)
        for f in tmp.faces:
            nf = bm.faces.new([mp[v] for v in f.verts]); nf.material_index = idx; nf.smooth = smooth
            for lp in nf.loops:
                c = self.weather(lp.vert.co, m) if self.weather else (1, 1, 1)
                lp[self.cl] = (c[0], c[1], c[2], 1.0)
        tmp.free()
    def box(self, c, size, m, bevel=.03, rot=(0, 0, 0), seg=2, sub=0):
        t = bmesh.new(); bmesh.ops.create_cube(t, size=1.0)
        bmesh.ops.transform(t, matrix=Matrix.Diagonal((size[0], size[1], size[2], 1.0)), verts=t.verts)
        if sub: bmesh.ops.subdivide_edges(t, edges=list(t.edges), cuts=sub, use_grid_fill=True)   # more vertices so weathering has detail
        if bevel > 0: bmesh.ops.bevel(t, geom=list(t.edges), offset=min(bevel, min(size) * .45), segments=seg, affect='EDGES')
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
    def bar(self, p1, p2, r, m, seg=8):
        p1, p2 = Vector(p1), Vector(p2); d = p2 - p1; L = d.length
        t = bmesh.new(); bmesh.ops.create_cone(t, cap_ends=True, cap_tris=False, segments=seg, radius1=r, radius2=r, depth=L)
        q = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        bmesh.ops.transform(t, matrix=Matrix.Translation((p1 + p2) / 2) @ q, verts=t.verts)
        bmesh.ops.recalc_face_normals(t, faces=t.faces); self._add(t, m, True)
    def loft(self, rings, m, smooth=True, cap=True):
        """rings: list of closed rings (each a list of (x, y, z)), all with the same point count. Builds a skin through them."""
        t = bmesh.new(); vs = [[t.verts.new(p) for p in ring] for ring in rings]; n = len(rings[0])
        for i in range(len(rings) - 1):
            for j in range(n):
                t.faces.new((vs[i][j], vs[i][(j + 1) % n], vs[i + 1][(j + 1) % n], vs[i + 1][j]))
        if cap:
            t.faces.new(list(reversed(vs[0]))); t.faces.new(vs[-1])
        bmesh.ops.recalc_face_normals(t, faces=t.faces)
        if smooth: bmesh.ops.subdivide_edges(t, edges=[e for e in t.edges if len(e.link_faces) == 2], cuts=1, use_grid_fill=True)
        self._add(t, m, smooth)
    def finish(self, loc=(0, 0, 0)):
        me = bpy.data.meshes.new(self.name); self.bm.to_mesh(me); self.bm.free()
        for m in self.mats: me.materials.append(m)
        ob = bpy.data.objects.new(self.name, me); ob.location = loc; bpy.context.scene.collection.objects.link(ob); return ob

def ring(y, hb, hm, ht, zb, zm, zt):
    """An 8-point cross-section: bottom width hb, shoulder width hm, top width ht; heights zb (sill), zm (belt), zt (top)."""
    zl, zu = zb + (zm - zb) * .5, zm
    return [(-hb, y, zb), (hb, y, zb), (hm, y, zl), (hm, y, zu), (ht, y, zt), (-ht, y, zt), (-hm, y, zu), (-hm, y, zl)]

def export(out):
    bpy.ops.object.select_all(action='SELECT')
    kw = dict(filepath=out, export_format='GLB', export_apply=True, export_yup=True, export_materials='EXPORT', export_cameras=False, export_lights=False)
    try: bpy.ops.export_scene.gltf(export_vertex_color='ACTIVE', **kw)
    except TypeError: bpy.ops.export_scene.gltf(**kw)
    print('EXPORTED', out)
