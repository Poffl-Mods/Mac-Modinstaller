import Foundation

public struct ModError: LocalizedError {
    public let message: String
    public let arguments: [String]
    public init(_ message: String, _ arguments: String...) {
        self.message = message
        self.arguments = arguments
    }
    public var errorDescription: String? { Localization.text(message, language: .de, arguments: arguments) }
}

public enum ModKind: String, Codable, Sendable {
    case owlcat = "Owlcat"
    case umm = "UMM"
    public var folder: String { self == .umm ? "UnityModManager" : "Modifications" }
}

public struct Mod: Identifiable, Sendable {
    public var id: String { kind.rawValue + ":" + key }
    public let key: String
    public let name: String
    public let version: String
    public let kind: ModKind
    public let folder: URL
    public var enabled: Bool
    public let requirements: [String]
    public var packageWarnings: [ModWarning] = []
    public var hasOwlcatContent = false
    public var bundlePlatforms: [BundlePlatform] = []
}

public final class PreparedMod: Sendable {
    public let mod: Mod
    public let hasBundles: Bool
    public let size: UInt64
    private let temp: URL
    init(mod: Mod, hasBundles: Bool, size: UInt64, temp: URL) {
        self.mod = mod
        self.hasBundles = hasBundles
        self.size = size
        self.temp = temp
    }
    deinit { try? FileManager.default.removeItem(at: temp) }
}

/// Shared entry point for mod discovery, package preparation and installation.
/// Implementations are grouped by responsibility in the ModIO extensions.
public enum ModIO {
    static let fm = FileManager.default
}
