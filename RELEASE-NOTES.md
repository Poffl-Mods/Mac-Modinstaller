# Mac-ModInstaller 1.1.0

Remove installed mods directly from the app, with optional cleanup of their installer backups. This release also adds a separate Harmony maintenance action for Rogue Trader on Mac.

## Changes

- Added an **Uninstall …** button with confirmation for each installed mod.
- Removes the entire mod folder, including settings stored inside it, and the mod's loader configuration entry. External settings and saved games are retained.
- Keeps a recovery backup by default. Optionally deletes backups whose restore records identify the same mod folder, including the new recovery backup. Older activation-only backups without a mod association and other mods' backups are retained.
- Shows enabled dependent mods before uninstalling and requires the game to be closed. Failed configuration commits restore the mod folder.
- Added optional **Harmony for Mac** inspection, verified download of official Harmony 2.4.2.0, backup and guarded restore. Newer readable versions are not downgraded; no third-party binaries are bundled.
- Added uninstall translations in all six interface languages and pauses inventory refresh while the uninstall confirmation is open.

## Download and requirements

Download **Mac-ModInstaller-1.1.0-macOS-arm64.zip**, extract it, and move the app to Applications. Requires **Apple Silicon (M1 or newer) and macOS 13 or newer**. Intel Macs are not supported.

The app is locally ad-hoc signed, **not Developer ID signed or notarized by Apple**. If macOS blocks the first launch, follow [Apple's instructions](https://support.apple.com/102445) for allowing this specific app, provided you trust the download. Do not disable Gatekeeper globally.

Mod compatibility checks remain advisory. The installer does not convert AssetBundles or install mod loaders/dependencies. The optional Harmony action changes the game's shared DLL and may invalidate the game's signature; Steam verification or game updates may revert it. Backups do not include save games. See the included README for usage, recovery instructions and compatibility limits.

## Validation and license

All **50 automated tests passed** across the offline release run and the separate official Harmony download check. These checks cover uninstall cleanup, selective backup deletion, preservation of unrelated settings and mods, rollback, path safety, translations and inventory refresh. The optional local Unity-bundle test is excluded: its current local fixture targets Windows (19), whereas the test expects macOS (2). The optional network test was enabled and passed separately. Release packaging is checked for version, arm64 architecture, local code signature, ZIP integrity and matching extracted executable checksum.

Official releases are free for personal, non-commercial use. Modification, redistribution, rehosting and commercial use require Poffl's written permission; see LICENSE. No third-party mods or game files are included.

[Report an issue](https://github.com/Poffl-Mods/Mac-Modinstaller/issues).
