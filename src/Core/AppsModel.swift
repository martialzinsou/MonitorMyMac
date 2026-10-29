// ============================================================================
//  MonitorMyMac — modèle d'état de l'onglet Applications
//  Auteur : Martial Zinsou
//  ============================================================================
//
//  Gère trois écrans : inventaire + désinstallation complète, contrôle des
//  mises à jour, gestion des extensions (macOS et navigateurs).
//
//  La désinstallation est le seul endroit de l'application où un bundle de
//  `/Applications` peut être supprimé : elle exige une validation explicite
//  (`approveUninstall`) et quitte proprement l'application avant l'action.
// ============================================================================

import Foundation
import SwiftUI
import AppKit

/// État observable de l'onglet Applications.
final class AppsModel: ObservableObject {

    /// Instance unique : l'interface et le mode capture partagent le même état.
    static let shared = AppsModel()

    // -------------------------------------------------------------------------
    //  État publié
    // -------------------------------------------------------------------------

    /// Applications inventoriées (triées par taille décroissante).
    @Published private(set) var apps: [ManagedApp] = []
    /// Résidus de l'application examinée.
    @Published private(set) var residuals: [FileRecord] = []
    /// Application dont les résidus sont affichés.
    @Published private(set) var inspectedApp: ManagedApp?
    /// Chemins de résidus sélectionnés.
    @Published var residualSelection: Set<String> = []
    /// Bundles sélectionnés pour la désinstallation.
    @Published var uninstallSelection: Set<String> = []
    /// Bilan du contrôle de mises à jour.
    @Published private(set) var updates = UpdateAudit()
    /// Greffons macOS (`pluginkit`).
    @Published private(set) var plugins: [PluginEntry] = []
    /// Extensions de navigateurs.
    @Published private(set) var browserExtensions: [BrowserExtension] = []
    /// Filtre de recherche des deux listes.
    @Published var filter = ""
    /// Opération en cours ?
    @Published private(set) var isBusy = false
    /// Message d'état.
    @Published private(set) var message = "Aucun inventaire : lancez le balayage."
    /// Mode de suppression des fichiers.
    @Published var mode: DeletionMode = .trash
    /// Inclure les résidus dans la désinstallation.
    @Published var includeResiduals = true

    /// Applications correspondant au filtre.
    var visibleApps: [ManagedApp] {
        guard !filter.isEmpty else { return apps }
        let needle = filter.lowercased()
        return apps.filter { $0.name.lowercased().contains(needle)
            || ($0.bundleId ?? "").lowercased().contains(needle) }
    }

    /// Greffons correspondant au filtre.
    var visiblePlugins: [PluginEntry] {
        guard !filter.isEmpty else { return plugins }
        let needle = filter.lowercased()
        return plugins.filter { $0.identifier.lowercased().contains(needle)
            || $0.host.lowercased().contains(needle) }
    }

    /// Extensions de navigateurs correspondant au filtre.
    var visibleBrowserExtensions: [BrowserExtension] {
        guard !filter.isEmpty else { return browserExtensions }
        let needle = filter.lowercased()
        return browserExtensions.filter { $0.name.lowercased().contains(needle)
            || $0.browser.lowercased().contains(needle) }
    }

    /// Espace cumulé des applications inventoriées.
    var totalAppBytes: Int64 { apps.reduce(Int64(0)) { $0 + $1.sizeBytes } }

    /// Nombre de widgets repérés.
    var widgetCount: Int { plugins.filter { $0.isWidget }.count }

    // -------------------------------------------------------------------------
    //  Balayages
    // -------------------------------------------------------------------------

    /// Inventorie les applications installées.
    func scanApps() {
        guard !isBusy else { return }
        isBusy = true
        message = "Inventaire des applications…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let deadline = Date().addingTimeInterval(60)
            let found = AppsScanner.scan(deadline: deadline)
            DispatchQueue.main.async {
                self?.apps = found
                self?.isBusy = false
                self?.message = "\(found.count) applications inventoriées · "
                    + "\(Fmt.size(found.reduce(Int64(0)) { $0 + $1.sizeBytes })) au total."
                SystemMonitor.shared.appendLog("Applications : \(found.count) bundles inventoryés.")
            }
        }
    }

    /// Analyse les résidus d'une application (sans rien supprimer).
    func inspect(_ app: ManagedApp) {
        inspectedApp = app
        residuals = []
        residualSelection = []
        message = "Recherche des résidus de « \(app.name) »…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = ResidualScanner.residuals(for: app)
            DispatchQueue.main.async {
                self?.residuals = found
                self?.residualSelection = Set(found.filter { $0.deletable }.map(\.id))
                self?.message = "\(found.count) emplacement(s) trouvé(s) pour « \(app.name) » · "
                    + "\(Fmt.size(ResidualScanner.userResidualSize(found))) de résidus utilisateur."
            }
        }
    }

    /// Balayage combiné des extensions macOS et navigateurs.
    func scanExtensions() {
        guard !isBusy else { return }
        isBusy = true
        message = "Lecture des extensions (pluginkit + navigateurs)…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let plugins = ExtensionManager.plugins()
            let browser = ExtensionManager.browserExtensions()
            DispatchQueue.main.async {
                self?.plugins = plugins
                self?.browserExtensions = browser
                self?.isBusy = false
                self?.message = "\(plugins.count) greffons macOS · \(browser.count) extensions de navigateurs · "
                    + "\(plugins.filter { $0.isWidget }.count) widgets."
                SystemMonitor.shared.appendLog("Extensions : \(plugins.count) greffons et \(browser.count) extensions de navigateurs lus.")
            }
        }
    }

    /// Contrôle des mises à jour (Apple + Homebrew + canaux non vérifiables).
    func auditUpdates() {
        guard !isBusy else { return }
        isBusy = true
        message = "Interrogation de softwareupdate (peut prendre une minute)…"
        let snapshot = apps
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let audit = UpdateProber.audit(apps: snapshot)
            DispatchQueue.main.async {
                self?.updates = audit
                self?.isBusy = false
                let appleText = audit.apple.isEmpty ? "aucune mise à jour Apple" : "\(audit.apple.count) mise(s) à jour Apple"
                let brewText = audit.brewMissing ? " · Homebrew absent"
                    : (audit.brew.isEmpty ? " · Homebrew à jour" : " · \(audit.brew.count) via Homebrew")
                self?.message = "Contrôle terminé : \(appleText)\(brewText)."
                SystemMonitor.shared.appendLog("Mises à jour : \(appleText)\(brewText).")
            }
        }
    }

    // -------------------------------------------------------------------------
    //  Actions
    // -------------------------------------------------------------------------

    /// Désinstalle les applications sélectionnées, avec ou sans résidus.
    func uninstallSelected() {
        let chosen = apps.filter { uninstallSelection.contains($0.id) }
        guard !chosen.isEmpty, !isBusy else {
            message = "Aucune application sélectionnée dans la liste."
            return
        }
        isBusy = true
        let includeResiduals = self.includeResiduals
        let chosenMode = mode
        message = "Désinstallation de \(chosen.count) application(s)…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var report = DeletionReport()

            for app in chosen {
                let bundleURL = app.url
                // 1. Fermeture propre si l'application tourne.
                if app.isRunning,
                   let running = NSWorkspace.shared.runningApplications.first(where: {
                       $0.bundleURL == bundleURL }) {
                    running.terminate()
                    Thread.sleep(forTimeInterval: 1.2)
                    if !running.isTerminated { running.forceTerminate() }
                }
                // 2. Autorisation explicite du bundle, puis suppression.
                PathPolicy.approveUninstall(bundleURL)
                var urls = [bundleURL]
                if includeResiduals {
                    urls.append(contentsOf: ResidualScanner.residuals(for: app)
                        .filter { $0.deletable }.map(\.url))
                }
                report.merge(DeleteOps.apply(urls, mode: chosenMode))
                PathPolicy.revokeUninstallApprovals()
            }

            let deadline = Date().addingTimeInterval(60)
            let refreshed = AppsScanner.scan(deadline: deadline)
            DispatchQueue.main.async {
                PathPolicy.revokeUninstallApprovals()
                self?.apps = refreshed
                self?.uninstallSelection = []
                self?.residuals = []
                self?.inspectedApp = nil
                self?.isBusy = false
                self?.message = report.summary
                SystemMonitor.shared.appendLog("Désinstallation : \(report.summary)")
                for failure in report.failures.prefix(4) {
                    SystemMonitor.shared.appendLog("  ↳ échec \(Fmt.prettyPath(failure.path)) : \(failure.message)")
                }
            }
        }
    }

    /// Supprime uniquement les résidus sélectionnés de l'application examinée.
    func deleteSelectedResiduals() {
        let urls = residuals.filter { residualSelection.contains($0.id) }.map(\.url)
        guard !urls.isEmpty, !isBusy else { return }
        isBusy = true
        let chosenMode = mode
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let report = DeleteOps.apply(urls, mode: chosenMode)
            guard let app = self?.inspectedApp else { return }
            let remaining = ResidualScanner.residuals(for: app)
            DispatchQueue.main.async {
                self?.residuals = remaining
                self?.residualSelection = Set(remaining.filter { $0.deletable }.map(\.id))
                self?.isBusy = false
                self?.message = "Résidus : \(report.summary)"
                SystemMonitor.shared.appendLog("Résidus de « \(app.name) » : \(report.summary)")
            }
        }
    }

    /// Active ou désactive un greffon macOS.
    func setPlugin(_ plugin: PluginEntry, on: Bool) {
        let result = ExtensionManager.setEnabled(plugin, on: on)
        message = result
        SystemMonitor.shared.appendLog("Extensions : \(result)")
        scanExtensions()
    }

    /// Désenregistre un greffon (invalidation réversible).
    func invalidate(_ plugin: PluginEntry) {
        let result = ExtensionManager.invalidate(plugin)
        message = result
        SystemMonitor.shared.appendLog("Extensions : \(result)")
        scanExtensions()
    }

    /// Ouvre la page de gestion des extensions d'un navigateur.
    func openManagement(for browser: String) {
        let result = ExtensionManager.openManagementPage(for: browser)
        message = result
        SystemMonitor.shared.appendLog("Extensions : \(result)")
    }

    /// Désinstalle une extension de navigateur sélectionnée.
    func uninstallBrowserExtensions(_ entries: [BrowserExtension]) {
        guard !entries.isEmpty, !isBusy else { return }
        isBusy = true
        let chosenMode = mode
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var report = DeletionReport()
            var refused: [String] = []
            for entry in entries {
                if entry.browserRunning {
                    refused.append("\(entry.name) : \(entry.browser) est ouvert.")
                    continue
                }
                report.merge(DeleteOps.apply([URL(fileURLWithPath: entry.directory)], mode: chosenMode))
            }
            let refreshed = ExtensionManager.browserExtensions()
            DispatchQueue.main.async {
                self?.browserExtensions = refreshed
                self?.isBusy = false
                self?.message = report.summary + (refused.isEmpty ? "" : " · \(refused.count) navigateur(s) ouvert(s)")
                SystemMonitor.shared.appendLog("Extensions navigateurs : \(self?.message ?? "")")
            }
        }
    }

    /// Sélectionne/désélectionne un bundle dans la liste de désinstallation.
    func toggleUninstall(_ app: ManagedApp) {
        guard !app.isSystemLocation else { return }
        if uninstallSelection.contains(app.id) { uninstallSelection.remove(app.id) }
        else { uninstallSelection.insert(app.id) }
    }

    /// Met l'application en quarantaine de sécurité (déplacement réversible).
    func isolate(_ app: ManagedApp) -> String {
        PathPolicy.approveUninstall(app.url)
        defer { PathPolicy.revokeUninstallApprovals() }
        return Quarantine.isolate(app.url).map { "« \(app.name) » déplacé vers \(Fmt.prettyPath($0.path))." }
            ?? "Quarantaine impossible : autorisations refusées sur \(app.name)."
    }

    /// Met l'application en quarantaine et publie le résultat réel.
    func quarantine(_ app: ManagedApp) {
        let result = isolate(app)
        message = result
        SystemMonitor.shared.appendLog("Applications : \(result)")
        scanApps()
    }

    /// Ouvre l'emplacement de l'application dans le Finder.
    func revealInFinder(_ app: ManagedApp) {
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }

    /// Espace des bundles + résidus sélectionnés.
    var uninstallFootprint: Int64 {
        let bundles = apps.filter { uninstallSelection.contains($0.id) }.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let residue = includeResiduals
            ? residuals.filter { residualSelection.contains($0.id) }.reduce(Int64(0)) { $0 + $1.size }
            : 0
        return bundles + residue
    }
}
