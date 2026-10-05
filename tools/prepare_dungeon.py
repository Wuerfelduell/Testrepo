#!/usr/bin/env python3
"""Rebuild Omie's selected dungeon textures and attach them to converted geometry.
Inputs: the author's free ZIP and GLBs exported from its FBX meshes via Godot's GLTFDocument.
No models are generated. Unity metallic/smoothness is converted to glTF's G=roughness, B=metallic.
"""
from pathlib import Path, PurePosixPath
from zipfile import ZipFile
import io, json, struct, sys, hashlib
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets' / 'dungeon'
GROUPS = {
 'Mat_Floor': 'SM_DungeonKit_Mat_Floor',
 'Mat_Walls': 'SM_DungeonKit_Mat_Walls',
 'Mat_GeneralProps': 'SM_GeneralProps_Mat_GeneralProps',
 'Mat_WallProps': 'SM_WallProp_Mat_WallProps',
}

def prepare(archive):
    folder = OUT / 'textures'; folder.mkdir(parents=True, exist_ok=True)
    with ZipFile(archive) as z:
        for material, prefix in GROUPS.items():
            def read(suffix):
                name = next(n for n in z.namelist() if PurePosixPath(n).name == prefix + suffix + '.tga')
                return Image.open(io.BytesIO(z.read(name))).convert('RGBA').resize((512,512),Image.Resampling.LANCZOS)
            read('_AlbedoTransparency').save(folder / (material+'_BaseColor.png'))
            read('_Normal').convert('RGB').save(folder / (material+'_Normal.png'))
            packed = read('_MetallicSmoothness')
            orm = Image.merge('RGB', (Image.new('L',packed.size,255),ImageOps.invert(packed.getchannel('A')),packed.getchannel('R')))
            orm.save(folder / (material+'_ORM.png'))
    for path in sorted(OUT.glob('*.glb')):
        raw = path.read_bytes(); count = struct.unpack_from('<I',raw,12)[0]
        document = json.loads(raw[20:20+count]); binary = raw[28+count:]
        # Geometry conversion is intentionally texture-free: author FBX references stale PNG paths.
        # Replace all material references with the actual supplied maps, never blank fallback materials.
        document['images']=[];document['textures']=[]
        for material in document['materials']:
            group=next((name for name in GROUPS if material['name'].startswith(name)), material['name'])
            if group not in GROUPS: raise ValueError(f'Unknown material: {group}')
            start=len(document['textures'])
            for suffix in ['BaseColor','Normal','ORM']:
                document['images'].append({'uri':f'textures/{group}_{suffix}.png'})
                document['textures'].append({'source':len(document['images'])-1})
            material.clear();material.update({'name':group,'normalTexture':{'index':start+1},
              'pbrMetallicRoughness':{'baseColorTexture':{'index':start},'metallicRoughnessTexture':{'index':start+2},'metallicFactor':1.0,'roughnessFactor':1.0}})
        encoded=json.dumps(document,separators=(',',':')).encode();encoded+=b' '*(-len(encoded)%4)
        payload=struct.pack('<III',0x46546c67,2,28+len(encoded)+len(binary))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(binary),0x004e4942)+binary
        path.write_bytes(payload)
    records=json.loads((ROOT/'assets/source_archives.json').read_text())
    records=[r for r in records if r['archive']!='pbr-dungeon.zip']
    records.append({'archive':'pbr-dungeon.zip','sha256':hashlib.file_digest(Path(archive).open('rb'),'sha256').hexdigest()})
    (ROOT/'assets/source_archives.json').write_text(json.dumps(records,indent=2)+'\n')
    print('17 selected PBR dungeon models and shared 1K textures prepared.')

if __name__=='__main__':prepare(Path(sys.argv[1]))
