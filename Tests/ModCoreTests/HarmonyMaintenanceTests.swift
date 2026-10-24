import XCTest

@testable import ModCore

final class HarmonyMaintenanceTests: XCTestCase {
    var temp: URL!
    var game: URL!
    var root: URL!
    var target: URL { game.appendingPathComponent(HarmonyMaintenance.relativeTarget) }
    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        game = temp.appendingPathComponent("WH40KRT.app")
        root = temp.appendingPathComponent("UserData")
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Saved Games"), withIntermediateDirectories: true)
        let plist = ["CFBundleIdentifier": "com.Owlcat-Games.Warhammer-40000-Rogue-Trader"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: game.appendingPathComponent("Contents/Info.plist"))
        try managed().write(to: target)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: temp) }
    func managed(version: [UInt32]? = nil) -> Data {
        let helper = ModChecksTests()
        var bytes = helper.pe(managed: true)
        guard let version else { return bytes }
        bytes.append(Data(repeating: 0, count: 512))
        func put(_ value: UInt32, _ offset: Int, _ size: Int = 4) {
            for i in 0..<size { bytes[offset + i] = UInt8(truncatingIfNeeded: value >> (8 * i)) }
        }
        put(2, 134, 2)
        put(0x3000, 248 + 16)
        put(512, 248 + 20)
        put(0x3000, 416 + 12)
        put(512, 416 + 16)
        put(1024, 416 + 20)
        put(1, 1024 + 14, 2)
        put(16, 1040)
        put(0x8000_0020, 1044)
        put(1, 1056 + 14, 2)
        put(1, 1072)
        put(0x8000_0040, 1076)
        put(1, 1088 + 14, 2)
        put(1033, 1104)
        put(96, 1108)
        put(0x3080, 1120)
        put(92, 1124)
        let start = 1152
        put(92, start, 2)
        put(52, start + 2, 2)
        for (i, char) in "VS_VERSION_INFO\0".utf16.enumerated() { put(UInt32(char), start + 6 + i * 2, 2) }
        put(0xfeef_04bd, start + 40)
        put((version[0] << 16) | version[1], start + 48)
        put((version[2] << 16) | version[3], start + 52)
        return bytes
    }
    func testPEVersionMetadataAndCorruption() throws {
        let bytes = managed(version: [2, 4, 2, 0])
        XCTAssertEqual(PEFileVersion.read(bytes), "2.4.2.0")
        for length in 0..<bytes.count where length % 7 == 0 {
            XCTAssertNil(PEFileVersion.read(Data(bytes.prefix(length))))
        }
        XCTAssertNil(PEFileVersion.read(managed()))
        var corrupt = bytes
        corrupt[1044] = 0xff
        corrupt[1045] = 0xff
        corrupt[1046] = 0xff
        XCTAssertNil(PEFileVersion.read(corrupt))
    }
    func testInspectionRejectsWrongAppNativeDLLAndSymlink() throws {
        XCTAssertNil(try HarmonyMaintenance.inspect(game: game).fileVersion)
        try ModChecksTests().pe().write(to: target)
        XCTAssertThrowsError(try HarmonyMaintenance.inspect(game: game))
        try managed().write(to: target)
        let outside = temp.appendingPathComponent("outside.dll")
        try managed().write(to: outside)
        try FileManager.default.removeItem(at: target)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside)
        XCTAssertThrowsError(try HarmonyMaintenance.inspect(game: game))
        try FileManager.default.removeItem(at: target)
        try managed().write(to: target)
        try Data("not a plist".utf8).write(to: game.appendingPathComponent("Contents/Info.plist"))
        XCTAssertThrowsError(try HarmonyMaintenance.inspect(game: game))
    }
    func testRejectedPackageMakesNoChanges() throws {
        let zip = temp.appendingPathComponent("fake.zip")
        try Data("untrusted package".utf8).write(to: zip)
        let original = try Data(contentsOf: target)
        XCTAssertThrowsError(
            try HarmonyMaintenance.install(zip, inspected: HarmonyMaintenance.inspect(game: game), root: root)
        )
        XCTAssertEqual(try Data(contentsOf: target), original)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("RogueModInstaller Backups").path))
    }
    func testTransactionBackupRestoreAndConflictingChanges() throws {
        let original = try Data(contentsOf: target)
        let replacement = managed(version: [2, 4, 2, 0])
        let expected = HarmonyMaintenance.hash(replacement)
        let report = try HarmonyMaintenance.inspect(game: game)
        let backup = try HarmonyMaintenance.replace(
            replacement, inspected: report, root: root, expectedHash: expected)
        XCTAssertEqual(try Data(contentsOf: target), replacement)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("0Harmony.dll")), original)
        XCTAssertThrowsError(
            try HarmonyMaintenance.replace(replacement, inspected: report, root: root, expectedHash: expected)
        )
        let changed = managed(version: [2, 5, 0, 0])
        try changed.write(to: target)
        XCTAssertThrowsError(
            try HarmonyMaintenance.restoreBackup(
                backup, inspected: HarmonyMaintenance.inspect(game: game), root: root, expectedHash: expected)
        )
        XCTAssertEqual(try Data(contentsOf: target), changed)
        try replacement.write(to: target)
        try HarmonyMaintenance.restoreBackup(
            backup, inspected: HarmonyMaintenance.inspect(game: game), root: root, expectedHash: expected)
        XCTAssertEqual(try Data(contentsOf: target), original)
    }
    func testFailedCommitRetainsOriginalAndRecoveryBackup() throws {
        enum Failure: Error { case simulated }
        let replacement = managed(version: [2, 4, 2, 0])
        let original = try Data(contentsOf: target)
        XCTAssertThrowsError(
            try HarmonyMaintenance.replace(
                replacement, inspected: HarmonyMaintenance.inspect(game: game), root: root,
                beforeWrite: { throw Failure.simulated }, expectedHash: HarmonyMaintenance.hash(replacement)))
        XCTAssertEqual(try Data(contentsOf: target), original)
        let backups = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("RogueModInstaller Backups"), includingPropertiesForKeys: nil)
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: backups[0].appendingPathComponent("0Harmony.dll")), original)
    }
    func testDowngradeRejectedBeforeBackup() throws {
        try managed(version: [2, 5, 0, 0]).write(to: target)
        let report = try HarmonyMaintenance.inspect(game: game)
        XCTAssertTrue(report.isNewer)
        let replacement = managed(version: [2, 4, 2, 0])
        XCTAssertThrowsError(
            try HarmonyMaintenance.replace(
                replacement, inspected: report, root: root, expectedHash: HarmonyMaintenance.hash(replacement)
            ))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("RogueModInstaller Backups").path))
    }
    func testTamperedBackupAndWrongDestinationRejected() throws {
        let replacement = managed(version: [2, 4, 2, 0])
        let expected = HarmonyMaintenance.hash(replacement)
        let backup = try HarmonyMaintenance.replace(
            replacement, inspected: HarmonyMaintenance.inspect(game: game), root: root, expectedHash: expected
        )
        let recordURL = backup.appendingPathComponent("HarmonyRestore.json")
        let record = try Data(contentsOf: recordURL)
        var metadata = try JSONSerialization.jsonObject(with: record) as! [String: String]
        metadata["target"] = "/tmp/unrelated.dll"
        try JSONSerialization.data(withJSONObject: metadata).write(to: recordURL)
        XCTAssertThrowsError(
            try HarmonyMaintenance.restoreBackup(
                backup, inspected: HarmonyMaintenance.inspect(game: game), root: root, expectedHash: expected)
        )
        try record.write(to: recordURL)
        try Data("corrupt backup".utf8).write(to: backup.appendingPathComponent("0Harmony.dll"))
        XCTAssertThrowsError(
            try HarmonyMaintenance.restoreBackup(
                backup, inspected: HarmonyMaintenance.inspect(game: game), root: root, expectedHash: expected)
        )
        XCTAssertEqual(try Data(contentsOf: target), replacement)
    }
    func testOfficialLocalPackageWhenAvailable() throws {
        let zip = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("../vendor-downloads/Harmony-Fat.2.4.2.0.zip").standardizedFileURL
        guard FileManager.default.fileExists(atPath: zip.path) else {
            throw XCTSkip("Optional official package not distributed")
        }
        let backup = try HarmonyMaintenance.install(
            zip, inspected: HarmonyMaintenance.inspect(game: game), root: root)
        let report = try HarmonyMaintenance.inspect(game: game)
        XCTAssertTrue(report.isInstalled)
        XCTAssertEqual(report.fileVersion, "2.4.2.0")
        try HarmonyMaintenance.restore(backup, inspected: report, root: root)
        XCTAssertFalse(try HarmonyMaintenance.inspect(game: game).isInstalled)
    }
    func testOfficialNetworkDownloadWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["MACMOD_NETWORK_TESTS"] == "1" else {
            throw XCTSkip("Optional network smoke check")
        }
        let zip = try await HarmonyMaintenance.download()
        defer { try? FileManager.default.removeItem(at: zip) }
        XCTAssertEqual(
            HarmonyMaintenance.hash(try HarmonyMaintenance.payload(zip)), HarmonyMaintenance.dllHash)
    }
}
