# Mac-ModInstaller 1.0

First public release of a native Apple Silicon mod installer for Warhammer 40,000: Rogue Trader.

Download **Mac-ModInstaller-1.0.0-macOS-arm64.zip**, extract it, and move the app to Applications. Requires an Apple Silicon Mac (M1 or newer) and macOS 13 or newer. No Rosetta, Unity, Python or Xcode is needed to run it.

## Included

- Automatic detection of the game's user-data folder, with manual selection when needed.
- Local Owlcat and UnityModManager ZIP installation and updates, with activation controls and installed-mod search.
- Backups, rollback on installation errors and automatic inventory refresh.
- Dependency/version warnings and checks for native Windows/Linux binaries.
- AssetBundle target-platform inspection, including specific Windows/Linux warnings. Unreadable or unsupported formats remain unverified.
- Six interface languages and an Adeptus Mechanicus-inspired cogitator interface.
- Packaged language resources that work outside the development folder.

## Before installing

Close Rogue Trader before changing mods. Installation and configured activation do not guarantee successful loading in the game. The app does not install the mod loader, change Harmony, download dependencies or convert AssetBundles. Backups do not include save games.

This build is locally ad-hoc signed; it is **not Developer ID signed or notarized by Apple**. macOS may block the first launch. If you trust the download, follow [Apple's instructions for opening a specific unverified app](https://support.apple.com/102445). Do not disable Gatekeeper globally. Managed Macs may prohibit exceptions.

Bundle inspection supports UnityFS 6–8 with uncompressed/LZ4/LZ4HC blocks and SerializedFile 9–22. LZMA, legacy/encrypted/unknown formats and files exceeding inspection limits remain unverified. A macOS target is not a guarantee of game compatibility. Intel Macs are not supported by this build.

## Validation

All **38 automated tests passed**, covering installation/update behavior, rollback, configuration preservation, localization, inventory refresh and bundle-platform inspection. The local Unity-built Armoury: Orks bundle was recognized as macOS. In-game compatibility for arbitrary third-party mods has not been certified.

## License

Official application releases are free for personal, non-commercial use. Modification, redistribution, rehosting and commercial use require Poffl's written permission. The source code is not open source; see LICENSE. No game files, third-party mods, Unity SDK files or mod-loader binaries are bundled.

Report problems through [GitHub Issues](https://github.com/Poffl-Mods/Mac-Modinstaller/issues).
