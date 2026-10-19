import XCTest
import ZIPFoundation
@testable import ModCore

final class AssetBundlePlatformTests: XCTestCase {
    var temp: URL!
    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: temp) }
    func number(_ value: UInt64, _ count: Int, little: Bool = false) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: value >> (8 * (little ? $0 : count - 1 - $0))) })
    }
    func serialized(_ target: Int32, little: Bool = true, version: UInt64 = 22) -> Data {
        let metadata = Data("6000.0.64f1\0".utf8) + number(UInt64(UInt32(bitPattern: target)), 4, little: little) + Data(repeating: 0, count: 20)
        let headerSize = version >= 22 ? 48 : 20
        let size = headerSize + metadata.count
        var header = number(UInt64(metadata.count), 4) + number(UInt64(size), 4) + number(version, 4) + number(UInt64(size), 4)
        header += Data([little ? 0 : 1, 0, 0, 0])
        if version >= 22 { header += number(UInt64(metadata.count), 4) + number(UInt64(size), 8) + number(UInt64(size), 8) + number(0, 8) }
        return header + metadata
    }
    func lz4(_ data: Data) -> Data {
        var output = Data([UInt8(min(data.count, 15) << 4)])
        if data.count >= 15 {
            var extra = data.count - 15
            while extra >= 255 { output.append(255); extra -= 255 }
            output.append(UInt8(extra))
        }
        return output + data
    }
    func bundle(_ assets: [Data], version: UInt64 = 7, codec: Int = 0, infoCodec: Int = 0, atEnd: Bool = false, padding: Bool = false, split: Int? = nil) -> Data {
        let raw = assets.reduce(Data(), +)
        let pieces: [Data] = split.map { [Data(raw.prefix($0)), Data(raw.dropFirst($0))] } ?? [raw]
        let packed = pieces.map { codec == 2 || codec == 3 ? lz4($0) : $0 }
        var info = Data(repeating: 0, count: 16) + number(UInt64(pieces.count), 4)
        for (index, piece) in pieces.enumerated() {
            info += number(UInt64(piece.count), 4) + number(UInt64(packed[index].count), 4) + number(UInt64(codec), 2)
        }
        info += number(UInt64(assets.count), 4)
        var offset: UInt64 = 0
        for (i, asset) in assets.enumerated() {
            info += number(offset, 8) + number(UInt64(asset.count), 8) + number(4, 4) + Data("CAB-\(i)\0".utf8)
            offset += UInt64(asset.count)
        }
        let packedInfo = infoCodec == 2 || infoCodec == 3 ? lz4(info) : info
        let flags = UInt64(infoCodec) | 0x40 | (atEnd ? 0x80 : 0) | (padding ? 0x200 : 0)
        let prefix = Data("UnityFS\0".utf8) + number(version, 4) + Data("5.x.x\0".utf8) + Data("6000.0.64f1\0".utf8)
        func header(_ length: Int) -> Data {
            prefix + number(UInt64(length), 8) + number(UInt64(packedInfo.count), 4) + number(UInt64(info.count), 4) + number(flags, 4)
        }
        var value = header(0)
        if version >= 7 { while value.count % 16 != 0 { value.append(0) } }
        if !atEnd { value += packedInfo }
        if padding { while value.count % 16 != 0 { value.append(0) } }
        value += packed.reduce(Data(), +)
        if atEnd { value += packedInfo }
        value.replaceSubrange(0..<header(0).count, with: header(value.count))
        return value
    }
    func inspect(_ bytes: Data, name: String = "test.bundle") throws -> BundlePlatform {
        let file = temp.appendingPathComponent(name)
        try bytes.write(to: file)
        return AssetBundleReader.inspect(file, path: name)
    }
    func testPlatformsAcrossCompressionAlignmentAndEndianVariants() throws {
        for target: Int32 in [2, 5, 19, 24, 13, -2, 9999] {
            for codec in [0, 2, 3] {
                for atEnd in [false, true] {
                    let result = try inspect(bundle([serialized(target, little: false)], codec: codec, infoCodec: codec, atEnd: atEnd, padding: true))
                    XCTAssertTrue(result.complete)
                    XCTAssertEqual(result.targets, [target])
                    XCTAssertEqual(result.isMac, target == 2)
                }
            }
        }
        for version: UInt64 in [6, 8] {
            let result = try inspect(bundle([serialized(19, version: 17)], version: version))
            XCTAssertEqual(result.targets, [19])
        }
    }
    func testMultipleAssetsAndHeaderSpanningBlocks() throws {
        let result = try inspect(bundle([serialized(2), serialized(19)], codec: 2, infoCodec: 3, atEnd: true, split: 13))
        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.targets, [2, 19])
        XCTAssertFalse(result.isMac)
    }
    func testTruncatedCorruptUnsupportedAndResourceLimitsStayUnknown() throws {
        let valid = bundle([serialized(2)], codec: 2)
        for count in 0..<valid.count { XCTAssertFalse(try inspect(Data(valid.prefix(count))).complete) }
        XCTAssertFalse(try inspect(bundle([serialized(2)], codec: 1)).complete)
        XCTAssertFalse(try inspect(bundle([serialized(2)], infoCodec: 1)).complete)
        XCTAssertFalse(try inspect(bundle([serialized(2)], version: 9)).complete)
        XCTAssertFalse(try inspect(bundle([Data(repeating: 0xff, count: 64)])).complete)
        XCTAssertFalse(try inspect(Data("UnityRaw\0garbage".utf8)).complete)
        XCTAssertThrowsError(try AssetBundleReader.decode(Data(), codec: 2, size: AssetBundleReader.limit + 1))
        XCTAssertThrowsError(try AssetBundleReader.decode(Data([0, 0, 0]), codec: 2, size: 4))
        XCTAssertThrowsError(try AssetBundleReader.decode(Data([0xff, 0xff]), codec: 2, size: 4))
        XCTAssertThrowsError(try AssetBundleReader.serializedTarget(serialized(2, version: 23), fileSize: 100))
    }
    func testLZ4OverlappingMatchesAndBounds() throws {
        // One literal 'a', then a match at distance 1, then five final literals.
        let packed = Data([0x10, 97, 1, 0, 0x50, 98, 99, 100, 101, 102])
        XCTAssertEqual(try AssetBundleReader.decode(packed, codec: 2, size: 10), Data("aaaaabcdef".utf8))
        XCTAssertThrowsError(try AssetBundleReader.decode(packed, codec: 2, size: 9))
    }
    func testChecksUseMetadataNotFilenameAndKeepUnknownWarnings() throws {
        let bundles = temp.appendingPathComponent("Bundles/macOS")
        try FileManager.default.createDirectory(at: bundles, withIntermediateDirectories: true)
        try bundle([serialized(19)]).write(to: bundles.appendingPathComponent("misleading-mac"))
        var checks = try ModChecks.inspect(temp)
        XCTAssertTrue(checks.bundles)
        XCTAssertEqual(checks.platforms.first?.targets, [19])
        XCTAssertEqual(checks.warnings.map(\.code), ["bundle-platform"])
        try bundle([serialized(2)]).write(to: bundles.appendingPathComponent("misleading-mac"))
        checks = try ModChecks.inspect(temp)
        XCTAssertTrue(checks.warnings.isEmpty)
        XCTAssertTrue(checks.platforms.first?.isMac == true)
        try Data("UnityFS\0broken".utf8).write(to: bundles.appendingPathComponent("unknown"))
        XCTAssertEqual(try ModChecks.inspect(temp).warnings.map(\.code), ["bundles"])
    }
    func testPreparedMacBundleKeepsPresenceWithoutGenericWarning() throws {
        let folder = temp.appendingPathComponent("package")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"UniqueName":"Test","Version":"1"}"#.utf8).write(to: folder.appendingPathComponent("OwlcatModificationManifest.json"))
        try bundle([serialized(2)]).write(to: folder.appendingPathComponent("asset"))
        let zip = temp.appendingPathComponent("mod.zip")
        try FileManager.default.zipItem(at: folder, to: zip)
        let prepared = try ModIO.prepare(zip)
        XCTAssertTrue(prepared.hasBundles)
        XCTAssertEqual(prepared.mod.bundlePlatforms.first?.targets, [2])
        XCTAssertTrue(prepared.mod.packageWarnings.isEmpty)
    }
    func testWindowsBundleRequiresAcknowledgementAndInstalledScanRetainsPlatform() throws {
        let folder = temp.appendingPathComponent("package")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"UniqueName":"Test","Version":"1"}"#.utf8).write(to: folder.appendingPathComponent("OwlcatModificationManifest.json"))
        try bundle([serialized(19)], codec: 2).write(to: folder.appendingPathComponent("asset"))
        let zip = temp.appendingPathComponent("mod.zip")
        try FileManager.default.zipItem(at: folder, to: zip)
        let prepared = try ModIO.prepare(zip)
        let game = temp.appendingPathComponent("game")
        try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        let config = game.appendingPathComponent("OwlcatModificationManagerSettings.json")
        let original = Data(#"{"EnabledModifications":[]}"#.utf8)
        try original.write(to: config)
        XCTAssertThrowsError(try ModIO.install(prepared, root: game, acceptedWarnings: []))
        XCTAssertEqual(try Data(contentsOf: config), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: game.appendingPathComponent("RogueModInstaller Backups").path))
        let warnings = ModChecks.warnings(for: prepared.mod, installed: [])
        XCTAssertTrue(warnings.contains { $0.code == "bundle-platform" })
        _ = try ModIO.install(prepared, root: game, acceptedWarnings: Set(warnings.map(\.id)))
        let installed = try XCTUnwrap(ModIO.installed(root: game).first)
        XCTAssertEqual(installed.bundlePlatforms.first?.targets, [19])
        XCTAssertTrue(installed.packageWarnings.contains { $0.code == "bundle-platform" })
    }
    func testLocalRealMacBundleWhenAvailable() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("../RogueTrader-Modding/Build/ArmouryOrks/Bundles/ArmouryOrks_BlueprintDirectReferences").standardizedFileURL
        guard FileManager.default.fileExists(atPath: file.path) else { throw XCTSkip("Optional local Unity-built bundle is not distributed") }
        let result = AssetBundleReader.inspect(file, path: file.lastPathComponent)
        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.targets, [2])
    }
}
