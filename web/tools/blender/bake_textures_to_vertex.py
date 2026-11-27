# Turns a textured glTF into a small, texture-free .glb for the game: samples each texture at every vertex and stores it as a vertex colour.
#   blender -b -P bake_textures_to_vertex.py -- <in/scene.gltf> <out.glb> [grid]   (grid = texture size to sample at, default 256)
import bpy, sys, math
argv = sys.argv[sys.argv.index('--') + 1:]
SRC, OUT = argv[0], argv[1]; GRID = int(argv[2]) if len(argv) > 2 else 256
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

# skinned characters: bake the current pose into the mesh and drop the skeleton, so the plain mesh shows correctly
for ob in [o for o in bpy.context.scene.objects if o.type == 'MESH' and any(m.type == 'ARMATURE' for m in o.modifiers)]:
    bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True); bpy.context.view_layer.objects.active = ob
    try: bpy.ops.object.convert(target='MESH')
    except Exception as e: print('CONVERT FAIL', ob.name, e)
for ob in [o for o in bpy.context.scene.objects if o.type == 'ARMATURE']: bpy.data.objects.remove(ob)
cache = {}
def pixels(img):
    if img.name not in cache:
        w, h = img.size
        if w > GRID or h > GRID: img.scale(GRID, GRID)
        cache[img.name] = (img.size[0], img.size[1], list(img.pixels[:]), img.channels)
    return cache[img.name]
def sample(img, uv):
    w, h, px, ch = pixels(img); x = int((uv[0] % 1.0) * w) % w; y = int((uv[1] % 1.0) * h) % h; i = (y * w + x) * 4
    return (px[i], px[i + 1], px[i + 2])
def tex_of(m):
    if not m or not m.use_nodes: return None, (.6, .6, .6)
    base = (.8, .8, .8)
    for n in m.node_tree.nodes:
        if n.type == 'BSDF_PRINCIPLED':
            c = n.inputs['Base Color']; base = tuple(c.default_value[:3])
            if c.is_linked and c.links[0].from_node.type == 'TEX_IMAGE': return c.links[0].from_node.image, base
    return None, base

for ob in [o for o in bpy.context.scene.objects if o.type == 'MESH']:
    me = ob.data; ca = me.color_attributes.new('Col', 'FLOAT_COLOR', 'CORNER'); uvl = me.uv_layers.active
    info = [tex_of(s.material) for s in ob.material_slots]
    for poly in me.polygons:
        img, base = info[poly.material_index] if poly.material_index < len(info) else (None, (.6, .6, .6))
        for li in poly.loop_indices:
            if img and uvl: r, g, b = sample(img, uvl.data[li].uv)
            else: r, g, b = base
            ca.data[li].color = (r, g, b, 1.0)
    # the colour now lives in the vertices: make every material plain white so it is not applied twice
    for s in ob.material_slots:
        m = s.material
        if m and m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type == 'BSDF_PRINCIPLED':
                    for inp in n.inputs:
                        for l in list(inp.links): m.node_tree.links.remove(l)
                    n.inputs['Base Color'].default_value = (1, 1, 1, 1); m.diffuse_color = (1, 1, 1, 1)
bpy.ops.object.select_all(action='SELECT')
try: bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_apply=True, export_yup=True, export_materials='EXPORT', export_vertex_color='ACTIVE', export_cameras=False, export_lights=False, export_animations=False)
except TypeError: bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_apply=True, export_yup=True, export_materials='EXPORT', export_cameras=False, export_lights=False)
print('BAKED', OUT)
