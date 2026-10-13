#!/usr/bin/env python3
"""Prepare the Overcity town kit from Quaternius' free Medieval Village MegaKit [Standard].
Usage: python3 tools/prepare_town.py "Medieval Village MegaKit[Standard].zip"
Source: https://quaternius.itch.io/medieval-village-megakit (CC0 1.0).
Every glTF model of the free pack becomes a self-contained GLB in assets/town/ (geometry and
author materials unchanged); the shared textures go to assets/town/textures/ at 1K (512 px for
roughness maps). No models are generated or edited.
"""
from pathlib import Path, PurePosixPath
from zipfile import ZipFile
import hashlib, io, json, struct, sys
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets' / 'town'
ARCHIVE_NAME = 'medieval-village-megakit-standard.zip'
# Unused by the glTF models (they belong to the paid pack's shaders).
SKIP_TEXTURES = {'T_BottomWear.png', 'T_TopWear.png', 'T_BrushedNoise.png', 'T_Noise_Terrain.png', 'T_WindowGradient.png'}

def texture_size(name):
    return 512 if 'Roughness' in name or 'ORM' in name else 1024

def glb(document, binary):
    encoded = json.dumps(document, separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4)
    binary += b'\0' * (-len(binary) % 4)
    total = 12 + 8 + len(encoded) + 8 + len(binary)
    return (struct.pack('<III', 0x46546c67, 2, total) + struct.pack('<II', len(encoded), 0x4e4f534a) + encoded +
            struct.pack('<II', len(binary), 0x004e4942) + binary)

def prepare(archive):
    (OUT / 'textures').mkdir(parents=True, exist_ok=True)
    used = set()
    models = 0
    with ZipFile(archive) as z:
        names = z.namelist()
        by_path = {PurePosixPath(n): n for n in names}
        for name in sorted(n for n in names if n.endswith('.gltf') and '/glTF/' in n):
            path = PurePosixPath(name)
            document = json.loads(z.read(name))
            buffers = document.get('buffers', [])
            if len(buffers) != 1:
                raise ValueError(f'{path.name}: expected one buffer')
            binary = z.read(by_path[path.parent / buffers[0]['uri']])
            buffers[0].pop('uri')
            buffers[0]['byteLength'] = len(binary)
            for image in document.get('images', []):
                image['uri'] = 'textures/' + image['uri']
                used.add(image['uri'][len('textures/'):])
            (OUT / (path.stem + '.glb')).write_bytes(glb(document, binary))
            models += 1
        for texture in sorted(used):
            if texture in SKIP_TEXTURES:
                raise ValueError(f'{texture} is used by a model')
            source = next(n for n in names if n.endswith('/glTF/' + texture))
            image = Image.open(io.BytesIO(z.read(source)))
            image = image.convert('RGBA' if image.mode in ('RGBA', 'LA', 'P') else 'RGB')
            size = texture_size(texture)
            if max(image.size) > size:
                image = image.resize((size, size), Image.Resampling.LANCZOS)
            image.save(OUT / 'textures' / texture, optimize=True)
        licence = next(n for n in names if n.endswith('License_Standard.txt'))
        (ROOT / 'assets' / 'licenses' / 'quaternius_medieval_village.txt').write_bytes(z.read(licence))
    records = json.loads((ROOT / 'assets/source_archives.json').read_text())
    records = [r for r in records if r['archive'] != ARCHIVE_NAME]
    records.append({'archive': ARCHIVE_NAME, 'sha256': hashlib.file_digest(Path(archive).open('rb'), 'sha256').hexdigest()})
    (ROOT / 'assets/source_archives.json').write_text(json.dumps(records, indent=2) + '\n')
    print(f'{models} town models and {len(used)} shared textures prepared in assets/town/.')

if __name__ == '__main__':
    prepare(Path(sys.argv[1]))
