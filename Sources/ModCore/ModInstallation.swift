import Foundation

// Coordinate installation and activation through the shared backup transaction.
extension ModIO {
    public static func install(_ package: PreparedMod, root: URL, acceptedWarnings: Set<String>? = nil) throws
        -> URL
    {
        guard isGameData(root) else {
            throw ModError("Bitte den Rogue-Trader-Benutzerdatenordner auswählen.")
        }
        let mods = try installed(root: root)
        if package.mod.kind == .umm {
            guard
                fm.fileExists(atPath: root.appendingPathComponent("UnityModManager/UnityModManager.dll").path)
            else {
                throw ModError(
                    "UMM wurde hier noch nicht gefunden. Rogue Trader zuerst einmal starten. Dieser Installer ersetzt keinen Mod-Loader."
                )
            }
        }
        let existing = mods.first { $0.id == package.mod.id }
        if let acceptedWarnings {
            let current = ModChecks.warnings(for: package.mod, installed: mods, replacing: existing)
            guard Set(current.map(\.id)).isSubset(of: acceptedWarnings) else {
                throw ModError("Prüfergebnisse haben sich geändert. ZIP erneut öffnen und Hinweise prüfen.")
            }
        }
        let target =
            existing?.folder
            ?? root.appendingPathComponent(package.mod.kind.folder).appendingPathComponent(package.mod.key)
        if existing == nil && fm.fileExists(atPath: target.path) {
            throw ModError("Der Zielordner existiert, gehört aber nicht eindeutig zu diesem Mod.")
        }
        let config = configURL(package.mod.kind, root: root)
        let data = try configData(root: root, kind: package.mod.kind, key: package.mod.key, enabled: true)
        return try transaction(
            root: root, target: target, config: config, data: data, payload: package.mod.folder)
    }

    public static func setEnabled(_ mod: Mod, root: URL, enabled: Bool) throws -> URL {
        let data = try configData(root: root, kind: mod.kind, key: mod.key, enabled: enabled)
        return try transaction(
            root: root, target: mod.folder, config: configURL(mod.kind, root: root), data: data, payload: nil)
    }
}
