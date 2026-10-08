import Foundation
import ZIPFoundation

public struct ModError: LocalizedError {
    public let message: String
    public let arguments: [String]
    public init(_ message: String, _ arguments: String...) { self.message = message; self.arguments = arguments }
    public var errorDescription: String? { Localization.text(message, language: .de, arguments: arguments) }
}
public enum ModKind: String, Codable, Sendable { case owlcat = "Owlcat", umm = "UMM"
    public var folder: String { self == .umm ? "UnityModManager" : "Modifications" }
}
public struct Mod: Identifiable, Sendable {
    public var id: String { kind.rawValue + ":" + key }
    public let key: String
    public let name: String
    public let version: String
    public let kind: ModKind
    public let folder: URL
    public var enabled: Bool
    public let requirements: [String]
}
public final class PreparedMod: Sendable {
    public let mod: Mod
    public let hasBundles: Bool
    public let size: UInt64
    private let temp: URL
    init(mod: Mod, hasBundles: Bool, size: UInt64, temp: URL) {
        self.mod = mod; self.hasBundles = hasBundles; self.size = size; self.temp = temp
    }
    deinit { try? FileManager.default.removeItem(at: temp) }
}
public enum ModIO {
    static let fm = FileManager.default
    public static func candidates(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        ["Library/Application Support/Owlcat Games/Warhammer 40000 Rogue Trader",
         "Library/Application Support/com.Owlcat-Games.Warhammer-40000-Rogue-Trader"]
            .map { home.appendingPathComponent($0) }.filter { isGameData($0) }
    }
    public static func isGameData(_ url: URL) -> Bool {
        fm.fileExists(atPath: url.appendingPathComponent("OwlcatModificationManagerSettings.json").path)
        || fm.fileExists(atPath: url.appendingPathComponent("UnityModManager/Params.xml").path)
        || fm.fileExists(atPath: url.appendingPathComponent("Saved Games").path)
    }
    static func json(_ url: URL) throws -> [String: Any] {
        var data = try Data(contentsOf: url)
        if data.starts(with: [0xef, 0xbb, 0xbf]) { data.removeFirst(3) }
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ModError("Ungültiges JSON: {0}", url.lastPathComponent)
        }
        return value
    }
    static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.count < 160 && id != "." && id != ".." && !id.hasPrefix(".")
        && id.rangeOfCharacter(from: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-. ")).inverted) == nil
        && id == id.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func readMod(_ folder: URL) throws -> Mod? {
        let umm = folder.appendingPathComponent("Info.json")
        let owl = folder.appendingPathComponent("OwlcatModificationManifest.json")
        let kind: ModKind
        let metadata: [String: Any]
        // UMM packages often include an Owlcat manifest for Steam Workshop as well.
        if fm.fileExists(atPath: umm.path) { kind = .umm; metadata = try json(umm) }
        else if fm.fileExists(atPath: owl.path) { kind = .owlcat; metadata = try json(owl) }
        else { return nil }
        guard let key = metadata[kind == .umm ? "Id" : "UniqueName"] as? String, validID(key) else {
            throw ModError("Der Mod enthält keine gültige Kennung.")
        }
        if kind == .umm {
            guard let assembly = metadata["AssemblyName"] as? String,
                  !assembly.contains("/"), !assembly.contains("\\"), assembly.lowercased().hasSuffix(".dll"),
                  fm.fileExists(atPath: folder.appendingPathComponent(assembly).path) else {
                throw ModError("Die in Info.json angegebene Mod-DLL fehlt.")
            }
        }
        return Mod(key: key, name: metadata["DisplayName"] as? String ?? key,
                   version: metadata["Version"] as? String ?? "?", kind: kind, folder: folder, enabled: false,
                   requirements: metadata[kind == .umm ? "Requirements" : "Dependencies"] as? [String] ?? [])
    }
    public static func prepare(_ zip: URL) throws -> PreparedMod {
        guard zip.pathExtension.lowercased() == "zip" else { throw ModError("Bitte eine ZIP-Datei auswählen.") }
        let archive = try Archive(url: zip, accessMode: .read)
        let temp = fm.temporaryDirectory.appendingPathComponent("RogueMods-" + UUID().uuidString)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        do {
            var total: UInt64 = 0; var seen = Set<String>(); var entries = 0
            for entry in archive {
                // Owlcat's ZIP writer includes a harmless root-directory entry.
                if entry.type == .directory && ["/", "./", ""].contains(entry.path) { continue }
                entries += 1
                guard entries <= 100_000 else { throw ModError("Das ZIP enthält zu viele Dateien.") }
                let parts = entry.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
                guard !entry.path.hasPrefix("/"), !entry.path.contains("\\"), !entry.path.contains("\0"),
                      !parts.contains(".."), !parts.isEmpty, entry.type != .symlink else {
                    throw ModError("Das ZIP enthält einen unsicheren Pfad oder eine Verknüpfung.")
                }
                let normalized = parts.filter { $0 != "." }.joined(separator: "/")
                guard !normalized.isEmpty else { continue }
                guard seen.insert(normalized.precomposedStringWithCanonicalMapping.lowercased()).inserted else {
                    throw ModError("Doppelte Dateinamen im ZIP: {0}", normalized)
                }
                total += entry.uncompressedSize
                guard total <= 4 * 1024 * 1024 * 1024 else { throw ModError("Das entpackte ZIP überschreitet 4 GB.") }
                if parts.first == "__MACOSX" { continue }
                let destination = temp.appendingPathComponent(normalized)
                if entry.type == .directory {
                    try fm.createDirectory(at: destination, withIntermediateDirectories: true)
                } else {
                    try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    guard fm.createFile(atPath: destination.path, contents: nil) else { throw ModError("ZIP-Datei konnte nicht angelegt werden.") }
                    let handle = try FileHandle(forWritingTo: destination)
                    defer { try? handle.close() }
                    var written: UInt64 = 0
                    let crc = try archive.extract(entry) { chunk in
                        written += UInt64(chunk.count)
                        guard written <= entry.uncompressedSize else { throw ModError("Ungültige Größenangabe im ZIP.") }
                        try handle.write(contentsOf: chunk)
                    }
                    guard written == entry.uncompressedSize, crc == entry.checksum else { throw ModError("Das ZIP ist beschädigt (Prüfsumme oder Größe).") }
                }
            }
            let enumerator = fm.enumerator(at: temp, includingPropertiesForKeys: [.isDirectoryKey])!
            var roots = Set<URL>()
            for case let url as URL in enumerator {
                if ["Info.json", "OwlcatModificationManifest.json"].contains(url.lastPathComponent) {
                    roots.insert(url.deletingLastPathComponent())
                }
            }
            guard roots.count == 1, let root = roots.first, let mod = try readMod(root) else {
                throw ModError("Bitte genau einen Mod pro ZIP hinzufügen. Info.json oder OwlcatModificationManifest.json fehlt bzw. ist mehrdeutig.")
            }
            // Don't silently drop a second payload outside a wrapper folder.
            for case let url as URL in fm.enumerator(at: temp, includingPropertiesForKeys: [.isRegularFileKey])! {
                if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
                   !url.path.hasPrefix(root.path + "/"), url.lastPathComponent != ".DS_Store" {
                    throw ModError("Zusätzliche Dateien außerhalb des Mod-Ordners. Bitte ein einzelnes Mod-Paket verwenden.")
                }
            }
            let bundles = fm.fileExists(atPath: root.appendingPathComponent("Bundles").path)
            return PreparedMod(mod: mod, hasBundles: bundles, size: total, temp: temp)
        } catch { try? fm.removeItem(at: temp); throw error }
    }
    static func safe(_ url: URL, in root: URL) throws {
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard path.hasPrefix(resolvedRoot + "/") else { throw ModError("Der Zielpfad verlässt den Spielordner.") }
        // Also refuse symlinks within the game directory (config files and mod folders).
        var cursor = url.standardizedFileURL
        while cursor.path != root.standardizedFileURL.path && cursor.path != "/" {
            if (try? cursor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw ModError("Verknüpfungen im Installationspfad werden nicht überschrieben.")
            }
            cursor.deleteLastPathComponent()
        }
    }
    static func configURL(_ kind: ModKind, root: URL) -> URL {
        root.appendingPathComponent(kind == .umm ? "UnityModManager/Params.xml" : "OwlcatModificationManagerSettings.json")
    }
    static func xml(_ data: Data?) throws -> XMLDocument {
        if let data, String(decoding: data, as: UTF8.self).uppercased().contains("<!DOCTYPE") { throw ModError("DTD-Deklarationen sind in der UMM-Konfiguration nicht zulässig.") }
        let document = try XMLDocument(data: data ?? Data("<?xml version=\"1.0\"?><Param><ModParams/></Param>".utf8), options: [.nodePreserveAll, .nodeLoadExternalEntitiesNever])
        guard document.dtd == nil, document.rootElement()?.name == "Param" else { throw ModError("Ungültige UMM-Konfiguration.") }
        return document
    }
    static func configData(root: URL, kind: ModKind, key: String, enabled: Bool) throws -> Data {
        let url = configURL(kind, root: root)
        try safe(url, in: root)
        let old = fm.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        if kind == .umm {
            let doc = try xml(old); let root = doc.rootElement()!
            let parents = root.elements(forName: "ModParams")
            guard parents.count <= 1 else { throw ModError("Doppelte UMM-ModParams-Einträge.") }
            let parent = parents.first ?? XMLElement(name: "ModParams")
            if parents.isEmpty { root.addChild(parent) }
            let matches = parent.elements(forName: "Mod").filter { $0.attribute(forName: "Id")?.stringValue == key }
            guard matches.count <= 1 else { throw ModError("Doppelte Mod-Kennung in Params.xml.") }
            let node = matches.first ?? XMLElement(name: "Mod")
            if matches.isEmpty { node.addAttribute(XMLNode.attribute(withName: "Id", stringValue: key) as! XMLNode); parent.addChild(node) }
            node.removeAttribute(forName: "Enabled")
            node.addAttribute(XMLNode.attribute(withName: "Enabled", stringValue: enabled ? "true" : "false") as! XMLNode)
            return doc.xmlData(options: .nodePrettyPrint)
        }
        var obj: [String: Any] = old == nil ? ["SourceDirectories": [], "EnabledModifications": []] : try json(url)
        for name in ["EnabledModifications", "DisabledModifications"] {
            if obj[name] != nil && !(obj[name] is [String]) { throw ModError("Ungültige Liste {0} in der Spielkonfiguration.", name) }
        }
        var enabledIDs = obj["EnabledModifications"] as? [String] ?? []
        if enabled { if !enabledIDs.contains(key) { enabledIDs.append(key) } }
        else { enabledIDs.removeAll { $0 == key } }
        obj["EnabledModifications"] = enabledIDs
        if var disabled = obj["DisabledModifications"] as? [String] {
            disabled.removeAll { $0 == key }; if !enabled { disabled.append(key) }; obj["DisabledModifications"] = disabled
        }
        return try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
    }
    public static func installed(root: URL) throws -> [Mod] {
        var result: [Mod] = []
        for kind in [ModKind.owlcat, .umm] {
            let folder = root.appendingPathComponent(kind.folder); try safe(folder, in: root)
            guard fm.fileExists(atPath: folder.path) else { continue }
            let config = configURL(kind, root: root); try safe(config, in: root)
            var enabledIDs = Set<String>(); var ummDisabled = Set<String>()
            if fm.fileExists(atPath: config.path) {
                if kind == .owlcat { enabledIDs = Set(try json(config)["EnabledModifications"] as? [String] ?? []) }
                else {
                    let doc = try xml(Data(contentsOf: config))
                    for node in doc.rootElement()?.elements(forName: "ModParams").first?.elements(forName: "Mod") ?? [] {
                        if let key = node.attribute(forName: "Id")?.stringValue,
                           node.attribute(forName: "Enabled")?.stringValue?.lowercased() == "false" { ummDisabled.insert(key) }
                    }
                }
            }
            for item in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) {
                guard try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
                try safe(item, in: root)
                if var mod = try readMod(item) {
                    guard mod.kind == kind else { throw ModError("{0} liegt im falschen Mod-Ordner. Bitte die vorhandene Installation prüfen.", mod.name) }
                    mod.enabled = kind == .umm ? !ummDisabled.contains(mod.key) : enabledIDs.contains(mod.key)
                    result.append(mod)
                }
            }
        }
        guard Set(result.map(\.id)).count == result.count else { throw ModError("Eine Mod-Kennung ist mehrfach installiert.") }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    public static func install(_ package: PreparedMod, root: URL) throws -> URL {
        guard isGameData(root) else { throw ModError("Bitte den Rogue-Trader-Benutzerdatenordner auswählen.") }
        let mods = try installed(root: root)
        if package.mod.kind == .umm {
            guard fm.fileExists(atPath: root.appendingPathComponent("UnityModManager/UnityModManager.dll").path) else {
                throw ModError("UMM wurde hier noch nicht gefunden. Rogue Trader zuerst einmal starten. Dieser Installer ersetzt keinen Mod-Loader.")
            }
        }
        let existing = mods.first { $0.id == package.mod.id }
        let target = existing?.folder ?? root.appendingPathComponent(package.mod.kind.folder).appendingPathComponent(package.mod.key)
        if existing == nil && fm.fileExists(atPath: target.path) { throw ModError("Der Zielordner existiert, gehört aber nicht eindeutig zu diesem Mod.") }
        let config = configURL(package.mod.kind, root: root)
        let data = try configData(root: root, kind: package.mod.kind, key: package.mod.key, enabled: true)
        return try transaction(root: root, target: target, config: config, data: data, payload: package.mod.folder)
    }
    public static func setEnabled(_ mod: Mod, root: URL, enabled: Bool) throws -> URL {
        let data = try configData(root: root, kind: mod.kind, key: mod.key, enabled: enabled)
        return try transaction(root: root, target: nil, config: configURL(mod.kind, root: root), data: data, payload: nil)
    }
    static func transaction(root: URL, target: URL?, config: URL, data: Data, payload: URL?, beforeCommit: (() throws -> Void)? = nil) throws -> URL {
        try safe(config, in: root); if let target { try safe(target, in: root) }
        let backupRoot = root.appendingPathComponent("RogueModInstaller Backups"); try safe(backupRoot, in: root)
        let backup = backupRoot.appendingPathComponent(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-") + "-" + UUID().uuidString.prefix(8))
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)
        let originalConfig = fm.fileExists(atPath: config.path) ? try Data(contentsOf: config) : nil
        if let originalConfig { try originalConfig.write(to: backup.appendingPathComponent(config.lastPathComponent)) }
        let previous = backup.appendingPathComponent("PreviousMod")
        let stage = backup.appendingPathComponent("StagedMod")
        let record: [String: Any] = ["configuration": config.path, "modFolder": target?.path ?? "", "hadConfiguration": originalConfig != nil]
        try JSONSerialization.data(withJSONObject: record, options: .prettyPrinted).write(to: backup.appendingPathComponent("Restore.json"))
        var movedOld = false; var installedNew = false
        do {
            if let payload, let target {
                try fm.copyItem(at: payload, to: stage)
                let receiptName = ".rogue-mod-files.json"
                let owned: Set<String>
                if let receipt = try? Data(contentsOf: target.appendingPathComponent(receiptName)),
                   let paths = try? JSONDecoder().decode([String].self, from: receipt) { owned = Set(paths) }
                else { owned = [] }
                var payloadFiles: [String] = []
                for case let file as URL in fm.enumerator(at: stage, includingPropertiesForKeys: [.isRegularFileKey])! {
                    if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                        payloadFiles.append(String(file.resolvingSymlinksInPath().path.dropFirst(stage.resolvingSymlinksInPath().path.count + 1)))
                    }
                }
                // Keep user-created files; remove obsolete files owned by the preceding package.
                if fm.fileExists(atPath: target.path) {
                    for case let old as URL in fm.enumerator(at: target, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey])! {
                        if try old.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw ModError("Verknüpfung im vorhandenen Mod-Ordner.") }
                        let relative = String(old.resolvingSymlinksInPath().path.dropFirst(target.resolvingSymlinksInPath().path.count + 1))
                        let to = stage.appendingPathComponent(relative)
                        if !fm.fileExists(atPath: to.path) && !owned.contains(relative) && relative != receiptName {
                            if try old.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true { try fm.createDirectory(at: to, withIntermediateDirectories: true) }
                            else { try fm.copyItem(at: old, to: to) }
                        }
                    }
                    try fm.moveItem(at: target, to: previous); movedOld = true
                }
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(payloadFiles).write(to: stage.appendingPathComponent(receiptName), options: .atomic)
                try fm.moveItem(at: stage, to: target); installedNew = true
            }
            try fm.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Don't overwrite changes made by another program during staging.
            let now = fm.fileExists(atPath: config.path) ? try Data(contentsOf: config) : nil
            guard now == originalConfig else { throw ModError("Die Konfiguration wurde zwischenzeitlich geändert. Bitte erneut versuchen.") }
            try beforeCommit?()
            try data.write(to: config, options: .atomic)
            return backup
        } catch {
            do {
                if let target, installedNew { try fm.removeItem(at: target) }
                if let target, movedOld { try fm.moveItem(at: previous, to: target) }
            } catch {
                throw ModError("Wiederherstellung erforderlich. Die Sicherung liegt unter {0}. Ursache: {1}", backup.path, error.localizedDescription)
            }
            throw error
        }
    }
}
