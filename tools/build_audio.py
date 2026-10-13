#!/usr/bin/env python3
"""Package 11: builds assets/audio/ from free CC0 sources.

Downloads every source pack (cached in build/audio_sources/), cuts and mixes the clips
with ffmpeg, normalises loudness and writes OGG Vorbis files with the names that
src/audio/sound_library.gd expects. Run from the repo root:

    python3 tools/build_audio.py

Needs: python3 with numpy, ffmpeg with libvorbis, py7zr (pip) for the .7z packs.
Every source is CC0; authors and links are listed in assets/CREDITS.md.
"""
from __future__ import annotations

import json
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "build" / "audio_sources"
OUT = ROOT / "assets" / "audio"
OGA = "https://opengameart.org/sites/default/files/"

# id -> (download url, page, author). All CC0.
SOURCES: dict[str, tuple[str, str, str]] = {
    "k_rpg": ("https://kenney.nl/media/pages/assets/rpg-audio/8e99002d76-1677590336/kenney_rpg-audio.zip", "https://kenney.nl/assets/rpg-audio", "Kenney"),
    "k_impact": ("https://kenney.nl/media/pages/assets/impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip", "https://kenney.nl/assets/impact-sounds", "Kenney"),
    "k_ui": ("https://kenney.nl/media/pages/assets/interface-sounds/fa43c1dd4d-1677589452/kenney_interface-sounds.zip", "https://kenney.nl/assets/interface-sounds", "Kenney"),
    "k_casino": ("https://kenney.nl/media/pages/assets/casino-audio/2472606a04-1721639069/kenney_casino-audio.zip", "https://kenney.nl/assets/casino-audio", "Kenney"),
    "k_jingles": ("https://kenney.nl/media/pages/assets/music-jingles/f37e530b9e-1677590399/kenney_music-jingles.zip", "https://kenney.nl/assets/music-jingles", "Kenney"),
    "rd_rpg": (OGA + "80-CC0-RPG-SFX_0.zip", "https://opengameart.org/content/80-cc0-rpg-sfx", "rubberduck"),
    "rd_creature": (OGA + "80-CC0-creature-SFX_0.zip", "https://opengameart.org/content/80-cc0-creature-sfx", "rubberduck"),
    "rd_water": (OGA + "water-splash-slime-sfx.zip", "https://opengameart.org/content/40-cc0-water-splash-slime-sfx", "rubberduck"),
    "ad_rpg": (OGA + "rpg_sound_pack.zip", "https://opengameart.org/content/rpg-sound-pack", "artisticdude"),
    "ad_swish": (OGA + "swishes.zip", "https://opengameart.org/content/swishes-sound-pack", "artisticdude"),
    "ad_freeze": (OGA + "freeze.wav", "https://opengameart.org/content/freeze-spell-0", "artisticdude"),
    "bart_ice": (OGA + "icespells.zip", "https://opengameart.org/content/ice-spells", "bart"),
    "sm_cure": (OGA + "curemagic.zip", "https://opengameart.org/content/cure-magic", "someoneman"),
    "qb_dark": (OGA + "dark_magic.7z", "https://opengameart.org/content/3-dark-magic-spells", "qubodup"),
    "qb_ghost": (OGA + "ghostbreath.flac", "https://opengameart.org/content/ghost-breath", "qubodup"),
    "qb_eerie": (OGA + "independent_nu_ljudbank-atmosphere_moody.7z", "https://opengameart.org/content/4-atmospheric-ghostly-loops", "qubodup (Independent.nu)"),
    "qb_drip": (OGA + "atmosbasement.mp3_.flac", "https://opengameart.org/content/dripping-water-loop", "qubodup"),
    "qb_steps": (OGA + "Fantozzi-footsteps.7z", "https://opengameart.org/content/fantozzis-footsteps-grasssand-stone", "Fantozzi, uploaded by qubodup"),
    "js_dungeon": (OGA + "dungeon_ambient_1_0.ogg", "https://opengameart.org/content/loopable-dungeon-ambience", "jaggedstone"),
    "mk_vocal": (OGA + "vocal_samples.zip", "https://opengameart.org/content/dialog-vocal-samples", "mirceakitsune"),
    "m_lament": (OGA + "Lament_for_a_Warriors_Soul_REUPLOAD.mp3", "https://opengameart.org/content/fantasy-lament-for-a-warriors-soul", "randommind"),
    "m_dungeon": (OGA + "dungeon002_0.ogg", "https://opengameart.org/content/dungeon-ambience", "yd"),
    "m_battle": (OGA + "battleThemeA.mp3", "https://opengameart.org/content/battle-theme-a", "cynicmusic"),
    "m_pursuit": (OGA + "determined_pursuit_loop.wav", "https://opengameart.org/content/determined-pursuit-epic-orchestra-loop", "emmama"),
    "m_victory": (OGA + "victory.wav", "https://opengameart.org/content/medieval-victory-theme", "randommind"),
    "m_defeat": (OGA + "defeat.wav", "https://opengameart.org/content/medieval-defeat-theme", "randommind"),
}

# Sound effects: target -> [(source id, member path inside the pack, options)].
# Several entries are mixed together. Options: start, dur (seconds), gain (dB), delay (s), fade (s).
SFX: dict[str, list[tuple[str, str, dict]]] = {
    "ui_click_1": [("k_ui", "Audio/select_001.ogg", {})],
    "ui_click_2": [("k_ui", "Audio/select_002.ogg", {})],
    "dice_roll_1": [("k_casino", "Audio/dice-shake-1.ogg", {})],
    "dice_roll_2": [("k_casino", "Audio/dice-shake-2.ogg", {})],
    "dice_land_1": [("k_casino", "Audio/dice-throw-1.ogg", {})],
    "dice_land_2": [("k_casino", "Audio/dice-throw-2.ogg", {})],
    "dice_crit": [("k_jingles", "Audio/Pizzicato jingles/jingles_PIZZI04.ogg", {})],
    "dice_fumble": [("k_jingles", "Audio/Pizzicato jingles/jingles_PIZZI01.ogg", {})],
    "footstep_stone_1": [("k_impact", "Audio/footstep_concrete_000.ogg", {})],
    "footstep_stone_2": [("k_impact", "Audio/footstep_concrete_001.ogg", {})],
    "footstep_stone_3": [("k_impact", "Audio/footstep_concrete_002.ogg", {})],
    "footstep_stone_4": [("k_impact", "Audio/footstep_concrete_003.ogg", {})],
    "footstep_dirt_1": [("qb_steps", "Fantozzi-footsteps/ogg/Fantozzi-SandL1.ogg", {})],
    "footstep_dirt_2": [("qb_steps", "Fantozzi-footsteps/ogg/Fantozzi-SandR1.ogg", {})],
    "footstep_dirt_3": [("qb_steps", "Fantozzi-footsteps/ogg/Fantozzi-SandL2.ogg", {})],
    "footstep_dirt_4": [("qb_steps", "Fantozzi-footsteps/ogg/Fantozzi-SandR2.ogg", {})],
    "footstep_wood_1": [("k_impact", "Audio/footstep_wood_000.ogg", {})],
    "footstep_wood_2": [("k_impact", "Audio/footstep_wood_001.ogg", {})],
    "footstep_wood_3": [("k_impact", "Audio/footstep_wood_002.ogg", {})],
    "footstep_wood_4": [("k_impact", "Audio/footstep_wood_003.ogg", {})],
    "footstep_water_1": [("rd_water", "splash_09.ogg", {})],
    "footstep_water_2": [("rd_water", "splash_10.ogg", {})],
    "footstep_water_3": [("rd_water", "splash_06.ogg", {})],
    "swing_1": [("ad_rpg", "RPG Sound Pack/battle/swing.wav", {})],
    "swing_2": [("ad_rpg", "RPG Sound Pack/battle/swing2.wav", {})],
    "swing_3": [("ad_rpg", "RPG Sound Pack/battle/swing3.wav", {})],
    # No free bow recording found: a short swish plus a dull wooden knock as the string.
    "bow_shot_1": [("ad_swish", "swishes/swish-3.wav", {"delay": 0.03}), ("k_impact", "Audio/impactWood_light_000.ogg", {"gain": -8})],
    "bow_shot_2": [("ad_swish", "swishes/swish-5.wav", {"delay": 0.03}), ("k_impact", "Audio/impactWood_light_001.ogg", {"gain": -8})],
    "hit_slashing_1": [("rd_rpg", "blade_01.ogg", {})],
    "hit_slashing_2": [("rd_rpg", "blade_03.ogg", {})],
    "hit_piercing_1": [("k_rpg", "Audio/knifeSlice.ogg", {})],
    "hit_piercing_2": [("k_rpg", "Audio/knifeSlice2.ogg", {})],
    "hit_bludgeoning_1": [("k_impact", "Audio/impactPunch_heavy_000.ogg", {})],
    "hit_bludgeoning_2": [("k_impact", "Audio/impactPunch_heavy_001.ogg", {})],
    "hit_fire": [("rd_rpg", "spell_fire_07.ogg", {})],
    "hit_cold": [("bart_ice", "ice.wav", {})],
    "hit_force": [("ad_rpg", "RPG Sound Pack/battle/magic1.wav", {})],
    "miss_1": [("ad_swish", "swishes/swish-7.wav", {})],
    "miss_2": [("ad_swish", "swishes/swish-9.wav", {})],
    "critical": [("k_impact", "Audio/impactMetal_heavy_000.ogg", {}), ("k_impact", "Audio/impactPunch_heavy_002.ogg", {"gain": -3})],
    "death_1": [("rd_rpg", "creature_die_01.ogg", {})],
    "death_2": [("rd_creature", "grunt_01.ogg", {})],
    "spell_cast": [("rd_rpg", "spell_01.ogg", {})],
    "spell_impact": [("rd_rpg", "spell_02.ogg", {})],
    "spell_cast_fire": [("rd_rpg", "spell_fire_01.ogg", {})],
    "spell_impact_fire": [("rd_rpg", "spell_fire_05.ogg", {})],
    "spell_impact_flames": [("rd_rpg", "spell_fire_03.ogg", {})],
    "spell_cast_frost": [("ad_freeze", "freeze.wav", {})],
    "spell_impact_frost": [("bart_ice", "coldsnap.wav", {})],
    "spell_cast_arcane": [("ad_rpg", "RPG Sound Pack/battle/spell.wav", {"dur": 1.6, "fade": 0.5})],
    "spell_impact_arcane": [("qb_dark", "dark_magic/fout-02.flac", {})],
    "spell_cast_sleep": [("sm_cure", "Cure6.wav", {})],
    "spell_impact_sleep": [("qb_ghost", "ghostbreath.flac", {"dur": 2.2, "fade": 0.8})],
    "spell_shield": [("k_impact", "Audio/impactBell_heavy_000.ogg", {}), ("k_impact", "Audio/impactGlass_light_000.ogg", {"gain": -6})],
    "heal": [("sm_cure", "Cure1.wav", {})],
    "level_up": [("k_jingles", "Audio/Pizzicato jingles/jingles_PIZZI02.ogg", {}), ("sm_cure", "Cure3.wav", {"gain": -6, "delay": 0.15})],
    "loot_pickup_1": [("k_rpg", "Audio/handleCoins.ogg", {})],
    "loot_pickup_2": [("k_rpg", "Audio/handleCoins2.ogg", {})],
}

# Music: target -> (source id, options). Loops are kept untouched so they still loop.
MUSIC: dict[str, tuple[str, dict]] = {
    "menu": ("m_lament", {}),
    "exploration": ("m_dungeon", {}),
    "combat": ("m_battle", {}),
    "boss": ("m_pursuit", {}),
    "victory": ("m_victory", {}),
    "death": ("m_defeat", {}),
}

SFX_PEAK_DB = -1.0
MUSIC_LUFS = -16.0
ROOM_TONE_LUFS = -24.0


def fetch(source_id: str) -> Path:
    url = SOURCES[source_id][0]
    folder = CACHE / source_id
    archive = folder / url.rsplit("/", 1)[-1]
    if not archive.exists():
        folder.mkdir(parents=True, exist_ok=True)
        print("download", url)
        request = urllib.request.Request(url, headers={"User-Agent": "Overcity-audio-build"})
        with urllib.request.urlopen(request, timeout=300) as response:
            archive.write_bytes(response.read())
    # Keep Godot from importing the raw packs (build/ is git-ignored but inside the project).
    (CACHE / ".gdignore").touch()
    marker = folder / ".extracted"
    if not marker.exists():
        if archive.suffix == ".zip":
            with zipfile.ZipFile(archive) as zf:
                zf.extractall(folder)
        elif archive.suffix == ".7z":
            import py7zr
            with py7zr.SevenZipFile(archive) as zf:
                zf.extractall(folder)
        marker.write_text("ok")
    return folder


def member(source_id: str, path: str) -> Path:
    folder = fetch(source_id)
    direct = folder / path
    if direct.exists():
        return direct
    matches = [p for p in folder.rglob(Path(path).name) if "__MACOSX" not in p.parts]
    if not matches:
        sys.exit(f"missing {path} in {source_id}")
    return matches[0]


def decode(path: Path, rate: int = 44100, channels: int = 1) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-ac", str(channels), "-ar", str(rate), "-f", "f32le", "-"],
                         check=True, capture_output=True).stdout
    data = np.frombuffer(raw, np.float32).copy()
    return data.reshape(-1, channels) if channels > 1 else data


def encode(samples: np.ndarray, target: Path, quality: int, rate: int = 44100) -> None:
    channels = 1 if samples.ndim == 1 else samples.shape[1]
    target.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(rate), "-ac", str(channels), "-i", "-",
                    "-c:a", "libvorbis", "-q:a", str(quality), "-map_metadata", "-1", str(target)],
                   input=samples.astype(np.float32).tobytes(), check=True)


def trim_silence(x: np.ndarray, threshold: float = 0.003) -> np.ndarray:
    loud = np.flatnonzero(np.abs(x) > threshold)
    if loud.size == 0:
        return x
    start = max(0, loud[0] - 64)
    end = min(len(x), loud[-1] + 2205)
    return x[start:end]


def fade(x: np.ndarray, seconds: float, rate: int = 44100, at_start: bool = False) -> np.ndarray:
    n = min(len(x), int(seconds * rate))
    if n <= 0:
        return x
    ramp = np.linspace(1.0, 0.0, n, dtype=np.float32)
    if at_start:
        x[:n] *= ramp[::-1]
    else:
        x[-n:] *= ramp
    return x


def clip_for(source_id: str, path: str, options: dict, rate: int = 44100) -> np.ndarray:
    x = decode(member(source_id, path), rate)
    x = trim_silence(x)
    if "start" in options:
        x = x[int(options["start"] * rate):]
    if "dur" in options:
        x = x[:int(options["dur"] * rate)]
    if "fade" in options:
        x = fade(x, options["fade"], rate)
    x = fade(x, 0.004, rate, at_start=True)
    x = x * (10 ** (options.get("gain", 0.0) / 20))
    if options.get("delay"):
        x = np.concatenate([np.zeros(int(options["delay"] * rate), np.float32), x])
    return x


def peak_normalise(x: np.ndarray, peak_db: float) -> np.ndarray:
    peak = float(np.abs(x).max()) or 1.0
    return x * (10 ** (peak_db / 20) / peak)


def build_sfx() -> None:
    for name, parts in SFX.items():
        clips = [clip_for(*part) for part in parts]
        mix = np.zeros(max(len(c) for c in clips), np.float32)
        for clip in clips:
            mix[:len(clip)] += clip
        mix = fade(mix, 0.01)
        encode(peak_normalise(mix, SFX_PEAK_DB), OUT / "sfx" / f"{name}.ogg", quality=4)


def loudnorm(source: Path, target: Path, lufs: float, channels: int, quality: int, linear: bool = True) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    # Two-pass EBU R128 loudness normalisation, true peak at most -1.5 dBTP (no clipping).
    first = subprocess.run(["ffmpeg", "-hide_banner", "-i", str(source), 
                            "-af", f"loudnorm=I={lufs}:TP=-1.5:LRA=11:print_format=json", "-f", "null", "-"],
                           check=True, capture_output=True, text=True).stderr
    stats = json.loads(first[first.rindex("{"):first.rindex("}") + 1])
    af = (f"loudnorm=I={lufs}:TP=-1.5:LRA=11:measured_I={stats['input_i']}:measured_TP={stats['input_tp']}"
          f":measured_LRA={stats['input_lra']}:measured_thresh={stats['input_thresh']}:offset={stats['target_offset']}:linear={str(linear).lower()}"
          ",alimiter=limit=0.7:level=false")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(source), "-af", af, "-ar", "44100",
                    "-ac", str(channels), "-c:a", "libvorbis", "-q:a", str(quality), "-map_metadata", "-1", str(target)], check=True)


def build_music() -> None:
    for name, (source_id, _options) in MUSIC.items():
        folder = fetch(source_id)
        source = folder / SOURCES[source_id][0].rsplit("/", 1)[-1]
        loudnorm(source, OUT / "music" / f"{name}.ogg", MUSIC_LUFS, channels=2, quality=3)


def build_ambience() -> None:
    rate = 44100
    # Room tone: the loopable dungeon ambience, quiet, mono (it plays on the Ambience bus).
    # Dynamic mode, because its few loud knocks would otherwise break the true-peak limit.
    loudnorm(fetch("js_dungeon") / "dungeon_ambient_1_0.ogg", OUT / "ambience" / "room_tone.ogg",
             ROOM_TONE_LUFS, channels=1, quality=2, linear=False)
    # Drips: the three loudest single drops cut out of the basement drip recording.
    drips = decode(member("qb_drip", "atmosbasement.mp3_.flac"), rate)
    envelope = np.convolve(np.abs(drips), np.ones(441) / 441, mode="same")
    chosen: list[int] = []
    for index in np.argsort(envelope)[::-1]:
        if all(abs(int(index) - c) > rate for c in chosen):
            chosen.append(int(index))
        if len(chosen) == 3:
            break
    for number, centre in enumerate(sorted(chosen), start=1):
        clip = drips[max(0, centre - int(0.08 * rate)):centre + int(0.9 * rate)].copy()
        clip = fade(fade(clip, 0.02, rate, at_start=True), 0.4, rate)
        encode(peak_normalise(clip, SFX_PEAK_DB), OUT / "ambience" / f"drip_{number}.ogg", quality=3)
    # Whispers near the living boss: a ghostly drone with whispered syllables scattered
    # over it, each with a small echo. Loops as a whole (20 s, faded ends).
    drone = decode(member("qb_eerie", "atmoseerie02.mp3.flac"), rate)
    drone = drone[: 20 * rate] * 0.5
    for number, start in [(1, 1.5), (2, 4.2), (3, 7.9), (1, 11.3), (2, 14.6), (3, 17.2)]:
        whisper = clip_for("mk_vocal", f"whisper_{number}.ogg", {"gain": -4}, rate)
        for echo, gain in [(0.0, 1.0), (0.23, 0.45), (0.51, 0.2)]:
            offset = int((start + echo) * rate)
            end = min(len(drone), offset + len(whisper))
            drone[offset:end] += whisper[: end - offset] * gain
    drone = fade(fade(drone, 1.0, rate, at_start=True), 1.0, rate)
    encode(peak_normalise(drone, -3.0), OUT / "ambience" / "whispers.ogg", quality=3)


def main() -> None:
    build_sfx()
    build_music()
    build_ambience()
    total = sum(p.stat().st_size for p in OUT.rglob("*.ogg"))
    print(f"assets/audio: {len(list(OUT.rglob('*.ogg')))} files, {total / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
