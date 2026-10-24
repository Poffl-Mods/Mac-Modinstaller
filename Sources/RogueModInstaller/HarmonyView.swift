import ModCore
import SwiftUI

struct HarmonyView: View {
    @ObservedObject var model: InstallerModel
    let inspection: HarmonyInspection
    @State private var acknowledged = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(model.t("Harmony für Mac …")).font(.title2)
            Text(model.t("Gemeinsame Harmony-Datei: {0}", inspection.game.path))
                .font(.caption).textSelection(.enabled)
            Text(
                model.t(
                    "Dateiversion: {0} · Angebotene Version: {1}",
                    inspection.fileVersion ?? model.t("Unbekannt"), HarmonyMaintenance.version))
            if inspection.isInstalled {
                Text(model.t("Diese Harmony-Ausgabe ist bereits installiert."))
                    .foregroundStyle(Forge.phosphor)
            } else if inspection.isNewer {
                Text(model.t("Eine neuere Harmony-Version ist vorhanden. Kein Downgrade durchgeführt."))
            }
            Text(
                model.t(
                    "Ersetzt die gemeinsame Harmony-DLL in der Spiel-App, nicht die DLLs einzelner Mods. Der Download erfolgt aus dem offiziellen Harmony-Release auf GitHub. Die ursprüngliche Datei wird gesichert."
                ))
            Text(
                model.t(
                    "Das verändert die Spiel-App und kann ihre Signatur ungültig machen. Spielupdates oder eine Dateiprüfung können die Änderung überschreiben. Eine Garantie für funktionierende Mods ist damit nicht verbunden."
                )
            )
            .foregroundStyle(Forge.brass)
            Toggle(
                model.t("Spiel geschlossen; Änderung an der Spiel-App und Sicherung verstanden."),
                isOn: $acknowledged
            )
            .toggleStyle(.checkbox).disabled(model.busy)
            if model.busy { ProgressView() }
            HStack {
                Button(model.t("Harmony-Sicherungsordner auswählen"), action: model.chooseHarmonyBackup)
                Button(model.t("Harmony wiederherstellen"), action: model.restoreHarmony)
                    .disabled(model.harmonyBackup == nil || !acknowledged)
            }.disabled(model.busy)
            if let backup = model.harmonyBackup {
                Text(backup.path).font(.caption).textSelection(.enabled)
            }
            HStack {
                Button(model.t("Abbrechen")) { model.harmonyInspection = nil }.disabled(model.busy)
                Spacer()
                Button(
                    model.t("Harmony {0} installieren", HarmonyMaintenance.version),
                    action: model.updateHarmony
                )
                .disabled(model.busy || !acknowledged || inspection.isInstalled || inspection.isNewer)
            }
        }
        .padding(26).frame(width: 640).fixedSize(horizontal: false, vertical: true)
        .background(CogitatorBackdrop()).foregroundStyle(Forge.parchment)
        .buttonStyle(ForgeButtonStyle()).preferredColorScheme(.dark)
        .interactiveDismissDisabled(model.busy)
        .onChange(of: model.harmonyBackup) { _ in acknowledged = false }
    }
}
