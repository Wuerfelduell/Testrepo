# Asset-Auswahl – Auftrag 01

**Status: prüfbare Teilumsetzung, keine vollständige Freigabe von Auftrag 01/M0.**

Die Auswahl verbessert die alten flach eingefärbten Low-Poly-Proben durch
normalgemappte Haut und Kleidung, ORM-Texturen, höher aufgelöste Figuren und einen
texturierten Dungeon. Eine durchgehende Stil-Freigabe durch den Owner steht aus.

## Enthalten

| Bereich | Tatsächlicher Umfang |
|---|---|
| Menschliche Grundmodelle | Superhero Male / Female, jeweils geriggt und mit Haut-PBR-Texturen |
| Kleidung | Male/Female Peasant und Male/Female Ranger; eigenständige geriggte Kleidungsproben |
| Animationen | 43 Originalclips; die T-Pose ist als Bewegung nicht auswählbar, 42 Clips stehen bereit |
| Dungeon | 17 kostenlose Modelle: Boden, Wand, Durchgang, Treppe, Wandabschlüsse, Sockel, Bücherregal, Tisch, Hocker, Fass, zwei Tränke, Schild und vier Fackel-/Haltervarianten |
| Texturen | Geteilte externe PNGs: Farb-, Normal- und Rauheits-/Metallkanäle; Figuren max. 1K, Dungeon 512 px |
| Szene | Dungeon-Raum, sechs ursprüngliche Modellproben plus Kultist, gemeinsame Animationsauswahl, Orbit/Zoom, zwei Beleuchtungsansichten |

Die Galerie zeigt die Paketinhalte ehrlich als Grundmodelle und Kleidungsproben.
Kleidungsproben sind keine fertigen Helden oder Gegner. Es wurden keine nackten
Grundkörper zu Kriegern/Bossen umbenannt und keine neuen Charaktermodelle erzeugt.

## Animationen

Die Originalnamen im GLB enden teilweise auf `_Loop`. Godot entfernt diesen Import-
Suffix und setzt den Loop-Modus. Beispiel: `Idle_Loop` → `Idle`, `Walk_Loop` → `Walk`,
`Sprint_Loop` → `Sprint`. Jeder der sechs Modellproben bekommt dieselbe Bibliothek;
Knochen werden nach Namen und Restpose zugeordnet. Positionen behalten die
Restlängen der jeweiligen Figur und übernehmen die Bewegung aus der Animation.

Hauptauswahl: `Idle`, `Walk`, `Sprint`, `Sword_Attack`, `Spell_Simple_Shoot`,
`Hit_Chest`, `Death01`. Weitere vorhandene Bewegungen sind direkt auswählbar.
Eine Schwertanimation liefert keine Schwertgeometrie. Auftrag 01b ergänzt jetzt ein
eigenes Schwert und eine Axt als prüfbare Testobjekte, siehe unten.

## Nicht enthalten / noch zu entscheiden

- Vollständige Klassenoptik für alle 12 Klassen. Die geprüfte kostenlose Version
  des Outfits-Packs enthält nur Bauern- und Rangerkleidung. Die übrigen Outfits
  sind in der kostenpflichtigen Source-Version und wurden nicht verwendet.
- Fertige Köpfe/Haarvarianten für alle Outfit-Kombinationen. Die freie Base-Version
  liefert hier Superhero-Körper; das vollständige Regular-Sortiment gehört nicht
  zu dieser kostenlosen Auswahl. Keine improvisierte Kopfmontage wurde als fertig bezeichnet.
- Drei bis vier eigenständige animierte Gegnermodelle und ein Boss derselben Qualität.
- Bogen, Stab und vollständige Klassenrüstung in passenden PBR-Materialien.
  Schwert und Axt sind seit Auftrag 01b als selbst modellierte Testobjekte vorhanden;
  ihre Art-Freigabe steht aus.
- Blut-/Treffereffekte, Magie und animiertes Feuer. Fackelgeometrie und warme
  Schattenlichter sind vorhanden, aber noch kein vollständiges VFX-Paket.
- Türen, Truhen, Knochen und Ketten: der kostenlose Dungeon-Teil enthält nur
  einen offenen Durchgang und einen Teil der benötigten Requisiten.
- Windows-EXE, Regelkern und Kampf: gehören zu den nächsten Aufträgen.

## Reproduzieren

Die originalen Download-Archive bleiben außerhalb des Repos. `source_archives.json`
enthält ihre SHA-256-Werte, [CREDITS.md](CREDITS.md) die direkten Quellen und Lizenzen.
`tools/prepare_assets.py` übernimmt die ausgewählten Standard-Figuren und die
Animationsbibliothek aus `base-characters.zip`, `outfits.zip`, `animations.zip`.
`tools/convert_dungeon.gd` konvertiert die 17 FBX-Geometrien aus einem temporären
Godot-Projekt; `tools/prepare_dungeon.py` ordnet die mitgelieferten Texturen korrekt zu.
Die ursprünglichen FBX-Dateien verweisen auf nicht mitgelieferte PNG-Pfade;
eine untexturierte Erstkonvertierung ist daher nur ein Zwischenschritt.
Die geprüften endgültigen GLBs haben funktionierende Farb-, Normal- und ORM-Texturen.

## Erneute Standard-Prüfung – Auftrag 01b, 06.10.2026

Das kostenlose itch.io-Archiv wurde erneut heruntergeladen und vollständig
inventarisiert. SHA-256: `c3468b18871cc8c8f05ab14df7712baf22cb9f389cbd870babf130e595187f70`.
Es ist bytegleich mit dem Archiv vom 05.10. Die allgemeine Packbeschreibung nennt
12 Outfits/62 Teile; die Vergleichsgrafik auf derselben Seite bezeichnet die freie
Standard-Version ausdrücklich als Ranger und Peasant. Die archivierte Lizenzdatei
erklärt ebenfalls, dass Standard nur einen Teil enthält. Die übrigen Outfits und
Blender-Quelldateien sind nicht im freien Download.

Tatsächlicher Inhalt: **4 komplette Outfits, 20 modulare Modell-Exporte**, jeweils
in FBX und glTF (keine zusätzlichen Outfits durch doppelte Format-Zählung).
[outfit_standard_inventory.json](outfit_standard_inventory.json) enthält jeden Pfad.

| Outfit | Vollmodell | Separate Exporte |
|---|---|---|
| Peasant weiblich | Female_Peasant | Female_Peasant_Arms, Female_Peasant_Body, Female_Peasant_Feet, Female_Peasant_Legs |
| Peasant männlich | Male_Peasant | Male_Peasant_Arms, Male_Peasant_Body, Male_Peasant_Feet, Male_Peasant_Legs |
| Ranger weiblich | Female_Ranger | Female_Ranger_Acc_Pauldrons, Female_Ranger_Arms, Female_Ranger_Body, Female_Ranger_Feet, Female_Ranger_Head_Hood, Female_Ranger_Legs |
| Ranger männlich | Male_Ranger | Male_Ranger_Acc_Pauldron, Male_Ranger_Arms, Male_Ranger_Body, Male_Ranger_Feet_Boots, Male_Ranger_Head_Hood, Male_Ranger_Legs |

Keine kostenlosen Knight-, Wizard- oder Cleric-Outfits gefunden. Die vorhandenen
Vollmodelle enthalten bereits die oben genannten Teile; es wurde kein zusätzliches
Outfit übersehen. Keine kostenpflichtigen Inhalte heruntergeladen.

## Undead Cultist, Schwert und Axt – Art-Test, keine Produktionsfreigabe

- `characters/undead_cultist/model.glb`: bestehende Ranger-Kapuze, Ärmel, Bracer,
  Gürtel, Beine und Stiefel; Ranger-Tunika zur unregelmäßigen Robe verlängert.
  Kopf und Augen sind aus dem vorhandenen männlichen Grundkörper ausgeschnitten.
  Grau-grüne Haut, dunkle burgunderfarbene Stoffvariation, grün emittierende Augen.
- Das Ranger-Rig mit allen 65 Knochen, Restpositionen und Restrotationen bleibt
  erhalten. Kein neues Rig, keine zusätzlichen Animationsclips und keine spezielle
  Retargeting-Stufe für den Gegner. Die vorhandene gemeinsame Bibliothek wird wie
  bei allen Modellproben geladen: dieselben **42 Motion-Clips**.
- `weapons/sword.glb`: **544 Dreiecke**. `weapons/axe.glb`: **540 Dreiecke**.
  Beide wurden mit Blender-Python modelliert; geteilte Albedo-/Normal-/ORM-Karten
  beruhen auf der bereits vorhandenen Dungeon-Textur. Metall, Leder und Holz
  unterscheiden sich über eigene PBR-Materialparameter.
- Der männliche Grundkörper trägt das Schwert, der Kultist die Axt. Beide Waffen
  hängen über `BoneAttachment3D` an `hand_r`, ohne sich auf Weltpositionen zu stützen.
  Auch Lauf-, Treffer-, Zauber- und Todesclips sind mit angehängter Waffe prüfbar.
  Die Vorschau hat noch keinen spielmechanischen Waffenwechsel.
- Galerie: sechs ursprüngliche Proben plus Kultist, gleiche Beleuchtung;
  **Enemy close-up** fokussiert den bewaffneten Grundkörper und den Kultisten.
  **Reset view / R** stellt den normalen Zoom wieder her. Vorhandene Dateien und
  Modelle wurden nicht überschrieben oder umbenannt.

Echte Godot-Aufnahmen (1280 × 720, Compatibility/OpenGL-Software-Renderer,
dieselbe Raumbeleuchtung): [Normalzoom](../docs/enemy-test-normal.png) und
[Nahansicht](../docs/enemy-test-closeup.png). Die Nahansicht blendet die übrigen
Figuren aus, damit die Testobjekte und ihre Beschriftungen lesbar bleiben.
Eine volle Forward+-Bildabnahme mit SSAO/volumetrischem Nebel steht noch aus.

Reproduktion: `python tools/prepare_enemy_textures.py` (Pillow + NumPy), danach
`blender --background --factory-startup --python tools/build_enemy_test.py` (Blender
4.x, gebaut mit 4.0.2). Der Generator arbeitet ausschließlich mit Repo-Quellen.
`enemy_test_manifest.json` dokumentiert Teile und Dreieckszahlen.

Prüfen: `godot --headless --script res://tools/check_showcase.gd` prüft zusätzlich
Rig-Identität, sichtbare Waffen-Geometrie, PBR-Referenzen, Emission, tatsächliche
Waffenbewegung und Griffbindung in allen Clips. Screenshots lassen sich auf Linux
mit `bash tools/capture_enemy_test.sh /pfad/zu/godot` aufnehmen (Xvfb + xauth),
oder direkt mit Godot über `-- --capture=/absoluter/pfad.png --enemy-closeup`.
Der normale Screenshot lässt `--enemy-closeup` weg. Ein Dummy-Headless-Renderer
kann keine Bilder aufnehmen.

## M1-Figuren, Waffen und Treffereffekte – Auftrag 07, 10.10.2026

**Status: eingebaut und geprüft, Art-Freigabe durch den Owner steht aus.** Gleiche
Methode wie 01b: vorhandene CC0-Körper und -Outfits auf dem gemeinsamen 65-Knochen-Rig,
dazu per Skript gebaute starre Teile (Helme, Platten, Masken, Hörner, Umhänge), die an
vorhandene Knochen gebunden sind. Kein neues Rig, keine neuen Animationen, keine Käufe,
keine KI-Modelle, keine Downloads.

| Figur | Ordner | Silhouette | Waffe(n) |
|---|---|---|---|
| Guard | `characters/enemy_guard` | Kettle-Hut über Kettenhaube, rotes Wappenrock, Stahl-Schulterstücke | Speer + Rundschild (links) |
| Bandit | `characters/enemy_bandit` | rotes Kopftuch mit Knoten, schwarzes Gesichtstuch, Bolzenköcher, schwarzes Leder | leichte Armbrust (links), Scimitar für Nahkampf |
| Cultist | `characters/enemy_cultist` | blutrote Kapuzenrobe, Knochenmaske, rot glimmende Augen, Strick mit Knochenamuletten | Sichel |
| Cult Priest (Boss) | `characters/boss_cult_priest` | 1,22× Größe, Widderhörner + Knochenkrone, hoher Kragen, schwerer Umhang, Knochen-Schulterstücke, leuchtendes Brustsiegel und Augen | Priesterstab mit Schädel, Hörnern, grünem Edelstein |
| Fighter m/w | `characters/hero_fighter_*` | Kettenhaube, glatter Brustpanzer, Schulterlamellen, Messingnieten | Langschwert + Heater-Schild |
| Wizard m/w | `characters/hero_wizard_*_hood`, `*_hat` | bodenlange Robe; Kapuze **oder** Spitzhut | Stab mit leuchtendem Kristall |

Waffen (`weapons/`, Blender-Python, gleiche PBR-Karten wie Schwert/Axt, je ≤ 1500 Dreiecke):
Dolch, Scimitar, Sichel, Streitkolben, Speer, Stab, Priesterstab, Kurzbogen, leichte
Armbrust, Heater-Schild, Rundschild. Dreieckszahlen: `m1_art_manifest.json`.

**Manifeste**
- `weapons/weapons.json`: Szene, Hand und Griff-Transform je Waffe. Bogen und Armbrust
  sitzen links, weil der vorhandene Fernkampf-Clip `Spell_Simple_Shoot` den linken Arm
  ausstreckt; Stangenwaffen liegen entlang des Unterarms.
- `characters/looks.json`: Standardwaffe (`main_hand`) und immer getragenes `off_hand`
  (Schild) je Figurenszene. `PreviewActor`/`CombatActor` lesen das automatisch.
- `characters/hero_looks.json` (für Auftrag 06): `class`, `body` (`male`/`female`),
  `look_id`, `name_key`, `scene`. Fighter und Wizard, je männlich und weiblich.

**Arena:** `data/monsters/guard|bandit|cultist.tres` verweisen jetzt auf die eigenen
Modelle; jeder Angriff hat sein Waffenmodell. Der Bandit zieht beim Nahkampf den
Scimitar (`swap_weapon`). `data/monsters/cult_priest.tres` ist ein reiner Optik-Eintrag
(ohne Werte, `is_valid() == false`, kann nicht versehentlich in einen Kampf).

**Treffereffekte** (`src/world/vfx/hits/hit_effects.gd`, CPUParticles3D für den
Compatibility-Renderer): Blutspritzer bei physischem Schaden (Hieb/Stich/Wucht) mit
Blutfleck am Boden, stärkerer Spritzer + roter Lichtblitz bei kritischen Treffern,
Funken bei verfehltem Nahkampfangriff, Staub, wenn ein Toter am Boden aufschlägt.
Zauberschaden blutet nicht (Effekte dafür gehören zu Auftrag 05).

**Showcase:** neue Reihen vor den alten Proben; Knöpfe *Enemies*, *Hero looks*,
*Weapons*, *Hit effects*. Echte Godot-Aufnahmen (1280 × 720, Compatibility/llvmpipe):
[Übersicht im Normalzoom](../docs/m1-overview.png), [Gegner nah](../docs/m1-enemies.png),
[Heldenlooks](../docs/m1-heroes.png), [Waffen](../docs/m1-weapons.png),
[Treffereffekte](../docs/m1-hits.png).

**Reproduzieren:** `python3 tools/prepare_m1_textures.py` (Pillow + NumPy), dann
`blender --background --factory-startup --python tools/build_m1_art.py` oder mit dem
`bpy`-Wheel `python3.11 tools/build_m1_art.py` (gebaut mit bpy 5.0.1). Einzelne Teile:
`... build_m1_art.py -- enemy_guard spear`. Screenshots: `bash tools/capture_m1_art.sh godot`.

**Größe:** die neuen GLBs liegen zwischen 0,1 und 2,5 MB, `assets/` insgesamt ≈ 67 MB
(vorher ≈ 50 MB). GitHub verlangt LFS erst ab 100 MB pro Datei; die Entscheidung, ob die
50-MB-Richtlinie aus Auftrag 01 angehoben oder LFS eingerichtet wird, liegt beim Owner
(siehe Handover 10.10.2026). Bis dahin bleiben alle Dateien normale Git-Dateien.

### Ehrliche Einschätzung
- **Gut:** Die vier Gegner sind im Normalzoom klar unterscheidbar (Hut + Schild vs.
  Kopftuch + Armbrust vs. Kapuze + Maske vs. Hörner + Umhang + Größe). Waffen bleiben in
  allen 42 Clips in der Hand; die Armbrust zeigt beim Schuss nach vorne. Blut, Funken und
  Staub lesen sich in der Arena-Kamera.
- **Schwach:** Kleidung bleibt Quaternius-Ranger/Peasant-Schnitt, nur umgefärbt und
  ergänzt; Fighter m/w und Wizard m/w unterscheiden sich kaum, weil Haube/Kapuze die
  Köpfe verdecken. Der Brustpanzer ist eine glatte Schale ohne Kanten/Gravur. Köpfe
  sind kahl (keine freien Haar-Meshes), unter dem Spitzhut sichtbar. Der Umhang des
  Bosses und die Roben haben keine Stoffsimulation und können beim Laufen mit den
  Beinen schneiden. Metall wirkt im Compatibility-Renderer ohne Reflexionen dunkel.
  Die Maske des Kultisten hat nur angedeutete Augenlöcher.
- **Animation:** Es gibt weiter keinen echten Bogen-/Armbrust-Clip, keinen Schildblock
  und keinen Speerstoß; Speer und Stab nutzen den Schwertschwung.
- **Nicht machbar auf diesem Weg:** nicht-humanoide Monster (Untote Tiere, Spinnen,
  Wölfe, Dämonen mit anderem Skelett) – dafür braucht es Modelle mit eigenem Rig und
  eigenen Animationen. Auch die HUD-Porträts (Auftrag 05) zeigen noch die alten Gesichter.
