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
Eine Schwertanimation liefert keine Schwertgeometrie; Waffen fehlen noch.

## Nicht enthalten / noch zu entscheiden

- Vollständige Klassenoptik für alle 12 Klassen. Die geprüfte kostenlose Version
  des Outfits-Packs enthält nur Bauern- und Rangerkleidung. Die übrigen Outfits
  sind in der kostenpflichtigen Source-Version und wurden nicht verwendet.
- Fertige Köpfe/Haarvarianten für alle Outfit-Kombinationen. Die freie Base-Version
  liefert hier Superhero-Körper; das vollständige Regular-Sortiment gehört nicht
  zu dieser kostenlosen Auswahl. Keine improvisierte Kopfmontage wurde als fertig bezeichnet.
- Drei bis vier eigenständige animierte Gegnermodelle und ein Boss derselben Qualität.
- Schwert, Axt, Bogen, Stab sowie Klassenrüstung in passenden PBR-Materialien.
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
