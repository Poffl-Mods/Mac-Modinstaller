import CryptoKit
import Foundation
import ZIPFoundation

public struct HarmonyInspection: Identifiable, Sendable {
    public let game: URL
    public let fingerprint: String
    public let fileVersion: String?
    public var id: String { game.path }
    public var isInstalled: Bool { fingerprint == HarmonyMaintenance.dllHash }
    public var isNewer: Bool {
        guard let fileVersion, let current = CheckedVersion(fileVersion),
            let offered = CheckedVersion(HarmonyMaintenance.version)
        else { return false }
        return current > offered
    }
}

/// An explicit maintenance operation on the shared game runtime, never mod payloads.
public enum HarmonyMaintenance {
    public static let version = "2.4.2.0"
    public static let downloadURL = URL(
        string: "https://github.com/pardeike/Harmony/releases/download/v2.4.2.0/Harmony-Fat.2.4.2.0.zip")!
    static let archiveHash = "a5fc5f9d9640b927d786a0527faa18bf7aa776788235140c59e9b73de87a7774"
    static let dllHash = "7b9e756306fa3d7620e02a857c8927a6ab04973f9bd8a77d3866700a6deac55c"
    static let relativeTarget = "Contents/Resources/Data/Managed/0Harmony.dll"
    static let fm = FileManager.default

    struct Backup: Codable {
        let target: String
        let originalHash: String
        let installedHash: String
    }
    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func read(_ url: URL, limit: Int = 16 * 1024 * 1024) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard try handle.seekToEnd() <= UInt64(limit) else {
            throw ModError("Harmony-Datei oder Download ungültig.")
        }
        try handle.seek(toOffset: 0)
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw ModError("Harmony-Datei oder Download ungültig.") }
        return data
    }
    static func target(_ game: URL) throws -> URL {
        let target = game.appendingPathComponent(relativeTarget)
        try ModIO.safe(target, in: game)
        let plist = try read(game.appendingPathComponent("Contents/Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        guard game.pathExtension == "app",
            info?["CFBundleIdentifier"] as? String == "com.Owlcat-Games.Warhammer-40000-Rogue-Trader",
            fm.fileExists(atPath: target.path)
        else {
            throw ModError("Keine gültige Rogue-Trader-App mit Harmony gefunden.")
        }
        return target
    }
    public static func inspect(game: URL) throws -> HarmonyInspection {
        let bytes = try read(target(game))
        guard ModChecks.peKind(bytes) == .managed else {
            throw ModError("Harmony-Datei oder Download ungültig.")
        }
        return HarmonyInspection(game: game, fingerprint: hash(bytes), fileVersion: PEFileVersion.read(bytes))
    }
    public static func download() async throws -> URL {
        let (temp, response) = try await URLSession.shared.download(from: downloadURL)
        defer { try? fm.removeItem(at: temp) }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
            hash(try read(temp, limit: 32 * 1024 * 1024)) == archiveHash
        else {
            throw ModError("Harmony-Datei oder Download ungültig.")
        }
        let owned = fm.temporaryDirectory.appendingPathComponent("Harmony-" + UUID().uuidString + ".zip")
        try fm.moveItem(at: temp, to: owned)
        return owned
    }
    static func payload(_ zip: URL) throws -> Data {
        guard hash(try read(zip, limit: 32 * 1024 * 1024)) == archiveHash else {
            throw ModError("Harmony-Datei oder Download ungültig.")
        }
        let archive = try Archive(url: zip, accessMode: .read)
        guard let entry = archive["net472/0Harmony.dll"], entry.type == .file,
            entry.uncompressedSize <= 16 * 1024 * 1024
        else {
            throw ModError("Harmony-Datei oder Download ungültig.")
        }
        var data = Data()
        let crc = try archive.extract(entry) { chunk in
            guard data.count + chunk.count <= 16 * 1024 * 1024 else {
                throw ModError("Harmony-Datei oder Download ungültig.")
            }
            data.append(chunk)
        }
        guard crc == entry.checksum, hash(data) == dllHash else {
            throw ModError("Harmony-Datei oder Download ungültig.")
        }
        return data
    }
    public static func install(_ zip: URL, inspected: HarmonyInspection, root: URL) throws -> URL {
        let data = try payload(zip)
        return try replace(data, inspected: inspected, root: root)
    }
    // Separated from package verification for deterministic transaction fault tests.
    static func replace(
        _ data: Data, inspected: HarmonyInspection, root: URL,
        beforeWrite: (() throws -> Void)? = nil, expectedHash: String = dllHash
    ) throws -> URL {
        guard ModIO.isGameData(root) else {
            throw ModError("Bitte den Rogue-Trader-Benutzerdatenordner auswählen.")
        }
        guard hash(data) == expectedHash else { throw ModError("Harmony-Datei oder Download ungültig.") }
        let current = try inspect(game: inspected.game)
        guard current.fingerprint == inspected.fingerprint, !current.isInstalled else {
            throw ModError("Die Harmony-Datei wurde inzwischen verändert. Bitte erneut prüfen.")
        }
        guard !current.isNewer else {
            throw ModError("Eine neuere Harmony-Version ist vorhanden. Kein Downgrade durchgeführt.")
        }
        let destination = try target(inspected.game)
        let original = try read(destination)
        guard hash(original) == current.fingerprint else {
            throw ModError("Die Harmony-Datei wurde inzwischen verändert. Bitte erneut prüfen.")
        }
        let backup = root.appendingPathComponent("RogueModInstaller Backups/Harmony-" + UUID().uuidString)
        try ModIO.safe(backup, in: root)
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)
        try original.write(to: backup.appendingPathComponent("0Harmony.dll"), options: .atomic)
        let record = Backup(
            target: destination.standardizedFileURL.path, originalHash: hash(original),
            installedHash: expectedHash)
        try JSONEncoder().encode(record).write(
            to: backup.appendingPathComponent("HarmonyRestore.json"), options: .atomic)
        try beforeWrite?()
        let finalTarget = try target(inspected.game)
        guard hash(try read(finalTarget)) == inspected.fingerprint else {
            throw ModError("Die Harmony-Datei wurde inzwischen verändert. Bitte erneut prüfen.")
        }
        // Atomic replacement either succeeds completely or retains the original DLL.
        try data.write(to: finalTarget, options: .atomic)
        return backup
    }
    public static func restore(_ backup: URL, inspected: HarmonyInspection, root: URL) throws {
        try restoreBackup(backup, inspected: inspected, root: root)
    }
    static func restoreBackup(
        _ backup: URL, inspected: HarmonyInspection, root: URL, expectedHash: String = dllHash
    ) throws {
        guard ModIO.isGameData(root) else {
            throw ModError("Bitte den Rogue-Trader-Benutzerdatenordner auswählen.")
        }
        try ModIO.safe(backup, in: root)
        let recordURL = backup.appendingPathComponent("HarmonyRestore.json")
        let originalURL = backup.appendingPathComponent("0Harmony.dll")
        try ModIO.safe(recordURL, in: root)
        try ModIO.safe(originalURL, in: root)
        let record = try JSONDecoder().decode(Backup.self, from: read(recordURL))
        let destination = try target(inspected.game)
        let original = try read(originalURL)
        guard record.target == destination.standardizedFileURL.path,
            record.installedHash == expectedHash, hash(original) == record.originalHash,
            ModChecks.peKind(original) == .managed
        else { throw ModError("Harmony-Sicherung ungültig oder nicht passend zur Spiel-App.") }
        let current = try read(destination)
        guard hash(current) == inspected.fingerprint, hash(current) == record.installedHash else {
            throw ModError("Die Harmony-Datei wurde inzwischen verändert. Bitte erneut prüfen.")
        }
        try original.write(to: destination, options: .atomic)
    }
}
