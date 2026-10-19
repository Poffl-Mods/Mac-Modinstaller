import Foundation

public struct ModWarning: Sendable, Identifiable {
    public let code: String
    public let message: Message
    public var id: String { code + ":" + message.arguments.joined(separator: "|") }
    init(_ code: String, _ key: String, _ arguments: String...) {
        self.code = code
        self.message = Message(key, arguments: arguments)
    }
}

// Numeric versions, legacy letter patches (1.2.3a), and SemVer prereleases.
// Unknown formats stay unknown; never silently compare them as version zero.
struct CheckedVersion: Comparable {
    let numbers: [UInt64]
    let patch: String
    let prerelease: [String]
    init?(_ raw: String) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[vV]?(\d+(?:\.\d+)*)([a-zA-Z]*)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$"#
        guard let match = value.range(of: pattern, options: .regularExpression), match == value.startIndex..<value.endIndex else { return nil }
        let regex = try! NSRegularExpression(pattern: pattern)
        let result = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value))!
        func group(_ index: Int) -> String {
            let range = result.range(at: index)
            return range.location == NSNotFound ? "" : (value as NSString).substring(with: range)
        }
        let parts = group(1).split(separator: ".").map { UInt64($0) }
        guard parts.allSatisfy({ $0 != nil }) else { return nil }
        var numeric = parts.map { $0! }
        while numeric.count > 1 && numeric.last == 0 { numeric.removeLast() }
        numbers = numeric; patch = group(2).lowercased()
        let pre = group(3)
        guard pre.isEmpty || !pre.split(separator: ".", omittingEmptySubsequences: false).contains(where: { $0.isEmpty }) else { return nil }
        prerelease = pre.isEmpty ? [] : pre.split(separator: ".").map(String.init)
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        for i in 0..<max(lhs.numbers.count, rhs.numbers.count) {
            let a = i < lhs.numbers.count ? lhs.numbers[i] : 0
            let b = i < rhs.numbers.count ? rhs.numbers[i] : 0
            if a != b { return a < b }
        }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        if lhs.prerelease.isEmpty != rhs.prerelease.isEmpty { return !lhs.prerelease.isEmpty }
        for (a, b) in zip(lhs.prerelease, rhs.prerelease) where a != b {
            if let x = UInt64(a), let y = UInt64(b) { return x < y }
            if UInt64(a) != nil && UInt64(b) == nil { return true }
            if UInt64(a) == nil && UInt64(b) != nil { return false }
            return a < b
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}

extension Message {
    public init(_ key: String, arguments: [String]) { self.key = key; self.arguments = arguments }
}

public enum ModChecks {
    public static func warnings(for mod: Mod, installed: [Mod], replacing: Mod? = nil) -> [ModWarning] {
        var result = mod.packageWarnings
        if CheckedVersion(mod.version) == nil {
            result.append(ModWarning("version", "Versionsangabe fehlt oder ist nicht vergleichbar: {0}", mod.version))
        }
        if let old = replacing {
            if let incoming = CheckedVersion(mod.version), let current = CheckedVersion(old.version) {
                if incoming < current { result.append(ModWarning("downgrade", "Downgrade: {0} ersetzt die neuere Version {1}.", mod.version, old.version)) }
            } else {
                result.append(ModWarning("comparison", "Versionsvergleich mit der installierten Version {0} nicht möglich.", old.version))
            }
        }
        for raw in mod.requirements {
            let requirement = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // An exact ID wins over a suffix that happens to resemble a version.
            let exact = installed.filter { $0.key == requirement && (mod.kind == .owlcat || $0.kind == .umm) }
            var key = requirement; var minimum: String?
            if exact.isEmpty {
                let prefixes = installed.filter { requirement.hasPrefix($0.key + "-") && (mod.kind == .owlcat || $0.kind == .umm) }.sorted { $0.key.count > $1.key.count }
                if let dependency = prefixes.first {
                    key = dependency.key; minimum = String(requirement.dropFirst(key.count + 1))
                } else if let range = requirement.range(of: #"-(?=[vV]?\d)"#, options: .regularExpression) {
                    key = String(requirement[..<range.lowerBound])
                    minimum = String(requirement[range.upperBound...])
                }
            }
            guard ModIO.validID(key) else {
                result.append(ModWarning("requirement-format", "Abhängigkeit nicht lesbar: {0}", raw)); continue
            }
            let matches = installed.filter { $0.key == key && (mod.kind == .owlcat || $0.kind == .umm) }
            if matches.count > 1 {
                result.append(ModWarning("ambiguous", "Abhängigkeit mehrfach vorhanden: {0}", key)); continue
            }
            if let minimum, CheckedVersion(minimum) == nil {
                result.append(ModWarning("requirement-version", "Mindestversion der Abhängigkeit nicht lesbar: {0}", raw))
            }
            guard let dependency = matches.first else {
                result.append(ModWarning("missing", "Abhängigkeit fehlt: {0}", raw)); continue
            }
            if !dependency.enabled { result.append(ModWarning("disabled", "Abhängigkeit ist deaktiviert: {0}", key)) }
            if let minimum, let required = CheckedVersion(minimum) {
                if let actual = CheckedVersion(dependency.version) {
                    if actual < required { result.append(ModWarning("outdated", "Abhängigkeit {0}: benötigt {1}, installiert {2}.", key, minimum, dependency.version)) }
                } else {
                    result.append(ModWarning("dependency-unknown", "Version der Abhängigkeit {0} nicht prüfbar: {1}", key, dependency.version))
                }
            }
        }
        // ModFinder uses a universal MicroPatches requirement. Here it is advisory,
        // limited to Owlcat content packages, and never presented as proof of failure.
        if mod.kind == .owlcat && mod.hasOwlcatContent && !mod.requirements.contains(where: { $0 == "MicroPatches" || $0.hasPrefix("MicroPatches-") }) {
            let micro = installed.first { $0.kind == .umm && $0.key == "MicroPatches" }
            if micro == nil || micro?.enabled == false {
                result.append(ModWarning("micropatches", "Owlcat-Inhalte erkannt. Prüfe, ob dieser Mod eine aktive, Mac-kompatible MicroPatches-Version benötigt."))
            }
        }
        // Deduplicate warnings without changing their display order.
        var seen = Set<String>()
        return result.filter { seen.insert($0.id).inserted }
    }

    static func inspect(_ folder: URL) throws -> (warnings: [ModWarning], bundles: Bool, content: Bool, platforms: [BundlePlatform]) {
        var warnings: [ModWarning] = []; var bundles = false; var content = false
        var platforms: [BundlePlatform] = []
        for case let file as URL in FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])! {
            let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard info.isSymbolicLink != true, info.isRegularFile == true else { continue }
            let relative = String(file.path.dropFirst(folder.path.count + 1))
            let components = relative.lowercased().split(separator: "/")
            let handle = try FileHandle(forReadingFrom: file)
            let header: Data
            do {
                let prefix = try handle.read(upToCount: 8) ?? Data()
                if prefix.starts(with: [0x4d, 0x5a]) {
                    try handle.seek(toOffset: 0)
                    header = try handle.read(upToCount: 65_536) ?? Data()
                } else { header = prefix }
                try handle.close()
            }
            catch { try? handle.close(); throw error }
            let unity = header.starts(with: Data("UnityFS\0".utf8)) || header.starts(with: Data("UnityRaw\0".utf8)) || header.starts(with: Data("UnityWeb\0".utf8))
            let bundleFile = components.first == "bundles" && !["manifest", "txt", "json", "meta"].contains(file.pathExtension.lowercased())
            if unity || bundleFile {
                bundles = true
                let platform = AssetBundleReader.inspect(file, path: relative)
                platforms.append(platform)
                let incompatible = platform.targets.filter { [5, 19, 17, 24, 25, 9, 13, 20, 31, 33, 37, 38].contains($0) }
                if !incompatible.isEmpty {
                    warnings.append(ModWarning("bundle-platform", "AssetBundle {0}: gebaut für {1}. Für dieses Bundle wird eine macOS-Ausgabe benötigt.", relative, incompatible.map(BundlePlatform.name).joined(separator: ", ")))
                }
                if (!platform.isMac && incompatible.isEmpty) || !platform.complete {
                    warnings.append(ModWarning("bundles", "AssetBundle {0}: Zielplattform nicht sicher prüfbar. Verwende eine bestätigte macOS-Ausgabe.", relative))
                }
                if components.contains(where: { ["windows", "win64", "win32", "standalonewindows", "standalonewindows64"].contains(String($0)) }) {
                    warnings.append(ModWarning("windows-bundle", "AssetBundle im Windows-Pfad: {0}. Verwende eine macOS-Ausgabe.", relative))
                }
            }
            if components.first == "blueprints" || unity || bundleFile { content = true }
            if header.starts(with: [0x7f, 0x45, 0x4c, 0x46]) {
                warnings.append(ModWarning("linux-native", "Linux-Binärdatei erkannt: {0}. Auf macOS nicht nativ ladbar.", relative))
            } else if header.starts(with: [0x4d, 0x5a]) {
                switch peKind(header) {
                case .native: warnings.append(ModWarning("windows-native", "Native Windows-Binärdatei erkannt: {0}. Auf macOS nicht nativ ladbar.", relative))
                case .unknown: warnings.append(ModWarning("unknown-pe", "Windows/CLR-Binärformat nicht eindeutig prüfbar: {0}.", relative))
                case .managed: break // Managed .NET mod DLLs use PE too; don't label them Windows-only.
                }
            }
        }
        return (warnings, bundles, content, platforms.sorted { $0.path < $1.path })
    }

    enum PEKind { case native, managed, unknown }
    static func peKind(_ bytes: Data) -> PEKind {
        func u16(_ index: Int) -> UInt16? {
            guard index >= 0, index + 2 <= bytes.count else { return nil }
            return UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
        }
        func u32(_ index: Int) -> UInt32? {
            guard index >= 0, index + 4 <= bytes.count else { return nil }
            return (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[index + $1]) << (8 * $1) }
        }
        guard let offset = u32(0x3c) else { return .unknown }
        let pe = Int(offset)
        guard u32(pe) == 0x00004550, let size = u16(pe + 20) else { return .unknown }
        let optional = pe + 24
        guard optional + Int(size) <= bytes.count, let magic = u16(optional), [0x10b, 0x20b].contains(magic) else { return .unknown }
        let directory = optional + (magic == 0x10b ? 96 : 112)
        guard let count = u32(directory - 4) else { return .unknown }
        if count <= 14 { return .native }
        guard directory + 15 * 8 <= optional + Int(size), let clr = u32(directory + 14 * 8), let clrSize = u32(directory + 14 * 8 + 4) else { return .unknown }
        guard clr != 0 && clrSize >= 20 else { return .native }
        // Locate the CLI header through PE section RVAs and inspect ILONLY.
        guard let sections = u16(pe + 6) else { return .unknown }
        let start = optional + Int(size)
        for i in 0..<Int(sections) {
            let section = start + i * 40
            guard let rva = u32(section + 12), let rawSize = u32(section + 16), let raw = u32(section + 20) else { return .unknown }
            if clr >= rva && UInt64(clr) < UInt64(rva) + UInt64(rawSize) {
                let location = Int(raw) + Int(clr - rva)
                guard let flags = u32(location + 16) else { return .unknown }
                return flags & 1 == 1 && flags & 0x10 == 0 ? .managed : .native
            }
        }
        return .unknown
    }
}
