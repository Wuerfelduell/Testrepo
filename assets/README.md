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
| Szene | Dungeon-Raum, sechs Modellproben, gemeinsame Animationsauswahl, Orbit/Zoom, zwei Beleuchtungsansichten |

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
- Das Ranger-Rig mit allen 62 Knochen, Restpositionen und Restrotationen bleibt
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
