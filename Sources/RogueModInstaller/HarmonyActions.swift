import AppKit
import ModCore
import SwiftUI
import UniformTypeIdentifiers

extension InstallerModel {
    func chooseHarmony() {
        guard !busy, preview == nil, harmonyInspection == nil, root != nil, ensureGameClosed() else { return }
        let panel = NSOpenPanel()
        panel.title = t("Rogue-Trader-Spiel-App auswählen")
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support/Steam/steamapps/common/Warhammer 40,000 Rogue Trader")
        guard panel.runModal() == .OK, let game = panel.url else { return }
        busy = true
        work.async {
            let result = Result { try HarmonyMaintenance.inspect(game: game) }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let report): self.harmonyInspection = report
                case .failure(let error): self.error = Localization.error(error, language: self.language)
                }
            }
        }
    }
    func updateHarmony() {
        guard let inspection = harmonyInspection, let root, !busy,
            !inspection.isInstalled, !inspection.isNewer, ensureGameClosed()
        else { return }
        busy = true
        status = Message("Harmony wird von GitHub geladen und geprüft …")
        Task {
            do {
                let zip = try await HarmonyMaintenance.download()
                guard ensureGameClosed() else {
                    try? FileManager.default.removeItem(at: zip)
                    busy = false
                    harmonyInspection = nil
                    return
                }
                work.async {
                    defer { try? FileManager.default.removeItem(at: zip) }
                    let result = Result {
                        try HarmonyMaintenance.install(zip, inspected: inspection, root: root)
                    }
                    DispatchQueue.main.async {
                        self.harmonyInspection = nil
                        if case .success(let backup) = result {
                            self.harmonyBackup = backup
                            UserDefaults.standard.set(backup.path, forKey: "harmonyBackup")
                        }
                        self.complete(
                            result,
                            success: Message("Harmony aktualisiert. Die ursprüngliche Datei wurde gesichert.")
                        )
                    }
                }
            } catch {
                harmonyInspection = nil
                busy = false
                self.error = Localization.error(error, language: language)
                status = Message("Änderung nicht abgeschlossen.")
            }
        }
    }
    func restoreHarmony() {
        guard let inspection = harmonyInspection, let root, let backup = harmonyBackup,
            !busy, ensureGameClosed()
        else { return }
        busy = true
        work.async {
            let result = Result {
                try HarmonyMaintenance.restore(backup, inspected: inspection, root: root)
                return backup
            }
            DispatchQueue.main.async {
                self.harmonyInspection = nil
                self.complete(
                    result, success: Message("Die ursprüngliche Harmony-Datei wurde wiederhergestellt."))
            }
        }
    }
    func chooseHarmonyBackup() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = t("Harmony-Sicherungsordner auswählen")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = root?.appendingPathComponent("RogueModInstaller Backups")
        if panel.runModal() == .OK { harmonyBackup = panel.url }
    }
}
