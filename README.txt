Mac-ModInstaller
================
Native Apple Silicon mod installer for Warhammer 40,000: Rogue Trader.

STATUS: Work in progress. No public release is available yet.
The local development build is 0.2.0. Application binaries, game files, third-party
mod ZIPs and local test logs are intentionally excluded from this repository.

PERMISSION REQUIRED
Publicly visible does not mean freely usable. Original project code and materials
are all rights reserved. Ask Poffl for express written permission before using,
modifying or distributing them. See LICENSE for the terms and GitHub-platform
exceptions; third-party dependencies retain their respective licenses.
Permission requests: https://github.com/Poffl-Mods/Mac-Modinstaller/issues

Features
- Automatically locate Rogue Trader user data, with manual folder selection.
- Add one mod ZIP via drag-and-drop or the native file picker.
- Detect Owlcat and UMM formats, including dual-manifest packages.
- Install/update mods and edit Owlcat JSON or UMM Params.xml activation settings.
- List/search installed mods, enable/disable them, and retain backups.
- English, German, French, Spanish, Russian and Simplified Chinese UI.
- Runs natively on Apple Silicon; no Rosetta, Unity or Python runtime required.

Development (after obtaining permission)
Open Package.swift in Xcode, or run swift test and ./build-app.sh.
The app is built at dist/Mac-ModInstaller.app. Builds use local ad-hoc signing;
public distribution and notarization are not configured.

Validation
14 tests passed on the development Mac, including localization coverage,
installation/update behavior, config preservation and rollback.
Real ToyBox, ReDress and Armoury: Orks ZIPs were tested in isolated directories.
Those external packages are not distributed here. Their optional local smoke
checks require the external packages; the remaining tests create their own fixtures.
UI folder detection, ZIP selection and language changes were checked locally.
Game/Harmony compatibility is not guaranteed by installation alone.

Next session
- Exercise Finder drag-and-drop end to end.
- Test UMM mods in the game; keep loader/Harmony compatibility separate.
- Review remaining failure cases and backup recovery UX before a release.
- Decide on future scope without adding a download catalog or load-order editor
  to this first version unless needed.

Deutsche Bedienungs- und Entwicklungsnotizen
------------------------------------------
Mac-ModInstaller 0.2.0 — lokaler Modinstaller für Rogue Trader

Start: dist/Mac-ModInstaller.app öffnen. Die App läuft nativ auf Apple Silicon.

Bedienung
1. Rogue Trader vollständig beenden.
2. Der Benutzerdatenordner wird automatisch gefunden. Bei mehreren Treffern oder
   einem abweichenden Speicherort über „Ändern …“ auswählen.
3. Eine Mod-ZIP in das Feld ziehen oder über „ZIP auswählen …“ öffnen.
4. Name, Version und Ziel prüfen, dann „Installieren“ bzw. „Aktualisieren“ klicken.
5. Das Spiel neu starten. Die Mod-Liste zeigt die konfigurierte Aktivierung,
   nicht eine Bestätigung, dass das Spiel den Mod erfolgreich ausgeführt hat.

Unterstützte Formate
- Info.json plus Mod-DLL: UnityModManager/<Id>, Aktivierung in Params.xml.
- OwlcatModificationManifest.json: Modifications/<UniqueName>, Aktivierung in
  OwlcatModificationManagerSettings.json.
- Bei beiden Manifesten hat Info.json Vorrang (z.B. ToyBox und ReDress).
- ZIPs mit oder ohne umschließenden Mod-Ordner. Ein Mod pro ZIP.
- Aktivieren/deaktivieren, Updates, Suchfilter, Ordner im Finder öffnen.

Sicherungen
Vor Änderungen werden Konfiguration und bei Updates der alte Mod-Ordner unter
„RogueModInstaller Backups“ im Spiel-Benutzerdatenordner gesichert.
Restore.json beschreibt die Zielpfade. Zum manuellen Wiederherstellen zuerst
Spiel und Installer schließen. Gesicherte Konfiguration an ihren ursprünglichen
Ort kopieren; bei einem Mod-Update den aktuellen Mod-Ordner zur Seite verschieben
und PreviousMod an den in Restore.json genannten modFolder-Pfad kopieren.
Die Sicherungen enthalten auch später hinzugefügte User-Dateien. Nach einer
Wiederherstellung die anderen seitdem installierten Mods prüfen, da die
Konfiguration den Stand der betreffenden Sicherung enthält.
Sicherungen werden nicht automatisch gelöscht.
Bei Fehlern während des Kopierens/Schreibens wird der Mod-Ordner zurückgesetzt.
Bei Prozessabbruch oder Stromausfall bleibt die Sicherung für manuelle Reparatur.

Updates
Vom Installer erfasste Paketdateien werden bei Updates ersetzt bzw. entfernt,
wenn die neue Version sie nicht mehr enthält. Zusätzliche lokale Dateien bleiben
erhalten, solange das neue Paket sie nicht selbst mitliefert. Bei erstmals
übernommenen fremden Installationen ist die Herkunft vorhandener Dateien nicht
bekannt; solche Dateien werden konservativ erhalten.

Grenzen dieser ersten Version
- Kein Download-Katalog, keine automatische Abhängigkeitsauflösung und kein
  Loadorder-Editor. Bestehende Reihenfolge wird beim erneuten Aktivieren eines
  bereits aktivierten Owlcat-Mods beibehalten. UMM verwaltet seine Reihenfolge.
- Keine Änderungen an Harmony, Spiel-DLLs, Rosetta oder dem Mod-Loader selbst.
- Keine Garantie der Mac-Kompatibilität eines ZIPs. AssetBundles werden erkannt
  und in der Vorschau angesprochen, jedoch nicht in Mac-Bundles umgewandelt.
- Nur lokale Installation, keine Steam-Workshop-Verwaltung.
- Keine Deinstallation in dieser ersten Version; Deaktivieren ist möglich.
- Maximal 4 GB entpackt / 100.000 ZIP-Einträge; Verknüpfungen, unsichere Pfade,
  mehrdeutige Pakete und fehlerhafte Konfigurationen werden abgelehnt.
- Lokal ad-hoc signiert, nicht für öffentliche Verteilung notarisiert.

Entwicklung
Swift / SwiftUI, macOS 13+, ZIPFoundation 0.9.20 (MIT).
Package.swift in Xcode öffnen oder im Projektordner ausführen:
  swift test
  ./build-app.sh
Build und Tests benötigen Xcode bzw. die passenden Swift-Werkzeuge.
Die fertige App benötigt weder Xcode noch Python, Unity oder Rosetta.
ZIPFoundation-Lizenz wird mit der App ausgeliefert.

Validierung am 08.10.2026
11 Tests erfolgreich: Owlcat/UMM-Routing, UTF-8 BOM, JSON-/XML-Erhalt,
Aktivierung, Updates, Sicherung, Rollback bei simuliertem Schreibfehler,
Entfernung veralteter Paketdateien, Pfad-/Symlink-Abwehr, DTD-Abwehr.
Echte ToyBox-1.7.34-, ReDress-1.4.5- und ArmouryOrks-0.4.9-Pakete in
isolierten Ordnern installiert. Keine zusätzliche Installation ins echte Spiel.
GUI: automatische Erkennung des echten Spielordners, ArmouryOrks-Status,
Dateiauswahl und ToyBox-Vorschau mit korrektem UMM-Ziel geprüft.
Finder-Drag-and-drop ist implementiert; ein echter Finder-Drag wurde nicht separat automatisiert geprüft.
Kein Spieltest als Teil dieser App-Entwicklung.

Version 0.2.0: App in Mac-ModInstaller umbenannt. Sprachauswahl oben rechts:
English, Deutsch, Français, Español, Русский, 简体中文 (vereinfachtes Chinesisch).
Die Auswahl wird gespeichert und sofort auf die app-eigenen Texte angewendet.
Native macOS-Menüs und Teile des Dateidialogs folgen der Systemsprache.
Die Bundle-ID und bisherigen Sicherungspfade bleiben für bestehende Einstellungen stabil.
85 Meldungen in sechs Sprachen, 14 Tests erfolgreich.
