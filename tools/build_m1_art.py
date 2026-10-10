#!/usr/bin/env python3
"""Prompt 07 (M1 art): enemies, boss, hero looks and weapons from repository parts only.

Same method as 01b (build_enemy_test.py): the CC0 Quaternius outfits and bodies on their
shared 65-bone rig, plus scripted rigid pieces (helmets, plates, masks, horns, cloaks)
skinned to existing bones. No new skeleton, no new animation, no downloads, no AI models.

Run prepare_m1_textures.py first, then either
  blender --background --factory-startup --python tools/build_m1_art.py
or, with the `bpy` wheel (Blender as a Python module, used on 10-10-2026: bpy 5.0.1):
  python3.11 tools/build_m1_art.py
GLBs reference the shared PNGs next to them; source models stay untouched.
"""
from pathlib import Path
import json, math, struct, tempfile
import bpy, bmesh
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
CHAR = ASSETS / "characters"
WEAPONS = ASSETS / "weapons"
CHAR_TRIANGLE_BUDGET = 32000
WEAPON_TRIANGLE_BUDGET = 1500

# ---------------------------------------------------------------- materials / export

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    return m


SKIN = {
    "male": {"albedo": "../textures/T_Superhero_Male_Dark.png", "normal": "../textures/T_Superhero_Male_Normal.png", "orm": "../textures/T_Superhero_Male_Roughness.png"},
    "female": {"albedo": "../textures/T_Superhero_Female_Dark_BaseColor.png", "normal": "../textures/T_Superhero_Female_Normal.png", "orm": "../textures/T_Superhero_Female_Roughness.png"},
}
HANDS = {
    "male": {"albedo": "../textures/T_Regular_Male_Dark_BaseColor.png", "normal": "../textures/T_Regular_Male_Normal.png", "orm": "../textures/T_Regular_Male_Roughness.png", "metal": 0},
    "female": {"albedo": "../textures/T_Regular_Female_Dark_BaseColor.png", "normal": "../textures/T_Regular_Female_Normal.png", "orm": "../textures/T_Regular_Female_Roughness.png", "metal": 0},
}
EYES = {"albedo": "../textures/T_Eye_Brown.png", "normal": "../textures/T_Eye_Normal.png", "rough": .35}
METAL_C = {"albedo": "../../weapons/textures/forged_albedo.png", "normal": "../../weapons/textures/surface_normal.png", "orm": "../../weapons/textures/surface_orm.png", "metal": 1, "rough": .6}
WOOD_C = {"albedo": "../../weapons/textures/haft_albedo.png", "normal": "../../weapons/textures/surface_normal.png", "orm": "../../weapons/textures/surface_orm.png", "metal": 0, "rough": 1}


def outfit(albedo, atlas="Ranger"):
    return {"albedo": "../m1_textures/" + albedo, "normal": f"../textures/T_{atlas}_Normal.png", "orm": f"../textures/T_{atlas}_ORM.png", "metal": 1, "rough": 1}


def cloth(albedo):
    return {"albedo": "../m1_textures/" + albedo, "normal": "../textures/T_Peasant_Normal.png", "metal": 0, "rough": .95}


def tinted(base, color, **extra):
    spec = dict(base); spec["color"] = color; spec.update(extra); return spec


def export(objects, output, maps):
    """Pack geometry and remap material images to shared PNGs (01b exporter, plus doubleSided/emission flags)."""
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / "model.gltf"
        bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLTF_SEPARATE",
                                  use_selection=True, export_animations=False,
                                  export_cameras=False, export_lights=False,
                                  export_skins=True, export_yup=True)
        doc = json.loads(path.read_text())
        binary = bytearray((Path(folder) / doc["buffers"][0]["uri"]).read_bytes())
        doc["buffers"] = [{"byteLength": len(binary)}]
        doc["images"], doc["textures"] = [], []
        doc["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]
        uris = {}

        def texture(uri):
            if uri not in uris:
                uris[uri] = len(doc["images"])
                doc["images"].append({"uri": uri})
                doc["textures"].append({"source": uris[uri], "sampler": 0})
            return {"index": uris[uri]}

        for m in doc.get("materials", []):
            original = m["name"].split(".")[0]
            spec = maps[original]
            m.clear(); m.update({"name": original, "doubleSided": spec.get("double", True)})
            pbr = {"baseColorFactor": spec.get("color", [1, 1, 1, 1]),
                   "metallicFactor": spec.get("metal", 0), "roughnessFactor": spec.get("rough", 1)}
            if "albedo" in spec:
                pbr["baseColorTexture"] = texture(spec["albedo"])
            if "orm" in spec:
                pbr["metallicRoughnessTexture"] = texture(spec["orm"])
            m["pbrMetallicRoughness"] = pbr
            if "normal" in spec:
                m["normalTexture"] = dict(texture(spec["normal"]), scale=spec.get("normal_scale", .7))
            if "emission" in spec:
                m["emissiveFactor"] = spec["emission"]
                m["extensions"] = {"KHR_materials_emissive_strength": {"emissiveStrength": spec.get("emission_strength", 3)}}
                if "KHR_materials_emissive_strength" not in doc.setdefault("extensionsUsed", []):
                    doc["extensionsUsed"].append("KHR_materials_emissive_strength")
        encoded = json.dumps(doc, separators=(",", ":")).encode()
        encoded += b" " * (-len(encoded) % 4)
        binary.extend(b"\0" * (-len(binary) % 4))
        payload = struct.pack("<III", 0x46546C67, 2, 28 + len(encoded) + len(binary))
        payload += struct.pack("<II", len(encoded), 0x4E4F534A) + encoded
        payload += struct.pack("<II", len(binary), 0x004E4942) + binary
        output.write_bytes(payload)
        return sum(doc["accessors"][p["indices"]]["count"] // 3
                   for mesh in doc["meshes"] for p in mesh["primitives"])

# ---------------------------------------------------------------- geometry helpers

def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def from_bmesh(name, bm, mat):
    data = bpy.data.meshes.new(name)
    bm.to_mesh(data); bm.free()
    obj = link(bpy.data.objects.new(name, data))
    data.materials.append(mat)
    if not data.uv_layers:
        box_uv(obj)
    return obj


def from_pydata(name, verts, faces, mat):
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces); data.validate(); data.update()
    obj = link(bpy.data.objects.new(name, data))
    data.materials.append(mat)
    box_uv(obj)
    return obj


def box_uv(obj, scale=2.5):
    """Simple box projection: tiling detail maps (metal, wood, bone) need no atlas."""
    data = obj.data
    uv = data.uv_layers.new(name="UVMap")
    for poly in data.polygons:
        n = poly.normal
        axis = max(range(3), key=lambda i: abs(n[i]))
        for loop in poly.loop_indices:
            v = data.vertices[data.loops[loop].vertex_index].co
            a, b = [(v.y, v.z), (v.x, v.z), (v.x, v.y)][axis]
            uv.data[loop].uv = (a * scale + .5, b * scale + .5)


def frame(direction):
    d = direction.normalized()
    helper = Vector((0, 0, 1)) if abs(d.z) < .9 else Vector((1, 0, 0))
    u = d.cross(helper).normalized()
    return u, d.cross(u).normalized()


def tube(name, points, radii, mat, sides=8, cap=True, squash=1.0):
    """Ring sweep along a polyline: horns, bow limbs, curved hafts, hat cones."""
    points = [Vector(p) for p in points]
    verts, faces = [], []
    for i, p in enumerate(points):
        d = (points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)])
        u, w = frame(d)
        for s in range(sides):
            a = 2 * math.pi * s / sides
            verts.append(p + (u * math.cos(a) + w * math.sin(a) * squash) * radii[i])
    for i in range(len(points) - 1):
        for s in range(sides):
            a, b = i * sides + s, i * sides + (s + 1) % sides
            faces.append((a, b, b + sides, a + sides))
    if cap:
        faces.append(tuple(range(sides - 1, -1, -1)))
        if radii[-1] > .0015:
            faces.append(tuple(range((len(points) - 1) * sides, len(points) * sides)))
    return from_pydata(name, verts, faces, mat)


def prism(name, profile, thickness, mat, bevel=.004, axis="y", offset=0.0):
    """Extrude an (x, z) outline along Y: blades, guards, shield faces."""
    n = len(profile)
    verts = [(x, offset - thickness / 2, z) for x, z in profile] + [(x, offset + thickness / 2, z) for x, z in profile]
    faces = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
    faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    obj = from_pydata(name, verts, faces, mat)
    if bevel:
        apply(obj, ("BEVEL", {"width": bevel, "segments": 1, "limit_method": "ANGLE"}))
    return obj


def cylinder(name, radius, depth, center, mat, sides=10, axis=(0, 0, 1), radius2=None):
    axis = Vector(axis).normalized(); c = Vector(center)
    return tube(name, [c - axis * depth / 2, c + axis * depth / 2], [radius, radius if radius2 is None else radius2], mat, sides)


def sphere(name, radius, center, mat, segments=10, rings=6, scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
    for v in bm.verts:
        v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2])) + Vector(center)
    return from_bmesh(name, bm, mat)


def apply(obj, *modifiers):
    """Evaluate modifiers without operators (works in background Blender and the bpy wheel)."""
    # Existing (armature) modifiers stay on the object but are left out of the bake.
    existing = list(obj.modifiers)
    for mod in existing:
        mod.show_viewport = False
    added = []
    for kind, props in modifiers:
        mod = obj.modifiers.new(kind.title(), kind)
        for key, value in props.items():
            setattr(mod, key, value)
        added.append(mod)
    graph = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(graph), preserve_all_data_layers=True, depsgraph=graph)
    old = obj.data
    for mod in added:
        obj.modifiers.remove(mod)
    for mod in existing:
        mod.show_viewport = True
    obj.data = mesh
    bpy.data.meshes.remove(old)
    return obj


def delete_verts(obj, predicate):
    bm = bmesh.new(); bm.from_mesh(obj.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if predicate(obj.matrix_world @ v.co)], context="VERTS")
    bm.to_mesh(obj.data); bm.free()


def merge(name, objects):
    """Join rigid pieces into one mesh (fewer draw calls) keeping per-object materials."""
    target = objects[0]
    bm = bmesh.new()
    mats = []
    for obj in objects:
        offset = len(mats)
        for slot in obj.data.materials:
            mats.append(slot)
        part = bmesh.new(); part.from_mesh(obj.data)
        for face in part.faces:
            face.material_index += offset
        part.transform(obj.matrix_world)
        temp = bpy.data.meshes.new("tmp"); part.to_mesh(temp); part.free()
        bm.from_mesh(temp); bpy.data.meshes.remove(temp)
    data = bpy.data.meshes.new(name); bm.to_mesh(data); bm.free()
    for m in mats:
        data.materials.append(m)
    for obj in objects:
        bpy.data.objects.remove(obj, do_unlink=True)
    result = link(bpy.data.objects.new(name, data))
    # Identical material slots collapse into one surface per material.
    unique = []
    for m in data.materials:
        if m not in unique:
            unique.append(m)
    remap = [unique.index(m) for m in data.materials]
    for poly in data.polygons:
        poly.material_index = remap[poly.material_index]
    data.materials.clear()
    for m in unique:
        data.materials.append(m)
    return result


def skin_to(obj, rig, weights):
    """weights: callable(world_co) -> {bone: weight}. Rigid pieces return one bone."""
    obj.parent = rig
    groups = {}
    for v in obj.data.vertices:
        for bone, w in weights(obj.matrix_world @ v.co).items():
            if w <= 0:
                continue
            if bone not in groups:
                groups[bone] = obj.vertex_groups.new(name=bone)
            groups[bone].add([v.index], w, "REPLACE")
    mod = obj.modifiers.new("Armature", "ARMATURE"); mod.object = rig
    return obj


def rigid(bone):
    return lambda co: {bone: 1.0}

# ---------------------------------------------------------------- character assembly

class Figure:
    def __init__(self, outfit_name, keep, gender):
        reset()
        bpy.ops.import_scene.gltf(filepath=str(CHAR / outfit_name / "model.glb"))
        self.rig = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
        self.gender = gender
        self.parts = []
        for obj in list(bpy.context.scene.objects):
            if obj.type != "MESH":
                continue
            if obj.parent != self.rig:
                bpy.data.objects.remove(obj, do_unlink=True); continue
            short = obj.name.split("_", 2)[-1].split(".")[0]
            if obj.name.endswith(".001") or short not in keep:
                bpy.data.objects.remove(obj, do_unlink=True); continue
            if short.startswith("Feet") or short == "Arms_Bracer":
                # 01b: dense boot/bracer detail is mostly hidden under hems and sleeves.
                apply(obj, ("DECIMATE", {"ratio": .45}))
            self.parts.append(obj)
        self.head = None

    def borrow(self, outfit_name, shorts, mat):
        """Take extra pieces from another outfit on the same rig (e.g. Ranger bracers)."""
        before = set(bpy.context.scene.objects)
        bpy.ops.import_scene.gltf(filepath=str(CHAR / outfit_name / "model.glb"))
        imported = set(bpy.context.scene.objects) - before
        for obj in imported:
            short = obj.name.split("_", 2)[-1].split(".")[0] if obj.type == "MESH" else ""
            if obj.type == "MESH" and short in shorts and not obj.name.endswith(".001"):
                world = obj.matrix_world.copy()
                obj.parent = self.rig; obj.matrix_world = world
                for modifier in obj.modifiers:
                    if modifier.type == "ARMATURE":
                        modifier.object = self.rig
                for slot in obj.material_slots:
                    slot.material = mat
                if short == "Arms_Bracer":
                    apply(obj, ("DECIMATE", {"ratio": .45}))
                self.parts.append(obj)
            else:
                bpy.data.objects.remove(obj, do_unlink=True)

    def part(self, short):
        return next(o for o in self.parts if o.name.split("_", 2)[-1].split(".")[0] == short)

    def dress(self, outfit_mat, hands_mat):
        for obj in self.parts:
            for slot in obj.material_slots:
                slot.material = hands_mat if "Regular" in slot.material.name else outfit_mat

    def add_head(self, skin_mat, eye_mat, brow_mat=None):
        source = "superhero_male_fullbody" if self.gender == "male" else "superhero_female_fullbody"
        before = set(bpy.context.scene.objects)
        bpy.ops.import_scene.gltf(filepath=str(CHAR / source / "model.glb"))
        imported = set(bpy.context.scene.objects) - before
        body = next(o for o in imported if o.type == "MESH" and o.name.lower().startswith("superhero"))
        eyes = next(o for o in imported if o.type == "MESH" and o.name.startswith("Eyes"))
        brows = next(o for o in imported if o.type == "MESH" and o.name.startswith("Eyebrows"))
        cut = 1.51 if self.gender == "male" else 1.47
        delete_verts(body, lambda co: co.z < cut)
        keep = [(body, skin_mat), (eyes, eye_mat)] + ([(brows, brow_mat)] if brow_mat else [])
        for obj, mat in keep:
            world = obj.matrix_world.copy()
            obj.parent = self.rig; obj.matrix_world = world
            for modifier in obj.modifiers:
                if modifier.type == "ARMATURE":
                    modifier.object = self.rig
            obj.data.materials.clear(); obj.data.materials.append(mat)
            for face in obj.data.polygons:
                face.material_index = 0
            self.parts.append(obj)
        for obj in imported:
            if all(obj is not k for k, _ in keep):
                bpy.data.objects.remove(obj, do_unlink=True)
        self.head, self.eyes = body, eyes
        left = [eyes.matrix_world @ v.co for v in eyes.data.vertices if (eyes.matrix_world @ v.co).x > 0]
        self.eye = sum(left, Vector()) / len(left)          # left eye centre
        self.head_centre = Vector((0, self.eye.y + .085, self.eye.z + .012))
        return body

    def bone_head(self, name):
        return self.rig.matrix_world @ self.rig.data.bones[name].head_local

    def add(self, obj, weights):
        skin_to(obj, self.rig, weights)
        self.parts.append(obj)
        return obj

    def export(self, folder, maps, scale=1.0):
        if scale != 1.0:
            self.rig.scale = (scale, scale, scale)
        triangles = export([self.rig] + self.parts, CHAR / folder / "model.glb", maps)
        assert triangles <= CHAR_TRIANGLE_BUDGET, (folder, triangles)
        return {"triangles": triangles, "parts": sorted(o.name for o in self.parts)}

# ---- pieces built on a figure ------------------------------------------------------

def lengthen_tunic(fig, waist, hem, flare=.65, wave=.04, depth=.3):
    """01b robe method, parameterised: stretch the tunic skirt below `waist` down to `hem`."""
    obj = fig.part("Body")
    bottom = min(v.co.z for v in obj.data.vertices)
    factor = (waist - hem) / (waist - bottom)
    pelvis, left, right = (obj.vertex_groups.get(n) for n in ("pelvis", "thigh_l", "thigh_r"))
    for v in obj.data.vertices:
        z = v.co.z
        if z >= waist:
            continue
        t = min(1, (waist - z) / (waist - bottom))
        v.co.z = waist - (waist - z) * factor
        v.co.x *= 1 + flare * t
        v.co.y = .04 + (v.co.y - .04) * (1 + depth * t)
        if t > .7:
            v.co.z += wave * math.sin(v.co.x * 53 + v.co.y * 31)
        for group in obj.vertex_groups:
            group.remove([v.index])
        pelvis.add([v.index], 1 - t * .6, "REPLACE")
        (right if v.co.x < 0 else left).add([v.index], t * .6, "REPLACE")


def mirror_part(fig, short, name, mat):
    """Copy a left-side piece to the right: X mirrored, flipped winding, _l/_r groups swapped."""
    src = fig.part(short)
    obj = src.copy(); obj.data = src.data.copy(); obj.name = name
    link(obj)
    bm = bmesh.new(); bm.from_mesh(obj.data)
    for v in bm.verts:
        v.co.x = -v.co.x
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(obj.data); bm.free()
    for group in obj.vertex_groups:
        if group.name.endswith("_l"):
            group.name = group.name[:-2] + "_tmp"
    for group in obj.vertex_groups:
        if group.name.endswith("_r"):
            group.name = group.name[:-2] + "_l"
    for group in obj.vertex_groups:
        if group.name.endswith("_tmp"):
            group.name = group.name[:-4] + "_r"
    obj.data.materials.clear(); obj.data.materials.append(mat)
    for face in obj.data.polygons:
        face.material_index = 0
    fig.parts.append(obj)
    return obj


def cuirass(fig, mat, top, bottom, inflate=.022, rings=8, sides=24):
    """A smooth plate shell around the existing torso. Each ring vertex sits just outside the
    furthest tunic vertex in its direction; radii are then relaxed so cloth folds vanish."""
    body = fig.part("Body")
    centre_y = .03
    points = [v.co.copy() for v in body.data.vertices if bottom - .04 < v.co.z < top + .04]
    radii = []
    for r in range(rings):
        z = bottom + (top - bottom) * r / (rings - 1)
        row = []
        for s_ in range(sides):
            a = 2 * math.pi * s_ / sides
            best = .08
            for p in points:
                if abs(p.z - z) > .035:
                    continue
                dx, dy = p.x, p.y - centre_y
                diff = abs((math.atan2(dy, dx) - a + math.pi) % (2 * math.pi) - math.pi)
                if diff < .2:
                    best = max(best, math.hypot(dx, dy))
            row.append(best)
        radii.append(row)
    for _ in range(4):
        radii = [[(radii[r][s_] * 2 + radii[r][s_ - 1] + radii[r][(s_ + 1) % sides] +
                   radii[max(r - 1, 0)][s_] + radii[min(r + 1, rings - 1)][s_]) / 6
                  for s_ in range(sides)] for r in range(rings)]
    verts, faces = [], []
    for r in range(rings):
        z = bottom + (top - bottom) * r / (rings - 1)
        for s_ in range(sides):
            a = 2 * math.pi * s_ / sides
            radius = radii[r][s_] + inflate
            verts.append((math.cos(a) * radius, centre_y + math.sin(a) * radius, z))
    for r in range(rings - 1):
        for s_ in range(sides):
            a, b = r * sides + s_, r * sides + (s_ + 1) % sides
            faces.append((a, a + sides, b + sides, b))
    obj = from_pydata("Plate_Cuirass", verts, faces, mat)
    apply(obj, ("SUBSURF", {"levels": 1}), ("SOLIDIFY", {"thickness": .01, "offset": 1}))
    obj.data.uv_layers.remove(obj.data.uv_layers[0]); box_uv(obj, 3)
    return fig.add(obj, torso_weights(fig))


def skirt_material(fig, waist, mat):
    """Faces fully below the waist (the lengthened skirt) get their own atlas variant."""
    obj = fig.part("Body")
    obj.data.materials.append(mat)
    index = len(obj.data.materials) - 1
    for poly in obj.data.polygons:
        if all(obj.data.vertices[i].co.z < waist - .02 for i in poly.vertices):
            poly.material_index = index


def surface_y(fig, x, z, front=True, names=("Body", "Legs")):
    best = None
    for short in names:
        try:
            obj = fig.part(short)
        except StopIteration:
            continue
        for v in obj.data.vertices:
            if abs(v.co.x - x) < .05 and abs(v.co.z - z) < .05:
                if best is None or (v.co.y < best if front else v.co.y > best):
                    best = v.co.y
    return best


def hanging_panel(fig, name, mat, top, bottom, width_top, width_bottom, front, gap=.022,
                  flare=.04, rows=12, cols=6, weights=None):
    """Tabards and cloaks: a cloth grid sampled to the existing body surface, then let fall."""
    verts, faces = [], []
    last = .0
    for r in range(rows + 1):
        t = r / rows
        z = top + (bottom - top) * t
        half = width_top + (width_bottom - width_top) * t
        for c in range(cols + 1):
            x = -half + 2 * half * c / cols
            y = surface_y(fig, x * .8, z, front)
            y = last if y is None else y
            last = y
            fall = flare * t * t
            y = y - gap - fall if front else y + gap + fall
            # A slight curve around the body keeps edges from cutting into the hips.
            y += (abs(x) / max(half, .01)) ** 2 * (.03 if front else -.03)
            verts.append((x, y, z))
    for r in range(rows):
        for c in range(cols):
            a = r * (cols + 1) + c
            quad = (a, a + 1, a + cols + 2, a + cols + 1)
            faces.append(quad if not front else quad[::-1])
    obj = from_pydata(name, verts, faces, mat)
    apply(obj, ("SOLIDIFY", {"thickness": .006, "offset": 0}))
    return fig.add(obj, weights)


def shell(fig, name, mat, target, offset, keep, segments=24, rings=16, radius=.25):
    """A sphere shrink-wrapped onto the head (or hood) and trimmed: caps, masks, helmets."""
    obj = sphere(name, radius, fig.head_centre, mat, segments, rings)
    apply(obj, ("SHRINKWRAP", {"target": target, "offset": offset, "wrap_method": "NEAREST_SURFACEPOINT"}))
    delete_verts(obj, lambda co: not keep(co))
    apply(obj, ("SOLIDIFY", {"thickness": .006, "offset": 1}))
    box_uv(obj, 6)
    return fig.add(obj, rigid("Head"))


def ring(name, centre, inner, outer, z_drop, mat, sides=24, sy=1.0, thickness=.008):
    c = Vector(centre)
    verts, faces = [], []
    for s in range(sides):
        a = 2 * math.pi * s / sides
        d = Vector((math.cos(a), math.sin(a) * sy, 0))
        verts += [c + d * inner, c + d * outer + Vector((0, 0, -z_drop))]
    for s in range(sides):
        a, b = 2 * s, 2 * ((s + 1) % sides)
        faces.append((a, b, b + 1, a + 1))
    obj = from_pydata(name, verts, faces, mat)
    return apply(obj, ("SOLIDIFY", {"thickness": thickness, "offset": 0}))


def torso_weights(fig):
    def weights(co):
        z = co.z
        if z > 1.36:
            return {"spine_03": 1}
        if z > 1.2:
            t = (z - 1.2) / .16; return {"spine_03": t, "spine_02": 1 - t}
        if z > 1.04:
            t = (z - 1.04) / .16; return {"spine_02": t, "spine_01": (1 - t) * .5, "pelvis": (1 - t) * .5}
        t = min(1, (1.04 - z) / .5)
        return {"pelvis": 1 - t * .5, "thigh_l": t * .25, "thigh_r": t * .25}
    return weights


def cloak_weights(fig):
    def weights(co):
        z = co.z
        if z > 1.38:
            side = co.x / .2
            return {"spine_03": .7, "clavicle_l": max(0, side) * .3, "clavicle_r": max(0, -side) * .3, "neck_01": .0}
        if z > 1.05:
            t = (z - 1.05) / .33; return {"spine_03": t, "spine_01": 1 - t}
        t = min(1, (1.05 - z) / .8)
        return {"pelvis": 1 - t * .3, "thigh_l": t * .15, "thigh_r": t * .15}
    return weights

# ---------------------------------------------------------------- figures

def guard():
    fig = Figure("male_ranger", {"Arms", "Arms_Bracer", "Body", "Body_Belt_1", "Feet_Boots", "Head_Hood", "Legs", "Acc_Pauldron"}, "male")
    cloth_m, hands, skin, eyes = (material(n) for n in ("GuardGambeson", "GuardHands", "GuardSkin", "GuardEyes"))
    mail, steel, tabard, leather = (material(n) for n in ("GuardMail", "GuardSteel", "GuardTabard", "GuardLeather"))
    fig.dress(cloth_m, hands)
    fig.part("Head_Hood").data.materials[0] = mail          # the hood becomes a mail coif
    fig.part("Acc_Pauldron").data.materials[0] = steel
    mirror_part(fig, "Acc_Pauldron", "Guard_Pauldron_R", steel)
    fig.add_head(skin, eyes)
    hood = fig.part("Head_Hood")
    brow = fig.eye.z + .045
    # Kettle hat: a dome wrapped over the coif plus a wide, slightly dropped brim.
    dome = shell(fig, "Kettle_Dome", steel, hood, .012, lambda co: co.z > brow)
    hat_r = max(abs(v.co.x) for v in dome.data.vertices)
    brim = ring("Kettle_Brim", (0, fig.head_centre.y, brow + .002), hat_r * .92, hat_r + .09, .045, steel, sy=1.08)
    box_uv(brim, 6); fig.add(brim, rigid("Head"))
    comb = prism("Kettle_Comb", [(-.0, brow + .02)] + [(math.cos(a) * hat_r * .95, brow + .02 + math.sin(a) * (max(v.co.z for v in dome.data.vertices) - brow + .006)) for a in [i * math.pi / 8 for i in range(9)]],
                 .01, steel, bevel=.002)
    comb.rotation_euler = (0, 0, math.pi / 2); comb.location = (0, fig.head_centre.y, 0)
    bpy.context.view_layer.update()
    fig.add(comb, rigid("Head"))
    # City tabard, front and back.
    hanging_panel(fig, "Tabard_Front", tabard, 1.45, .62, .15, .19, True, weights=torso_weights(fig))
    hanging_panel(fig, "Tabard_Back", tabard, 1.45, .64, .16, .19, False, weights=torso_weights(fig))
    maps = {
        "GuardGambeson": outfit("guard_albedo.png"), "GuardHands": HANDS["male"], "GuardSkin": SKIN["male"], "GuardEyes": EYES,
        "GuardMail": tinted(METAL_C, [.62, .62, .64, 1], metal=.6, rough=.6, normal_scale=1.4),
        "GuardSteel": tinted(METAL_C, [.78, .78, .8, 1], metal=.6, rough=.5),
        "GuardTabard": cloth("cloth_red.png"), "GuardLeather": tinted(WOOD_C, [.5, .32, .2, 1]),
    }
    return fig.export("enemy_guard", maps)


def bandit():
    fig = Figure("male_peasant", {"Arms", "Body", "Feet", "Legs"}, "male")
    cloth_m, hands, skin, eyes = (material(n) for n in ("BanditCloth", "BanditHands", "BanditSkin", "BanditEyes"))
    red, black, leather, wood = (material(n) for n in ("BanditBandana", "BanditMask", "BanditLeather", "BanditWood"))
    fig.dress(cloth_m, hands)
    fig.borrow("male_ranger", {"Acc_Pauldron", "Arms_Bracer"}, material("BanditGear"))
    fig.add_head(skin, eyes, material("BanditBrows"))
    head = fig.head
    e = fig.eye
    # Bandana: a fitted cloth cap tied above the brows, with two knot tails behind.
    shell(fig, "Bandana", red, head, .009, lambda co: co.z > e.z + .03 - (co.y - e.y) * .25)
    back = fig.head_centre + Vector((0, .1, .02))
    for side in (-1, 1):
        tail = tube("Bandana_Tail", [back + Vector((side * .015, 0, 0)), back + Vector((side * .04, .04, -.06)), back + Vector((side * .05, .05, -.14))],
                    [.018, .016, .01], red, sides=4, squash=.25)
        fig.add(tail, rigid("Head"))
    # Face cloth over nose, mouth and chin; hangs as a point under the chin.
    shell(fig, "Face_Cloth", black, head, .008, lambda co: co.y < fig.head_centre.y - .035 and e.z - .105 < co.z < e.z - .022)
    # Bolt quiver on the back.
    spine = fig.bone_head("spine_03")
    base = Vector((-.10, spine.y + .17, 1.13)); top = Vector((-.02, spine.y + .2, 1.55))
    pieces = [cylinder("Quiver", .045, (top - base).length, (base + top) / 2, leather, axis=top - base, sides=10)]
    for i in range(4):
        tip = top + Vector(((i - 1.5) * .018, .0, .07 + .01 * (i % 2)))
        pieces.append(cylinder("Bolt", .005, .14, tip - Vector((0, 0, .05)), wood, sides=4))
        pieces.append(prism("Fletch", [(-.012, 0), (.012, 0), (0, .04)], .003, black, bevel=0, offset=0))
        pieces[-1].location = tip + Vector((0, 0, .015)); bpy.context.view_layer.update()
    fig.add(merge("Bandit_Quiver", pieces), rigid("spine_03"))
    # A leather belt with a dagger sheath on the left hip.
    belt = cylinder("Belt", .175, .05, (0, .02, 1.06), leather, sides=16)
    fig.add(belt, lambda co: {"pelvis": 1})
    maps = {
        "BanditCloth": outfit("bandit_albedo.png", "Peasant"), "BanditGear": outfit("bandit_gear_albedo.png"), "BanditHands": HANDS["male"], "BanditSkin": SKIN["male"],
        "BanditEyes": EYES, "BanditBrows": {"albedo": "../textures/T_Hair_1_BaseColor.png", "rough": .8},
        "BanditBandana": cloth("cloth_red.png"), "BanditMask": cloth("cloth_black.png"),
        "BanditLeather": tinted(WOOD_C, [.45, .28, .18, 1]), "BanditWood": WOOD_C,
    }
    return fig.export("enemy_bandit", maps)


def cultist():
    fig = Figure("female_ranger", {"Arms", "Arms_Bracer", "Body", "Body_Belt_1", "Feet", "Head_Hood", "Legs"}, "female")
    robe, hands, skin, eyes, bone = (material(n) for n in ("CultRobe", "CultHands", "CultSkin", "CultEyes", "CultBone"))
    fig.dress(robe, hands)
    lengthen_tunic(fig, 1.10, .30, flare=.7)
    fig.add_head(skin, eyes)
    e = fig.eye
    eye_r = Vector((-e.x, e.y, e.z))
    # Bone face mask with eye holes; the eyes behind it glow a dull red.
    shell(fig, "Bone_Mask", bone, fig.head, .010,
          lambda co: co.y < fig.head_centre.y - .04 and e.z - .085 < co.z < e.z + .055
          and math.hypot(co.x - e.x, co.z - e.z) > .019 and math.hypot(co.x - eye_r.x, co.z - eye_r.z) > .019)
    # A rope belt and a few dangling bone charms.
    pieces = [cylinder("Rope", .16, .02, (0, .02, 1.13), material("CultRope"), sides=14)]
    for i, x in enumerate((-.08, -.03, .05)):
        pieces.append(cylinder("Charm", .006, .1 + .03 * i, (x, -.12, 1.06 - .015 * i), material("CultRope"), sides=4))
        pieces.append(sphere("Charm_Bone", .016, (x, -.125, 1.0 - .02 * i), bone, 6, 4, (1, .6, 1.4)))
    fig.add(merge("Cult_Rope", pieces), lambda co: {"pelvis": 1})
    maps = {
        "CultRobe": outfit("cultist_albedo.png"), "CultHands": tinted(HANDS["female"], [.85, .8, .78, 1]),
        "CultSkin": dict(SKIN["female"], albedo="../m1_textures/cultist_skin.png"),
        "CultEyes": {"color": [.9, .18, .1, 1], "rough": .3, "emission": [1, .16, .06], "emission_strength": 2},
        "CultBone": {"color": [.8, .76, .68, 1], "albedo": "../m1_textures/bone_albedo.png", "normal": "../../weapons/textures/surface_normal.png", "rough": .75},
        "CultRope": tinted(WOOD_C, [.6, .5, .38, 1]),
    }
    return fig.export("enemy_cultist", maps)


def cult_priest():
    fig = Figure("male_ranger", {"Arms", "Arms_Bracer", "Body", "Body_Belt_1", "Body_Belt_2", "Feet_Boots", "Head_Hood", "Legs", "Acc_Pauldron"}, "male")
    robe, hands, skin, eyes, bone, cloak, gem, gold = (material(n) for n in (
        "PriestRobe", "PriestHands", "PriestSkin", "PriestEyes", "PriestBone", "PriestCloak", "PriestGem", "PriestGold"))
    fig.dress(robe, hands)
    fig.part("Acc_Pauldron").data.materials[0] = bone
    mirror_part(fig, "Acc_Pauldron", "Priest_Pauldron_R", bone)
    lengthen_tunic(fig, 1.12, .10, flare=.9, wave=.05, depth=.45)
    skirt_material(fig, 1.12, material("PriestSkirt"))
    fig.add_head(skin, eyes)
    hood = fig.part("Head_Hood")
    e, hc = fig.eye, fig.head_centre
    # Ram horns sweeping out of the hood, and a crown of bone spikes around it.
    for side in (-1, 1):
        path = [Vector((side * .10, hc.y + .02, e.z + .08)), Vector((side * .21, hc.y + .05, e.z + .17)),
                Vector((side * .30, hc.y + .15, e.z + .15)), Vector((side * .31, hc.y + .20, e.z + .03)),
                Vector((side * .25, hc.y + .12, e.z - .05)), Vector((side * .27, hc.y + .02, e.z - .04))]
        fig.add(tube("Horn", path, [.05, .044, .034, .024, .014, .003], bone, sides=8), rigid("Head"))
    crown = []
    hood_top = max((hood.matrix_world @ v.co).z for v in hood.data.vertices)
    for i in range(9):
        a = math.pi * (.15 + .7 * i / 8) + math.pi       # front half arc
        base = Vector((math.cos(a) * .165, hc.y + math.sin(a) * .165 * 1.05 - .01, hood_top - .07))
        height = .2 if i == 4 else .09 + .05 * (1 - abs(i - 4) / 4)
        crown.append(tube("Spike", [base, base + Vector((math.cos(a) * .02, math.sin(a) * .02, height))], [.016, .002], bone, sides=5))
    crown.append(ring("Crown_Band", (0, hc.y - .01, hood_top - .065), .145, .16, -.01, gold, sides=20, sy=1.05, thickness=.02))
    crown.append(sphere("Crown_Gem", .022, (0, hc.y - .175, hood_top - .045), gem, 8, 6))
    fig.add(merge("Bone_Crown", crown), rigid("Head"))
    # Heavy cloak with a high collar.
    hanging_panel(fig, "Cloak", cloak, 1.55, .08, .23, .42, False, gap=.03, flare=.16, rows=16, cols=8,
                  weights=cloak_weights(fig))
    collar = ring("Cloak_Collar", (0, .06, 1.52), .13, .17, -.09, cloak, sides=16, sy=1.15, thickness=.012)
    delete_verts(collar, lambda co: co.y < -.02)
    box_uv(collar, 3); fig.add(collar, rigid("spine_03"))
    # Glowing sigil on the chest.
    sigil = ring("Sigil", (0, 0, 0), .035, .05, 0, gem, sides=12, thickness=.004)
    sigil.rotation_euler = (math.pi / 2, 0, 0); sigil.location = (0, surface_y(fig, 0, 1.36) - .015, 1.36)
    bpy.context.view_layer.update()
    fig.add(sigil, rigid("spine_03"))
    maps = {
        "PriestRobe": outfit("priest_albedo.png"), "PriestSkirt": outfit("priest_skirt_albedo.png"), "PriestHands": tinted(HANDS["male"], [.6, .58, .58, 1]),
        "PriestSkin": dict(SKIN["male"], albedo="../m1_textures/priest_skin.png"),
        "PriestEyes": {"color": [1, .45, .05, 1], "rough": .3, "emission": [1, .42, .04], "emission_strength": 5},
        "PriestBone": {"albedo": "../m1_textures/bone_albedo.png", "normal": "../../weapons/textures/surface_normal.png", "rough": .7},
        "PriestCloak": cloth("cloth_crimson.png"),
        "PriestGem": {"color": [.45, 1, .2, 1], "rough": .2, "emission": [.4, 1, .15], "emission_strength": 6},
        "PriestGold": tinted(METAL_C, [.9, .66, .27, 1], metal=.6, rough=.4),
    }
    return fig.export("boss_cult_priest", maps, scale=1.22)


def fighter(gender):
    outfit_name = gender + "_ranger"
    pauldron = "Acc_Pauldron" if gender == "male" else "Acc_Pauldrons"
    feet = "Feet_Boots" if gender == "male" else "Feet"
    fig = Figure(outfit_name, {"Arms", "Arms_Bracer", "Body", "Body_Belt_1", feet, "Head_Hood", "Legs", pauldron}, gender)
    names = ("FighterCloth", "FighterHands", "FighterSkin", "FighterEyes", "FighterMail", "FighterPlate", "FighterBrass")
    cloth_m, hands, skin, eyes, mail, plate, brass = (material(n) for n in names)
    fig.dress(cloth_m, hands)
    fig.part("Head_Hood").data.materials[0] = mail
    fig.part(pauldron).data.materials[0] = plate
    mirror_part(fig, pauldron, "Fighter_Pauldron_R", plate)
    fig.add_head(skin, eyes, material("FighterBrows"))
    # Shaped cuirass from the torso itself; open at the arm holes.
    top, bottom = (1.45, 1.12) if gender == "male" else (1.39, 1.10)
    cuirass(fig, plate, top, bottom)
    # Layered shoulder lames over the leather pauldrons.
    for side in (-1, 1):
        shoulder = fig.bone_head("upperarm_l" if side > 0 else "upperarm_r")
        for i in range(3):
            centre = shoulder + Vector((side * (.03 + .045 * i), 0, .0))
            radius = .085 - .008 * i
            arc = []
            for s in range(9):
                a = math.pi * (.05 + .9 * s / 8)
                arc.append((centre.x, centre.y + math.cos(a) * radius, centre.z + math.sin(a) * radius - .01))
            lame = tube("Lame", arc, [.012] * 9, plate, sides=4, squash=3.5)
            lame.scale = (1, 1, 1)
            fig.add(lame, rigid("upperarm_l" if side > 0 else "upperarm_r"))
    # Brass rivet line down the breastplate.
    rivets = []
    for i in range(4):
        z = bottom + .06 + i * (top - bottom - .12) / 3
        y = surface_y(fig, 0, z) - .03
        rivets.append(sphere("Rivet", .008, (0, y, z), brass, 6, 4))
    fig.add(merge("Rivets", rivets), torso_weights(fig))
    maps = {
        "FighterCloth": outfit("fighter_albedo.png"), "FighterHands": HANDS[gender], "FighterSkin": SKIN[gender], "FighterEyes": EYES,
        "FighterBrows": {"albedo": "../textures/T_Hair_%d_BaseColor.png" % (1 if gender == "male" else 2), "rough": .8},
        "FighterMail": tinted(METAL_C, [.4, .4, .43, 1], metal=.6, rough=.6, normal_scale=1.4),
        "FighterPlate": tinted(METAL_C, [.86, .87, .9, 1], metal=.6, rough=.42),
        "FighterBrass": tinted(METAL_C, [.9, .68, .34, 1], metal=.6, rough=.4),
    }
    return fig.export("hero_fighter_" + gender, maps)


def wizard(gender, headwear):
    feet = "Feet_Boots" if gender == "male" else "Feet"
    keep = {"Arms", "Arms_Bracer", "Body", "Body_Belt_1", feet, "Legs"}
    if headwear == "hood":
        keep.add("Head_Hood")
    fig = Figure(gender + "_ranger", keep, gender)
    robe, hands, skin, eyes, trim, hat_m = (material(n) for n in ("WizRobe", "WizHands", "WizSkin", "WizEyes", "WizTrim", "WizHat"))
    fig.dress(robe, hands)
    waist = 1.10 if gender == "male" else 1.08
    lengthen_tunic(fig, waist, .06, flare=.8, wave=.03, depth=.4)
    skirt_material(fig, waist, material("WizSkirt"))
    fig.add_head(skin, eyes, material("WizBrows"))
    e, hc = fig.eye, fig.head_centre
    if headwear == "hat":
        base_z = e.z + .06
        brim = ring("Hat_Brim", (0, hc.y - .005, base_z), .1, .27, .03, hat_m, sides=24, sy=1.08, thickness=.01)
        box_uv(brim, 3)
        cone_pts, radii = [], []
        for i in range(9):
            t = i / 8
            cone_pts.append((0, hc.y + .02 + .16 * t ** 2.2, base_z - .01 + .36 * t - .05 * t ** 3))
            radii.append(.118 * (1 - t) ** 1.1 + .004)
        cone = tube("Hat_Cone", cone_pts, radii, hat_m, sides=14)
        band = cylinder("Hat_Band", .12, .03, (0, hc.y - .003, base_z + .018), trim, sides=14)
        fig.add(merge("Wizard_Hat", [brim, cone, band]), rigid("Head"))
    # Trim along the hem: a thin band ring at the robe bottom reads at isometric zoom.
    maps = {
        "WizRobe": outfit("wizard_albedo.png"), "WizSkirt": outfit("wizard_skirt_albedo.png"), "WizHands": HANDS[gender], "WizSkin": SKIN[gender], "WizEyes": EYES,
        "WizBrows": {"albedo": "../textures/T_Hair_%d_BaseColor.png" % (1 if gender == "male" else 2), "rough": .8},
        "WizTrim": tinted(METAL_C, [.9, .68, .3, 1], metal=.6, rough=.4),
        "WizHat": cloth("cloth_blue.png"),
    }
    return fig.export("hero_wizard_%s_%s" % (gender, headwear), maps)

# ---------------------------------------------------------------- weapons

def weapon_maps():
    return {
        "ForgedSteel": {"albedo": "textures/forged_albedo.png", "normal": "textures/surface_normal.png", "orm": "textures/surface_orm.png", "metal": 1, "rough": .65},
        "AgedIron": {"albedo": "textures/forged_albedo.png", "normal": "textures/surface_normal.png", "orm": "textures/surface_orm.png", "color": [.30, .29, .28, 1], "metal": 1, "rough": .95},
        "OldLeather": {"albedo": "textures/haft_albedo.png", "normal": "textures/surface_normal.png", "orm": "textures/surface_orm.png", "color": [.5, .35, .24, 1], "metal": 0, "rough": 1},
        "CharredWood": {"albedo": "textures/haft_albedo.png", "normal": "textures/surface_normal.png", "orm": "textures/surface_orm.png", "metal": 0, "rough": 1},
        "PaleWood": {"albedo": "textures/haft_albedo.png", "normal": "textures/surface_normal.png", "orm": "textures/surface_orm.png", "color": [1.4, 1.25, 1.0, 1], "metal": 0, "rough": 1},
        "BowString": {"color": [.75, .7, .6, 1], "rough": 1},
        "PaintBlue": {"albedo": "textures/haft_albedo.png", "normal": "textures/surface_normal.png", "orm": "textures/surface_orm.png", "color": [.25, .38, .85, 1], "metal": 0, "rough": .9},
        "PaintRed": {"albedo": "textures/haft_albedo.png", "normal": "textures/surface_normal.png", "orm": "textures/surface_orm.png", "color": [1.0, .25, .18, 1], "metal": 0, "rough": .9},
        "Brass": {"albedo": "textures/forged_albedo.png", "normal": "textures/surface_normal.png", "orm": "textures/surface_orm.png", "color": [.95, .7, .34, 1], "metal": .6, "rough": .45},
        "Bone": {"albedo": "../characters/m1_textures/bone_albedo.png", "normal": "textures/surface_normal.png", "rough": .7},
        "ArcaneGem": {"color": [.35, .6, 1, 1], "rough": .15, "emission": [.3, .55, 1], "emission_strength": 5},
        "VileGem": {"color": [.45, 1, .2, 1], "rough": .15, "emission": [.4, 1, .15], "emission_strength": 6},
    }


def build_weapon(kind):
    reset()
    steel, iron, leather, wood, pale = (material(n) for n in ("ForgedSteel", "AgedIron", "OldLeather", "CharredWood", "PaleWood"))
    string, brass = material("BowString"), material("Brass")
    grip = lambda length, z, r=.022: [cylinder("Grip", r, length, (0, 0, z), leather, sides=8)] + \
        [cylinder("Binding", r + .002, .006, (0, 0, z - length / 2 + .02 + i * (length - .04) / 4), leather, sides=8) for i in range(5)]
    if kind == "dagger":
        prism("Blade", [(-.022, .07), (.022, .07), (.02, .22), (0, .33), (-.02, .22)], .014, steel)
        prism("Guard", [(-.065, .055), (.065, .055), (.06, .075), (-.06, .075)], .026, iron)
        grip(.11, 0, .017); cylinder("Pommel", .024, .025, (0, 0, -.065), iron, sides=8)
    elif kind == "scimitar":
        edge = [(-.03 + .10 * (t / 8) ** 2, .10 + .70 * t / 8) for t in range(9)]
        back = [(.022 + .12 * (t / 8) ** 2.2, .10 + .62 * t / 8) for t in range(8, -1, -1)]
        prism("Curved blade", edge + [(.13, .82)] + back, .02, steel)
        prism("Guard", [(-.08, .08), (.08, .08), (.06, .11), (-.06, .11)], .03, brass)
        grip(.18, -.005); cylinder("Pommel", .028, .03, (0, 0, -.11), brass, sides=8)
    elif kind == "sickle":
        cylinder("Handle", .02, .28, (0, 0, -.02), wood, sides=8)
        crescent = [(-.13 + math.cos(a) * .14, .14 + math.sin(a) * .16) for a in [math.pi * (.95 * i / 10) for i in range(11)]]
        inner = [(-.13 + math.cos(a) * .105, .17 + math.sin(a) * .115) for a in [math.pi * (.92 - .82 * i / 10) for i in range(11)]]
        prism("Crescent", crescent + inner, .012, iron)
        cylinder("Collar", .026, .04, (0, 0, .12), iron, sides=8)
    elif kind == "mace":
        cylinder("Haft", .02, .55, (0, 0, .12), wood, sides=8)
        grip(.2, -.06, .023)
        cylinder("Head core", .045, .14, (0, 0, .44), iron, sides=8)
        for i in range(6):
            f = prism("Flange", [(0, .37), (.075, .40), (.08, .48), (0, .52)], .012, steel)
            f.rotation_euler = (0, 0, i * math.pi / 3)
        sphere("Cap", .03, (0, 0, .53), iron, 8, 5)
    elif kind == "spear":
        cylinder("Shaft", .017, 2.0, (0, 0, .25), wood, sides=8)
        prism("Leaf head", [(0, 1.24), (.045, 1.33), (.03, 1.45), (0, 1.55), (-.03, 1.45), (-.045, 1.33)], .016, steel)
        cylinder("Socket", .022, .1, (0, 0, 1.22), iron, sides=8, radius2=.018)
        cylinder("Butt cap", .02, .05, (0, 0, -.74), iron, sides=8)
        grip(.22, 0, .02)
    elif kind == "staff":
        path = [(0, 0, -.8), (.01, 0, -.3), (-.01, 0, .3), (.012, 0, .8), (0, 0, 1.0)]
        tube("Gnarled shaft", path, [.022, .02, .021, .024, .03], wood, sides=8)
        for i in range(4):
            a = i * math.pi / 2
            tube("Claw", [(0, 0, .98), (math.cos(a) * .05, math.sin(a) * .05, 1.05), (math.cos(a) * .03, math.sin(a) * .03, 1.14)], [.012, .009, .002], wood, sides=5)
        sphere("Arcane gem", .038, (0, 0, 1.08), material("ArcaneGem"), 10, 6)
        grip(.2, 0, .025)
    elif kind == "staff_priest":
        tube("Black shaft", [(0, 0, -.9), (0, 0, .4), (0, 0, 1.15)], [.022, .022, .028], material("CharredWood"), sides=8)
        bone = material("Bone")
        for side in (-1, 1):
            tube("Bone horn", [(0, 0, 1.12), (side * .08, 0, 1.2), (side * .12, 0, 1.33), (side * .08, 0, 1.42)], [.024, .02, .012, .002], bone, sides=6)
        sphere("Vile gem", .045, (0, 0, 1.24), material("VileGem"), 10, 6)
        sphere("Skull", .05, (0, 0, 1.13), bone, 8, 6, (1, 1.1, .9))
        grip(.22, 0, .026)
    elif kind == "shortbow":
        limb = [(-.035 * (1 - (abs(t) ** 1.6)) - .0, 0, .5 * t) for t in [i / 6 - 1 for i in range(13)]]
        limb = [(x + .06 * abs(z / .5) ** 2, y, z) for x, y, z in limb]
        tube("Limbs", limb, [.011 + .009 * (1 - abs(z / .5)) for _, _, z in limb], pale, sides=6)
        tube("String", [limb[0], limb[-1]], [.0025, .0025], string, sides=4)
        grip(.1, 0, .019)
    elif kind == "light_crossbow":
        prism("Stock", [(-.026, -.18), (.026, -.18), (.03, .38), (-.03, .38)], .055, wood, bevel=.006)
        prism("Butt", [(-.02, -.18), (.02, -.18), (.03, -.34), (-.06, -.36), (-.05, -.18)], .05, wood, bevel=.006)
        prism("Trigger", [(-.02, -.05), (-.06, -.04), (-.065, -.02), (-.02, -.01)], .01, iron, bevel=0)
        prod = [(0, .02 + .05 * (abs(t) ** 2), .36 - .03 * abs(t)) for t in [i / 5 - 1 for i in range(11)]]
        prod = [(x * 0 + .28 * t, y, z) for (x, y, z), t in zip(prod, [i / 5 - 1 for i in range(11)])]
        tube("Steel prod", prod, [.02 - .008 * abs(t) for t in [i / 5 - 1 for i in range(11)]], steel, sides=6, squash=.6)
        tube("String", [prod[0], (0, -.0, .08), prod[-1]], [.0025] * 3, string, sides=4)
        cylinder("Bolt", .006, .3, (0, -.026, .22), material("PaleWood"), sides=5)
        stirrup = ring("Stirrup", (0, 0, 0), .03, .045, 0, iron, sides=10)
        stirrup.rotation_euler = (math.pi / 2, 0, 0); stirrup.location = (0, 0, .42)
    elif kind in ("shield_heater", "shield_round"):
        paint = material("PaintBlue" if kind == "shield_heater" else "PaintRed")
        if kind == "shield_heater":
            right = [(.27 * math.cos(a), .05 - .47 * math.sin(a)) for a in [math.pi / 2 * i / 7 for i in range(8)]]
            outline = [(-.27, .30), (.27, .30)] + right + [(-x, z) for x, z in reversed(right[:-1])]
            prism("Shield face", outline, .03, paint, bevel=.006, offset=-.03)
            prism("Rim", [(x * 1.07, z * 1.05 + .01) for x, z in outline], .022, iron, bevel=.004, offset=-.012)
            prism("Cross", [(-.03, -.38), (.03, -.38), (.03, .28), (-.03, .28)], .036, brass, bevel=.003, offset=-.032)
            prism("Cross bar", [(-.24, .10), (.24, .10), (.24, .16), (-.24, .16)], .036, brass, bevel=.003, offset=-.032)
        else:
            cylinder("Shield face", .32, .03, (0, -.03, 0), paint, sides=20, axis=(0, 1, 0))
            ring("Rim", (0, 0, 0), .30, .335, 0, iron, sides=20, thickness=.04).rotation_euler = (math.pi / 2, 0, 0)
            sphere("Boss", .075, (0, -.05, 0), iron, 10, 6, (1, .6, 1))
        cylinder("Grip bar", .014, .14, (0, .012, 0), leather, sides=6)
    parts = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.context.view_layer.update()
    triangles = export(parts, WEAPONS / (kind + ".glb"), weapon_maps())
    assert triangles <= WEAPON_TRIANGLE_BUDGET, (kind, triangles)
    return {"triangles": triangles}


if __name__ == "__main__":
    import sys
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    info = {"generator": "Blender " + bpy.app.version_string, "characters": {}, "weapons": {}}
    builders = {
        "enemy_guard": guard, "enemy_bandit": bandit, "enemy_cultist": cultist, "boss_cult_priest": cult_priest,
        "hero_fighter_male": lambda: fighter("male"), "hero_fighter_female": lambda: fighter("female"),
        "hero_wizard_male_hood": lambda: wizard("male", "hood"), "hero_wizard_female_hood": lambda: wizard("female", "hood"),
        "hero_wizard_male_hat": lambda: wizard("male", "hat"), "hero_wizard_female_hat": lambda: wizard("female", "hat"),
    }
    weapon_kinds = ["dagger", "scimitar", "sickle", "mace", "spear", "staff", "staff_priest", "shortbow",
                    "light_crossbow", "shield_heater", "shield_round"]
    for name, build in builders.items():
        if not only or name in only:
            info["characters"][name] = build()
    for kind in weapon_kinds:
        if not only or kind in only:
            info["weapons"][kind] = build_weapon(kind)
    if not only:
        (ASSETS / "m1_art_manifest.json").write_text(json.dumps(info, indent=2) + "\n")
    print(json.dumps(info))
