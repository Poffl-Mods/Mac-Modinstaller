import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ModCore

@MainActor final class InstallerModel: ObservableObject {
    @Published var root: URL? { didSet { invalidateInventory() } }
    @Published var mods: [Mod] = []
    @Published var busy = false { didSet { invalidateInventory() } }
    @Published var status = Message("ZIP hinzufügen, prüfen, installieren.")
    @Published var language: AppLanguage = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "de") ?? .de {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "interfaceLanguage") }
    }
    func t(_ key: String, _ args: String...) -> String { Localization.text(key, language: language, arguments: args) }
    func render(_ message: Message) -> String { Localization.text(message.key, language: language, arguments: message.arguments) }
    func cancelPreview() { preview = nil; if !busy { status = Message("ZIP hinzufügen, prüfen, installieren.") } }
    @Published var error: String? { didSet { invalidateInventory() } }
    @Published var preview: PreparedMod? { didSet { invalidateInventory() } }
    @Published var filter = ""
    @Published var pendingToggle: Mod? { didSet { invalidateInventory() } }
    @Published var toggleWarnings: [ModWarning] = []
    func warnings(_ mod: Mod, replacing: Mod? = nil) -> [ModWarning] {
        ModChecks.warnings(for: mod, installed: mods, replacing: replacing)
    }
    var lastBackup: URL?
    let work = DispatchQueue(label: "de.poffl.roguemods.install", qos: .userInitiated)
    private var inventoryTimer: Timer?
    private var inventoryReadInFlight = false
    private var inventoryGeneration = 0
    private var appliedStamp: InventoryStamp?
    private var observedStamp: InventoryStamp?
    private var inventoryBlocked: Bool {
        busy || preview != nil || pendingToggle != nil || error != nil || NSApplication.shared.modalWindow != nil
    }
    private func invalidateInventory() {
        inventoryGeneration += 1
        appliedStamp = nil
        observedStamp = nil
    }
    init(defaults: UserDefaults = .standard, refreshInterval: TimeInterval = 2) {
        if let saved = defaults.string(forKey: "gameData"), ModIO.isGameData(URL(fileURLWithPath: saved)) { root = URL(fileURLWithPath: saved) }
        else { let found = ModIO.candidates(); if found.count == 1 { root = found.first } }
        refresh()
        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshAutomatically() }
        }
        inventoryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    deinit { inventoryTimer?.invalidate() }

    // Poll the small manifests/configurations, not mod payloads. No focus change is
    // needed, and replacing a whole mod directory or configuration is detected too.
    func refreshAutomatically() {
        guard let root, !inventoryBlocked, !inventoryReadInFlight else { return }
        inventoryReadInFlight = true
        let generation = inventoryGeneration
        let previous = observedStamp
        let applied = appliedStamp
        work.async {
            let result = Result { () throws -> (InventoryStamp, [Mod]?) in
                let stamp = try InventoryStamp(root: root)
                guard stamp != applied, stamp == previous else { return (stamp, nil) }
                let mods = try ModIO.installed(root: root)
                // Ignore a read spanning an external transaction; retry next poll.
                guard try InventoryStamp(root: root) == stamp else { return (stamp, nil) }
                return (stamp, mods)
            }
            DispatchQueue.main.async {
                self.inventoryReadInFlight = false
                guard self.root == root, self.inventoryGeneration == generation, !self.inventoryBlocked else { return }
                // Transient partial writes must not replace the list or open alerts.
                if case .success(let (stamp, mods)) = result {
                    self.observedStamp = stamp
                    if let mods { self.mods = mods; self.appliedStamp = stamp }
                }
            }
        }
    }
    func refresh() {
        guard !inventoryBlocked else { return }
        invalidateInventory()
        guard let root else { status = Message("Spielordner wählen oder Rogue Trader einmal starten."); mods = []; return }
        do { mods = try ModIO.installed(root: root) }
        catch { self.error = Localization.error(error, language: self.language) }
    }
    func chooseRoot() {
        let panel = NSOpenPanel(); panel.title = t("Rogue-Trader-Benutzerdaten wählen")
        panel.message = t("Ordner mit Modifications, UnityModManager oder Saved Games auswählen.")
        panel.prompt = t("Auswählen"); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.directoryURL = root ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        if panel.runModal() == .OK, let url = panel.url {
            guard ModIO.isGameData(url) else { error = t("Das ist kein erkennbarer Rogue-Trader-Benutzerdatenordner."); return }
            root = url; UserDefaults.standard.set(url.path, forKey: "gameData"); refresh()
        }
    }
    func chooseZIP() {
        let panel = NSOpenPanel(); panel.title = t("Mod-ZIP hinzufügen"); panel.allowedContentTypes = [.zip]
        panel.prompt = t("Auswählen"); panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { prepare(url) }
    }
    func prepare(_ url: URL) {
        guard !busy, preview == nil else { return }
        busy = true; status = Message("ZIP wird geprüft …")
        work.async {
            let result = Result { try ModIO.prepare(url) }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let package): self.preview = package; self.status = Message("Bereit zur Installation.")
                case .failure(let error): self.error = Localization.error(error, language: self.language); self.status = Message("ZIP konnte nicht hinzugefügt werden.")
                }
            }
        }
    }
    func ensureGameClosed() -> Bool {
        let running = NSWorkspace.shared.runningApplications.contains {
            let name = $0.executableURL?.lastPathComponent.lowercased() ?? ""
            let bundle = $0.bundleIdentifier?.lowercased() ?? ""
            return name == "wh40krt" || bundle.contains("warhammer-40000-rogue-trader") || bundle.contains("roguetrader")
        }
        if running { error = t("Bitte Rogue Trader vollständig beenden, damit das Spiel die Einstellungen nicht überschreibt.") }
        return !running
    }
    func install(acceptedWarnings: Set<String>) {
        guard let package = preview, let root, !busy, ensureGameClosed() else { return }
        preview = nil; busy = true; status = Message("{0} wird installiert …", package.mod.name)
        work.async {
            let result = Result { try ModIO.install(package, root: root, acceptedWarnings: acceptedWarnings) }
            DispatchQueue.main.async { self.complete(result, success: Message("{0} installiert und aktiviert. Spiel neu starten.", package.mod.name)) }
        }
    }
    func toggle(_ mod: Mod) {
        var prospective = mods
        if let index = prospective.firstIndex(where: { $0.id == mod.id }) { prospective[index].enabled.toggle() }
        if mod.enabled {
            // Disabling a dependency also affects mods which stay enabled.
            toggleWarnings = prospective.filter { $0.enabled && $0.id != mod.id }.flatMap { dependent in
                let before = Set(warnings(dependent).map(\.id))
                return ModChecks.warnings(for: dependent, installed: prospective).filter { !before.contains($0.id) }
            }
        } else { toggleWarnings = warnings(mod) }
        if !toggleWarnings.isEmpty { pendingToggle = mod; return }
        applyToggle(mod)
    }
    func applyToggle(_ mod: Mod) {
        guard let root, !busy, ensureGameClosed() else { return }
        busy = true; status = Message("Aktivierung wird gespeichert …")
        work.async {
            let result = Result { try ModIO.setEnabled(mod, root: root, enabled: !mod.enabled) }
            DispatchQueue.main.async { self.complete(result, success: Message(mod.enabled ? "{0} deaktiviert. Spiel neu starten." : "{0} aktiviert. Spiel neu starten.", mod.name)) }
        }
    }
    func complete(_ result: Result<URL, Error>, success: Message) {
        busy = false
        switch result {
        case .success(let backup): lastBackup = backup; status = success
        case .failure(let failure): error = Localization.error(failure, language: language); status = Message("Änderung nicht abgeschlossen.")
        }
        refresh()
    }
}

