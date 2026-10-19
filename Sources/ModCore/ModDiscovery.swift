import Foundation

// Find game-data folders and read installed mod manifests and activation state.
extension ModIO {
    public static func candidates(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            "Library/Application Support/Owlcat Games/Warhammer 40000 Rogue Trader",
            "Library/Application Support/com.Owlcat-Games.Warhammer-40000-Rogue-Trader",
        ]
        .map { home.appendingPathComponent($0) }.filter { isGameData($0) }
    }

    public static func isGameData(_ url: URL) -> Bool {
        fm.fileExists(atPath: url.appendingPathComponent("OwlcatModificationManagerSettings.json").path)
            || fm.fileExists(atPath: url.appendingPathComponent("UnityModManager/Params.xml").path)
            || fm.fileExists(atPath: url.appendingPathComponent("Saved Games").path)
    }

    static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.count < 160 && id != "." && id != ".." && !id.hasPrefix(".")
            && id.rangeOfCharacter(
                from: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-. ")).inverted) == nil
            && id == id.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func manifest(_ name: String, in folder: URL) throws -> URL? {
        let matches = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.lowercased() == name.lowercased() }
        guard matches.count <= 1 else { throw ModError("Mehrdeutiger Manifest-Dateiname: {0}", name) }
        return matches.first
    }

    public static func readMod(_ folder: URL) throws -> Mod? {
        let umm = try manifest("Info.json", in: folder)
        let owl = try manifest("OwlcatModificationManifest.json", in: folder)
        let kind: ModKind
        let metadata: [String: Any]
        // UMM packages often include an Owlcat manifest for Steam Workshop as well.
        if let umm {
            kind = .umm
            metadata = try json(umm)
        } else if let owl {
            kind = .owlcat
            metadata = try json(owl)
        } else {
            return nil
        }
        guard let key = metadata[kind == .umm ? "Id" : "UniqueName"] as? String, validID(key) else {
            throw ModError("Der Mod enthält keine gültige Kennung.")
        }
        if kind == .umm {
            guard let assembly = metadata["AssemblyName"] as? String,
                !assembly.contains("/"), !assembly.contains("\\"), assembly.lowercased().hasSuffix(".dll"),
                fm.fileExists(atPath: folder.appendingPathComponent(assembly).path)
            else {
                throw ModError("Die in Info.json angegebene Mod-DLL fehlt.")
            }
        }
        var mod = Mod(
            key: key, name: metadata["DisplayName"] as? String ?? key,
            version: metadata["Version"] as? String ?? "?", kind: kind, folder: folder, enabled: false,
            requirements: metadata[kind == .umm ? "Requirements" : "Dependencies"] as? [String] ?? [])
        let checks = try ModChecks.inspect(folder)
        mod.packageWarnings = checks.warnings
        mod.hasOwlcatContent = checks.content
        mod.bundlePlatforms = checks.platforms
        if let raw = metadata[kind == .umm ? "Requirements" : "Dependencies"], !(raw is [String]) {
            mod.packageWarnings.append(
                ModWarning("requirements-metadata", "Abhängigkeiten im Manifest sind nicht lesbar."))
        }
        return mod
    }

    public static func installed(root: URL) throws -> [Mod] {
        var result: [Mod] = []
        for kind in [ModKind.owlcat, .umm] {
            let folder = root.appendingPathComponent(kind.folder)
            try safe(folder, in: root)
            guard fm.fileExists(atPath: folder.path) else { continue }
            let config = configURL(kind, root: root)
            try safe(config, in: root)
            var enabledIDs = Set<String>()
            var ummDisabled = Set<String>()
            if fm.fileExists(atPath: config.path) {
                if kind == .owlcat {
                    enabledIDs = Set(try json(config)["EnabledModifications"] as? [String] ?? [])
                } else {
                    let doc = try xml(Data(contentsOf: config))
                    for node in doc.rootElement()?.elements(forName: "ModParams").first?.elements(
                        forName: "Mod") ?? []
                    {
                        if let key = node.attribute(forName: "Id")?.stringValue,
                            node.attribute(forName: "Enabled")?.stringValue?.lowercased() == "false"
                        {
                            ummDisabled.insert(key)
                        }
                    }
                }
            }
            for item in try fm.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
            {
                guard try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                    continue
                }
                try safe(item, in: root)
                if var mod = try readMod(item) {
                    guard mod.kind == kind else {
                        throw ModError(
                            "{0} liegt im falschen Mod-Ordner. Bitte die vorhandene Installation prüfen.",
                            mod.name)
                    }
                    mod.enabled = kind == .umm ? !ummDisabled.contains(mod.key) : enabledIDs.contains(mod.key)
                    result.append(mod)
                }
            }
        }
        guard Set(result.map(\.id)).count == result.count else {
            throw ModError("Eine Mod-Kennung ist mehrfach installiert.")
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
