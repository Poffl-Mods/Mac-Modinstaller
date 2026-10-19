# Mac-ModInstaller 1.0.1

A maintenance release with a cleaner internal code structure. Features, installation behavior and the interface are unchanged from 1.0.0.

## Changes

- Split ModCore into separate files for discovery, ZIP preparation, configuration, installation and backup transactions.
- Expanded compact statements to make the code easier to read and maintain.
- Kept existing method signatures, validation rules and installation/rollback behavior.

## Download and requirements

Download **Mac-ModInstaller-1.0.1-macOS-arm64.zip**, extract it, and move the app to Applications. Requires **Apple Silicon (M1 or newer) and macOS 13 or newer**. Intel Macs are not supported.

The app is locally ad-hoc signed, **not Developer ID signed or notarized by Apple**. If macOS blocks the first launch, follow [Apple's instructions](https://support.apple.com/102445) for allowing this specific app, provided you trust the download. Do not disable Gatekeeper globally.

Mod compatibility checks remain advisory. The installer does not convert AssetBundles or install mod loaders/dependencies. Backups do not include save games. See the included README for usage, recovery instructions and compatibility limits.

## Validation and license

All **38 automated tests passed**, and the release build, application version, code signature and packaged ZIP were checked.

Official releases are free for personal, non-commercial use. Modification, redistribution, rehosting and commercial use require Poffl's written permission; see LICENSE. No third-party mods or game files are included.

[Report an issue](https://github.com/Poffl-Mods/Mac-Modinstaller/issues).
