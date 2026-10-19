import Foundation

// Read JSON/XML and prepare activation changes while preserving unrelated settings.
extension ModIO {
    static func json(_ url: URL) throws -> [String: Any] {
        var data = try Data(contentsOf: url)
        if data.starts(with: [0xef, 0xbb, 0xbf]) { data.removeFirst(3) }
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ModError("Ungültiges JSON: {0}", url.lastPathComponent)
        }
        return value
    }

    static func configURL(_ kind: ModKind, root: URL) -> URL {
        root.appendingPathComponent(
            kind == .umm ? "UnityModManager/Params.xml" : "OwlcatModificationManagerSettings.json")
    }

    static func xml(_ data: Data?) throws -> XMLDocument {
        if let data, String(decoding: data, as: UTF8.self).uppercased().contains("<!DOCTYPE") {
            throw ModError("DTD-Deklarationen sind in der UMM-Konfiguration nicht zulässig.")
        }
        let document = try XMLDocument(
            data: data ?? Data("<?xml version=\"1.0\"?><Param><ModParams/></Param>".utf8),
            options: [.nodePreserveAll, .nodeLoadExternalEntitiesNever])
        guard document.dtd == nil, document.rootElement()?.name == "Param" else {
            throw ModError("Ungültige UMM-Konfiguration.")
        }
        return document
    }

    static func configData(root: URL, kind: ModKind, key: String, enabled: Bool) throws -> Data {
        let url = configURL(kind, root: root)
        try safe(url, in: root)
        let old = fm.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        if kind == .umm {
            let doc = try xml(old)
            let root = doc.rootElement()!
            let parents = root.elements(forName: "ModParams")
            guard parents.count <= 1 else { throw ModError("Doppelte UMM-ModParams-Einträge.") }
            let parent = parents.first ?? XMLElement(name: "ModParams")
            if parents.isEmpty { root.addChild(parent) }
            let matches = parent.elements(forName: "Mod").filter {
                $0.attribute(forName: "Id")?.stringValue == key
            }
            guard matches.count <= 1 else { throw ModError("Doppelte Mod-Kennung in Params.xml.") }
            let node = matches.first ?? XMLElement(name: "Mod")
            if matches.isEmpty {
                node.addAttribute(XMLNode.attribute(withName: "Id", stringValue: key) as! XMLNode)
                parent.addChild(node)
            }
            node.removeAttribute(forName: "Enabled")
            node.addAttribute(
                XMLNode.attribute(withName: "Enabled", stringValue: enabled ? "true" : "false") as! XMLNode)
            return doc.xmlData(options: .nodePrettyPrint)
        }
        var obj: [String: Any] =
            old == nil ? ["SourceDirectories": [], "EnabledModifications": []] : try json(url)
        for name in ["EnabledModifications", "DisabledModifications"] {
            if obj[name] != nil && !(obj[name] is [String]) {
                throw ModError("Ungültige Liste {0} in der Spielkonfiguration.", name)
            }
        }
        var enabledIDs = obj["EnabledModifications"] as? [String] ?? []
        if enabled {
            if !enabledIDs.contains(key) { enabledIDs.append(key) }
        } else {
            enabledIDs.removeAll { $0 == key }
        }
        obj["EnabledModifications"] = enabledIDs
        if var disabled = obj["DisabledModifications"] as? [String] {
            disabled.removeAll { $0 == key }
            if !enabled { disabled.append(key) }
            obj["DisabledModifications"] = disabled
        }
        return try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
    }
}
