#!/usr/bin/env python3
"""Deterministic material variations from the CC0 maps already in this repository.

Run with Python + Pillow + NumPy before build_enemy_test.py. No new asset downloads.
Original maps are never changed; the new GLBs reuse their existing normal/ORM maps.
"""
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/characters/undead_cultist/textures"
OUT.mkdir(parents=True, exist_ok=True)


def variation(source, output, color, decay):
    image = Image.open(source).convert("RGB").resize((512, 512), Image.Resampling.LANCZOS)
    pixels = np.asarray(image, dtype=np.float32) / 255
    luminance = pixels @ np.array([.2126, .7152, .0722])
    rng = np.random.default_rng(101)
    patches = Image.fromarray((rng.random((24, 24)) * 255).astype("uint8"))
    patches = np.asarray(patches.resize(image.size, Image.Resampling.BICUBIC)) / 255
    # Keep the author's folds, seams and UV details; add muted mottling, not flat paint.
    brightness = .25 + .95 * luminance
    rgb = brightness[..., None] * np.array(color)
    rgb += (patches[..., None] - .5) * np.array(decay)
    rgb += rng.normal(0, .008, rgb.shape)
    # A palette keeps these narrow-colour variations compact without reducing the UV resolution.
    Image.fromarray(np.uint8(np.clip(rgb, 0, 1) * 255)).quantize(colors=128).save(output)


variation(ROOT / "assets/characters/textures/T_Ranger_BaseColor.png",
          OUT / "robe_albedo.png", [.34, .16, .19], [.10, .10, .045])
variation(ROOT / "assets/characters/textures/T_Superhero_Male_Dark.png",
          OUT / "skin_albedo.png", [.50, .57, .43], [.13, .15, .09])
variation(ROOT / "assets/characters/textures/T_Regular_Male_Dark_BaseColor.png",
          OUT / "hands_albedo.png", [.50, .57, .43], [.13, .15, .09])

weapon = ROOT / "assets/weapons/textures"
weapon.mkdir(parents=True, exist_ok=True)
source = Image.open(ROOT / "assets/dungeon/textures/Mat_GeneralProps_BaseColor.png")
source = np.asarray(source.convert("RGB").resize((256, 256)), dtype=np.float32) / 255
grain = source @ np.array([.2126, .7152, .0722])
y, x = np.mgrid[:256, :256]
rng = np.random.default_rng(2026)
scratches = .025 * np.sin(x * .8 + y * .07) + rng.normal(0, .015, (256, 256))
metal = np.clip(.47 + grain * .30 + scratches, 0, 1)
Image.fromarray(np.uint8(np.stack([metal*.93, metal*.98, metal], axis=-1) * 255)).save(weapon / "forged_albedo.png")
wood = .22 + grain * .32 + .025 * np.sin(x * .22 + np.sin(y * .05))
Image.fromarray(np.uint8(np.clip(wood[..., None] * [.86, .51, .29], 0, 1) * 255)).save(weapon / "haft_albedo.png")
# Fine scored surface. OpenGL/glTF tangent normals, +Y (the Godot convention).
height = .05 * grain + .002 * np.sin(x * .8)
dy, dx = np.gradient(height)
normal = np.stack([-dx*6, -dy*6, np.ones_like(dx)], axis=-1)
normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
Image.fromarray(np.uint8((normal*.5+.5)*255)).save(weapon / "surface_normal.png")
roughness = np.uint8(np.clip(.50 + grain*.25, 0, 1)*255)
Image.fromarray(np.stack([np.full_like(roughness, 255), roughness, np.full_like(roughness, 255)], axis=-1)).save(weapon / "surface_orm.png")
print("Enemy-test material variations written; source textures unchanged.")
