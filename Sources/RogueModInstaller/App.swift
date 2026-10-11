import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ModCore

@main struct RogueModInstallerApp: App {
    @StateObject var model = InstallerModel()
    init() {
        // Set the running Dock icon as well as the bundle icon, bypassing stale OS caches.
        if let url = Bundle.main.url(forResource: "CogitatorIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = icon
        }
    }
    var body: some Scene {
        WindowGroup("Mac-ModInstaller") {
            MainView(model: model).frame(minWidth: 860, minHeight: 700)
                .environment(\.locale, Locale(identifier: model.language.rawValue))
                .onOpenURL { model.prepare($0) }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshAutomatically() }
        }
        .defaultSize(width: 1000, height: 790)
        .commands { CommandGroup(replacing: .newItem) { Button(model.t("Mod-ZIP hinzufügen …")) { model.chooseZIP() }.keyboardShortcut("o").disabled(model.busy || model.preview != nil) } }
    }
}
struct MainView: View {
    @ObservedObject var model: InstallerModel
    @State private var hovering = false
    var filtered: [Mod] { model.mods.filter { model.filter.isEmpty || $0.name.localizedCaseInsensitiveContains(model.filter) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            connection
            intake
            inventory
            statusBar
            HStack {
                Rectangle().fill(Forge.brass.opacity(0.3)).frame(height: 1)
                Text(model.t("Gelobt sei der Omnissiah.").uppercased())
                    .font(.system(size: 9, design: .monospaced)).tracking(2).foregroundStyle(Forge.brass)
                    .fixedSize()
                Rectangle().fill(Forge.brass.opacity(0.3)).frame(height: 1)
            }.accessibilityHidden(true)
        }.padding(28).background(CogitatorBackdrop())
            .foregroundStyle(Forge.parchment).tint(Forge.phosphor)
            .buttonStyle(ForgeButtonStyle()).preferredColorScheme(.dark)
            .sheet(isPresented: Binding(get: { model.preview != nil }, set: { if !$0 { model.cancelPreview() } })) {
                if let package = model.preview { PreviewView(model: model, package: package) }
            }
            .confirmationDialog(model.t("Prüfhinweise"), isPresented: Binding(get: { model.pendingToggle != nil }, set: { if !$0 { model.pendingToggle = nil } }), titleVisibility: .visible) {
                Button(model.t("Trotzdem fortfahren")) {
                    if let mod = model.pendingToggle { model.pendingToggle = nil; model.applyToggle(mod) }
                }
                Button(model.t("Abbrechen"), role: .cancel) { model.pendingToggle = nil }
            } message: { Text(model.toggleWarnings.map { model.render($0.message) }.joined(separator: "\n\n")) }
            .alert(model.t("Bitte prüfen"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button(model.t("OK")) { model.error = nil }
            } message: { Text(model.error ?? "") }
    }
    private var header: some View {
        HStack(spacing: 18) {
            MachineSigil().frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 5) {
                Text("ROGUE TRADER  /  ADEPTUS MECHANICUS")
                    .font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2).foregroundStyle(Forge.brass)
                Text("Mac-ModInstaller").font(.system(size: 29, weight: .semibold, design: .serif))
                Text(model.t("Cogitator des Maschinenkults")).font(.system(size: 12, design: .monospaced)).foregroundStyle(Forge.muted)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 9) {
                Text("COGITATOR • MAC / LOCAL").font(.system(size: 9, design: .monospaced)).foregroundStyle(Forge.brass)
                Picker(model.t("Sprache"), selection: $model.language) {
                    ForEach(AppLanguage.allCases) { language in Text(language.name).tag(language) }
                }.pickerStyle(.menu).frame(width: 190)
            }
        }.padding(.bottom, 6)
    }
    private var connection: some View {
        HStack(spacing: 14) {
            Image(systemName: "externaldrive.connected.to.line.below").font(.system(size: 22)).foregroundStyle(Forge.brass)
            VStack(alignment: .leading, spacing: 6) {
                RiteHeading(index: "I", title: model.t("Verbindung zum Datenaltar"))
                Text(model.root == nil ? model.t("Spielordner nicht gefunden") : model.t("Spielordner verbunden"))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(model.root == nil ? Forge.brass : Forge.phosphor)
                Text(model.root?.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") ?? model.t("Wähle die Benutzerdaten deiner Rogue-Trader-Installation."))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Forge.muted)
                    .lineLimit(1).truncationMode(.middle).help(model.root?.path ?? "")
            }
            Spacer()
            Button(model.t("Ändern …")) { model.chooseRoot() }.disabled(model.busy || model.preview != nil)
        }.padding(16).forgePanel()
    }
    private var intake: some View {
        VStack(spacing: 12) {
            HStack {
                RiteHeading(index: "II", title: model.t("Ritus der Integration"))
                Spacer()
                Text("+ + +").font(.system(size: 10, design: .monospaced)).foregroundStyle(Forge.brass)
            }
            HStack(spacing: 24) {
                ZStack {
                    Circle().stroke(Forge.brass.opacity(0.3), lineWidth: 1).frame(width: 78, height: 78)
                    Circle().stroke(Forge.brass.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [2, 5])).frame(width: 94, height: 94)
                    Image(systemName: "square.and.arrow.down").font(.system(size: 30, weight: .light)).foregroundStyle(Forge.phosphor)
                }.frame(width: 100, height: 100).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 9) {
                    Text(hovering ? model.t("ZIP hier ablegen") : model.t("Mod-ZIP hierher ziehen"))
                        .font(.system(size: 21, weight: .medium, design: .serif))
                    Text(model.t("Owlcat und Unity Mod Manager werden automatisch erkannt."))
                        .font(.system(size: 12)).foregroundStyle(Forge.muted).fixedSize(horizontal: false, vertical: true)
                    Button(model.t("ZIP auswählen …"), action: model.chooseZIP)
                        .buttonStyle(ForgeButtonStyle(prominent: true)).disabled(model.busy || model.preview != nil)
                }
                Spacer(minLength: 0)
            }.padding(.vertical, 5)
        }.padding(18).background(Forge.phosphor.opacity(hovering ? 0.10 : 0.025)).forgePanel()
            .overlay(Rectangle().stroke(Forge.phosphor.opacity(hovering ? 0.9 : 0), lineWidth: 2))
            .dropDestination(for: URL.self) { urls, _ in
                guard !model.busy, model.preview == nil else { return false }
                guard urls.count == 1, let url = urls.first else { model.error = model.t("Bitte eine ZIP-Datei auf einmal hinzufügen."); return false }
                model.prepare(url); return true
            } isTargeted: { hovering = $0 }
    }
    private var inventory: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                RiteHeading(index: "III", title: model.t("Installierte Mods"))
                Text(String(format: "%02d", model.mods.count)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Forge.phosphor)
                Spacer()
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Forge.brass)
                    TextField(model.t("Suchen"), text: $model.filter).textFieldStyle(.plain)
                }.font(.system(size: 12)).padding(8).frame(width: 180)
                    .background(Forge.void).overlay(Rectangle().stroke(Forge.brass.opacity(0.25)))
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel(model.t("Liste aktualisieren")).help(model.t("Liste aktualisieren")).disabled(model.busy || model.preview != nil || model.pendingToggle != nil || model.error != nil)
            }.padding(14)
            Rectangle().fill(Forge.brass.opacity(0.25)).frame(height: 1)
            ScrollView {
                LazyVStack(spacing: 0) {
                    if model.mods.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "square.stack.3d.up").font(.system(size: 25, weight: .light)).foregroundStyle(Forge.brass)
                            Text(model.t("Das Datenarchiv erwartet deine Mods.")).font(.system(size: 17, design: .serif))
                            Text(model.t("Füge eine Mod-ZIP hinzu. Die App übernimmt Ordner und Aktivierung."))
                                .font(.system(size: 12)).foregroundStyle(Forge.muted)
                        }.frame(maxWidth: .infinity).padding(.vertical, 30)
                    } else if filtered.isEmpty {
                        Text(model.t("Keine passenden Mods.")).foregroundStyle(Forge.muted).padding(30)
                    }
                    ForEach(filtered) { mod in
                        modRow(mod)
                        Rectangle().fill(Forge.brass.opacity(0.13)).frame(height: 1)
                    }
                }
            }.frame(minHeight: 125)
        }.forgePanel()
    }
    private func modRow(_ mod: Mod) -> some View {
        HStack(spacing: 12) {
            Image(systemName: mod.kind == .umm ? "gearshape.2" : "shippingbox")
                .font(.system(size: 20)).foregroundStyle(Forge.brass).frame(width: 34)
            VStack(alignment: .leading, spacing: 5) {
                Text(mod.name).font(.system(size: 14, weight: .semibold))
                Text(model.t("Version {0}  ·  {1}", mod.version, mod.kind.rawValue))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Forge.muted)
                WarningList(model: model, warnings: model.warnings(mod))
            }
            Spacer()
            Button { NSWorkspace.shared.open(mod.folder) } label: { Image(systemName: "folder") }
                .accessibilityLabel(model.t("Mod-Ordner öffnen")).help(model.t("Mod-Ordner öffnen"))
            Toggle(mod.enabled ? model.t("Aktiv") : model.t("Inaktiv"), isOn: Binding(get: { mod.enabled }, set: { _ in model.toggle(mod) }))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(mod.enabled ? Forge.phosphor : Forge.muted)
                .toggleStyle(.switch).controlSize(.small).frame(minWidth: 120).disabled(model.busy || model.preview != nil)
        }.padding(.vertical, 14).padding(.horizontal, 16)
    }
    private var statusBar: some View {
        HStack(spacing: 12) {
            if model.busy { ProgressView().controlSize(.small) }
            else { Circle().fill(model.root == nil ? Forge.brass : Forge.phosphor).frame(width: 6, height: 6).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 4) {
                Text(model.t("Maschinengeist-Protokoll").uppercased())
                    .font(.system(size: 9, design: .monospaced)).tracking(1).foregroundStyle(Forge.brass)
                Text(model.render(model.status)).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Forge.muted).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(model.t("Sicherungen")) {
                if let root = model.root {
                    let folder = root.appendingPathComponent("RogueModInstaller Backups")
                    if FileManager.default.fileExists(atPath: folder.path) { NSWorkspace.shared.open(folder) }
                }
            }.disabled(model.root == nil)
        }.padding(12).forgePanel()
    }
}
struct PreviewView: View {
    @ObservedObject var model: InstallerModel
    let package: PreparedMod
    @State private var acknowledged = false
    var checks: [ModWarning] { model.warnings(package.mod, replacing: existing) }
    var existing: Mod? { model.mods.first { $0.id == package.mod.id } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                MachineSigil().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 5) {
                    RiteHeading(index: "II", title: model.t("Ritus der Integration"))
                    Text(existing == nil ? model.t("Mod hinzufügen") : model.t("Mod aktualisieren"))
                        .font(.system(size: 24, weight: .semibold, design: .serif))
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(package.mod.name).font(.system(size: 18, weight: .semibold, design: .serif))
                        Text(model.t("Version {0} · {1} · {2}", package.mod.version, package.mod.kind.rawValue, (Double(package.size) / 1_000_000).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: model.language.rawValue))) + " MB"))
                            .font(.system(size: 12, design: .monospaced)).foregroundStyle(Forge.muted)
                        if let existing { Text(model.t("Installiert: {0}. Die bisherige Version wird gesichert.", existing.version)).font(.callout) }
                        Label(model.t("Wird installiert und aktiviert"), systemImage: "checkmark.circle").foregroundStyle(Forge.phosphor)
                        Text(model.t("Ziel: {0}", package.mod.kind.folder + "/" + (existing?.folder.lastPathComponent ?? package.mod.key)))
                            .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        if !package.mod.requirements.isEmpty { Text(model.t("Benötigt: {0}", package.mod.requirements.joined(separator: ", "))).font(.callout) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(18).forgePanel()
                    if !checks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(model.t("Prüfhinweise")).font(.headline)
                            WarningList(model: model, warnings: checks)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).forgePanel()
                    }
                    if package.mod.kind == .umm {
                        Text(model.t("Die Spiel- und Harmony-Kompatibilität bestimmt der Mod. Die App installiert das Paket in den vorhandenen UMM.")).font(.callout).foregroundStyle(Forge.muted)
                    }
                    if model.root == nil { Text(model.t("Bitte zuerst im Hauptfenster den Spielordner auswählen.")).foregroundStyle(Forge.brass) }
                }
            }.frame(maxHeight: 440)
            if !checks.isEmpty {
                Toggle(model.t("Hinweise gelesen; trotzdem installieren."), isOn: $acknowledged)
                    .toggleStyle(.checkbox).font(.callout)
            }
            HStack {
                Button(model.t("Abbrechen")) { model.cancelPreview() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(existing == nil ? model.t("Installieren") : model.t("Aktualisieren")) { model.install(acceptedWarnings: Set(checks.map(\.id))) }
                    .buttonStyle(ForgeButtonStyle(prominent: true)).disabled(model.root == nil || (!checks.isEmpty && !acknowledged)).keyboardShortcut(.defaultAction)
            }.padding(.top, 6)
        }.padding(28).frame(width: 600).background(CogitatorBackdrop())
            .onChange(of: checks.map(\.id)) { _ in acknowledged = false }
            .foregroundStyle(Forge.parchment).buttonStyle(ForgeButtonStyle()).preferredColorScheme(.dark)
    }
}

struct WarningList: View {
    @ObservedObject var model: InstallerModel
    let warnings: [ModWarning]
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(warnings) { warning in
                Label(model.render(warning.message), systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(Forge.brass)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
