// ============================================================================
//  MonitorMyMac — modèle d'état de l'onglet Performance
//  Auteur : Martial Zinsou
//  ============================================================================
//
//  Pilote les quatre actions de l'onglet : mémoire vive, éléments de démarrage,
//  scripts de maintenance, processus gourmands. Toutes les mesures sont lues
//  sur le système réel (`vm_stat`, `sysctl`, `ps`, `top`, `launchctl`) et les
//  opérations privilégiées passent par l'invite macOS.
// ============================================================================

import Foundation
import SwiftUI
import AppKit

/// État observable de l'onglet Performance.
final class PerformanceModel: ObservableObject {

    /// Instance unique : l'interface et le mode capture partagent le même état.
    static let shared = PerformanceModel()

    // -------------------------------------------------------------------------
    //  État publié
    // -------------------------------------------------------------------------

    /// Instantané mémoire courant (vide jusqu'à la première mesure réelle).
    @Published private(set) var snapshot = MemorySnapshot.empty
    /// Gain mesuré après le dernier `purge` (octets de mémoire inactive récupérés).
    @Published private(set) var lastPurgeGain: Int64?
    /// Date du dernier purge réussi.
    @Published private(set) var lastPurgeDate: Date?
    /// Processus les plus consommateurs (CPU/RAM).
    @Published private(set) var processes: [ProcessEntry] = []
    /// Énergie associée aux processus (nil par processus si `top` a échoué).
    @Published private(set) var energyAvailable = false
    /// Éléments de démarrage détectés.
    @Published private(set) var loginItems: [LoginItem] = []
    /// Tâches de maintenance et leurs sorties réelles.
    @Published private(set) var tasks: [MaintenanceTask] = MaintenanceScripts.tasks()
    /// Opération en cours ?
    @Published private(set) var isBusy = false
    /// Message d'état de la dernière opération.
    @Published private(set) var message = "Prêt."
    /// Sortie détaillée (maintenance) à afficher en bas de carte.
    @Published private(set) var consoleOutput = ""

    // -------------------------------------------------------------------------
    //  Rafraîchissement global
    // -------------------------------------------------------------------------

    /// Recharge mémoire, processus et éléments de démarrage.
    func refreshAll() {
        guard !isBusy else { return }
        isBusy = true
        message = "Lecture des compteurs système…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snapshot = MemorySnapshot.read()
            let entries = ProcessProbe.topConsumers(limit: 20)
            let energy = ProcessProbe.energyByPid()
            let merged: [ProcessEntry] = entries.map { entry in
                var mutable = entry
                mutable.energy = energy[entry.pid]
                return mutable
            }
            let items = StartupManager.items()
            DispatchQueue.main.async {
                self?.snapshot = snapshot
                self?.processes = merged
                self?.energyAvailable = !energy.isEmpty
                self?.loginItems = items
                self?.isBusy = false
                self?.message = "Mesures à jour (\(merged.count) processus suivis, \(items.count) éléments de démarrage)."
            }
        }
    }

    // -------------------------------------------------------------------------
    //  1. Libération de la mémoire vive
    // -------------------------------------------------------------------------

    /// Exécute `purge` avec droits administrateur et mesure le gain réel.
    ///
    /// La méthode compare la mémoire inactive + libre avant et après l'appel :
    /// le chiffre affiché provient de cette mesure, pas d'une estimation.
    func purgeMemory() {
        guard !isBusy else { return }
        isBusy = true
        let before = MemorySnapshot.read()
        message = "Authentification puis purge de la RAM…"
        SystemMonitor.shared.appendLog("Performance : purge de la mémoire vive demandée (\(Fmt.size(before.purgeable)) récupérables avant).")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = Shell.runWithAdmin("/usr/sbin/purge", timeout: 180)
            Thread.sleep(forTimeInterval: 1.0)
            let after = MemorySnapshot.read()
            let gain = max(0, after.purgeable - before.purgeable)
            DispatchQueue.main.async {
                self?.snapshot = after
                self?.isBusy = false
                if outcome.succeeded {
                    self?.lastPurgeGain = gain
                    self?.lastPurgeDate = Date()
                    self?.message = "Purge effectuée : \(Fmt.size(gain)) de plus récupérables "
                        + "(libre \(Fmt.size(after.free)), inactive \(Fmt.size(after.inactive)), "
                        + "soit \(Fmt.size(after.purgeable)) au total)."
                    SystemMonitor.shared.appendLog("  ↳ purge RAM : \(Fmt.size(gain)) de pages rendues disponibles.")
                } else {
                    self?.message = "Purge non exécutée : \(outcome.failure ?? "échec")"
                    SystemMonitor.shared.appendLog("  ↳ purge RAM annulée : \(outcome.failure ?? "échec")")
                }
            }
        }
    }

    /// Mémoire occupée par les applications, en pourcentage de la RAM totale.
    var memoryPressureRatio: Double { snapshot.pressure }

    // -------------------------------------------------------------------------
    //  2. Éléments de démarrage
    // -------------------------------------------------------------------------

    /// Désactive ou réactive un élément de démarrage.
    func toggle(_ item: LoginItem) {
        guard !isBusy else { return }
        isBusy = true
        message = item.disabledByApp ? "Réactivation de « \(item.title) »…" : "Désactivation de « \(item.title) »…"
        SystemMonitor.shared.appendLog("Démarrage : action sur « \(item.label) » (\(item.kind.rawValue)).")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = item.disabledByApp ? StartupManager.enable(item) : StartupManager.disable(item)
            let items = StartupManager.items()
            DispatchQueue.main.async {
                self?.loginItems = items
                self?.message = result
                self?.isBusy = false
                SystemMonitor.shared.appendLog("  ↳ \(result)")
            }
        }
    }

    /// Éléments réellement désactivés par l'app (pour le compteur de la carte).
    var disabledStartupCount: Int { loginItems.filter { $0.disabledByApp }.count }

    // -------------------------------------------------------------------------
    //  3. Scripts de maintenance
    // -------------------------------------------------------------------------

    /// Exécute une tâche de maintenance et conserve sa sortie réelle.
    func run(task: MaintenanceTask) {
        guard !isBusy else { return }
        isBusy = true
        message = task.needsAdmin == .no
            ? "Exécution : \(task.title)…"
            : "Exécution : \(task.title) (authentification macOS)…"
        SystemMonitor.shared.appendLog("Maintenance : \(task.title) — \(task.command)")

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let executed = MaintenanceScripts.run(task)
            DispatchQueue.main.async {
                if let index = self?.tasks.firstIndex(where: { $0.id == executed.id }) {
                    self?.tasks[index] = executed
                }
                self?.consoleOutput = "[\(executed.title)]\n\(executed.output)"
                self?.isBusy = false
                self?.message = executed.succeeded
                    ? "« \(task.title) » terminée."
                    : "« \(task.title) » : \(executed.output.prefix(160))"
                let firstLine = executed.output.split(separator: "\n").first.map(String.init) ?? ""
                SystemMonitor.shared.appendLog("  ↳ "
                    + (executed.succeeded ? "OK" : "échec") + " — \(firstLine)")
            }
        }
    }

    /// Enchaîne toutes les tâches (les tâches root déclenchent une invite).
    func runAll() {
        guard !isBusy else { return }
        let queue = tasks
        DispatchQueue.global(qos: .utility).async { [weak self] in
            for task in queue {
                DispatchQueue.main.async { self?.isBusy = true; self?.message = "Suite de maintenance : \(task.title)…" }
                let executed = MaintenanceScripts.run(task)
                DispatchQueue.main.async {
                    if let index = self?.tasks.firstIndex(where: { $0.id == executed.id }) {
                        self?.tasks[index] = executed
                    }
                    self?.consoleOutput += "\n[\(executed.title)]\n\(executed.output)"
                }
            }
            DispatchQueue.main.async {
                self?.isBusy = false
                self?.message = "Suite de maintenance exécutée : consulter les sorties de chaque carte."
                SystemMonitor.shared.appendLog("Maintenance : suite exécutée (\(queue.count) scripts).")
            }
        }
    }

    // -------------------------------------------------------------------------
    //  4. Processus gourmands
    // -------------------------------------------------------------------------

    /// Applications triées par CPU cumulé (helpers regroupés).
    var appConsumers: [AppConsumption] {
        return Array(ProcessProbe.groupedByApplication(processes).prefix(8))
    }

    /// Ferme toutes les instances d'une application (puis les pids restants).
    func quit(_ group: AppConsumption) {
        isBusy = true
        message = "Fermeture de « \(group.name) »…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var report: [String] = []
            // 1. Fermeture propre via NSRunningApplication si le nom correspond.
            for application in NSWorkspace.shared.runningApplications
            where application.localizedName == group.name {
                application.terminate()
                report.append("\(application.localizedName ?? group.name) : fermeture demandée.")
            }
            // 2. Signaux sur les pids restants de notre session.
            let entries = ProcessProbe.topConsumers(limit: 60)
            for pid in group.pids {
                guard let entry = entries.first(where: { $0.pid == pid }) else { continue }
                if entry.killable {
                    report.append("pid \(pid) (\(entry.name)) : \(ProcessProbe.terminate(entry))")
                } else {
                    report.append("pid \(pid) (\(entry.name)) : ignoré — \(entry.blockReason)")
                }
            }
            let text = report.joined(separator: "\n")
            let items = ProcessProbe.topConsumers(limit: 20)
            DispatchQueue.main.async {
                self?.processes = items
                self?.message = "Fermeture traitée : \(report.count) action(s)."
                self?.consoleOutput = text
                self?.isBusy = false
                SystemMonitor.shared.appendLog("Processus : \(report.first ?? "aucune action")")
            }
        }
    }

    /// Force la fermeture d'un processus précis.
    func terminate(_ entry: ProcessEntry) {
        guard entry.killable else {
            message = "pid \(entry.pid) : \(entry.blockReason)"
            return
        }
        let result = ProcessProbe.terminate(entry)
        message = "pid \(entry.pid) (\(entry.name)) : \(result)"
        SystemMonitor.shared.appendLog("Processus : \(message)")
        refreshAll()
    }

    // -------------------------------------------------------------------------
    //  Pratiques pour l'affichage
    // -------------------------------------------------------------------------

    /// Positionne la carte mémoire : jauge, détail, état.
    ///
    /// - Important : la RAM est rendue avec `Fmt.shortSize` (binaire, 1 Go =
    ///   1 073 741 824 o), comme l'onglet Surveillance. `Fmt.size` s'appuie sur
    ///   `ByteCountFormatter` en style « fichier » (décimal) et affichait
    ///   17,18 Go pour les mêmes 16,0 Go de la jauge — deux onglets, deux
    ///   chiffres pour une seule barrette.
    var memoryCardDetail: String {
        return "\(Fmt.shortSize(snapshot.used)) utilisés sur \(Fmt.shortSize(snapshot.total)) · "
             + "câblée \(Fmt.shortSize(snapshot.wired)) · compressée \(Fmt.shortSize(snapshot.compressed)) · "
             + "échange \(Fmt.shortSize(snapshot.swapUsed))"
    }

    /// Ce que « purge » pourrait rendre, sans droits administrateur.
    var purgeableEstimate: String { Fmt.shortSize(snapshot.purgeable) }
}
