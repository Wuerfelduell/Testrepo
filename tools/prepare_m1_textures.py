#!/usr/bin/env python3
"""Prompt 07: deterministic material variations from the CC0 maps already in this repo.

Run with Python + Pillow + NumPy before build_m1_art.py. No downloads, no generated art.
Source maps are never changed. Unlike the 01b variation (one colour over everything),
the Ranger atlas is split by hue: its green cloth, brown leather and grey metal regions
get separate colours, so one model keeps readable cloth / leather / metal contrast.
"""
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/characters/textures"
OUT = ROOT / "assets/characters/m1_textures"
OUT.mkdir(parents=True, exist_ok=True)
SIZE = 512


def load(name):
    image = Image.open(SRC / name).convert("RGB").resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    return np.asarray(image, dtype=np.float32) / 255


def hsv(rgb):
    maximum, minimum = rgb.max(-1), rgb.min(-1)
    delta = maximum - minimum + 1e-6
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    hue = np.where(maximum == r, ((g - b) / delta) % 6, np.where(maximum == g, (b - r) / delta + 2, (r - g) / delta + 4)) * 60
    return hue, delta / (maximum + 1e-6), maximum


def smooth(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)


def mottle(seed, amount):
    rng = np.random.default_rng(seed)
    patches = Image.fromarray((rng.random((20, 20)) * 255).astype("uint8")).resize((SIZE, SIZE), Image.Resampling.BICUBIC)
    return (np.asarray(patches, dtype=np.float32) / 255 - .5)[..., None] * np.array(amount)


def save(rgb, name):
    Image.fromarray(np.uint8(np.clip(rgb, 0, 1) * 255)).quantize(colors=160).save(OUT / name)


def ranger(name, cloth, leather, metal=1.0, seed=1, grime=(.05, .05, .04)):
    """cloth: replaces the green regions; leather: tints the brown regions; metal keeps grey."""
    rgb = load("T_Ranger_BaseColor.png")
    hue, saturation, value = hsv(rgb)
    luminance = rgb @ np.array([.2126, .7152, .0722])
    green = smooth(.12, .30, saturation) * smooth(55, 75, hue) * (1 - smooth(165, 185, hue))
    brown = smooth(.18, .35, saturation) * (1 - smooth(45, 60, hue))
    grey = 1 - np.clip(green + brown, 0, 1)
    shade = (.30 + 1.6 * luminance)[..., None]
    out = rgb * grey[..., None] * metal
    out += green[..., None] * shade * np.array(cloth)
    out += brown[..., None] * (.35 + 1.4 * luminance)[..., None] * np.array(leather)
    out += mottle(seed, grime)
    save(out, name)


def peasant(name, dark, light, seed=1):
    """Peasant atlas: dark vest/trousers -> dark; pale shirt/cloth -> light; tan straps kept warm."""
    rgb = load("T_Peasant_BaseColor.png")
    luminance = rgb @ np.array([.2126, .7152, .0722])
    pale = smooth(.38, .55, luminance)[..., None]
    shade = (.35 + 1.5 * luminance)[..., None]
    out = (1 - pale) * shade * np.array(dark) + pale * (.25 + .9 * luminance)[..., None] * np.array(light)
    out += mottle(seed, (.04, .035, .03))
    save(out, name)


def skin(name, source, color, seed=1):
    rgb = load(source)
    luminance = rgb @ np.array([.2126, .7152, .0722])
    out = (.25 + .95 * luminance)[..., None] * np.array(color) + mottle(seed, (.05, .05, .05))
    save(out, name)


# Enemies. Guard: undyed gambeson and oiled brown leather under a red city tabard.
ranger("guard_albedo.png", cloth=[.22, .19, .15], leather=[.30, .19, .12], seed=11)
# Bandit: soot-black and moss-brown, sun-bleached shirt; deliberately no uniform colour.
peasant("bandit_albedo.png", dark=[.20, .17, .13], light=[.42, .37, .29], seed=12)
# Bandit's borrowed Ranger bracers / pauldron: worn black leather, rusty buckles.
ranger("bandit_gear_albedo.png", cloth=[.12, .11, .10], leather=[.17, .12, .09], metal=.75, seed=17)
# Cultist: dried-blood crimson robe, black leather.
ranger("cultist_albedo.png", cloth=[.30, .03, .05], leather=[.10, .08, .08], metal=.7, seed=13)
# Cult Priest: near-black robe with a violet cast; the cloak uses its own cloth map below.
ranger("priest_albedo.png", cloth=[.10, .07, .13], leather=[.16, .10, .09], metal=.85, seed=14)
skin("priest_skin.png", "T_Superhero_Male_Dark.png", [.50, .47, .46], seed=15)
skin("cultist_skin.png", "T_Superhero_Female_Dark_BaseColor.png", [.78, .70, .66], seed=16)
# Heroes. Fighter: navy gambeson, dark leather. Wizard: midnight blue robe, tan leather.
ranger("fighter_albedo.png", cloth=[.08, .13, .26], leather=[.26, .16, .10], seed=21)
ranger("wizard_albedo.png", cloth=[.10, .09, .30], leather=[.40, .27, .15], seed=22)
# Robe skirts: the stretched tunic hem sits in the atlas' leather area, so it gets cloth colour.
ranger("wizard_skirt_albedo.png", cloth=[.10, .09, .30], leather=[.09, .08, .27], seed=23)
ranger("priest_skirt_albedo.png", cloth=[.10, .07, .13], leather=[.09, .06, .11], metal=.85, seed=24)

# Plain cloth for tabards, bandanas and cloaks: the peasant shirt weave, recoloured.
weave = load("T_Peasant_BaseColor.png")[300:428, 20:148]
weave = np.asarray(Image.fromarray(np.uint8(weave * 255)).resize((256, 256), Image.Resampling.BICUBIC), dtype=np.float32) / 255
weave_lum = weave @ np.array([.2126, .7152, .0722])
for name, color in [("cloth_red.png", [.36, .06, .05]), ("cloth_black.png", [.13, .11, .12]),
                    ("cloth_crimson.png", [.24, .025, .04]), ("cloth_blue.png", [.09, .09, .27])]:
    rgb = (.45 + .9 * (weave_lum - weave_lum.mean()) + .55)[..., None] * np.array(color)
    Image.fromarray(np.uint8(np.clip(rgb, 0, 1) * 255)).save(OUT / name)

# Bone (horns, crown, cultist mask): pale, slightly yellow, from the existing stone grain.
stone = Image.open(ROOT / "assets/dungeon/textures/Mat_GeneralProps_BaseColor.png").convert("RGB").resize((256, 256))
grain = np.asarray(stone, dtype=np.float32) / 255 @ np.array([.2126, .7152, .0722])
y, x = np.mgrid[:256, :256]
bone = .62 + .30 * (grain - grain.mean()) + .03 * np.sin(y * .35 + np.sin(x * .05) * 3)
Image.fromarray(np.uint8(np.clip(bone[..., None] * [.95, .88, .74], 0, 1) * 255)).save(OUT / "bone_albedo.png")
print("M1 material variations written; source textures unchanged.")
