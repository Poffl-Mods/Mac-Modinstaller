import XCTest
import Foundation
import ZIPFoundation
import ModCore
@testable import RogueModInstaller

final class InventoryRefreshTests: XCTestCase {
    var root: URL!
    var defaults: UserDefaults!
    var suite: String!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("InstallerRefresh-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{\"EnabledModifications\":[]}".utf8).write(to: root.appendingPathComponent("OwlcatModificationManagerSettings.json"))
        suite = "InstallerRefreshTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(root.path, forKey: "gameData")
    }
    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try FileManager.default.removeItem(at: root)
    }
    func package(_ version: String, key: String = "ArmouryOrks") throws -> PreparedMod {
        let zip = root.appendingPathComponent(UUID().uuidString + ".zip")
        let archive = try Archive(url: zip, accessMode: .create)
        let bytes = Data("{\"UniqueName\":\"\(key)\",\"DisplayName\":\"\(key)\",\"Version\":\"\(version)\"}".utf8)
        try archive.addEntry(with: "OwlcatModificationManifest.json", type: .file, uncompressedSize: Int64(bytes.count)) { offset, size in
            bytes.subdata(in: Int(offset)..<(Int(offset) + size))
        }
        return try ModIO.prepare(zip)
    }
    @MainActor func eventually(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Inventory did not converge")
    }
    @MainActor func testExternalUpdateActivationAdditionRemovalAndRootChange() async throws {
        _ = try ModIO.install(package("0.4.9"), root: root)
        let model = InstallerModel(defaults: defaults, refreshInterval: 0.03)
        XCTAssertEqual(model.mods.first?.version, "0.4.9")
        let status = model.status.key
        // External install uses the same production transaction as the CLI fallback.
        _ = try ModIO.install(package("0.4.11"), root: root)
        try await eventually { model.mods.first?.version == "0.4.11" }
        XCTAssertTrue(model.mods[0].enabled)
        _ = try ModIO.setEnabled(model.mods[0], root: root, enabled: false)
        try await eventually { model.mods.first?.enabled == false }
        _ = try ModIO.install(package("1", key: "Added"), root: root)
        try await eventually { model.mods.count == 2 }
        try FileManager.default.removeItem(at: root.appendingPathComponent("Modifications/Added"))
        try await eventually { model.mods.count == 1 }
        XCTAssertEqual(model.status.key, status)
        XCTAssertNil(model.error)
        let second = root.appendingPathComponent("SecondGame")
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: second.appendingPathComponent("OwlcatModificationManagerSettings.json"))
        model.refreshAutomatically()
        model.root = second
        try await eventually { model.mods.isEmpty }
    }
    @MainActor func testBusyPreviewConfirmationAndErrorPauseRefresh() async throws {
        _ = try ModIO.install(package("0.4.9"), root: root)
        let model = InstallerModel(defaults: defaults, refreshInterval: 0.03)
        for blocker in 0..<4 {
            let old = model.mods[0].version
            switch blocker {
            case 0: model.busy = true
            case 1: model.preview = try package("9")
            case 2: model.pendingToggle = model.mods[0]
            default: model.error = "Existing error"
            }
            _ = try ModIO.install(package("0.4.\(12 + blocker)"), root: root)
            model.refresh() // Manual refresh must respect the same protection.
            model.refreshAutomatically()
            try await Task.sleep(nanoseconds: 150_000_000)
            XCTAssertEqual(model.mods[0].version, old)
            switch blocker {
            case 0: model.busy = false
            case 1: XCTAssertNotNil(model.preview); model.cancelPreview()
            case 2: XCTAssertNotNil(model.pendingToggle); model.pendingToggle = nil
            default: XCTAssertEqual(model.error, "Existing error"); model.error = nil
            }
            try await eventually { model.mods[0].version == "0.4.\(12 + blocker)" }
        }
    }
    @MainActor func testTransientInvalidConfigurationKeepsListAndRetries() async throws {
        _ = try ModIO.install(package("0.4.11"), root: root)
        let model = InstallerModel(defaults: defaults, refreshInterval: 0.03)
        let config = root.appendingPathComponent("OwlcatModificationManagerSettings.json")
        try Data("partial JSON".utf8).write(to: config, options: .atomic)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(model.mods.first?.version, "0.4.11")
        XCTAssertTrue(model.mods[0].enabled)
        XCTAssertNil(model.error)
        try Data("{\"EnabledModifications\":[]}".utf8).write(to: config, options: .atomic)
        try await eventually { model.mods.first?.enabled == false }
    }
    @MainActor func testInFlightReadIsDiscardedWhenOperationBegins() async throws {
        _ = try ModIO.install(package("0.4.9"), root: root)
        let model = InstallerModel(defaults: defaults, refreshInterval: 60)
        _ = try ModIO.install(package("0.4.11"), root: root)
        // First observation records the changed stamp without publishing a list.
        model.refreshAutomatically()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(model.mods.first?.version, "0.4.9")
        let gate = DispatchSemaphore(value: 0)
        model.work.async { gate.wait() }
        model.refreshAutomatically()
        // Even if busy clears before the full read returns, its generation is obsolete.
        model.busy = true
        model.busy = false
        gate.signal()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(model.mods.first?.version, "0.4.9")
        model.refreshAutomatically()
        try await Task.sleep(nanoseconds: 100_000_000)
        model.refreshAutomatically()
        try await eventually { model.mods.first?.version == "0.4.11" }
    }
    @MainActor func testExternalUMMInstallAndActivation() async throws {
        let umm = root.appendingPathComponent("UnityModManager")
        try FileManager.default.createDirectory(at: umm, withIntermediateDirectories: true)
        try Data("runtime".utf8).write(to: umm.appendingPathComponent("UnityModManager.dll"))
        let model = InstallerModel(defaults: defaults, refreshInterval: 0.03)
        let zip = root.appendingPathComponent("UMM.zip")
        let archive = try Archive(url: zip, accessMode: .create)
        for (name, contents) in ["Info.json": "{\"Id\":\"TestUMM\",\"AssemblyName\":\"Test.dll\",\"Version\":\"1.0\"}", "Test.dll": "fixture"] {
            let bytes = Data(contents.utf8)
            try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(bytes.count)) { offset, size in
                bytes.subdata(in: Int(offset)..<(Int(offset) + size))
            }
        }
        _ = try ModIO.install(ModIO.prepare(zip), root: root)
        try await eventually { model.mods.first?.key == "TestUMM" }
        XCTAssertTrue(model.mods[0].enabled)
        _ = try ModIO.setEnabled(model.mods[0], root: root, enabled: false)
        try await eventually { model.mods.first?.enabled == false }
    }
    func testStampDetectsSameSizeEditsAndUMMConfigurationReplacement() throws {
        let umm = root.appendingPathComponent("UnityModManager")
        try FileManager.default.createDirectory(at: umm, withIntermediateDirectories: true)
        let config = umm.appendingPathComponent("Params.xml")
        try Data("AAAA".utf8).write(to: config)
        let old = try InventoryStamp(root: root)
        try Data("BBBB".utf8).write(to: config, options: .atomic)
        XCTAssertNotEqual(old, try InventoryStamp(root: root))
    }
}
