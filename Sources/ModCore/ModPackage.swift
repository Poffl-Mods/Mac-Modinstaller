import Foundation
import ZIPFoundation

// Validate and extract a single mod ZIP, retaining temporary files for its preview.
extension ModIO {
    public static func prepare(_ zip: URL) throws -> PreparedMod {
        guard zip.pathExtension.lowercased() == "zip" else {
            throw ModError("Bitte eine ZIP-Datei auswählen.")
        }
        let archive = try Archive(url: zip, accessMode: .read)
        let temp = fm.temporaryDirectory.appendingPathComponent("RogueMods-" + UUID().uuidString)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        do {
            var total: UInt64 = 0
            var seen = Set<String>()
            var entries = 0
            for entry in archive {
                // Owlcat's ZIP writer includes a harmless root-directory entry.
                if entry.type == .directory && ["/", "./", ""].contains(entry.path) { continue }
                entries += 1
                guard entries <= 100_000 else { throw ModError("Das ZIP enthält zu viele Dateien.") }
                let parts = entry.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
                guard !entry.path.hasPrefix("/"), !entry.path.contains("\\"), !entry.path.contains("\0"),
                    !parts.contains(".."), !parts.isEmpty, entry.type != .symlink
                else {
                    throw ModError("Das ZIP enthält einen unsicheren Pfad oder eine Verknüpfung.")
                }
                let normalized = parts.filter { $0 != "." }.joined(separator: "/")
                guard !normalized.isEmpty else { continue }
                guard seen.insert(normalized.precomposedStringWithCanonicalMapping.lowercased()).inserted
                else {
                    throw ModError("Doppelte Dateinamen im ZIP: {0}", normalized)
                }
                total += entry.uncompressedSize
                guard total <= 4 * 1024 * 1024 * 1024 else {
                    throw ModError("Das entpackte ZIP überschreitet 4 GB.")
                }
                if parts.first == "__MACOSX" { continue }
                let destination = temp.appendingPathComponent(normalized)
                if entry.type == .directory {
                    try fm.createDirectory(at: destination, withIntermediateDirectories: true)
                } else {
                    try fm.createDirectory(
                        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    guard fm.createFile(atPath: destination.path, contents: nil) else {
                        throw ModError("ZIP-Datei konnte nicht angelegt werden.")
                    }
                    let handle = try FileHandle(forWritingTo: destination)
                    defer { try? handle.close() }
                    var written: UInt64 = 0
                    let crc = try archive.extract(entry) { chunk in
                        written += UInt64(chunk.count)
                        guard written <= entry.uncompressedSize else {
                            throw ModError("Ungültige Größenangabe im ZIP.")
                        }
                        try handle.write(contentsOf: chunk)
                    }
                    guard written == entry.uncompressedSize, crc == entry.checksum else {
                        throw ModError("Das ZIP ist beschädigt (Prüfsumme oder Größe).")
                    }
                }
            }
            let enumerator = fm.enumerator(at: temp, includingPropertiesForKeys: [.isDirectoryKey])!
            var roots = Set<URL>()
            for case let url as URL in enumerator {
                if ["info.json", "owlcatmodificationmanifest.json"].contains(
                    url.lastPathComponent.lowercased())
                {
                    roots.insert(url.deletingLastPathComponent())
                }
            }
            guard roots.count == 1, let root = roots.first, let mod = try readMod(root) else {
                throw ModError(
                    "Bitte genau einen Mod pro ZIP hinzufügen. Info.json oder OwlcatModificationManifest.json fehlt bzw. ist mehrdeutig."
                )
            }
            // Don't silently drop a second payload outside a wrapper folder.
            for case let url as URL in fm.enumerator(
                at: temp, includingPropertiesForKeys: [.isRegularFileKey])!
            {
                if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
                    !url.path.hasPrefix(root.path + "/"), url.lastPathComponent != ".DS_Store"
                {
                    throw ModError(
                        "Zusätzliche Dateien außerhalb des Mod-Ordners. Bitte ein einzelnes Mod-Paket verwenden."
                    )
                }
            }
            let bundles = !mod.bundlePlatforms.isEmpty
            return PreparedMod(mod: mod, hasBundles: bundles, size: total, temp: temp)
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }
}
