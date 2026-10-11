import Foundation
import ModCore

// Content comparisons also detect same-size edits and atomic file replacements.
struct InventoryStamp: Equatable {
    private let files: [String: Data]
    private let directories: [String]

    init(root: URL) throws {
        let fm = FileManager.default
        var files: [String: Data] = [:]
        var directories: [String] = []
        func read(_ url: URL) throws {
            if fm.fileExists(atPath: url.path) { files[url.path] = try Data(contentsOf: url) }
        }
        try read(root.appendingPathComponent("OwlcatModificationManagerSettings.json"))
        try read(root.appendingPathComponent("UnityModManager/Params.xml"))
        for kind in [ModKind.owlcat, .umm] {
            let folder = root.appendingPathComponent(kind.folder)
            guard fm.fileExists(atPath: folder.path) else { continue }
            directories.append(folder.path)
            for mod in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) {
                guard try mod.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
                directories.append(mod.path)
                for file in try fm.contentsOfDirectory(at: mod, includingPropertiesForKeys: nil)
                    where ["info.json", "owlcatmodificationmanifest.json"].contains(file.lastPathComponent.lowercased()) {
                    try read(file)
                }
            }
        }
        self.files = files
        self.directories = directories.sorted()
    }
}
