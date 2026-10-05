# The RPG

Godot-4-Projekt für das geplante Fantasy-RPG. Aktuell enthält es die erste
Asset-Showcase aus Auftrag 01; **noch kein spielbares RPG**.

## Starten

1. Repository mit `git clone` oder als GitHub-ZIP herunterladen.
2. `project.godot` mit **Godot 4.7.2 stable, Standard-Ausgabe** öffnen.
3. Import abwarten, dann **F6** für `scenes/showcase/asset_showcase.tscn` oder **F5**.

Die Szene zeigt zwei menschliche Grundmodelle und vier Kleidungsproben in einem
kleinen Dungeon. Sie dient der Art-Prüfung; die Kleider sind noch keine fertig
zusammengesetzten Spielfiguren. Die beiden Grundmodelle tragen keine Klassenrüstung.

| Bedienung | Wirkung |
|---|---|
| Dropdown oder Q / E | Animation wechseln |
| Pfeiltasten oder rechte Maustaste ziehen | Kamera drehen |
| Mausrad | Zoom |
| R | Ansicht zurücksetzen |
| L | Atmosphärische Beleuchtung / helle Prüfansicht |

Forward+ ist die Hauptdarstellung mit SSAO, Glow und volumetrischem Nebel.
Für Geräte ohne Vulkan: `godot --rendering-method gl_compatibility --path .`.
Dieser Fallback hat kein SSAO und keinen volumetrischen Nebel.

## Prüfen

```sh
godot --headless --editor --import
godot --headless --script res://tools/check_showcase.gd
```

Der Check prüft die geladenen Modelle, die 42 nutzbaren Animationsclips auf allen
sechs Proben, Knochenreferenzen, PBR-Texturzuordnung, Tastatur-Umschaltung und
Übersetzungen. Er ersetzt die visuelle Freigabe der Modelle durch den Owner nicht.

## Stand und nächste Arbeit

Details zu Quellen, Lizenzen, Animationen und fehlenden Modellen stehen in
[assets/README.md](assets/README.md) und [assets/CREDITS.md](assets/CREDITS.md).
Das kuratierte Asset-Set bleibt unter 50 MB und wird vollständig als normale Git-Dateien gespeichert. Falls spätere Assets diesen Umfang überschreiten, muss Git LFS gemäß Auftrag 01 eingerichtet werden.

**Auftrag 01 ist teilweise umgesetzt und noch nicht abgeschlossen.** Die
kostenlosen, überprüften Figurenpakete decken die vollständigen Anforderungen an
12 Klassen, 3–4 Gegner und einen Boss nicht ab. Die offene Asset-Entscheidung steht
in [handover/05-10-2026.md](handover/05-10-2026.md).
Aufträge 02–04 bleiben in der vom Koordinator festgelegten Reihenfolge ausstehend.
Regelkern, Kampfsystem, Windows-Export und vollständige Spielfiguren folgen später.
