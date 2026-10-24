import XCTest
import Foundation
import ZIPFoundation
@testable import ModCore

final class ModCoreTests: XCTestCase {
    var temp: URL!
    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("RogueModsTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: temp) }
    func game() throws -> URL {
        let root = temp.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("UnityModManager"), withIntermediateDirectories: true)
        try Data("runtime".utf8).write(to: root.appendingPathComponent("UnityModManager/UnityModManager.dll"))
        try Data("{\"SourceDirectories\":[\"custom\"],\"EnabledModifications\":[\"Other\"],\"DisabledModifications\":[],\"customField\":42}".utf8)
            .write(to: root.appendingPathComponent("OwlcatModificationManagerSettings.json"))
        try Data("<?xml version=\"1.0\"?><Param><UIFont>Arial</UIFont><ModParams><Mod Id=\"OtherUMM\" Enabled=\"false\"/></ModParams></Param>".utf8)
            .write(to: root.appendingPathComponent("UnityModManager/Params.xml"))
        return root
    }
    func zip(_ files: [String: String]) throws -> URL {
        let url = temp.appendingPathComponent(UUID().uuidString + ".zip")
        let a = try Archive(url: url, accessMode: .create)
        for (path, value) in files {
            let bytes = Data(value.utf8)
            try a.addEntry(with: path, type: .file, uncompressedSize: Int64(bytes.count)) { offset, size in
                bytes.subdata(in: Int(offset)..<(Int(offset) + size))
            }
        }
        return url
    }
    func owl(_ id: String = "Test", version: String = "1") -> String {
        "{\"UniqueName\":\"\(id)\",\"DisplayName\":\"Test Mod\",\"Version\":\"\(version)\"}"
    }
    func testUninstallTransactionRestoresModWhenCommitFails() throws {
        let root = try game()
        let p = try ModIO.prepare(zip(["OwlcatModificationManifest.json": owl(), "Settings.json": "settings"]))
        _ = try ModIO.install(p, root: root)
        let mod = try XCTUnwrap(ModIO.installed(root: root).first)
        let config = ModIO.configURL(.owlcat, root: root)
        let original = try Data(contentsOf: config)
        XCTAssertThrowsError(try ModIO.transaction(root: root, target: mod.folder, config: config,
            data: Data("{}".utf8), payload: nil, removeTarget: true, beforeCommit: { throw ModError("fixture failure") }))
        XCTAssertEqual(try Data(contentsOf: config), original)
        XCTAssertEqual(try String(contentsOf: mod.folder.appendingPathComponent("Settings.json")), "settings")
        XCTAssertEqual(try ModIO.installed(root: root).first?.id, mod.id)
    }
    func testUninstallRemovesSettingsAndConfigurationAndRetainsRecovery() throws {
        let root = try game()
        let p = try ModIO.prepare(zip(["OwlcatModificationManifest.json": owl(), "Settings.json": "{\"custom\":true}"]))
        let installBackup = try ModIO.install(p, root: root)
        let mod = try XCTUnwrap(ModIO.installed(root: root).first)
        let backup = try XCTUnwrap(ModIO.uninstall(mod, root: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: mod.folder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.appendingPathComponent("PreviousMod/Settings.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installBackup.path))
        let config = try ModIO.json(ModIO.configURL(.owlcat, root: root))
        XCTAssertEqual(config["EnabledModifications"] as? [String], ["Other"])
        XCTAssertEqual(config["customField"] as? Int, 42)
        XCTAssertTrue(try ModIO.installed(root: root).isEmpty)
    }
    func testUninstallDeletesOnlyAssociatedBackupsAndUMMEntry() throws {
        let root = try game()
        let p = try ModIO.prepare(zip(["Info.json": "{\"Id\":\"Test\",\"AssemblyName\":\"Test.dll\"}", "Test.dll": "fixture", "Settings.xml": "settings"]))
        let installBackup = try ModIO.install(p, root: root)
        let mod = try XCTUnwrap(ModIO.installed(root: root).first)
        let toggleBackup = try ModIO.setEnabled(mod, root: root, enabled: false)
        let other = try ModIO.prepare(zip(["OwlcatModificationManifest.json": owl("OtherMod")]))
        let otherBackup = try ModIO.install(other, root: root)
        XCTAssertNil(try ModIO.uninstall(mod, root: root, removeBackups: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: mod.folder.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: installBackup.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: toggleBackup.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: otherBackup.path))
        let doc = try ModIO.xml(Data(contentsOf: ModIO.configURL(.umm, root: root)))
        let ids = doc.rootElement()!.elements(forName: "ModParams").first!.elements(forName: "Mod").compactMap { $0.attribute(forName: "Id")?.stringValue }
        XCTAssertEqual(ids, ["OtherUMM"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("UnityModManager/UnityModManager.dll").path))
    }
    func testUninstallRejectsStaleTargetAndUnsafeBackup() throws {
        let root = try game()
        let p = try ModIO.prepare(zip(["OwlcatModificationManifest.json": owl()]))
        let backup = try ModIO.install(p, root: root)
        let mod = try XCTUnwrap(ModIO.installed(root: root).first)
        let record = backup.appendingPathComponent("Restore.json")
        try FileManager.default.removeItem(at: record)
        try FileManager.default.createSymbolicLink(at: record, withDestinationURL: temp.appendingPathComponent("outside"))
        XCTAssertThrowsError(try ModIO.uninstall(mod, root: root, removeBackups: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: mod.folder.path))
        try FileManager.default.removeItem(at: mod.folder)
        XCTAssertThrowsError(try ModIO.uninstall(mod, root: root))
    }
    func testOwlcatInstallAndDisablePreservesConfig() throws {
        let root = try game()
        let p = try ModIO.prepare(zip(["Wrapper/OwlcatModificationManifest.json": owl(), "Wrapper/Blueprints/a.jbp": "{} "]))
        let backup = try ModIO.install(p, root: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.appendingPathComponent("OwlcatModificationManagerSettings.json").path))
        let config = try ModIO.json(root.appendingPathComponent("OwlcatModificationManagerSettings.json"))
        XCTAssertEqual(config["EnabledModifications"] as? [String], ["Other", "Test"])
        XCTAssertEqual(config["customField"] as? Int, 42)
        let mod = try XCTUnwrap(ModIO.installed(root: root).first)
        XCTAssertTrue(mod.enabled)
        _ = try ModIO.setEnabled(mod, root: root, enabled: false)
        XCTAssertFalse(try XCTUnwrap(ModIO.installed(root: root).first).enabled)
    }
    func testUMMPriorityBOMAndXMLPreservation() throws {
        let root = try game()
        let info = "\u{feff}{\"Id\":\"0ToyBox0\",\"AssemblyName\":\"ToyBox.dll\",\"Version\":\"1\"}"
        let p = try ModIO.prepare(zip(["Info.json": info, "OwlcatModificationManifest.json": owl("0ToyBox0"), "ToyBox.dll": "fixture"]))
        XCTAssertEqual(p.mod.kind, .umm)
        _ = try ModIO.install(p, root: root)
        let config = try String(contentsOf: root.appendingPathComponent("UnityModManager/Params.xml"))
        XCTAssertTrue(config.contains("<UIFont>Arial</UIFont>"))
        XCTAssertTrue(config.contains("Id=\"OtherUMM\" Enabled=\"false\""))
        XCTAssertTrue(config.contains("Id=\"0ToyBox0\" Enabled=\"true\""))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Modifications/0ToyBox0").path))
        let mod = try XCTUnwrap(ModIO.installed(root: root).first)
        _ = try ModIO.setEnabled(mod, root: root, enabled: false)
        XCTAssertFalse(try XCTUnwrap(ModIO.installed(root: root).first).enabled)
    }
    func testUpdateBacksUpOldVersionAndKeepsUserSettings() throws {
        let root = try game()
        _ = try ModIO.install(ModIO.prepare(zip(["OwlcatModificationManifest.json": owl(), "payload": "old"])), root: root)
        let dir = root.appendingPathComponent("Modifications/Test")
        try Data("my choices".utf8).write(to: dir.appendingPathComponent("UserSettings.json"))
        let backup = try ModIO.install(ModIO.prepare(zip(["OwlcatModificationManifest.json": owl(version: "2"), "payload": "new"])), root: root)
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("payload")), "new")
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("UserSettings.json")), "my choices")
        XCTAssertEqual(try String(contentsOf: backup.appendingPathComponent("PreviousMod/payload")), "old")
        XCTAssertEqual(try ModIO.installed(root: root).count, 1)
    }
    func testRejectsTraversalAndAmbiguousMods() throws {
        XCTAssertThrowsError(try ModIO.prepare(zip(["../escape": "bad", "OwlcatModificationManifest.json": owl()])))
        XCTAssertThrowsError(try ModIO.prepare(zip(["one/OwlcatModificationManifest.json": owl(), "two/OwlcatModificationManifest.json": owl("Other")])))
        XCTAssertThrowsError(try ModIO.prepare(zip(["OwlcatModificationManifest.json": owl("../bad")])))
        XCTAssertThrowsError(try ModIO.prepare(zip(["OwlcatModificationManifest.json": owl(), "same": "1", "SAME": "2"])))
    }
    func testInvalidConfigDoesNotTouchInstalledMod() throws {
        let root = try game()
        let p = try ModIO.prepare(zip(["OwlcatModificationManifest.json": owl(), "payload": "old"]))
        _ = try ModIO.install(p, root: root)
        let config = root.appendingPathComponent("OwlcatModificationManagerSettings.json")
        try Data("broken".utf8).write(to: config)
        XCTAssertThrowsError(try ModIO.install(p, root: root))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Modifications/Test/payload")), "old")
        XCTAssertEqual(try String(contentsOf: config), "broken")
    }
    func testRejectsSymlinkDestination() throws {
        let root = try game()
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Modifications"), withDestinationURL: temp)
        let p = try ModIO.prepare(zip(["OwlcatModificationManifest.json": owl()]))
        XCTAssertThrowsError(try ModIO.install(p, root: root))
    }
    func testRejectsSymlinkArchive() throws {
        let url = temp.appendingPathComponent("link.zip")
        let a = try Archive(url: url, accessMode: .create)
        let data = Data("/tmp".utf8)
        try a.addEntry(with: "link", type: .symlink, uncompressedSize: Int64(data.count)) { offset, count in data.subdata(in: Int(offset)..<(Int(offset)+count)) }
        XCTAssertThrowsError(try ModIO.prepare(url))
    }
    func testRollbackOnCommitFailure() throws {
        let root = try game()
        let config = root.appendingPathComponent("OwlcatModificationManagerSettings.json")
        let original = try Data(contentsOf: config)
        let old = try ModIO.prepare(zip(["OwlcatModificationManifest.json": owl(), "payload": "old"]))
        _ = try ModIO.install(old, root: root)
        let target = root.appendingPathComponent("Modifications/Test")
        let next = try ModIO.prepare(zip(["OwlcatModificationManifest.json": owl(version: "2"), "payload": "new"]))
        let before = try Data(contentsOf: config)
        XCTAssertThrowsError(try ModIO.transaction(root: root, target: target, config: config, data: original, payload: next.mod.folder) {
            throw ModError("Simulated write failure")
        })
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("payload")), "old")
        XCTAssertEqual(try Data(contentsOf: config), before)
    }
    func testUpdateRemovesObsoletePackageFiles() throws {
        let root = try game()
        _ = try ModIO.install(ModIO.prepare(zip(["OwlcatModificationManifest.json": owl(), "obsolete.dll": "old"])), root: root)
        _ = try ModIO.install(ModIO.prepare(zip(["OwlcatModificationManifest.json": owl(version: "2")])), root: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Modifications/Test/obsolete.dll").path))
    }
    func testEnablePreservesExistingOrderAndRejectsDTD() throws {
        let root = try game()
        let config = root.appendingPathComponent("OwlcatModificationManagerSettings.json")
        try Data("{\"EnabledModifications\":[\"Test\",\"Other\"]}".utf8).write(to: config)
        let data = try ModIO.configData(root: root, kind: .owlcat, key: "Test", enabled: true)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["EnabledModifications"] as? [String], ["Test", "Other"])
        XCTAssertThrowsError(try ModIO.xml(Data("<!DOCTYPE Param [<!ENTITY x 'bad'>]><Param/>".utf8)))
    }
    func testLocalRealPackagesIfAvailable() throws {
        let base = URL(fileURLWithPath: "/private/tmp/rt-mod-compatibility")
        for name in ["ToyBox", "ReDress"] {
            let url = base.appendingPathComponent(name + ".zip")
            if FileManager.default.fileExists(atPath: url.path) {
                let p = try ModIO.prepare(url)
                XCTAssertEqual(p.mod.kind, .umm)
                _ = try ModIO.install(p, root: game())
            }
        }
        let orks = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).deletingLastPathComponent().appendingPathComponent("RogueTrader-Modding/Build/ArmouryOrks.zip")
        if FileManager.default.fileExists(atPath: orks.path) {
            let p = try ModIO.prepare(orks); XCTAssertTrue(p.hasBundles); XCTAssertEqual(p.mod.kind, .owlcat)
            _ = try ModIO.install(p, root: game())
        }
    }
}
