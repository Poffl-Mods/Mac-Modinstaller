Mac-ModInstaller 1.0.1
====================
A native Apple Silicon mod installer for Warhammer 40,000: Rogue Trader.

Requirements
- Apple Silicon Mac (M1 or newer), macOS 13 Ventura or newer.
- A local Rogue Trader installation. Intel Macs are not supported by this build.
- No Unity, Xcode, Python or Rosetta required to run the application.

Quick start
1. Extract the release ZIP and move Mac-ModInstaller.app to Applications.
2. Close Rogue Trader, then open Mac-ModInstaller.
3. The app looks for the game's user-data folder automatically. If necessary,
   choose it manually with the folder button. Do not select the game .app.
4. Drag one mod ZIP into the app or use the ZIP picker.
5. Review the destination, dependencies and compatibility warnings, then install.
6. Restart the game. The list shows configured activation, not successful
   runtime loading. Only install mods from sources you trust.

Opening the application
This release is locally ad-hoc signed, not Developer ID signed or notarized
by Apple. macOS may block the first launch. If you trust the download, follow
Apple's instructions for allowing this particular application through
System Settings > Privacy & Security > Open Anyway:
https://support.apple.com/102445
Do not disable Gatekeeper globally. Managed Macs may prohibit exceptions.

Features
- Owlcat and UnityModManager packages, including dual-manifest ZIPs.
- Install/update, enable/disable, installed-mod search and Finder access.
- Automatic inventory refresh when other tools change installed mods.
- Backups and rollback for failed installations/updates.
- Dependency/version checks and local platform checks.
- Bundle target platforms read from supported UnityFS metadata.
- English, German, French, Spanish, Russian and Simplified Chinese UI.
- Adeptus Mechanicus-inspired cogitator appearance and original icon.

Compatibility checks
Native Windows/Linux binaries, missing or outdated dependencies, version
downgrades and Windows-specific bundle paths produce warnings. Supported
UnityFS bundles report their serialized target platforms; Windows/Linux and
recognized mobile/console targets produce specific warnings. File names are
not treated as proof of platform compatibility.

Supported bundle inspection: UnityFS 6-8, uncompressed/LZ4/LZ4HC blocks,
SerializedFile 9-22. LZMA, legacy UnityRaw/UnityWeb, unknown/encrypted formats,
invalid data and files exceeding inspection limits remain explicitly unverified.
A macOS target does not guarantee working shaders, Harmony patches, native
libraries, game-version compatibility or successful loading in the game.
The installer does not convert bundles or replace the mod loader.

Harmony for Mac
Use "Harmony for Mac" to select the Rogue Trader game .app and inspect its
shared Harmony DLL. This is separate from installing individual mods. The
optional action downloads the pinned official Harmony Fat 2.4.2.0 release from
GitHub and installs its net472/0Harmony.dll after verifying both SHA-256 hashes.
It requires an explicit acknowledgement and a closed game. An identical build
is left alone; a newer readable file version is not downgraded. Unknown file
versions are displayed as unknown rather than assumed to be older.

The original DLL and HarmonyRestore.json are saved under "RogueModInstaller
Backups/Harmony-..." in the selected user-data folder. "Restore Harmony" restores
the saved DLL only if the backup matches the selected game and the currently
installed DLL still matches the updater's version. Choose the backup folder
manually if needed. Steam/game updates or file verification may revert changes.
Changing a file inside the game app may invalidate its signature; this operation
does not re-sign the game. This cannot fix all mod compatibility problems.
No Harmony binaries are bundled or redistributed. Official source/download:
https://github.com/pardeike/Harmony/releases/tag/v2.4.2.0

Backups
Before changes, configuration files are backed up under "RogueModInstaller
Backups" in the selected game's user-data folder. Updates also back up the
previous mod directory. Backups are not deleted automatically.

To restore manually, close both game and installer. Restore configuration files
to the paths recorded in Restore.json. For an update, move the current mod
folder aside and copy PreviousMod back to the recorded modFolder path. Review
other mods installed since that backup because the restored activation
configuration reflects the older state. Save games are not included in backups.
An ordinary installation error triggers rollback; an interruption or power loss
can require manual recovery from the retained backup.

Uninstalling
Use "Uninstall …" next to a mod and confirm removal. This removes the entire mod
folder, including settings inside it, and the mod's loader configuration entry.
External settings and saved games are retained. Enabled dependent mods are shown
before confirmation. Close the game first.
By default a recovery backup is retained. Select the backup deletion option to
also permanently remove backups whose Restore.json names this mod's folder,
including the new recovery backup. Old activation-only backups without a mod
association and backups of other mods are retained. Shared configuration snapshots
in those backups may still contain historical entries for the removed mod.

Scope
One mod per ZIP. No download catalog, dependency downloads, automatic updates,
load-order editor or Steam Workshop management. Dependencies
must be installed separately. Maximum 4 GB extracted / 100,000 ZIP entries;
unsafe paths, symbolic links and ambiguous packages are rejected.

License and support
Official releases are free for personal, non-commercial use. Modification,
redistribution, rehosting and commercial use require Poffl's written permission.
The source code is not open source. See LICENSE for full terms.
Report issues: https://github.com/Poffl-Mods/Mac-Modinstaller/issues
No third-party mods, game files, Unity SDK files or loader binaries are included.
This is an independent project, not an official Owlcat, Games Workshop, Unity
or Apple product. Third-party licenses are provided with the download.

Deutsch — Kurzstart
-------------------
Voraussetzungen: Apple Silicon (M1 oder neuer), macOS 13 oder neuer, Rogue Trader.
ZIP entpacken, Mac-ModInstaller.app nach Programme verschieben und öffnen.
Die App ist lokal signiert, aber nicht von Apple notarisiert. Bei einer Sperre
kann die einzelne App nach Prüfung der Downloadquelle unter Systemeinstellungen
> Datenschutz & Sicherheit > Dennoch öffnen freigegeben werden. Anleitung:
https://support.apple.com/de-de/102445

Spiel schließen. Der Benutzerdatenordner wird automatisch gesucht; bei Bedarf
manuell auswählen. Eine Mod-ZIP hineinziehen oder über den Dateidialog öffnen,
Vorschau und Hinweise prüfen, installieren und das Spiel neu starten.
Die angezeigte Aktivierung bestätigt nicht, dass die Mod im Spiel funktioniert.
Nicht prüfbare Bundles bleiben ausdrücklich ungeprüft; es erfolgt keine
Umwandlung in Mac-Bundles. Sicherungen enthalten keine Spielstände.
Kostenlos zur privaten, nichtkommerziellen Nutzung. Änderungen, Weitergabe und
kommerzielle Nutzung benötigen Poffls schriftliche Erlaubnis. Details: LICENSE.

Development
-----------
Swift / SwiftUI; ZIPFoundation 0.9.20 (MIT). After obtaining permission to build
or modify the source: swift test, then ./build-app.sh.
The script accepts additional Swift build options. Release output:
dist/Mac-ModInstaller.app. Create the distributable ZIP and SHA-256 checksum with ./package-release.sh.
38 automated tests passed for version 1.0.1. Historical validation notes:
DEVELOPMENT-NOTES.txt.
