#!/usr/bin/env python3
"""Import only selected, licensed assets from the owner's downloaded Standard archives.
Usage: python tools/prepare_assets.py /path/to/archive-directory
Pillow is required. Originals stay outside Git; source archive hashes are recorded.
"""
from pathlib import Path, PurePosixPath
from zipfile import ZipFile
import hashlib, json, struct, sys, io
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'assets'
ALIASES = {'T_Eye_Normal_png.png': 'T_Eye_Normal.png', 'T_Hair_1_Normal_png.png': 'T_Hair_1_Normal.png'}

def find_texture(z, name, source):
    name = ALIASES.get(name, name)
    source_dir = source.rsplit('/', 1)[0] + '/'
    direct = source_dir + name
    if direct in z.namelist():
        return name, z.read(direct)
    candidates = [n for n in z.namelist() if PurePosixPath(n).name == name and 'Normals-UnrealEngine' not in n]
    if 'Base Characters/' in source:
        godot_normals = [n for n in candidates if '/Base Characters/Textures/Normals Unity - Godot/' in n]
        candidates = godot_normals or [n for n in candidates if '/Base Characters/Textures/' in n and '/Normals ' not in n]
    if not candidates:
        raise ValueError(f'Missing source texture: {name}')
    values = {hashlib.sha256(z.read(n)).hexdigest() for n in candidates}
    if len(values) != 1:
        raise ValueError(f'Ambiguous texture contents: {name}')
    return name, z.read(candidates[0])

def pack_gltf(z, path, output):
    doc = json.loads(z.read(path)); prefix = path.rsplit('/', 1)[0] + '/'
    binary = bytearray(); offsets = []
    for buffer in doc['buffers']:
        binary.extend(b'\0' * (-len(binary) % 4)); offsets.append(len(binary))
        binary.extend(z.read(prefix + buffer['uri']))
    for view in doc.get('bufferViews', []):
        view['byteOffset'] = view.get('byteOffset', 0) + offsets[view.get('buffer', 0)]
        view['buffer'] = 0
    for image in doc.get('images', []):
        name, contents = find_texture(z, image['uri'], path)
        with Image.open(io.BytesIO(contents)) as original:
            if max(original.size) > 1024:
                ratio = 1024 / max(original.size)
                resized = original.resize((round(original.width * ratio), round(original.height * ratio)), Image.Resampling.LANCZOS)
                encoded_image = io.BytesIO(); resized.save(encoded_image, format='PNG')
                contents = encoded_image.getvalue()
        texture = ASSETS / 'characters' / 'textures' / name
        texture.parent.mkdir(parents=True, exist_ok=True)
        if texture.exists() and texture.read_bytes() != contents:
            raise ValueError(f'Texture collision: {name}')
        texture.write_bytes(contents); image['uri'] = '../textures/' + name
    doc['buffers'] = [{'byteLength': len(binary)}]
    encoded = json.dumps(doc, separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4); binary.extend(b'\0' * (-len(binary) % 4))
    payload = struct.pack('<III', 0x46546C67, 2, 28 + len(encoded) + len(binary))
    payload += struct.pack('<II', len(encoded), 0x4E4F534A) + encoded
    payload += struct.pack('<II', len(binary), 0x004E4942) + binary
    output.parent.mkdir(parents=True, exist_ok=True); output.write_bytes(payload)

def prepare(archives):
    licenses = ASSETS / 'licenses'; licenses.mkdir(parents=True, exist_ok=True)
    records = []
    for key, filename, subpath in [
        ('base', 'base-characters.zip', 'Base Characters/Godot - UE/'),
        ('outfits', 'outfits.zip', 'Exports/glTF (Godot-Unreal)/Outfits/')]:
        path = archives / filename
        with ZipFile(path) as z:
            license_name = next(n for n in z.namelist() if 'license' in n.lower())
            license_bytes = z.read(license_name)
            if b'CC0 1.0' not in license_bytes: raise ValueError('Expected pack-specific CC0 licence')
            (licenses / f'quaternius_{key}.txt').write_bytes(license_bytes)
            for n in z.namelist():
                if subpath in n and n.endswith('.gltf'):
                    pack_gltf(z, n, ASSETS / 'characters' / PurePosixPath(n).stem.lower() / 'model.glb')
        records.append({'archive': filename, 'sha256': hashlib.file_digest(path.open('rb'), 'sha256').hexdigest()})
    path = archives / 'animations.zip'
    with ZipFile(path) as z:
        (ASSETS / 'animations').mkdir(exist_ok=True)
        (ASSETS / 'animations' / 'universal.glb').write_bytes(z.read('Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb'))
        (licenses / 'quaternius_animations.txt').write_bytes(z.read('Universal Animation Library[Standard]/License.txt'))
    records.append({'archive': path.name, 'sha256': hashlib.file_digest(path.open('rb'), 'sha256').hexdigest()})
    (ASSETS / 'source_archives.json').write_text(json.dumps(records, indent=2) + '\n')
    print('Selected characters and animation library prepared.')

if __name__ == '__main__': prepare(Path(sys.argv[1]))
