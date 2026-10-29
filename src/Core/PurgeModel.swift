// ============================================================================
//  MonitorMyMac — modèle d'état de l'onglet Purge
//  Auteur : Martial Zinsou
//  ============================================================================
//
//  `PurgeModel` orchestre le cycle « balayer → examiner → agir » :
//
//    • `scan()`    lance les sept balayages les uns après les autres, hors du
//      fil principal, en publiant une progression textuelle ;
//    • la sélection est explicite (`Set<String>` de chemins) et l'espace
//      correspondant est chiffré en temps réel (`selectedBytes`) ;
//    • `act()` applique la suppression selon le mode choisi (corbeille par
//      défaut) et produit un `DeletionReport` fidèle (succès, échecs, blocages) ;
//    • les actions qui exigent root (corbeilles de volumes, logs système)
//      passent par l'invite macOS officielle.
// ============================================================================

import Foundation
import SwiftUI
import AppKit

/// État observable de l'onglet Purge.
final class PurgeModel: ObservableObject {

    /// Instance unique : l'interface et le mode capture partagent le même état.
    static let shared = PurgeModel()

    // -------------------------------------------------------------------------
    //  État publié
    // -------------------------------------------------------------------------

    /// Sections issues du dernier balayage.
    @Published private(set) var sections: [PurgeSection] = []
    /// Chemins sélectionnés pour la prochaine action.
    @Published var selection: Set<String> = []
    /// Balayage en cours ?
    @Published private(set) var isScanning = false
    /// Action de suppression en cours ?
    @Published private(set) var isActing = false
    /// Texte d'avancement (« Balayage des doublons… », etc.).
    @Published private(set) var progress = "Aucun balayage."
    /// Réglages (persistés dans `UserDefaults`).
    @Published var settings = PurgeSettings.load()
    /// Mode de suppression (corbeille réversible par défaut).
    @Published var mode: DeletionMode = .trash
    /// Rapport de la dernière action.
    @Published private(set) var lastReport: DeletionReport?
    /// Sortie brute de la dernière commande administrateur.
    @Published private(set) var lastAdminOutput: String?
    /// Espace total récupéré pendant cette session.
    @Published private(set) var sessionFreed: Int64 = 0

    // -------------------------------------------------------------------------
    //  Balayage
    // -------------------------------------------------------------------------

    /// Lance l'ensemble des balayages (asynchrone, fil utilisateur).
    func scan() {
        guard !isScanning, !isActing else { return }
        isScanning = true
        lastReport = nil
        selection = []
        settings.save()
        let snapshot = settings
        let started = Date()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var built: [PurgeSection] = []

            let steps: [(String, (Date) -> PurgeSection)] = [
                ("Caches utilisateur", { PurgeEngine.userCaches(days: snapshot.cacheAgeDays, deadline: $0) }),
                ("Logs et diagnostics", { PurgeEngine.systemJunk(days: snapshot.junkAgeDays, deadline: $0) }),
                ("Restes de mises à jour", { PurgeEngine.updateLeftovers(deadline: $0) }),
                ("Fichiers volumineux et anciens", {
                    PurgeEngine.largeAndOldFiles(sizeMB: snapshot.largeMinSizeMB,
                                                 ageDays: snapshot.largeMinAgeDays,
                                                 extraFolders: snapshot.extraFolders, deadline: $0)
                }),
                ("Doublons (empreinte SHA-256)", {
                    PurgeEngine.duplicates(minSizeMB: snapshot.duplicateMinSizeMB,
                                           extraFolders: snapshot.extraFolders, deadline: $0)
                }),
                ("Corbeilles", { PurgeEngine.trashLocations(deadline: $0) }),
                ("Traductions inutilisées", { PurgeEngine.unusedTranslations(deadline: $0) })
            ]

            for (label, build) in steps {
                self.publishProgress("Balayage : \(label)…")
                let deadline = Date().addingTimeInterval(22)
                let section = build(deadline)
                built.append(section)
            }

            let elapsed = Int(Date().timeIntervalSince(started))
            self.publishProgress("Balayage terminé en \(elapsed) s.")
            DispatchQueue.main.async {
                self.sections = built
                self.applyDefaultSelection(built)
                self.isScanning = false
                SystemMonitor.shared.appendLog("Purge : balayage terminé (\(built.count) familles analysées en \(elapsed) s).")
            }
        }
    }

    /// Pré-sélectionne ce qui est sûr ; laisse les données utilisateur décochées.
    private func applyDefaultSelection(_ sections: [PurgeSection]) {
        var chosen: Set<String> = []
        for section in sections where section.executable && section.risk != .caution {
            chosen.formUnion(section.defaultSelected)
        }
        selection = chosen
    }

    // -------------------------------------------------------------------------
    //  Sélection
    // -------------------------------------------------------------------------

    /// Espace représenté par la sélection courante.
    var selectedBytes: Int64 {
        var total: Int64 = 0
        for section in sections {
            for record in section.records where selection.contains(record.id) {
                total += record.size
            }
        }
        return total
    }

    /// Nombre d'éléments réellement concernés par la sélection.
    var selectedCount: Int {
        var count = 0
        for section in sections {
            for record in section.records where selection.contains(record.id) {
                count += record.members.isEmpty ? 1 : record.members.count
            }
        }
        return count
    }

    /// Case à cocher d'un élément.
    func isSelected(_ record: FileRecord) -> Bool { selection.contains(record.id) }

    /// Bascule la sélection d'un élément.
    func toggle(_ record: FileRecord) {
        guard record.deletable else { return }
        if selection.contains(record.id) { selection.remove(record.id) }
        else { selection.insert(record.id) }
    }

    /// Sélectionne ou désélectionne toute une section.
    func setSelection(_ section: PurgeSection, on: Bool) {
        guard section.executable else { return }
        for record in section.records {
            guard record.deletable, record.risk != .manualOnly else { continue }
            if on { selection.insert(record.id) } else { selection.remove(record.id) }
        }
    }

    /// Éléments URL effectivement supprimables pour la sélection courante.
    private func selectedURLs() -> [URL] {
        var urls: [URL] = []
        for section in sections {
            for record in section.records where selection.contains(record.id) {
                urls.append(contentsOf: record.members.isEmpty ? [record.url] : record.members)
            }
        }
        return urls
    }

    // -------------------------------------------------------------------------
    //  Action
    // -------------------------------------------------------------------------

    /// Supprime la sélection selon le mode choisi, puis relance un balayage.
    func act() {
        let urls = selectedURLs()
        guard !urls.isEmpty, !isActing, !isScanning else {
            publishProgress(mode == .trash
                ? "Rien de sélectionné : cochez des éléments après balayage."
                : "Rien de sélectionné.")
            return
        }
        isActing = true
        let chosenMode = mode
        SystemMonitor.shared.appendLog("Purge : suppression de \(urls.count) élément(s) — mode « \(chosenMode.rawValue) ».")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var aggregate = DeletionReport()
            // Par lots de 200 pour publier une progression utile.
            var index = 0
            while index < urls.count {
                let slice = Array(urls[index..<min(index + 200, urls.count)])
                aggregate.merge(DeleteOps.apply(slice, mode: chosenMode))
                index += 200
                self.publishProgress("Suppression : \(min(index, urls.count)) / \(urls.count)…")
            }

            DispatchQueue.main.async {
                self.lastReport = aggregate
                self.sessionFreed += aggregate.freedBytes
                self.isActing = false
                self.selection = []
                SystemMonitor.shared.appendLog("  ↳ \(aggregate.summary)")
                for failure in aggregate.failures.prefix(5) {
                    SystemMonitor.shared.appendLog("     échec \(Fmt.prettyPath(failure.path)) : \(failure.message)")
                }
                for blocked in aggregate.blocked.prefix(5) {
                    SystemMonitor.shared.appendLog("     bloqué \(Fmt.prettyPath(blocked.path)) : \(blocked.reason)")
                }
                if aggregate.freedBytes > 0 && !chosenMode.freesImmediately {
                    SystemMonitor.shared.appendLog("     rappel : mode corbeille → l'espace est libéré une fois la corbeille vidée.")
                }
                self.scan()
            }
        }
    }

    /// Vide les corbeilles des volumes externes avec droits administrateur.
    func emptyVolumeTrashesWithAdmin() {
        isActing = true
        publishProgress("Vidage des corbeilles de volumes (authentification macOS)…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let command = "for d in /Volumes/*/.Trashes; do [ -d \"$d\" ] && rm -rf \"$d\"/* 2>/dev/null; done; echo terminé"
            let outcome = Shell.runWithAdmin(command, timeout: 300)
            DispatchQueue.main.async {
                self?.lastAdminOutput = outcome.failure ?? outcome.excerpt
                self?.isActing = false
                self?.publishProgress(outcome.succeeded
                    ? "Corbeilles de volumes vidées."
                    : "Vidage des volumes non effectué : \(outcome.failure ?? "échec")")
                SystemMonitor.shared.appendLog("Corbeilles de volumes : "
                    + (outcome.succeeded ? "vidées (droits administrateur)." : "non vidées — \(outcome.failure ?? "échec")"))
            }
        }
    }

    /// Vide le courrier indésirable de Mail via AppleScript (commande officielle).
    func emptyMailJunk() {
        isActing = true
        publishProgress("Vidage du courrier indésirable de Mail…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = Shell.appleScript("""
            if application "Mail" is running then
                tell application "Mail" to empty junk mail
                return "ok"
            else
                return "Mail n'est pas ouvert"
            end if
            """, timeout: 60)
            DispatchQueue.main.async {
                self?.lastAdminOutput = outcome.failure ?? outcome.excerpt
                self?.isActing = false
                self?.publishProgress(outcome.succeeded
                    ? "Mail a vidé son courrier indésirable."
                    : "Impossible : \(outcome.failure ?? "échec") (autorisation « Automation » requise)")
                SystemMonitor.shared.appendLog("Courrier indésirable Mail : "
                    + (outcome.succeeded ? "vidé." : "non vidé — \(outcome.failure ?? "échec")"))
            }
        }
    }

    /// Ajoute un dossier personnel à l'analyse (gros fichiers et doublons).
    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Analyser ce dossier"
        panel.message = "MonitorMyMac ajoutera ce dossier à la recherche de fichiers volumineux et de doublons (aucune suppression automatique)."
        if panel.runModal() == .OK, let url = panel.url {
            guard !settings.extraFolders.contains(url.path) else { return }
            settings.extraFolders.append(url.path)
            SystemMonitor.shared.appendLog("Purge : dossier ajouté à l'analyse — \(Fmt.prettyPath(url.path)).")
            scan()
        }
    }

    /// Retire un dossier d'analyse supplémentaire.
    func removeFolder(_ path: String) {
        settings.extraFolders.removeAll { $0 == path }
        scan()
    }

    // -------------------------------------------------------------------------
    //  Helpers
    // -------------------------------------------------------------------------

    /// Publie un texte d'avancement sur le fil principal.
    private func publishProgress(_ text: String) {
        DispatchQueue.main.async { self.progress = text }
    }

    /// Temps de dernière modification connu le plus récent (info de carte).
    var lastScanSummary: String {
        let bytes = sections.reduce(Int64(0)) { $0 + $1.totalBytes }
        return "\(sections.count) famille(s) · \(Fmt.size(bytes)) signalés"
    }
}
