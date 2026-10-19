import XCTest
@testable import ModCore

final class LocalizationTests: XCTestCase {
    func testAllLanguagesHaveCompleteCatalogAndMatchingPlaceholders() throws {
        let base = try XCTUnwrap(Localization.catalog["de"])
        XCTAssertGreaterThan(base.count, 80)
        let regex = try NSRegularExpression(pattern: #"\{\d+\}"#)
        func placeholders(_ value: String) -> [String] {
            regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).map {
                (value as NSString).substring(with: $0.range)
            }.sorted()
        }
        for language in AppLanguage.allCases {
            let translated = try XCTUnwrap(Localization.catalog[language.rawValue])
            XCTAssertEqual(Set(base.keys), Set(translated.keys), language.rawValue)
            for (key, value) in translated {
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertEqual(placeholders(key), placeholders(value), "\(language.rawValue): \(key)")
            }
        }
    }
    func testDistributedAppFindsPackagedResourcesOutsideBuildTree() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Portable.app")
        let resources = app.appendingPathComponent("Contents/Resources/RogueModInstaller_ModCore.bundle")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "test.portable", "CFBundlePackageType": "APPL", "CFBundleExecutable": "Portable"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        let translations = Data(#"{"en":{"key":"Packaged translation"}}"#.utf8)
        try translations.write(to: resources.appendingPathComponent("Translations.json"))
        let bundle = try XCTUnwrap(Bundle(url: app))
        let packaged = try XCTUnwrap(Localization.packagedResources(in: bundle))
        let url = try XCTUnwrap(packaged.url(forResource: "Translations", withExtension: "json"))
        XCTAssertEqual(try Data(contentsOf: url), translations)
        XCTAssertTrue(url.path.hasPrefix(root.path))
    }
    func testDynamicArgumentsAreNotTranslatedOrReinterpreted() {
        let name = "Orks {1}"
        XCTAssertEqual(Localization.text("Version {0}  ·  {1}", language: .es, arguments: [name, "UMM"]), "Versión Orks {1}  ·  UMM")
        XCTAssertEqual(Localization.text("{0} aktiviert. Spiel neu starten.", language: .en, arguments: [name]), "Orks {1} enabled. Restart the game.")
    }
    func testCoreErrorsUseSelectedLanguage() {
        let error = ModError("Ungültiges JSON: {0}", "settings.json")
        XCTAssertEqual(Localization.error(error, language: .fr), "JSON invalide : settings.json")
        XCTAssertEqual(Localization.error(error, language: .ru), "Некорректный JSON: settings.json")
        XCTAssertEqual(Localization.error(error, language: .zhHans), "JSON 无效：settings.json")
    }
}
