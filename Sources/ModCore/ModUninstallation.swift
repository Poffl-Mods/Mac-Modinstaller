import Foundation

extension ModIO {
    /// Removes the mod directory (including its settings) and its loader configuration.
    /// Settings stored at arbitrary external paths cannot safely be attributed to a mod.
    public static func uninstall(_ mod: Mod, root: URL, removeBackups: Bool = false) throws -> URL? {
        guard isGameData(root), let current = try installed(root: root).first(where: { $0.id == mod.id }),
              current.folder.standardizedFileURL == mod.folder.standardizedFileURL else {
            throw ModError("Die Mod-Installation hat sich geändert. Bitte Liste aktualisieren.")
        }
        try safe(current.folder, in: root)
        let config = configURL(current.kind, root: root)
        try safe(config, in: root)
        let originalConfig = fm.fileExists(atPath: config.path) ? try Data(contentsOf: config) : nil
        let data: Data
        if current.kind == .umm {
            let doc = try xml(fm.fileExists(atPath: config.path) ? Data(contentsOf: config) : nil)
            for parent in doc.rootElement()?.elements(forName: "ModParams") ?? [] {
                for node in parent.elements(forName: "Mod") where node.attribute(forName: "Id")?.stringValue == current.key {
                    node.detach()
                }
            }
            data = doc.xmlData(options: .nodePrettyPrint)
        } else {
            var object: [String: Any] = originalConfig == nil ? [:] : try json(config)
            for key in ["EnabledModifications", "DisabledModifications"] {
                if let value = object[key] {
                    guard let ids = value as? [String] else { throw ModError("Ungültige Liste {0} in der Spielkonfiguration.", key) }
                    object[key] = ids.filter { $0 != current.key }
                }
            }
            data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        }
        // Resolve and validate all backup paths before changing anything. Only backups
        // whose restore record names this exact mod directory belong to this operation.
        let backupRoot = root.appendingPathComponent("RogueModInstaller Backups")
        try safe(backupRoot, in: root)
        var backups: [URL] = []
        if removeBackups, fm.fileExists(atPath: backupRoot.path) {
            for folder in try fm.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: [.isDirectoryKey]) {
                try safe(folder, in: root)
                guard try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
                let record = folder.appendingPathComponent("Restore.json")
                try safe(record, in: root)
                guard fm.fileExists(atPath: record.path) else { continue }
                if let path = try json(record)["modFolder"] as? String,
                   URL(fileURLWithPath: path).standardizedFileURL == current.folder.standardizedFileURL {
                    backups.append(folder)
                }
            }
        }
        let backup = try transaction(root: root, target: current.folder, config: config, data: data, payload: nil, removeTarget: true, beforeCommit: {
            let now = fm.fileExists(atPath: config.path) ? try Data(contentsOf: config) : nil
            guard now == originalConfig else {
                throw ModError("Die Konfiguration wurde zwischenzeitlich geändert. Bitte erneut versuchen.")
            }
        })
        if removeBackups {
            do {
                for folder in backups { try fm.removeItem(at: folder) }
                try fm.removeItem(at: backup)
            } catch {
                throw ModError("Mod deinstalliert; einige Sicherungen konnten nicht gelöscht werden: {0}", error.localizedDescription)
            }
            return nil
        }
        return backup
    }
}
