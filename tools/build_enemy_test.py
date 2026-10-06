#!/usr/bin/env python3
"""Blender 4.x: assemble the licensed existing parts and model two low-poly weapons.

Run prepare_enemy_textures.py, then:
  blender --background --factory-startup --python tools/build_enemy_test.py
Uses only repository geometry; no generated/downloaded character or new armature.
Exports GLBs with shared external PNGs, leaving every source model untouched.
"""
from pathlib import Path
import json, math, struct, tempfile
import bpy, bmesh

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
CHAR = ASSETS / "characters"
WEAPONS = ASSETS / "weapons"


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def material(name, color=(1, 1, 1, 1), metal=0, rough=.7):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = color
    p.inputs["Metallic"].default_value = metal
    p.inputs["Roughness"].default_value = rough
    return m


def export(objects, output, maps):
    """Pack geometry and remap material images to the original/derived shared PNGs."""
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

        def texture(uri):
            index = len(doc["images"])
            doc["images"].append({"uri": uri})
            doc["textures"].append({"source": index, "sampler": 0})
            return {"index": index}

        for m in doc.get("materials", []):
            original = m["name"].split(".")[0]
            spec = maps[original]
            m.clear(); m.update({"name": original, "doubleSided": original == "CultistCloth"})
            pbr = {"baseColorFactor": spec.get("color", [1, 1, 1, 1]),
                   "metallicFactor": spec.get("metal", 0), "roughnessFactor": spec.get("rough", 1)}
            if "albedo" in spec:
                pbr["baseColorTexture"] = texture(spec["albedo"])
            if "orm" in spec:
                pbr["metallicRoughnessTexture"] = texture(spec["orm"])
            m["pbrMetallicRoughness"] = pbr
            if "normal" in spec:
                m["normalTexture"] = dict(texture(spec["normal"]), scale=.7)
            if "emission" in spec:
                m["emissiveFactor"] = spec["emission"]
                m["extensions"] = {"KHR_materials_emissive_strength": {"emissiveStrength": 3}}
                doc.setdefault("extensionsUsed", []).append("KHR_materials_emissive_strength")
        encoded = json.dumps(doc, separators=(",", ":")).encode()
        encoded += b" " * (-len(encoded) % 4)
        binary.extend(b"\0" * (-len(binary) % 4))
        payload = struct.pack("<III", 0x46546C67, 2, 28 + len(encoded) + len(binary))
        payload += struct.pack("<II", len(encoded), 0x4E4F534A) + encoded
        payload += struct.pack("<II", len(binary), 0x004E4942) + binary
        output.write_bytes(payload)
        triangles = sum(doc["accessors"][p["indices"]]["count"] // 3
                        for mesh in doc["meshes"] for p in mesh["primitives"])
        return triangles


def cultist():
    clear()
    bpy.ops.import_scene.gltf(filepath=str(CHAR / "male_ranger/model.glb"))
    rig = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    rig.name = "CultistRig"
    parts = [o for o in bpy.context.scene.objects if o.type == "MESH" and o.name.startswith("Male_Ranger_")]
    cloth, hands = material("CultistCloth"), material("CultistHands")
    for obj in list(parts):
        if "Pauldron" in obj.name or "Belt_2" in obj.name:
            parts.remove(obj); bpy.data.objects.remove(obj, do_unlink=True); continue
        for slot in obj.material_slots:
            slot.material = hands if "Regular" in slot.material.name else cloth
        if obj.name == "Male_Ranger_Body":
            # The existing tunic is extended, with its UVs and upper-body weighting intact.
            # The hem uses the original thigh bones; no new skeleton/animation is introduced.
            for v in obj.data.vertices:
                z = v.co.z
                if z < 1.12:
                    t = min(1, (1.12-z)/.211)
                    v.co.z = 1.12 - (1.12-z)*3.8
                    v.co.x *= 1 + .65*t
                    v.co.y = .04 + (v.co.y-.04)*(1+.3*t)
                    if t > .70:
                        v.co.z += .045 * math.sin(v.co.x*53 + v.co.y*31)
                    for group in obj.vertex_groups:
                        group.remove([v.index])
                    side = "thigh_r" if v.co.x < 0 else "thigh_l"
                    obj.vertex_groups.get("pelvis").add([v.index], 1-t*.65, "REPLACE")
                    obj.vertex_groups.get(side).add([v.index], t*.65, "REPLACE")
        if "Boots" in obj.name or "Bracer" in obj.name:
            # Keep source silhouette while reducing detail mostly hidden below robe/sleeves.
            bpy.context.view_layer.objects.active = obj
            modifier = obj.modifiers.new("Hidden-detail reduction", "DECIMATE")
            modifier.ratio = .4
            bpy.ops.object.modifier_apply(modifier=modifier.name)

    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(CHAR / "superhero_male_fullbody/model.glb"))
    imported = set(bpy.context.scene.objects) - before
    body = next(o for o in imported if o.type == "MESH" and o.name.startswith("SuperHero_Male"))
    eyes = next(o for o in imported if o.type == "MESH" and o.name.startswith("Eyes"))
    bm = bmesh.new(); bm.from_mesh(body.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < 1.51], context="VERTS")
    bm.to_mesh(body.data); bm.free()
    skin, glow = material("CultistSkin"), material("CultistEyes", (.25, .9, .08, 1))
    for obj, mat in [(body, skin), (eyes, glow)]:
        world = obj.matrix_world.copy()
        obj.parent = rig; obj.matrix_world = world
        for modifier in obj.modifiers:
            if modifier.type == "ARMATURE": modifier.object = rig
        obj.data.materials.clear(); obj.data.materials.append(mat)
        for face in obj.data.polygons: face.material_index = 0
        parts.append(obj)
    for obj in imported:
        if obj not in (body, eyes): bpy.data.objects.remove(obj, do_unlink=True)
    maps = {
        "CultistCloth": {"albedo": "textures/robe_albedo.png", "normal": "../textures/T_Ranger_Normal.png", "orm": "../textures/T_Ranger_ORM.png", "rough": 1},
        "CultistSkin": {"albedo": "textures/skin_albedo.png", "normal": "../textures/T_Superhero_Male_Normal.png", "orm": "../textures/T_Superhero_Male_Roughness.png", "rough": .95},
        "CultistHands": {"albedo": "textures/hands_albedo.png", "normal": "../textures/T_Regular_Male_Normal.png", "orm": "../textures/T_Regular_Male_Roughness.png", "rough": .95},
        "CultistEyes": {"color": [.25, .9, .08, 1], "rough": .35, "emission": [.20, 1, .045]},
    }
    triangles = export([rig]+parts, CHAR / "undead_cultist/model.glb", maps)
    return {"triangles": triangles, "source_rig": "male_ranger", "parts": [o.name for o in parts]}


def mesh(name, vertices, faces, mat):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces); data.update()
    obj = bpy.data.objects.new(name, data); bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    uv = data.uv_layers.new(name="UVMap")
    for poly in data.polygons:
        for loop in poly.loop_indices:
            v = data.vertices[data.loops[loop].vertex_index].co
            uv.data[loop].uv = ((v.x+.4)/.8, (v.z+.2)/1.3)
    return obj


def prism(name, profile, thickness, mat):
    n = len(profile)
    vertices = [(x, -thickness/2, z) for x,z in profile] + [(x, thickness/2, z) for x,z in profile]
    faces = [tuple(range(n-1,-1,-1)), tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    obj = mesh(name, vertices, faces, mat)
    bpy.context.view_layer.objects.active = obj
    bevel = obj.modifiers.new("Forged edge bevel", "BEVEL"); bevel.width = .004; bevel.segments = 1
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return obj


def cylinder(name, radius, depth, z, mat, sides=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=radius, depth=depth, location=(0,0,z))
    obj = bpy.context.object; obj.name = name; obj.data.materials.append(mat)
    return obj


def weapons():
    result = {}
    for kind in ["sword", "axe"]:
        clear()
        steel = material("ForgedSteel", metal=1, rough=.65)
        iron = material("AgedIron", (.30,.29,.28,1), metal=1, rough=.95)
        leather = material("OldLeather", (.35,.19,.12,1), rough=.95)
        wood = material("CharredWood", rough=.9)
        if kind == "sword":
            prism("Blade", [(-.045,.15),(.045,.15),(.048,.68),(.026,.86),(0,.98),(-.026,.86),(-.048,.68)], .026, steel)
            prism("Crossguard", [(-.15,.145),(-.14,.18),(-.065,.165),(0,.16),(.065,.165),(.14,.18),(.15,.145),(.05,.12),(-.05,.12)], .04, iron)
            cylinder("Leather grip", .023, .23, -.005, leather)
            cylinder("Pommel", .036, .05, -.145, iron)
            for i in range(7):
                cylinder("Grip binding", .025, .007, -.09+i*.028, leather)
        else:
            cylinder("Wood haft", .024, .72, .14, wood)
            prism("Bearded axe head", [(-.06,.46),(-.055,.60),(.08,.64),(.23,.72),(.33,.66),(.32,.47),(.26,.34),(.20,.29),(.19,.42),(.08,.46)], .048, steel)
            cylinder("Socket", .038, .13, .525, iron)
            cylinder("Leather hand grip", .027, .23, -.07, leather)
            cylinder("Haft butt cap", .030, .025, -.22, iron)
            for i in range(6): cylinder("Grip binding", .029, .008, -.16+i*.035, leather)
        parts = [o for o in bpy.context.scene.objects if o.type == "MESH"]
        maps = {
            "ForgedSteel": {"albedo": "textures/forged_albedo.png", "normal": "textures/surface_normal.png", "orm": "textures/surface_orm.png", "metal": 1, "rough": .65},
            "AgedIron": {"albedo": "textures/forged_albedo.png", "normal": "textures/surface_normal.png", "orm": "textures/surface_orm.png", "color": [.30,.29,.28,1], "metal": 1, "rough": .95},
            "OldLeather": {"albedo": "textures/haft_albedo.png", "normal": "textures/surface_normal.png", "orm": "textures/surface_orm.png", "color": [.5,.35,.24,1], "metal": 0, "rough": 1},
            "CharredWood": {"albedo": "textures/haft_albedo.png", "normal": "textures/surface_normal.png", "orm": "textures/surface_orm.png", "metal": 0, "rough": 1},
        }
        triangles = export(parts, WEAPONS / (kind+".glb"), maps)
        assert triangles <= 1500, (kind, triangles)
        result[kind] = {"triangles": triangles, "grip_origin": [0,0,0], "blade_axis": "+Y in Godot"}
    return result


info = {"cultist": cultist(), "weapons": weapons(), "generator": "Blender "+bpy.app.version_string}
(ASSETS / "enemy_test_manifest.json").write_text(json.dumps(info, indent=2)+"\n")
print(json.dumps(info))
