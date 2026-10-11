import XCTest
import Foundation
import ZIPFoundation
@testable import ModCore

final class ModChecksTests: XCTestCase {
    var temp: URL!
    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("ModChecks-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: temp) }
    func mod(_ key: String, _ version: String = "1", kind: ModKind = .umm, enabled: Bool = true, requirements: [String] = []) -> Mod {
        Mod(key: key, name: key, version: version, kind: kind, folder: temp, enabled: enabled, requirements: requirements)
    }
    func codes(_ mod: Mod, _ installed: [Mod] = [], replacing: Mod? = nil) -> Set<String> {
        Set(ModChecks.warnings(for: mod, installed: installed, replacing: replacing).map(\.code))
    }
    func zip(_ files: [String: Data]) throws -> URL {
        let url = temp.appendingPathComponent(UUID().uuidString + ".zip")
        let archive = try Archive(url: url, accessMode: .create)
        for (name, bytes) in files {
            try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(bytes.count)) { offset, size in
                bytes.subdata(in: Int(offset)..<(Int(offset) + size))
            }
        }
        return url
    }
    func pe(managed: Bool = false, mixed: Bool = false, plus: Bool = false) -> Data {
        var data = Data(repeating: 0, count: 1024)
        func put(_ value: UInt32, _ offset: Int, _ size: Int = 4) {
            for i in 0..<size { data[offset + i] = UInt8(truncatingIfNeeded: value >> (8 * i)) }
        }
        data[0] = 0x4d; data[1] = 0x5a
        put(128, 0x3c); put(0x4550, 128); put(1, 134, 2)
        let optional = 152; let size = plus ? 240 : 224
        put(UInt32(size), 148, 2); put(plus ? 0x20b : 0x10b, optional, 2)
        let directories = optional + (plus ? 112 : 96)
        put(16, directories - 4)
        if managed {
            put(0x2000, directories + 14 * 8); put(72, directories + 14 * 8 + 4)
            let section = optional + size
            put(0x2000, section + 12); put(512, section + 16); put(512, section + 20)
            put(mixed ? 0 : 1, 528)
        }
        return data
    }
    func testVersionOrderingAndUnknownValues() throws {
        func v(_ raw: String) throws -> CheckedVersion { try XCTUnwrap(CheckedVersion(raw)) }
        XCTAssertLessThan(try v("1.9"), try v("1.10"))
        XCTAssertEqual(try v("v1.2.0"), try v("1.2"))
        XCTAssertLessThan(try v("1.2.3"), try v("1.2.3a"))
        XCTAssertLessThan(try v("1.2.3-alpha.2"), try v("1.2.3-alpha.10"))
        XCTAssertLessThan(try v("1.2.3-rc.1"), try v("1.2.3"))
        XCTAssertEqual(try v("1.2.3+build1"), try v("1.2.3+build2"))
        for raw in ["?", "", "latest", "1..2", "1.2-rc..1", "999999999999999999999999"] { XCTAssertNil(CheckedVersion(raw), raw) }
        XCTAssertTrue(codes(mod("Test", "?")).contains("version"))
    }
    func testMissingDisabledOutdatedAndSatisfiedDependencies() {
        let dependent = mod("Test", requirements: ["Dependency-1.10"])
        XCTAssertEqual(codes(dependent), ["missing"])
        XCTAssertEqual(codes(dependent, [mod("Dependency", "1.9", enabled: false)]), ["disabled", "outdated"])
        XCTAssertEqual(codes(dependent, [mod("Dependency", "1.10")]), [])
        XCTAssertEqual(codes(dependent, [mod("Dependency", "?")]), ["dependency-unknown"])
        XCTAssertEqual(codes(dependent, [mod("Dependency", kind: .owlcat)]), ["missing"])
        XCTAssertEqual(codes(mod("Test", requirements: ["Lib-2"]), [mod("Lib-2")]), [])
        XCTAssertEqual(codes(mod("Test", requirements: ["Lib-2-1.10"]), [mod("Lib-2", "1.9")]), ["outdated"])
    }
    func testDowngradeAndAmbiguousDependencies() {
        XCTAssertEqual(codes(mod("Test", "1.9"), replacing: mod("Test", "1.10")), ["downgrade"])
        XCTAssertEqual(codes(mod("Test", "1.10"), replacing: mod("Test", "1.9")), [])
        XCTAssertTrue(codes(mod("Test"), replacing: mod("Test", "unknown")).contains("comparison"))
        XCTAssertEqual(codes(mod("Test", kind: .owlcat, requirements: ["Lib"]), [mod("Lib"), mod("Lib", kind: .owlcat)]), ["ambiguous"])
    }
    func testMicroPatchesAdvisoryOnlyForOwlcatContent() {
        var content = mod("Test", kind: .owlcat)
        XCTAssertEqual(codes(content), [])
        content.hasOwlcatContent = true
        XCTAssertEqual(codes(content), ["micropatches"])
        XCTAssertEqual(codes(content, [mod("MicroPatches", enabled: false)]), ["micropatches"])
        XCTAssertEqual(codes(content, [mod("MicroPatches")]), [])
        var umm = mod("Test"); umm.hasOwlcatContent = true
        XCTAssertEqual(codes(umm), [])
    }
    func testLowercaseManifestsAndUMMPrioritySurviveInstallation() throws {
        let package = try ModIO.prepare(zip([
            "wrapper/info.JSON": Data(#"{"Id":"Test","Version":"1","AssemblyName":"Test.dll"}"#.utf8),
            "wrapper/owlcatmodificationmanifest.JSON": Data(#"{"UniqueName":"Test","Version":"1"}"#.utf8),
            "wrapper/Test.dll": pe(managed: true)
        ]))
        XCTAssertEqual(package.mod.kind, .umm)
        XCTAssertTrue(package.mod.packageWarnings.isEmpty)
        let game = temp.appendingPathComponent("game")
        try FileManager.default.createDirectory(at: game.appendingPathComponent("UnityModManager"), withIntermediateDirectories: true)
        try Data().write(to: game.appendingPathComponent("UnityModManager/UnityModManager.dll"))
        try Data("<Param><ModParams/></Param>".utf8).write(to: game.appendingPathComponent("UnityModManager/Params.xml"))
        _ = try ModIO.install(package, root: game, acceptedWarnings: [])
        XCTAssertEqual(try ModIO.installed(root: game).first?.key, "Test")
    }
    func testNativeWindowsManagedAndTruncatedPE() throws {
        for plus in [false, true] {
            XCTAssertEqual(ModChecks.peKind(pe(plus: plus)), .native)
            XCTAssertEqual(ModChecks.peKind(pe(managed: true, plus: plus)), .managed)
            XCTAssertEqual(ModChecks.peKind(pe(managed: true, mixed: true, plus: plus)), .native)
        }
        XCTAssertEqual(ModChecks.peKind(Data([0x4d, 0x5a])), .unknown)
        try pe().write(to: temp.appendingPathComponent("Native.dll"))
        try pe(managed: true).write(to: temp.appendingPathComponent("Managed.dll"))
        try Data([0x7f, 0x45, 0x4c, 0x46]).write(to: temp.appendingPathComponent("Linux.so"))
        let warnings = try ModChecks.inspect(temp).warnings
        XCTAssertEqual(Set(warnings.map(\.code)), ["windows-native", "linux-native"])
        XCTAssertFalse(warnings.contains { $0.message.arguments.contains("Managed.dll") })
    }
    func testRealBundleDetectionAndEmptyDirectory() throws {
        let bundleDir = temp.appendingPathComponent("Bundles/Windows")
        try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)
        XCTAssertFalse(try ModChecks.inspect(temp).bundles)
        try Data("UnityFS\0fixture".utf8).write(to: bundleDir.appendingPathComponent("bundle"))
        let checks = try ModChecks.inspect(temp)
        XCTAssertTrue(checks.bundles)
        XCTAssertTrue(checks.content)
        XCTAssertEqual(Set(checks.warnings.map(\.code)), ["bundles", "windows-bundle"])
        try FileManager.default.removeItem(at: temp.appendingPathComponent("Bundles"))
        try Data("UnityFS\0fixture".utf8).write(to: temp.appendingPathComponent("no-extension"))
        XCTAssertTrue(try ModChecks.inspect(temp).bundles)
    }
    func testWarningsRecheckedBeforeAnyWrites() throws {
        let game = temp.appendingPathComponent("game")
        try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        let config = game.appendingPathComponent("OwlcatModificationManagerSettings.json")
        let original = Data(#"{"EnabledModifications":[]}"#.utf8)
        try original.write(to: config)
        let package = try ModIO.prepare(zip([
            "OwlcatModificationManifest.json": Data(#"{"UniqueName":"Test","Version":"1","Dependencies":["Lib-2"]}"#.utf8)
        ]))
        XCTAssertThrowsError(try ModIO.install(package, root: game, acceptedWarnings: []))
        XCTAssertEqual(try Data(contentsOf: config), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: game.appendingPathComponent("RogueModInstaller Backups").path))
        let accepted = Set(ModChecks.warnings(for: package.mod, installed: []).map(\.id))
        _ = try ModIO.install(package, root: game, acceptedWarnings: accepted)
        XCTAssertEqual(try ModIO.installed(root: game).first?.key, "Test")
    }
    func testMalformedRequirementsVisible() throws {
        let package = try ModIO.prepare(zip([
            "OwlcatModificationManifest.json": Data(#"{"UniqueName":"Test","Dependencies":{"Lib":"1"}}"#.utf8)
        ]))
        XCTAssertEqual(codes(package.mod), ["version", "requirements-metadata"])
        XCTAssertEqual(codes(mod("Test", requirements: ["../Lib"])), ["requirement-format"])
    }
}
