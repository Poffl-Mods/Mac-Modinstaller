import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case en, de, fr, es, ru
    case zhHans = "zh-Hans"
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .en: return "English"
        case .de: return "Deutsch"
        case .fr: return "Français"
        case .es: return "Español"
        case .ru: return "Русский"
        case .zhHans: return "简体中文"
        }
    }
}
public struct Message: Sendable {
    public let key: String
    public let arguments: [String]
    public init(_ key: String, _ arguments: String...) { self.key = key; self.arguments = arguments }
}
public enum Localization {
    static let catalog: [String: [String: String]] = {
        guard let url = Bundle.module.url(forResource: "Translations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return catalog
    }()
    public static func text(_ key: String, language: AppLanguage, arguments: [String] = []) -> String {
        let template = catalog[language.rawValue]?[key] ?? catalog["en"]?[key] ?? key
        let regex = try! NSRegularExpression(pattern: #"\{(\d+)\}"#)
        let result = NSMutableString(string: template)
        for match in regex.matches(in: template, range: NSRange(location: 0, length: result.length)).reversed() {
            let index = Int((template as NSString).substring(with: match.range(at: 1)))!
            if arguments.indices.contains(index) { result.replaceCharacters(in: match.range, with: arguments[index]) }
        }
        return result as String
    }
    public static func error(_ error: Error, language: AppLanguage) -> String {
        if let error = error as? ModError { return text(error.message, language: language, arguments: error.arguments) }
        return text("Der Vorgang konnte nicht abgeschlossen werden. Details: {0}", language: language, arguments: [error.localizedDescription])
    }
}
