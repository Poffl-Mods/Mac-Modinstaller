import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ModCore

@MainActor final class InstallerModel: ObservableObject {
    @Published var root: URL?
    @Published var mods: [Mod] = []
    @Published var busy = false
    @Published var status = Message("ZIP hinzufügen, prüfen, installieren.")
    @Published var language: AppLanguage = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "de") ?? .de {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "interfaceLanguage") }
    }
    func t(_ key: String, _ args: String...) -> String { Localization.text(key, language: language, arguments: args) }
    func render(_ message: Message) -> String { Localization.text(message.key, language: language, arguments: message.arguments) }
    func cancelPreview() { preview = nil; if !busy { status = Message("ZIP hinzufügen, prüfen, installieren.") } }
    @Published var error: String?
    @Published var preview: PreparedMod?
    @Published var filter = ""
    var lastBackup: URL?
    let work = DispatchQueue(label: "de.poffl.roguemods.install", qos: .userInitiated)
    init() {
        if let saved = UserDefaults.standard.string(forKey: "gameData"), ModIO.isGameData(URL(fileURLWithPath: saved)) { root = URL(fileURLWithPath: saved) }
        else { let found = ModIO.candidates(); if found.count == 1 { root = found.first } }
        refresh()
    }
    func refresh() {
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
    func install() {
        guard let package = preview, let root, !busy, ensureGameClosed() else { return }
        preview = nil; busy = true; status = Message("{0} wird installiert …", package.mod.name)
        work.async {
            let result = Result { try ModIO.install(package, root: root) }
            DispatchQueue.main.async { self.complete(result, success: Message("{0} installiert und aktiviert. Spiel neu starten.", package.mod.name)) }
        }
    }
    func toggle(_ mod: Mod) {
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

@main struct RogueModInstallerApp: App {
    @StateObject var model = InstallerModel()
    var body: some Scene {
        WindowGroup("Mac-ModInstaller") {
            MainView(model: model).frame(minWidth: 820, minHeight: 590)
                .environment(\.locale, Locale(identifier: model.language.rawValue))
                .onOpenURL { model.prepare($0) }
        }
        .defaultSize(width: 940, height: 700)
        .commands { CommandGroup(replacing: .newItem) { Button(model.t("Mod-ZIP hinzufügen …")) { model.chooseZIP() }.keyboardShortcut("o").disabled(model.busy || model.preview != nil) } }
    }
}
struct MainView: View {
    @ObservedObject var model: InstallerModel
    @State private var hovering = false
    let accent = Color(red: 0.74, green: 0.53, blue: 0.24)
    var filtered: [Mod] { model.mods.filter { model.filter.isEmpty || $0.name.localizedCaseInsensitiveContains(model.filter) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 15) {
                Image(systemName: "shippingbox.fill").font(.system(size: 30)).foregroundStyle(accent)
                    .frame(width: 60, height: 60).background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mac-ModInstaller").font(.system(size: 27, weight: .bold, design: .rounded))
                    Text(model.t("Deine Mods. Ein Ort.")).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Text("ROGUE TRADER").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(.secondary)
                    Picker(model.t("Sprache"), selection: $model.language) {
                        ForEach(AppLanguage.allCases) { language in Text(language.name).tag(language) }
                    }.pickerStyle(.menu).frame(width: 220)
                }
            }
            HStack(spacing: 12) {
                Image(systemName: model.root == nil ? "folder.badge.questionmark" : "folder.badge.checkmark").foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.root == nil ? model.t("Spielordner nicht gefunden") : model.t("Spielordner verbunden")).font(.system(size: 12, weight: .semibold))
                    Text(model.root?.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") ?? model.t("Wähle die Benutzerdaten deiner Rogue-Trader-Installation."))
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(model.root?.path ?? "")
                }
                Spacer()
                Button(model.t("Ändern …")) { model.chooseRoot() }.disabled(model.busy || model.preview != nil)
            }.padding(14).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            VStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down").font(.system(size: 30, weight: .light)).foregroundStyle(accent)
                Text(hovering ? model.t("ZIP hier ablegen") : model.t("Mod-ZIP hierher ziehen")).font(.system(size: 17, weight: .semibold))
                Text(model.t("Owlcat und Unity Mod Manager werden automatisch erkannt.")).font(.system(size: 12)).foregroundStyle(.secondary)
                Button(model.t("ZIP auswählen …"), action: model.chooseZIP).buttonStyle(.borderedProminent).tint(accent).padding(.top, 3)
                    .disabled(model.busy || model.preview != nil)
            }.frame(maxWidth: .infinity).padding(.vertical, 23)
                .background(accent.opacity(hovering ? 0.13 : 0.035), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(accent.opacity(hovering ? 0.8 : 0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                .dropDestination(for: URL.self) { urls, _ in
                    guard !model.busy, model.preview == nil else { return false }
                    guard urls.count == 1, let url = urls.first else { model.error = model.t("Bitte eine ZIP-Datei auf einmal hinzufügen."); return false }
                    model.prepare(url); return true
                } isTargeted: { hovering = $0 }
            HStack {
                Text(model.t("Installierte Mods")).font(.headline)
                Text("\(model.mods.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                TextField(model.t("Suchen"), text: $model.filter).textFieldStyle(.roundedBorder).frame(width: 175)
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.help(model.t("Liste aktualisieren")).disabled(model.busy)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    if model.mods.isEmpty {
                        VStack(spacing: 8) {
                            Text(model.t("Platz für dein nächstes Abenteuer.")).font(.headline)
                            Text(model.t("Füge eine Mod-ZIP hinzu. Die App übernimmt Ordner und Aktivierung.")).font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 30)
                    } else if filtered.isEmpty { Text(model.t("Keine passenden Mods.")).foregroundStyle(.secondary).padding() }
                    ForEach(filtered) { mod in
                        HStack(spacing: 12) {
                            Image(systemName: mod.kind == .umm ? "puzzlepiece.extension" : "shippingbox").font(.title3).foregroundStyle(accent).frame(width: 30)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mod.name).font(.system(size: 13, weight: .semibold))
                                Text(model.t("Version {0}  ·  {1}", mod.version, mod.kind.rawValue)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { NSWorkspace.shared.open(mod.folder) } label: { Image(systemName: "folder") }.buttonStyle(.plain).help(model.t("Mod-Ordner öffnen"))
                            Toggle(mod.enabled ? model.t("Aktiv") : model.t("Inaktiv"), isOn: Binding(get: { mod.enabled }, set: { _ in model.toggle(mod) }))
                                .toggleStyle(.switch).controlSize(.small).frame(minWidth: 120).disabled(model.busy || model.preview != nil)
                        }.padding(.vertical, 13).padding(.horizontal, 12)
                        Divider()
                    }
                }
            }.frame(minHeight: 120)
            HStack(spacing: 9) {
                if model.busy { ProgressView().controlSize(.small) }
                else { Image(systemName: "info.circle").foregroundStyle(.secondary) }
                Text(model.render(model.status)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Spacer()
                Button(model.t("Sicherungen")) {
                    if let root = model.root { let folder = root.appendingPathComponent("RogueModInstaller Backups"); if FileManager.default.fileExists(atPath: folder.path) { NSWorkspace.shared.open(folder) } }
                }.font(.caption).disabled(model.root == nil)
            }
        }.padding(28).background(Color(nsColor: .windowBackgroundColor))
            .sheet(isPresented: Binding(get: { model.preview != nil }, set: { if !$0 { model.cancelPreview() } })) {
                if let package = model.preview { PreviewView(model: model, package: package) }
            }
            .alert(model.t("Bitte prüfen"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button(model.t("OK")) { model.error = nil }
            } message: { Text(model.error ?? "") }
    }
}
struct PreviewView: View {
    @ObservedObject var model: InstallerModel
    let package: PreparedMod
    var existing: Mod? { model.mods.first { $0.id == package.mod.id } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(existing == nil ? model.t("Mod hinzufügen") : model.t("Mod aktualisieren")).font(.title2.bold())
            Text(package.mod.name).font(.headline)
            Text(model.t("Version {0} · {1} · {2}", package.mod.version, package.mod.kind.rawValue, (Double(package.size) / 1_000_000).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: model.language.rawValue))) + " MB")).foregroundStyle(.secondary)
            if let existing { Text(model.t("Installiert: {0}. Die bisherige Version wird gesichert.", existing.version)).font(.callout) }
            Label(model.t("Wird installiert und aktiviert"), systemImage: "checkmark.circle").foregroundStyle(.green)
            Text(model.t("Ziel: {0}", package.mod.kind.folder + "/" + (existing?.folder.lastPathComponent ?? package.mod.key))).font(.callout).textSelection(.enabled)
            if !package.mod.requirements.isEmpty { Text(model.t("Benötigt: {0}", package.mod.requirements.joined(separator: ", "))).font(.callout) }
            if package.hasBundles {
                Label(model.t("Enthält AssetBundles. Verwende eine für macOS geeignete Ausgabe."), systemImage: "shippingbox").font(.callout)
            } else if package.mod.kind == .umm {
                Text(model.t("Die Spiel- und Harmony-Kompatibilität bestimmt der Mod. Die App installiert das Paket in den vorhandenen UMM.")).font(.callout).foregroundStyle(.secondary)
            }
            if model.root == nil { Text(model.t("Bitte zuerst im Hauptfenster den Spielordner auswählen.")).foregroundStyle(.orange) }
            HStack {
                Button(model.t("Abbrechen")) { model.cancelPreview() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(existing == nil ? model.t("Installieren") : model.t("Aktualisieren"), action: model.install).buttonStyle(.borderedProminent)
                    .disabled(model.root == nil).keyboardShortcut(.defaultAction)
            }.padding(.top, 10)
        }.padding(28).frame(width: 530)
    }
}
