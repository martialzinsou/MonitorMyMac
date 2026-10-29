// ============================================================================
//  MonitorMyMac — modèle d'état de l'onglet Sécurité
//  Auteur : Martial Zinsou
//  ============================================================================
//
//  Pilote les trois modules : traces de navigation, analyse de sécurité,
//  broyeur de fichiers. Comme ailleurs, rien n'est supprimé sans balayage
//  préalable ; la quarantaine est réversible ; le broyeur explique ses limites.
// ============================================================================

import Foundation
import SwiftUI
import AppKit

/// État observable de l'onglet Sécurité.
final class SecurityModel: ObservableObject {

    /// Instance unique : l'interface et le mode capture partagent le même état.
    static let shared = SecurityModel()

    // -------------------------------------------------------------------------
    //  État publié
    // -------------------------------------------------------------------------

    /// Traces de navigation détectées.
    @Published private(set) var traces: [BrowserTrace] = []
    /// Traces sélectionnées pour l'effacement.
    @Published var traceSelection: Set<String> = []
    /// Constats de l'analyse de sécurité.
    @Published private(set) var findings: [ThreatFinding] = []
    /// Fichier en cours d'examen de sécurité.
    @Published private(set) var assessment: String?
    /// Files d'attente du broyeur.
    @Published private(set) var shredQueue: [URL] = []
    /// Résultats de broyage (journal réel).
    @Published private(set) var shredResults: [ShredOutcome] = []
    /// Éléments mis en quarantaine.
    @Published private(set) var quarantined: [FileRecord] = []
    /// Mode de suppression des traces.
    @Published var mode: DeletionMode = .trash
    /// Nombre de passes du broyeur.
    @Published var passes: Int = 3
    /// Filtre de sévérité (nil = tout).
    @Published var severityFilter: ThreatSeverity?
    /// Opération en cours ?
    @Published private(set) var isBusy = false
    /// Message d'état.
    @Published var message = "Aucune analyse effectuée."

    /// Traces groupées par navigateur (pour les cartes).
    var tracesByBrowser: [BrowserTraceGroup] {
        var buckets: [String: (total: Int64, items: [BrowserTrace])] = [:]
        for trace in traces {
            var bucket = buckets[trace.browser] ?? (0, [])
            bucket.total += trace.size
            bucket.items.append(trace)
            buckets[trace.browser] = bucket
        }
        return buckets
            .map { BrowserTraceGroup(browser: $0.key, total: $0.value.total, items: $0.value.items) }
            .sorted { $0.total > $1.total }
    }

    /// Constats filtrés selon la sévérité choisie.
    var visibleFindings: [ThreatFinding] {
        guard let severityFilter = severityFilter else { return findings }
        return findings.filter { $0.severity == severityFilter }
    }

    /// Compteurs par sévérité (pastilles de la carte).
    var severityCounts: [ThreatCount] {
        return ThreatSeverity.allCases.map { severity in
            ThreatCount(severity: severity, count: findings.filter { $0.severity == severity }.count)
        }
    }

    /// Espace des traces sélectionnées.
    var selectedTraceBytes: Int64 {
        return traces.filter { traceSelection.contains($0.id) }.reduce(Int64(0)) { $0 + $1.size }
    }

    /// Navigateurs ouverts (alerte préalable à l'effacement).
    var runningBrowsers: [String] {
        return Array(Set(traces.filter { $0.browserRunning }.map(\.browser))).sorted()
    }

    // -------------------------------------------------------------------------
    //  Balayages
    // -------------------------------------------------------------------------

    /// Balaye les traces de navigation réelles.
    func scanTraces() {
        guard !isBusy else { return }
        isBusy = true
        message = "Recherche des traces de navigation…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let deadline = Date().addingTimeInterval(30)
            let found = BrowserData.traces(deadline: deadline)
            DispatchQueue.main.async {
                self?.traces = found
                self?.traceSelection = Set(found.filter { !$0.browserRunning && $0.readable
                    && $0.kind != .downloads }.map(\.id))
                self?.isBusy = false
                let bytes = found.reduce(Int64(0)) { $0 + $1.size }
                self?.message = "\(found.count) trace(s) sur "
                    + "\(Set(found.map(\.browser)).count) navigateur(s) · \(Fmt.size(bytes))."
                SystemMonitor.shared.appendLog("Sécurité : \(found.count) traces de navigation balayées (\(Fmt.size(bytes))).")
            }
        }
    }

    /// Analyse de sécurité complète (signatures + heuristiques + posture).
    func scanThreats(apps: [ManagedApp], plugins: [PluginEntry]) {
        guard !isBusy else { return }
        isBusy = true
        message = "Analyse de sécurité (signatures locales et heuristiques)…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let deadline = Date().addingTimeInterval(45)
            let found = SecurityScanner.scan(apps: apps, plugins: plugins, deadline: deadline)
            let quarantine = Quarantine.items()
            DispatchQueue.main.async {
                self?.findings = found
                self?.quarantined = quarantine
                self?.isBusy = false
                let confirmed = found.filter { $0.severity == .confirmed }.count
                let suspicious = found.filter { $0.severity == .suspicious }.count
                self?.message = found.isEmpty
                    ? "Aucun élément signalé. Rappel : détection par signatures, pas une garantie antivirus."
                    : "\(confirmed) signature(s) connue(s), \(suspicious) élément(s) suspect(s), "
                      + "\(found.count - confirmed - suspicious) information(s)."
                SystemMonitor.shared.appendLog("Sécurité : analyse terminée — \(confirmed) confirmé(s), \(suspicious) suspect(s).")
            }
        }
    }

    /// Vérification ciblée d'une application (codesign + Gatekeeper).
    func assess(_ app: ManagedApp) {
        isBusy = true
        message = "Vérification de « \(app.name) » (codesign + Gatekeeper)…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let report = SecurityScanner.assess(app)
            DispatchQueue.main.async {
                self?.assessment = report
                self?.isBusy = false
                self?.message = "Vérification de « \(app.name) » terminée."
                SystemMonitor.shared.appendLog("Sécurité : vérification de \(app.name) — "
                    + (report.split(separator: "\n").first.map(String.init) ?? ""))
            }
        }
    }

    // -------------------------------------------------------------------------
    //  Actions
    // -------------------------------------------------------------------------

    /// Efface les traces sélectionnées (les navigateurs ouverts sont épargnés).
    func clearSelectedTraces() {
        let chosen = traces.filter { traceSelection.contains($0.id) }
        guard !chosen.isEmpty, !isBusy else {
            message = "Aucune trace sélectionnée : relancez le balayage puis cochez."
            return
        }
        let blocked = chosen.filter { $0.browserRunning }
        let eligible = chosen.filter { !$0.browserRunning }
        guard !eligible.isEmpty else {
            message = "Tous les navigateurs concernés sont ouverts : fermez-les d'abord."
            return
        }
        isBusy = true
        let chosenMode = mode
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let report = DeleteOps.apply(eligible.map(\.url), mode: chosenMode)
            let deadline = Date().addingTimeInterval(30)
            let refreshed = BrowserData.traces(deadline: deadline)
            DispatchQueue.main.async {
                self?.traces = refreshed
                self?.traceSelection = []
                self?.isBusy = false
                var text = "Traces effacées : \(report.summary)"
                if !blocked.isEmpty {
                    text += " · \(blocked.count) trace(s) ignorée(s) (navigateur ouvert)"
                }
                if !report.blocked.isEmpty {
                    text += " · \(report.blocked.count) refus(s) par la politique de sécurité"
                }
                self?.message = text
                SystemMonitor.shared.appendLog("Navigation : \(text)")
            }
        }
    }

    /// Met un constat en quarantaine (déplacement réversible).
    func quarantine(_ finding: ThreatFinding) {
        let url = URL(fileURLWithPath: finding.path)
        guard finding.actionable else {
            message = "Quarantaine impossible pour « \(finding.title) » : \(PathPolicy.reason(for: url) ?? "élément non modifiable")."
            return
        }
        if let placed = Quarantine.isolate(url) {
            message = "« \(finding.title) » mis en quarantaine : \(Fmt.prettyPath(placed.path))."
            SystemMonitor.shared.appendLog("Sécurité : quarantaine de \(finding.title) (\(finding.signature)).")
            refreshQuarantine()
            recheckAfterAction()
        } else {
            message = "Quarantaine refusée par macOS (droits insuffisants ou élément protégé)."
        }
    }

    /// Supprime définitivement un constat (après quarantaine généralement).
    func delete(_ finding: ThreatFinding) {
        let url = URL(fileURLWithPath: finding.path)
        let report = DeleteOps.apply([url], mode: .permanent)
        message = report.summary
        SystemMonitor.shared.appendLog("Sécurité : suppression de \(finding.title) — \(report.summary)")
        recheckAfterAction()
    }

    /// Restaure un élément quarantainé.
    func restore(_ record: FileRecord) {
        message = Quarantine.restore(record.url)
            ? "Élément restauré à son emplacement d'origine."
            : "Restauration impossible : l'emplacement d'origine est indisponible."
        refreshQuarantine()
    }

    /// Vide la liste de quarantaine (suppression définitive).
    func purgeQuarantine() {
        let urls = Quarantine.items().map(\.url)
        guard !urls.isEmpty else { message = "Quarantaine déjà vide."; return }
        let report = DeleteOps.apply(urls, mode: .permanent)
        message = "Quarantaine purgée : \(report.summary)"
        SystemMonitor.shared.appendLog("Sécurité : quarantaine purgée (\(report.summary)).")
        refreshQuarantine()
    }

    /// Recharge la liste des éléments quarantainés.
    func refreshQuarantine() {
        quarantined = Quarantine.items()
    }

    /// Relance une analyse légère après une action destructive.
    private func recheckAfterAction() {
        refreshQuarantine()
        let deadline = Date().addingTimeInterval(20)
        findings = SecurityScanner.scan(apps: [], plugins: [], deadline: deadline)
            .filter { $0.severity != .informational || $0.title != "Accès complet au disque" }
    }

    // -------------------------------------------------------------------------
    //  Broyeur de fichiers
    // -------------------------------------------------------------------------

    /// Ajoute des fichiers ou dossiers au broyeur (sélecteur ou glisser-déposer).
    func enqueue(_ urls: [URL]) {
        let accepted = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        shredQueue.append(contentsOf: accepted.filter { !shredQueue.contains($0) })
        message = accepted.isEmpty
            ? "Aucun fichier valide à broyer."
            : "\(shredQueue.count) élément(s) en attente de broyage."
    }

    /// Retire un élément de la file sans le broyer.
    func dequeue(_ url: URL) {
        shredQueue.removeAll { $0 == url }
    }

    /// Broye toute la file, puis vide la file des éléments traités.
    func shredAll() {
        guard !shredQueue.isEmpty, !isBusy else {
            message = shredQueue.isEmpty ? "File du broyeur vide." : "Broyage déjà en cours."
            return
        }
        isBusy = true
        let queue = shredQueue
        let passes = self.passes
        message = "Broyage de \(queue.count) élément(s) en \(passes) passe(s)…"
        SystemMonitor.shared.appendLog("Broyeur : \(queue.count) élément(s), \(passes) passe(s).")

        DispatchQueue.global(qos: .utility).async { [weak self] in
            var outcomes: [ShredOutcome] = []
            let deadline = Date().addingTimeInterval(600)
            for url in queue {
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                if isDirectory.boolValue {
                    outcomes.append(contentsOf: FileShredder.shredDirectory(url, passes: passes, deadline: deadline))
                } else {
                    outcomes.append(FileShredder.shred(url, passes: passes))
                }
                DispatchQueue.main.async {
                    self?.shredResults = outcomes
                }
            }
            let bytes = outcomes.reduce(Int64(0)) { $0 + $1.bytesOverwritten }
            let failures = outcomes.compactMap(\.error)
            DispatchQueue.main.async {
                self?.isBusy = false
                self?.shredQueue = []
                self?.message = failures.isEmpty
                    ? "Broyage terminé : \(Fmt.size(bytes)) écrasés, \(outcomes.count) fichier(s) détruit(s)."
                    : "Broyage partiel : \(outcomes.count - failures.count) réussi(s), \(failures.count) échec(s)."
                SystemMonitor.shared.appendLog("Broyeur : \(self?.message ?? "") — "
                    + (failures.first.map { "premier échec : \($0)" } ?? ""))
            }
        }
    }

    /// Ouvre le sélecteur macOS et ajoute le choix à la file du broyeur.
    func pickForShredder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Ajouter à la file"
        panel.message = "Ces éléments seront écrasés puis supprimés définitivement (voir l'avertissement ci-dessous)."
        if panel.runModal() == .OK {
            enqueue(panel.urls)
        }
    }

    /// Choisis une application dans le Finder puis vérifie sa signature.
    func pickAndAssess() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.prompt = "Vérifier"
        panel.message = "codesign --verify et spctl --assess seront exécutés sur ce bundle."
        guard panel.runModal() == .OK, let url = panel.url,
              let app = AppsScanner.app(at: url) else {
            message = "Vérification annulée."
            return
        }
        assess(app)
    }

    /// Taille cumulée de la file du broyeur.
    var shredQueueBytes: Int64 {
        return shredQueue.reduce(Int64(0)) { $0 + Walker.size(of: $1) }
    }

    /// Avertissement honnête affiché sous le broyeur.
    var shredderDisclaimer: String {
        return "Écrasement réel des octets puis unlink. Sur APFS/SSD, macOS pratique le "
            + "copy-on-write et le TRIM : d'anciens blocs peuvent survivre à l'écrasement, "
            + "et les instantanés Local Time Machine gardent une copie. Pour des données "
            + "sensibles, la seule garantie robuste reste FileVault (chiffrement du volume)."
    }
}
