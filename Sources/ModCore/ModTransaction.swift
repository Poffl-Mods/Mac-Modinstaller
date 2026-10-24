import Foundation

// Protect destination paths and commit changes with backups and rollback.
extension ModIO {
    static func safe(_ url: URL, in root: URL) throws {
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard path.hasPrefix(resolvedRoot + "/") else {
            throw ModError("Der Zielpfad verlässt den Spielordner.")
        }
        // Also refuse symlinks within the game directory (config files and mod folders).
        var cursor = url.standardizedFileURL
        while cursor.path != root.standardizedFileURL.path && cursor.path != "/" {
            if (try? cursor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw ModError("Verknüpfungen im Installationspfad werden nicht überschrieben.")
            }
            cursor.deleteLastPathComponent()
        }
    }

    static func transaction(
        root: URL, target: URL?, config: URL, data: Data, payload: URL?,
        removeTarget: Bool = false, beforeCommit: (() throws -> Void)? = nil
    ) throws -> URL {
        try safe(config, in: root)
        if let target { try safe(target, in: root) }
        let backupRoot = root.appendingPathComponent("RogueModInstaller Backups")
        try safe(backupRoot, in: root)
        let backup = backupRoot.appendingPathComponent(
            ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-") + "-"
                + UUID().uuidString.prefix(8))
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)
        let originalConfig = fm.fileExists(atPath: config.path) ? try Data(contentsOf: config) : nil
        if let originalConfig {
            try originalConfig.write(to: backup.appendingPathComponent(config.lastPathComponent))
        }
        let previous = backup.appendingPathComponent("PreviousMod")
        let stage = backup.appendingPathComponent("StagedMod")
        let record: [String: Any] = [
            "configuration": config.path, "modFolder": target?.path ?? "",
            "hadConfiguration": originalConfig != nil,
        ]
        try JSONSerialization.data(withJSONObject: record, options: .prettyPrinted).write(
            to: backup.appendingPathComponent("Restore.json"))
        var movedOld = false
        var installedNew = false
        do {
            if let payload, let target {
                try fm.copyItem(at: payload, to: stage)
                let receiptName = ".rogue-mod-files.json"
                let owned: Set<String>
                if let receipt = try? Data(contentsOf: target.appendingPathComponent(receiptName)),
                    let paths = try? JSONDecoder().decode([String].self, from: receipt)
                {
                    owned = Set(paths)
                } else {
                    owned = []
                }
                var payloadFiles: [String] = []
                for case let file as URL in fm.enumerator(
                    at: stage, includingPropertiesForKeys: [.isRegularFileKey])!
                {
                    if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                        payloadFiles.append(
                            String(
                                file.resolvingSymlinksInPath().path.dropFirst(
                                    stage.resolvingSymlinksInPath().path.count + 1)))
                    }
                }
                // Keep user-created files; remove obsolete files owned by the preceding package.
                if fm.fileExists(atPath: target.path) {
                    for case let old as URL in fm.enumerator(
                        at: target, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey])!
                    {
                        if try old.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                            throw ModError("Verknüpfung im vorhandenen Mod-Ordner.")
                        }
                        let relative = String(
                            old.resolvingSymlinksInPath().path.dropFirst(
                                target.resolvingSymlinksInPath().path.count + 1))
                        let to = stage.appendingPathComponent(relative)
                        if !fm.fileExists(atPath: to.path) && !owned.contains(relative)
                            && relative != receiptName
                        {
                            if try old.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                                try fm.createDirectory(at: to, withIntermediateDirectories: true)
                            } else {
                                try fm.copyItem(at: old, to: to)
                            }
                        }
                    }
                    try fm.moveItem(at: target, to: previous)
                    movedOld = true
                }
                try fm.createDirectory(
                    at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(payloadFiles).write(
                    to: stage.appendingPathComponent(receiptName), options: .atomic)
                try fm.moveItem(at: stage, to: target)
                installedNew = true
            }
            if removeTarget, let target {
                try fm.moveItem(at: target, to: previous)
                movedOld = true
            }
            try fm.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Don't overwrite changes made by another program during staging.
            let now = fm.fileExists(atPath: config.path) ? try Data(contentsOf: config) : nil
            guard now == originalConfig else {
                throw ModError("Die Konfiguration wurde zwischenzeitlich geändert. Bitte erneut versuchen.")
            }
            try beforeCommit?()
            try data.write(to: config, options: .atomic)
            return backup
        } catch {
            do {
                if let target, installedNew { try fm.removeItem(at: target) }
                if let target, movedOld { try fm.moveItem(at: previous, to: target) }
            } catch {
                throw ModError(
                    "Wiederherstellung erforderlich. Die Sicherung liegt unter {0}. Ursache: {1}",
                    backup.path, error.localizedDescription)
            }
            throw error
        }
    }
}
