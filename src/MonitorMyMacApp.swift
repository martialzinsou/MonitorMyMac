// ============================================================================
//  MonitorMyMac — Application native macOS (SwiftUI)
//  Auteur : Martial Zinsou
//  ============================================================================
//
//  ARCHITECTURE GÉNÉRALE
//  ---------------------
//
//  MonitorMyMac est une application macOS 100 % native écrite en Swift + SwiftUI.
//  Elle propose huit onglets regroupés en quatre familles :
//
//    • SURVEILLANCE  — CPU, mémoire, stockage, matériel et historique en direct.
//    • PURGE         — sept familles balayées sur le disque : caches, journaux
//      et diagnostics, restes de mises à jour, traductions inutilisées, gros
//      fichiers anciens, doublons (SHA‑256) et corbeilles.
//    • PERFORMANCE   — purge de la RAM mesurée, processus gourmands, éléments
//      de démarrage et scripts de maintenance (permissions, Spotlight).
//    • APPLICATIONS  — inventaire, désinstallation complète (bundle + résidus),
//      mises à jour centralisées et extensions (pluginkit + navigateurs).
//    • SÉCURITÉ      — données de navigation, analyse anti‑malware par
//      signatures locales, quarantaine réversible, vérification de signature et
//      broyeur de fichiers.
//    • AIDE / FAQ / À PROPOS — fonctionnement expliqué, commandes réellement
//      appelées, limites assumées et captures d'écran de l'application elle‑même.
//
//  L'application propose également :
//      • une icône dans la barre de menus macOS (taux CPU en direct, accès
//        direct aux huit sections) ;
//      • des graphiques d'historique (courbes de tendance CPU & RAM) ;
//      • des rappels hebdomadaires de nettoyage par notifications ;
//      • un menu « Actions » et un menu « Navigation » avec raccourcis clavier.
//
//  COMPILATION (sans Xcode) :
//  -------------------------
//      ./build.sh                    # deux tranches (x86_64 + arm64), lipo, signature
//      ./build.sh --typecheck        # typage sous la cible macOS 11.0
//      ./build.sh --shots            # puis lance l'auto-capture des onglets
//      ./run.sh                      # compile et ouvre l'application
//
//  PRÉREQUIS : macOS 11.0 (Big Sur) ou supérieur, Intel ou Apple Silicon.
//  Le binaire produit est Universel 2 ; la tranche arm64 est compilée depuis
//  n'importe quelle machine, mais ne s'exécute que sur Apple Silicon.
//
//  STRUCTURE DU FICHIER :
//  ----------------------
//    1. SystemMonitor      — service observable (singleton) au cœur de l'app.
//    2. CPU / Memory / Disk— collecteurs de métriques système.
//    3. Device             — informations statiques (modèle, macOS, uptime).
//    4. Cleaner            — nettoyage et optimisation « express ».
//    5. Reminder           — rappels hebdomadaires via UserNotifications.
//    6. MenuBarDelegate    — icône de barre de menus + menu + notifications.
//    7. ContentView        — interface principale (en-tête, onglets, journal).
//    8. Cartes UI          — GaugeCard, DiskCard, SystemCard, HistoryChartCard.
//    9. ReminderCard       — interrupteur du rappel hebdomadaire.
//   10. Point d'entrée     — struct MonitorMyMacApp (@main) et ses menus.
//
//  Les onglets lourds vivent dans `src/UI/` (PurgeView, PerformanceView,
//  AppsView, SecurityView, DocsViews) et leurs moteurs dans `src/Core/`.
// ============================================================================

import SwiftUI
import AppKit
import UserNotifications
import Foundation

// ============================================================================
//  MARK: - SystemMonitor : service observable principal
//  ============================================================================

/// Service observable qui alimente l'ensemble de l'interface utilisateur.
///
/// Cette classe est un **singleton** (`SystemMonitor.shared`) afin que la fenêtre
/// principale et l'icône de la barre de menus partagent les mêmes données.
///
/// Responsabilités :
///   - collecter les métriques (CPU, RAM, disque) en temps réel ;
///   - conserver un historique des mesures pour les graphiques ;
///   - exécuter les opérations de nettoyage et d'optimisation ;
///   - gérer les rappels hebdomadaires et la barre de menus.
final class SystemMonitor: ObservableObject {

    /// Instance partagée de l'application (utilisée aussi par la barre de menus).
    static let shared = SystemMonitor()

    // -------------------------------------------------------------------------
    //  Métriques exposées à l'interface (observables)
    // -------------------------------------------------------------------------

    /// Taux d'utilisation du processeur, ratio entre 0.0 et 1.0.
    @Published var cpuUsage: Double = 0
    /// Texte « convivial » décrivant l'utilisation CPU (ex. « 45 % »).
    @Published var cpuDetail: String = "En attente…"
    /// Taux d'utilisation de la mémoire vive, ratio entre 0.0 et 1.0.
    @Published var memoryUsage: Double = 0
    /// Texte décrivant la mémoire (ex. « 6,2 Go utilisés sur 16,0 Go »).
    @Published var memoryDetail: String = "En attente…"
    /// Taux d'occupation du disque, ratio entre 0.0 et 1.0.
    @Published var diskUsage: Double = 0
    /// Texte décrivant l'espace disque (ex. « 21 Go utilisés / 640 Go »).
    @Published var diskDetail: String = "En attente…"
    /// Version du système d'exploitation (ex. « macOS 13.7.8 »).
    @Published var osInfo: String = "macOS"
    /// Modèle commercial du Mac (ex. « MacBook Pro »).
    @Published var modelInfo: String = "—"
    /// Marque et modèle du processeur.
    @Published var cpuName: String = "—"
    /// Nombre de cœurs logiques.
    @Published var coreCount: String = "—"
    /// Mémoire physique totale (ex. « 16 Go »).
    @Published var totalMemoryGB: String = "—"
    /// Durée d'activité de la machine (ex. « 3 jours »).
    @Published var uptime: String = "—"
    /// Journal texte consignant les actions effectuées.
    @Published var log: String = ""
    /// Message de statut affiché dans le pied de page (ex. « Prêt »).
    @Published var statusMessage: String = "Prêt"
    /// Indique si une opération (« Nettoyage » / « Optimisation ») est en cours.
    @Published var isProcessing = false
    /// Historique du taux CPU (dernier échantillon en fin de tableau).
    @Published var cpuHistory: [Double] = []
    /// Historique du taux mémoire (dernier échantillon en fin de tableau).
    @Published var memoryHistory: [Double] = []
    /// Activation des rappels hebdomadaires (persistée dans `UserDefaults`).
    @Published var remindersEnabled: Bool {
        didSet {
            // Sauvegarde du choix de l'utilisateur puis (dé)programmation.
            UserDefaults.standard.set(remindersEnabled, forKey: "weeklyReminderEnabled")
            if remindersEnabled {
                Reminder.scheduleWeeklyCleanup()
            } else {
                Reminder.cancelWeeklyCleanup()
            }
        }
    }

    // -------------------------------------------------------------------------
    //  Gestion du rafraîchissement en direct
    // -------------------------------------------------------------------------

    /// Minuteur périodique qui rafraîchit les métriques toutes les 2 secondes.
    private var refreshTimer: Timer?
    /// Nombre maximal de points d'historique (2 min à 2 s = 60 points).
    private let historyCapacity = 60

    /// Constructeur privé : l'accès passe obligatoirement par `SystemMonitor.shared`.
    private init() {
        // Restaure la préférence utilisateur enregistrée précédemment.
        remindersEnabled = UserDefaults.standard.bool(forKey: "weeklyReminderEnabled")
    }

    // -------------------------------------------------------------------------
    //  Cycle de vie : démarrage du rafraîchissement
    // -------------------------------------------------------------------------

    /// Démarre le rafraîchissement automatique de toutes les métriques.
    ///
    /// Cette méthode est appelée au lancement de l'application (barre de menus)
    /// et à l'apparition de la vue principale. Elle est idempotente :
    /// le minuteur précédent est invalidé avant d'en créer un nouveau.
    func startLiveUpdates() {
        refreshDeviceInfo()
        refreshMetrics()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshMetrics()
            self?.refreshMenuBar()
        }
    }

    /// Mesure en cours ? Empêche deux relevés simultanés de s'empiler.
    private var metricsInFlight = false

    /// Actualise les métriques dynamiques (CPU, RAM, disque) et l'historique.
    ///
    /// Les relevés (`top`, `vm_stat`, `df`, `sysctl`) sont des processus : ils
    /// sont donc lus **hors du fil principal**, puis publiés sur le fil
    /// principal. Les appeler directement ici gelait l'interface pendant
    /// environ une seconde toutes les deux secondes.
    ///
    /// Méthode publique appelée à chaque tick du minuteur, mais aussi manuellement
    /// via le bouton « Actualiser ». Elle met à jour les ratios et détails
    /// affichés par les cartes, enrichit les historiques (bornés à 60 points)
    /// puis rafraîchit le texte de l'icône de la barre de menus.
    func refreshMetrics() {
        guard !metricsInFlight else { return }
        metricsInFlight = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let cpu = CPU.usage()
            let memory = Memory.usage()
            let disk = Disk.usage()
            let memoryDetail = Memory.detail()
            let diskDetail = Disk.detail()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.cpuUsage = cpu
                self.memoryUsage = memory
                self.diskUsage = disk
                self.cpuDetail = String(format: "%.0f %%", cpu * 100)
                self.memoryDetail = memoryDetail
                self.diskDetail = diskDetail

                // Enregistre les échantillons pour les graphiques d'évolution.
                self.cpuHistory.append(cpu)
                self.memoryHistory.append(memory)
                if self.cpuHistory.count > self.historyCapacity {
                    self.cpuHistory.removeFirst(self.cpuHistory.count - self.historyCapacity)
                }
                if self.memoryHistory.count > self.historyCapacity {
                    self.memoryHistory.removeFirst(self.memoryHistory.count - self.historyCapacity)
                }
                self.metricsInFlight = false

                // Met à jour l'icône et le menu de la barre d'état.
                MenuBarDelegate.shared.updateQuickStats()
            }
        }
    }

    /// Lecture des informations « statiques » (modèle, CPU, uptime).
    ///
    /// Ces informations ne changent pas avec le temps : elles sont rechargées au
    /// lancement ou sur action manuelle. `system_profiler` et `uptime` sont des
    /// processus externes qui peuvent demander une à trois secondes ; ils
    /// tournent donc hors du fil principal, et seuls les résultats sont publiés.
    private var deviceInFlight = false

    func refreshDeviceInfo() {
        guard !deviceInFlight else { return }
        deviceInFlight = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let osInfo = Device.osVersion()
            let model = Device.macModel()
            let cpu = Device.cpuModel()
            let cores = Device.cpuCount()
            let memory = Device.memoryGB()
            let up = Device.uptime()
            DispatchQueue.main.async {
                self?.osInfo = osInfo
                self?.modelInfo = model
                self?.cpuName = cpu
                self?.coreCount = cores
                self?.totalMemoryGB = memory
                self?.uptime = up
                self?.deviceInFlight = false
            }
        }
    }

    /// Rafraîchit explicitement le contenu de l'icône de la barre de menus.
    func refreshMenuBar() {
        MenuBarDelegate.shared.updateQuickStats()
    }

    // -------------------------------------------------------------------------
    //  Nettoyage & optimisation
    // -------------------------------------------------------------------------

    /// Exécute l'ensemble des opérations de nettoyage en toute sécurité.
    ///
    /// Actions effectuées :
    ///   1. Fichiers temporaires de `/tmp` (plus de 60 minutes) ;
    ///   2. Caches utilisateur (`.cache`, `.log` plus de 2 heures) ;
    ///   3. Logs système (plus de 24 heures) ;
    ///   4. Vidage de la corbeille.
    ///
    /// Chaque étape est consignée dans le journal avec le nombre d'éléments
    /// supprimés. L'interface passe en « traitement » (`isProcessing`) pendant
    /// l'exécution pour éviter les opérations concurrentes.
    func runCleanup() {
        guard !isProcessing else { return }
        isProcessing = true
        statusMessage = "Nettoyage en cours…"

        appendLog("═══════════ NETTOYAGE ═══════════")

        // Les quatre collectes parcourent le disque : elles partent hors du fil
        // principal, seules les lignes de journal reviennent dans l'interface.
        // Le verbe diffère : les trois premières collectes vont à la corbeille
        // (réversible), la dernière la vide (définitif).
        let tasks: [(String, String, () -> Int)] = [
            ("Fichiers temporaires (/tmp)", "placé(s) à la corbeille", { Cleaner.tempFiles() }),
            ("Caches utilisateur", "placé(s) à la corbeille", { Cleaner.userCaches() }),
            ("Logs système", "placé(s) à la corbeille", { Cleaner.systemLogs() }),
            ("Corbeille", "définitivement supprimé(s)", { Cleaner.trash() })
        ]

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for (label, verb, task) in tasks {
                let count = task()
                DispatchQueue.main.async { self?.appendLog("  ✦ \(label) : \(count) élément(s) \(verb)") }
            }
            DispatchQueue.main.async {
                self?.appendLog("")
                self?.statusMessage = "Nettoyage terminé ✓"
                self?.isProcessing = false
            }
        }
    }

    /// Recherche les fichiers volumineux (> 100 Mo) et les signale sans les supprimer.
    ///
    /// La recherche porte sur les dossiers Téléchargements, Documents et Bureau.
    /// Les résultats sont affichés dans le journal ; la suppression reste à la
    /// discrétion de l'utilisateur (aucun fichier personnel n'est supprimé).
    func runOptimization() {
        guard !isProcessing else { return }
        isProcessing = true
        statusMessage = "Recherche des gros fichiers…"

        appendLog("═══════════ REPÉRAGE DES GROS FICHIERS ═══════════")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let files = Cleaner.largeFiles()
            DispatchQueue.main.async {
                if files.isEmpty {
                    self?.appendLog("Aucun fichier supérieur à 100 Mo trouvé.")
                    self?.appendLog("")
                } else {
                    self?.appendLog("Fichiers volumineux (> 100 Mo) :")
                    for file in files {
                        self?.appendLog("  • \(file)")
                    }
                    self?.appendLog("")
                    self?.appendLog("Astuce : effacez-les dans le Finder pour libérer de l'espace.")
                }
                self?.statusMessage = "Repérage terminé ✓"
                self?.isProcessing = false
            }
        }
    }

    /// Vide entièrement le journal des actions.
    func clearLog() {
        log = ""
    }

    /// Ajoute une ligne au journal (saut de ligne automatique).
    func appendLog(_ line: String) {
        if log.isEmpty {
            log = line
        } else {
            log += "\n" + line
        }
    }
}

// ============================================================================
//  MARK: - CPU : collecteur d'utilisation du processeur
//  ============================================================================

/// Fournit le taux d'utilisation du processeur.
///
/// Mesure obtenue via la commande `top -l 1 -n 0 -s 0` : on conserve la ligne
/// « CPU usage: X% user, Y% sys, Z% idle » et l'on déduit l'utilisation à partir
/// du pourcentage « idle ». La valeur est ensuite bornée entre 0.0 et 1.0.
enum CPU {
    /// Retourne le taux d'utilisation du CPU sous forme de ratio (0.0 → 1.0).
    ///
    /// - Returns: ratio d'utilisation, 1.0 signifiant « 100 % occupé ».
    static func usage() -> Double {
        let output = run("/usr/bin/top", ["-l", "1", "-n", "0", "-s", "0"]) ?? ""
        guard let line = output.split(separator: "\n")
            .first(where: { $0.contains("CPU usage") }) else { return 0 }
        let text = String(line)
        guard let idleRange = text.range(of: "% idle") else { return 0 }
        let before = String(text[text.startIndex..<idleRange.lowerBound])
        guard let lastPercent = before.split(separator: ",").last,
              var value = Double(lastPercent
                  .trimmingCharacters(in: CharacterSet.decimalDigits.inverted)
                  .replacingOccurrences(of: ",", with: ".")) else { return 0 }
        // `value` représente le pourcentage « idle » (ex. 47 → 47 %).
        value = min(max(value / 100, 0), 1)
        return 1 - value
    }

    /// Exécute une commande externe et renvoie sa sortie brute (ou nil).
    private static func run(_ cmd: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cmd)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

// ============================================================================
//  MARK: - Memory : collecteur de statistiques de la mémoire vive
//  ============================================================================

/// Fournit l'utilisation de la mémoire vive (RAM).
///
/// Le calcul combine deux sources :
///   • `vm_stat` : nombre de pages libres, actives, inactives, compressées… ;
///   • `hw.memsize` (via `ProcessInfo.physicalMemory`) : mémoire physique totale.
///
/// La mémoire « utilisée » correspond à la mémoire totale diminuée des pages
/// libres et inactives (considérées comme récupérables).
enum Memory {

    /// Retourne le ratio d'utilisation de la RAM (0.0 → 1.0).
    ///
    /// - Returns: ratio de mémoire utilisée.
    static func usage() -> Double {
        guard let memsize = Device.memsize(), let stats = vmStat() else { return 0 }
        let pageSize: Double = 4096
        let free = (stats["Pages free"] ?? 0) + (stats["Pages inactive"] ?? 0)
        let total = Double(memsize)
        let used = total - free * pageSize
        let ratio = used / total
        return min(max(ratio, 0), 1)
    }

    /// Construit un texte lisible décrivant la mémoire (ex. « 9,7 Go utilisés sur 16,0 Go »).
    static func detail() -> String {
        let used = Int64(Double(Device.memsize() ?? 0) * usage())
        let total = Int64((Device.memsize() ?? 0)) / 1
        let usedGB = Double(used) / 1_073_741_824
        let totalGB = Double(total) / 1_073_741_824
        // `String(format:)` suit la locale de la machine ; sur une installation
        // anglophone il rendrait « 9.7 » alors que toute l'interface est française.
        return "\(frNumber(usedGB)) Go utilisés sur \(frNumber(totalGB)) Go"
    }

    /// Formate un nombre avec une virgule décimale, quel que soit la locale.
    static func frNumber(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }

    /// Analyse la sortie de `vm_stat` et retourne un dictionnaire pages → valeur.
    ///
    /// Les valeurs « 1. » (terminaison de blocs) sont normalisées en entiers.
    /// - Returns: dictionnaire contenant le nombre de pages par catégorie.
    static func vmStat() -> [String: Double]? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/vm_stat")
        let pipe = Pipe()
        p.standardOutput = pipe
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            var result: [String: Double] = [:]
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: ":")
                if parts.count == 2 {
                    let key = String(parts[0])
                    var value = String(parts[1])
                        .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
                        .replacingOccurrences(of: ",", with: "")
                    // Normalise les valeurs du type « 123. » en « 123 ».
                    if let dot = value.firstIndex(of: ".") {
                        value = String(value[value.startIndex..<dot])
                    }
                    result[key] = Double(value)
                }
            }
            return result
        } catch {
            return nil
        }
    }
}

// ============================================================================
//  MARK: - Disk : collecteur d'utilisation du disque
//  ============================================================================

/// Fournit l'utilisation de l'espace disque du volume de démarrage.
///
/// La mesure provient de la commande `df -h /` ; le taux d'occupation est
/// extrait de la colonne « Capacity » (pourcentage), puis converti en ratio.
enum Disk {

    /// Retourne le ratio d'occupation du disque (0.0 → 1.0).
    static func usage() -> Double {
        guard let line = rootLine() else { return 0 }
        // Format attendu : Filesystem Size Used Avail Capacity ...
        let fields = line.split(separator: " ").map(String.init)
        guard fields.count > 4, let pct = Double(String(fields[4].dropLast())) else { return 0 }
        return min(max(pct / 100, 0), 1)
    }

    /// Construit un texte lisible décrivant l'espace disque.
    static func detail() -> String {
        guard let line = rootLine() else { return "—" }
        let fields = line.split(separator: " ").map(String.init)
        guard fields.count > 3 else { return "—" }
        // `df -h` rend des unités binaire façon annexes IEEE (« 21Gi », « 954Gi »)
        // que personne ne lit. On les remet en « Go » / « To » tout en gardant
        // la valeur mesurée, sans arrondi ni recalcul.
        return "\(human(fields[2])) utilisés / \(human(fields[1])) disponibles"
    }

    /// « 21Gi » → « 21 Go » ; « 1.5Ti » → « 1,5 To ».
    private static func human(_ raw: String) -> String {
        var value = raw
        let units: [(String, String)] = [("Ti", "To"), ("Gi", "Go"), ("Mi", "Mo"), ("Ki", "Ko")]
        for (from, to) in units where value.hasSuffix(from) {
            value = String(value.dropLast(from.count)) + " " + to
            break
        }
        return value.replacingOccurrences(of: ".", with: ",")
    }

    /// Renvoie la première ligne de données de `df -h /` (ligne du volume racine).
    private static func rootLine() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/df")
        p.arguments = ["-h", "/"]
        let pipe = Pipe()
        p.standardOutput = pipe
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            let lines = text.split(separator: "\n").map(String.init)
            if lines.count > 1 { return lines[1] } // saute la ligne d'entête
            return nil
        } catch {
            return nil
        }
    }
}

// ============================================================================
//  MARK: - Device : informations statiques de la machine
//  ============================================================================

/// Fournit des informations « statiques » sur l'ordinateur.
enum Device {

    /// Retourne la version du système d'exploitation, ex. « macOS 13.7.8 ».
    static func osVersion() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    /// Retourne la mémoire physique totale en octets.
    static func memsize() -> UInt64? {
        return ProcessInfo.processInfo.physicalMemory
    }

    /// Retourne la marque et le modèle du processeur (via `sysctl`).
    static func cpuModel() -> String {
        sysctlString("machdep.cpu.brand_string") ?? "—"
    }

    /// Retourne le nombre de cœurs logiques disponibles.
    static func cpuCount() -> String {
        "\(ProcessInfo.processInfo.activeProcessorCount)"
    }

    /// Retourne la mémoire totale arrondie en Go, ex. « 16 Go ».
    static func memoryGB() -> String {
        let mem = ProcessInfo.processInfo.physicalMemory
        return String(format: "%.0f Go", Double(mem) / 1_073_741_824)
    }

    /// Retourne le modèle commercial du Mac (ex. « MacBook Pro »).
    static func macModel() -> String {
        let output = sys("/usr/sbin/system_profiler", ["SPHardwareDataType"])
        for line in output.components(separatedBy: "\n") where line.contains("Model Name") {
            return line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "Model Name:", with: "")
        }
        return "Mac"
    }

    /// Retourne la durée d'activité de la machine depuis le dernier démarrage.
    ///
    /// La valeur est déduite de la sortie de la commande `uptime`.
    static func uptime() -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/uptime")
        let pipe = Pipe()
        p.standardOutput = pipe
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            // Extrait la portion « up X days, HH:MM ».
            if let range = text.range(of: "up ") {
                let tail = String(text[range.lowerBound...])
                if let comma = tail.range(of: ",") {
                    return String(tail[..<comma.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "day", with: "jour")
                        .replacingOccurrences(of: "days", with: "jours")
                        .replacingOccurrences(of: "min", with: "min")
                }
                return tail.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return "—"
        } catch {
            return "—"
        }
    }

    /// Lit une valeur de paramètre noyau (`sysctl -n <clé>`).
    private static func sysctlString(_ key: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/sysctl")
        p.arguments = ["-n", key]
        let pipe = Pipe()
        p.standardOutput = pipe
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// Exécute une commande externe et renvoie sa sortie (chaîne vide si échec).
    private static func sys(_ cmd: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cmd)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

// ============================================================================
//  MARK: - Cleaner : opérations de nettoyage et d'optimisation
//  ============================================================================

/// Regroupe les opérations de maintenance du système.
///
/// Toutes les suppressions sont volontairement **conservatrices** :
///   • seuls certains dossiers bien identifiés sont balayés ;
///   • les fichiers récents (caches de moins de 2 h, etc.) sont conservés ;
///   • aucun fichier personnel n'est jamais supprimé.
enum Cleaner {

    /// Place les fichiers temporaires de `/tmp` plus anciens que 60 minutes à la
    /// corbeille.
    /// - Returns: nombre de fichiers effectivement déplacés.
    static func tempFiles() -> Int {
        delete(in: "/tmp", patterns: ["*"], olderThanMinutes: 60)
    }

    /// Place les caches utilisateur (`.cache` / `.log`) plus anciens que 2 h à la
    /// corbeille.
    /// - Returns: nombre de fichiers effectivement déplacés.
    static func userCaches() -> Int {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return 0 }
        return delete(in: caches.path, patterns: ["*.cache", "*.log"], olderThanMinutes: 120)
    }

    /// Place les logs système de plus de 24 h à la corbeille (selon les
    /// permissions : ces fichiers appartiennent le plus souvent à root).
    /// - Returns: nombre de fichiers déplacés (0 si droits insuffisants).
    static func systemLogs() -> Int {
        delete(in: "/private/var/log", patterns: ["*.log"], olderThanMinutes: 1440)
    }

    /// Vide la corbeille de l'utilisateur courant.
    /// - Returns: nombre d'éléments supprimés.
    static func trash() -> Int {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        guard let items = try? FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil) else { return 0 }
        var removed = 0
        for item in items {
            do {
                try FileManager.default.removeItem(at: item)
                removed += 1
            } catch {
                // Ignoré : fichier verrouillé ou en cours d'utilisation.
            }
        }
        return removed
    }

    /// Recherche les gros fichiers (> 100 Mo) dans les dossiers courants.
    /// - Returns: chemins des fichiers volumineux trouvés.
    static func largeFiles() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dirs = ["Downloads", "Documents", "Desktop"].map { home.appendingPathComponent($0) }
        var files: [String] = []
        for dir in dirs where FileManager.default.fileExists(atPath: dir.path) {
            files.append(contentsOf: find(dir.path, patterns: ["*"], size: "+100M", limit: 6))
        }
        return files
    }

    // -------------------------------------------------------------------------
    //  Helpers génériques partagés
    // -------------------------------------------------------------------------

    /// Supprime, dans un dossier, tous les fichiers correspondant à des motifs
    /// et plus anciens qu'un seuil donné. Retourne le nombre de suppressions.
    ///
    /// Le geste va à la **corbeille** (`trashItem`) et non à `removeItem` : le
    /// nettoyage express reste réversible, comme dans l'espace Purge. Un fichier
    /// possédé par root (`/private/var/log`, une partie de `/tmp`) est refusé par
    /// macOS ; il est compté comme conservé, jamais comme supprimé.
    private static func delete(in directory: String, patterns: [String], olderThanMinutes minutes: Int) -> Int {
        guard FileManager.default.fileExists(atPath: directory) else { return 0 }
        var removed = 0
        for pattern in patterns {
            for file in find(directory, patterns: [pattern], olderThanMinutes: minutes) {
                do {
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: file), resultingItemURL: nil)
                    removed += 1
                } catch {
                    // Permission ou verrou : le fichier est simplement conservé.
                }
            }
        }
        return removed
    }

    /// Recherche des fichiers selon des critères (motif, ancienneté, taille).
    /// Retourne le chemin des fichiers trouvés, dans la limite `limit`.
    private static func find(_ directory: String, patterns: [String], olderThanMinutes minutes: Int? = nil, size: String? = nil, limit: Int = 1000) -> [String] {
        var args = [directory, "-type", "f"]
        if let minutes = minutes { args += ["-mmin", "+\(minutes)"] }
        if let size = size { args += ["-size", size] }
        var result: [String] = []
        for pattern in patterns {
            let fullArgs = args + ["-name", pattern]
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/find")
            p.arguments = fullArgs
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            do {
                try p.run()
                p.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let text = String(data: data, encoding: .utf8) {
                    result.append(contentsOf: text.split(separator: "\n").map(String.init).prefix(limit))
                }
            } catch {
                // Ignoré : continue avec le motif suivant.
            }
        }
        return result
    }
}

// ============================================================================
//  MARK: - Reminder : rappels hebdomadaires (UserNotifications)
//  ============================================================================

/// Service de rappels hebdomadaires de nettoyage.
///
/// Utilise le framework `UserNotifications` pour programmer une notification
/// récurrente chaque dimanche à 10 h. L'utilisateur peut l'activer ou la
/// désactiver depuis l'onglet Nettoyage.
enum Reminder {

    /// Identifiant stable de la notification (pour annulation ciblée).
    private static let identifier = "monitormymac.weekly.cleanup"

    /// Demande à macOS l'autorisation d'envoyer des notifications.
    ///
    /// La réponse de l'utilisateur est ignorée ; si elle est refusée, la
    /// programmation échouera silencieusement dans `scheduleWeeklyCleanup`.
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Programme le rappel hebdomadaire si l'autorisation est accordée.
    ///
    /// La notification contient la clé `action = "cleanup"` afin que le clic
    /// déclenche un nettoyage automatique (voir `MenuBarDelegate`).
    static func scheduleWeeklyCleanup() {
        requestAuthorization()
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = "MonitorMyMac ✨"
            content.body = "C’est le moment parfait pour un petit nettoyage de votre Mac."
            content.sound = .default
            content.userInfo = ["action": "cleanup"]

            // Déclencheur récurrent : dimanche à 10 h 00.
            var date = DateComponents()
            date.weekday = 1  // dimanche (calendrier grégorien : 1 = dimanche)
            date.hour = 10
            date.minute = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }

    /// Annule le rappel hebdomadaire programmé.
    static func cancelWeeklyCleanup() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

// ============================================================================
//  MARK: - MenuBarDelegate : icône de barre de menus macOS
//  ============================================================================

/// Gère l'icône et le menu de l'application dans la barre d'état macOS.
///
/// Rôles :
///   • afficher le taux CPU en direct dans la barre de menus ;
///   • fournir un menu déroulant (statistiques + actions rapides) ;
///   • servir de délégué aux notifications (clic → nettoyage).
final class MenuBarDelegate: NSObject, NSMenuDelegate, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    /// Instance partagée utilisée par l'interface et par le cycle de vie.
    static let shared = MenuBarDelegate()

    /// Élément « status item » inséré dans la barre d'état.
    private var statusItem: NSStatusItem?
    /// Menu contextuel affiché au clic sur l'icône.
    private let cpuMenuItem = NSMenuItem(title: "CPU —", action: nil, keyEquivalent: "")
    private let ramMenuItem = NSMenuItem(title: "RAM —", action: nil, keyEquivalent: "")
    private let diskMenuItem = NSMenuItem(title: "Disque —", action: nil, keyEquivalent: "")
    private let statusMenuItem = NSMenuItem(title: "Statut : Prêt", action: nil, keyEquivalent: "")
    private var menuBarTimer: Timer?

    // -------------------------------------------------------------------------
    //  Démarrage de l'application (NSApplicationDelegate)
    // -------------------------------------------------------------------------

    /// Appelée au lancement : crée l'icône de barre de menus et démarre l'app.
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        UNUserNotificationCenter.current().delegate = self
        SystemMonitor.shared.startLiveUpdates()
    }

    // -------------------------------------------------------------------------
    //  Création de l'élément d'état
    // -------------------------------------------------------------------------

    /// Instancie la « status item » avec son icône et son menu déroulant.
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "macbook.and.iphone",
            accessibilityDescription: "MonitorMyMac"
        )
        item.button?.title = " 0%"
        item.menu = buildMenu()
        statusItem = item
        updateQuickStats()
    }

    /// Construit le menu déroulant complet de la barre d'état.
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        // — En-tête du menu : ouvre la fenêtre principale.
        let appItem = NSMenuItem(title: "MonitorMyMac", action: #selector(openMainWindow), keyEquivalent: "")
        appItem.image = NSImage(systemSymbolName: ("macbook.and.iphone").mmSafeSymbol, accessibilityDescription: "")
        menu.addItem(appItem)
        menu.addItem(.separator())

        // — Statistiques en temps réel (non cliquables).
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        updateStatusMenuItems()
        for item in [cpuMenuItem, ramMenuItem, diskMenuItem] {
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // — Actions rapides.
        let cleanItem = NSMenuItem(title: "🧹  Nettoyage rapide", action: #selector(quickCleanup), keyEquivalent: "n")
        cleanItem.toolTip = "Les quatre collectes automatiques : /tmp au-delà de 60 min, caches utilisateur au-delà de 2 h, journaux système au-delà de 24 h, puis vidage de la corbeille. Les trois premières vont à la corbeille (réversible) ; la dernière est définitive."
        menu.addItem(cleanItem)

        // Le libellé dit ce que la commande fait vraiment : `Cleaner.largeFiles()`
        // liste des fichiers de plus de 100 Mo, il n'en supprime aucun. « Optimisation »
        // promettait une place libérée que rien ne délivrait.
        let optimizeItem = NSMenuItem(title: "🔍  Repérer les fichiers volumineux",
                                      action: #selector(quickOptimize), keyEquivalent: "o")
        optimizeItem.toolTip = "Liste les fichiers de plus de 100 Mo dans Téléchargements, Documents et Bureau (6 par dossier), sans rien supprimer. Supprimez vous-même dans le Finder ce que la liste révèle."
        menu.addItem(optimizeItem)

        menu.addItem(.separator())

        // — Navigation directe : les quatre espaces, la bande dépliable, le tiroir.
        // Les raccourcis affichés ici ne seraient pas globaux (une menu bar
        // d'agent ne les enregistre pas) : ils vivent dans les `CommandMenu`
        // SwiftUI, ce menu reste sans `keyEquivalent`.
        let sectionsItem = NSMenuItem(title: "🗂  Ouvrir une section", action: nil, keyEquivalent: "")
        let sectionsMenu = NSMenu(title: "Ouvrir une section")
        let spacesHeader = NSMenuItem(title: "Espaces de travail", action: nil, keyEquivalent: "")
        spacesHeader.isEnabled = false
        sectionsMenu.addItem(spacesHeader)
        for tab in AppTab.spaces {
            let item = NSMenuItem(title: tab.title, action: #selector(openSection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = tab.rawValue
            item.toolTip = tab.helpText
            sectionsMenu.addItem(item)
        }
        sectionsMenu.addItem(.separator())

        let monitorItem = NSMenuItem(title: "Déplier / replier les jauges",
                                     action: #selector(toggleMonitor), keyEquivalent: "")
        monitorItem.target = self
        monitorItem.toolTip = "Anneaux, courbes CPU/RAM et fiche matériel sous le bandeau (⌘⇧M)"
        sectionsMenu.addItem(monitorItem)
        let fullMonitor = NSMenuItem(title: "Page Surveillance complète",
                                     action: #selector(openSection(_:)), keyEquivalent: "")
        fullMonitor.target = self
        fullMonitor.representedObject = AppTab.surveillance.rawValue
        fullMonitor.toolTip = AppTab.surveillance.helpText
        sectionsMenu.addItem(fullMonitor)
        sectionsMenu.addItem(.separator())

        let docsHeader = NSMenuItem(title: "Documentation", action: nil, keyEquivalent: "")
        docsHeader.isEnabled = false
        sectionsMenu.addItem(docsHeader)
        for tab in AppTab.docs {
            let item = NSMenuItem(title: tab.title, action: #selector(openDocument(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = tab.rawValue
            item.toolTip = tab.helpText
            sectionsMenu.addItem(item)
        }
        sectionsItem.submenu = sectionsMenu
        menu.addItem(sectionsItem)

        menu.addItem(.separator())

        // — Sortie de l'application.
        let quitItem = NSMenuItem(title: "Quitter", action: #selector(quitApp), keyEquivalent: "q")
        menu.addItem(quitItem)

        return menu
    }

    // -------------------------------------------------------------------------
    //  Mise à jour des statistiques
    // -------------------------------------------------------------------------

    /// Dessine une icône dynamique pour la barre de menus (mini jauge ou sparkline CPU).
    ///
    /// Génère une image conforme aux contraintes de la barre de menus macOS (hauteur ~18-22 pt,
    /// mode modèle `isTemplate = true` pour s'adapter automatiquement aux modes clair et sombre).
    private func makeSparklineIcon(history: [Double], currentUsage: Double) -> NSImage {
        let width: CGFloat = 24
        let height: CGFloat = 14
        let image = NSImage(size: NSSize(width: width, height: height))
        
        image.lockFocus()
        
        // Cadre extérieur arrondi discret
        let bounds = NSRect(x: 0.5, y: 0.5, width: width - 1.0, height: height - 1.0)
        let borderPath = NSBezierPath(roundedRect: bounds, xRadius: 2.5, yRadius: 2.5)
        borderPath.lineWidth = 1.0
        NSColor.labelColor.withAlphaComponent(0.35).setStroke()
        borderPath.stroke()

        // Trace du sparkline (historique des points)
        let points = history.suffix(12)
        if points.count >= 2 {
            let path = NSBezierPath()
            path.lineWidth = 1.2
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            let count = points.count
            let stepX = (width - 4.0) / CGFloat(max(1, count - 1))
            let innerHeight = height - 4.0
            
            for (idx, val) in points.enumerated() {
                let clamped = min(max(val, 0.0), 1.0)
                let px = 2.0 + CGFloat(idx) * stepX
                let py = 2.0 + CGFloat(clamped) * innerHeight
                let pt = NSPoint(x: px, y: py)
                if idx == 0 {
                    path.move(to: pt)
                } else {
                    path.line(to: pt)
                }
            }
            NSColor.labelColor.setStroke()
            path.stroke()
        } else {
            // Repli sur une barre de niveau horizontale si l'historique est encore vide
            let clamped = min(max(currentUsage, 0.0), 1.0)
            let fillWidth = max(2.0, (width - 4.0) * CGFloat(clamped))
            let barRect = NSRect(x: 2.0, y: 3.0, width: fillWidth, height: height - 6.0)
            let barPath = NSBezierPath(roundedRect: barRect, xRadius: 1.5, yRadius: 1.5)
            NSColor.labelColor.setFill()
            barPath.fill()
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    /// Met à jour le texte de l'icône et les lignes de statistiques du menu.
    ///
    /// L'icône affiche un mini-graphique sparkline et le taux CPU (ex. « 23% ») ;
    /// l'infobulle et le menu affichent CPU, RAM et disque.
    func updateQuickStats() {
        guard let button = statusItem?.button else { return }
        let monitor = SystemMonitor.shared
        
        button.image = makeSparklineIcon(history: monitor.cpuHistory, currentUsage: monitor.cpuUsage)
        button.imagePosition = .imageLeading
        button.title = String(format: "%d%%", Int(monitor.cpuUsage * 100))
        button.toolTip = String(
            format: "CPU %d %% · RAM %d %% · Disque %d %%",
            Int(monitor.cpuUsage * 100),
            Int(monitor.memoryUsage * 100),
            Int(monitor.diskUsage * 100)
        )

        cpuMenuItem.title = String(format: "CPU   %d %%", Int(monitor.cpuUsage * 100))
        ramMenuItem.title = String(format: "RAM   %d %%", Int(monitor.memoryUsage * 100))
        diskMenuItem.title = String(format: "Disque   %d %%", Int(monitor.diskUsage * 100))
        statusMenuItem.title = "Statut : \(monitor.statusMessage)"
    }

    /// Marque les lignes de statistiques comme désactivées (lecture seule).
    private func updateStatusMenuItems() {
        cpuMenuItem.isEnabled = false
        ramMenuItem.isEnabled = false
        diskMenuItem.isEnabled = false
    }

    // -------------------------------------------------------------------------
    //  Actions du menu
    // -------------------------------------------------------------------------

    /// Rouvre et met au premier plan la fenêtre principale de l'application.
    @objc private func openMainWindow() {
        AppState.shared.showMainWindow()
    }

    /// Ouvre une section précise de la fenêtre depuis la barre de menus.
    ///
    /// L'onglet est passé dans `representedObject` (le `rawValue` de `AppTab`) :
    /// le menu reste ainsi synchronisé avec la liste des onglets SwiftUI.
    @objc private func openSection(_ sender: NSMenuItem) {
        guard let slug = sender.representedObject as? String, let tab = AppTab.fromSlug(slug) else { return }
        AppState.shared.go(tab)
    }

    /// Ouvre une page de documentation dans le tiroir « ? ».
    @objc private func openDocument(_ sender: NSMenuItem) {
        guard let slug = sender.representedObject as? String, let tab = AppTab.fromSlug(slug) else { return }
        AppState.shared.openDocs(tab)
    }

    /// Déplie ou replie les jauges détaillées sous le bandeau ambiant.
    @objc private func toggleMonitor() {
        AppState.shared.showMainWindow()
        AppState.shared.monitorExpanded.toggle()
    }

    /// Exécute un nettoyage complet sans ouvrir la fenêtre.
    @objc private func quickCleanup() {
        SystemMonitor.shared.runCleanup()
        scheduleMenuBarRefresh()
    }

    /// Exécute une analyse d'espace sans ouvrir la fenêtre.
    @objc private func quickOptimize() {
        SystemMonitor.shared.runOptimization()
        scheduleMenuBarRefresh()
    }

    /// Termine complètement l'application.
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    /// Rafraîchit le menu une fois l'action rapide terminée.
    private func scheduleMenuBarRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.updateQuickStats()
        }
    }

    // -------------------------------------------------------------------------
    //  NSMenuDelegate — observations du menu
    // -------------------------------------------------------------------------

    /// À l'ouverture du menu, les statistiques sont actualisées.
    func menuWillOpen(_ menu: NSMenu) {
        updateQuickStats()
    }

    // -------------------------------------------------------------------------
    //  UNUserNotificationCenterDelegate — interaction avec les notifications
    // -------------------------------------------------------------------------

    /// L'utilisateur clique sur un rappel : ouvre la fenêtre et lance le nettoyage.
    ///
    /// La notification de rappel porte la clé `userInfo["action"] == "cleanup"` ;
    /// lorsque l'utilisateur la touche, on affiche la fenêtre principale puis on
    /// exécute immédiatement un nettoyage.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.content.userInfo["action"] as? String == "cleanup" {
            openMainWindow()
            SystemMonitor.shared.runCleanup()
        }
        completionHandler()
    }
}

// ============================================================================
//  MARK: - ContentView : interface principale
//  ============================================================================

/// Vue racine de l'application.
///
/// La vue est organisée verticalement :
///   1. un **en-tête** (logo en verre, titre, bascule documentation, actualisation) ;
///   2. un **bandeau ambiant** avec CPU / RAM / disque en direct — cliquable, il
///      déplie les jauges complètes sans quitter l'espace où l'on se trouve ;
///   3. le **sélecteur des quatre espaces** (Purge, Performance, Applications,
///      Sécurité) et la phrase de guidage de l'espace actif ;
///   4. éventuellement le **tiroir de documentation** (Aide, FAQ, À propos) ;
///   5. le **contenu** de l'espace ou du document choisi ;
///   6. le **journal** des actions, puis le pied de page.
///
/// Le chemin le plus court vers une fonction principale tient en un clic ; la
/// documentation et les jauges détaillées en deux.
struct ContentView: View {

    /// Instance partagée du service de métriques (singleton).
    @StateObject private var monitor = SystemMonitor.shared
    /// Onglet courant : partagé avec les menus AppKit via `AppState`.
    @StateObject private var app = AppState.shared

    var body: some View {
        ZStack {
            // Fond subtil adaptatif (clair / sombre automatique).
            LinearGradient(
                colors: [
                    Color(NSColor.windowBackgroundColor).opacity(0.95),
                    Color.accentColor.opacity(0.06)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                statusStrip
                spaceSelector
                docsDrawer
                content
                footer
            }
        }
        .frame(minWidth: 760, minHeight: 620)
        .background(WindowResolver())
        .onAppear {
            // Démarre (ou relance) le rafraîchissement automatique des métriques.
            monitor.startLiveUpdates()
        }
    }

    // -------------------------------------------------------------------------
    //  En-tête élégant
    // -------------------------------------------------------------------------

    /// En-tête : logo dégradé, titre de l'application, boutons d'aide
    /// et d'actualisation manuelle.
    private var header: some View {
        HStack(spacing: 14) {
            // Logo de l'application : la vraie icône du bundle (.icns), donc la
            // même image que dans le Dock et ⌘-Tab. Sans elle, MMBrandIcon
            // redessine une pastille vectorielle et le journal de lancement le
            // signale.
            MMBrandIcon(tile: "AppIcon", accent: .purple, size: 52,
                        fallbackSymbol: "macbook.and.iphone")

            // Titre et sous-titre.
            VStack(alignment: .leading, spacing: 2) {
                Text("MonitorMyMac")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(Color.mmLabel)
                Text("Surveillez, nettoyez et optimisez votre Mac en un clin d’œil")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.mmSecondaryLabel)
            }

            Spacer()

            // Indicateur d'activité pendant une opération de maintenance.
            if monitor.isProcessing {
                ProgressView()
                    .controlSize(.small)
            }

            // Bouton d'aide : lève ou baisse le tiroir de documentation.
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if app.docsOpen {
                        app.closeDocs()
                    } else {
                        app.openDocs(.help)
                    }
                }
            } label: {
                Image(systemName: (app.docsOpen ? "questionmark.circle.fill" : "questionmark.circle").mmSafeSymbol)
                    .font(.system(size: 16))
                    .foregroundColor(app.docsOpen ? Color.mmIndigo : Color.mmSecondaryLabel)
            }
            .buttonStyle(.plain)
            .help(app.docsOpen
                ? "Refermer le tiroir Aide / FAQ / À propos (⌘⇧H)"
                : "Ouvrir le tiroir Aide / FAQ / À propos (⌘⇧H)")

            // Bouton d'actualisation manuelle.
            Button {
                monitor.refreshDeviceInfo()
                monitor.refreshMetrics()
            } label: {
                Image(systemName: ("arrow.clockwise").mmSafeSymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.mmLabel)
            }
            .buttonStyle(.bordered)
            .help("Actualiser immédiatement les statistiques")
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    // -------------------------------------------------------------------------
    //  Bandeau ambiant de surveillance
    // -------------------------------------------------------------------------

    /// Barre de mesures toujours visible : CPU, mémoire et disque en direct.
    ///
    /// La surveillance n'est plus un onglet : les trois chiffres qui comptent
    /// sont là, en tête de fenêtre, dans n'importe quel espace. Un clic sur le
    /// bandeau déplie les jauges complètes (anneaux, historical CPU/RAM, fiche
    /// matériel) **sans quitter l'espace où l'on se trouve** — c'est ce qui
    /// supprime l'aller-retour entre « Surveillance » et « Purge ».
    private var statusStrip: some View {
        HStack(spacing: 14) {
            StripMetric(title: "Processeur",
                        symbol: "cpu",
                        ratio: monitor.cpuUsage,
                        value: Fmt.percent(monitor.cpuUsage),
                        detail: "\(monitor.coreCount) cœurs · \(monitor.cpuName)",
                        color: .blue)

            StripMetric(title: "Mémoire",
                        symbol: "memorychip",
                        ratio: monitor.memoryUsage,
                        value: Fmt.percent(monitor.memoryUsage),
                        detail: monitor.memoryDetail,
                        color: .purple)

            StripMetric(title: "Stockage",
                        symbol: "internaldrive",
                        ratio: monitor.diskUsage,
                        value: Fmt.percent(monitor.diskUsage),
                        detail: monitor.diskDetail,
                        color: .green)

            // Ligne matériel : ce que la machine est, pas ce qu'elle fait.
            VStack(alignment: .trailing, spacing: 2) {
                Text(monitor.modelInfo)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.mmLabel)
                    .lineLimit(1)
                Text("\(monitor.osInfo) · \(monitor.totalMemoryGB) · levé depuis \(monitor.uptime)")
                    .font(.system(size: 10))
                    .foregroundColor(Color.mmTertiaryLabel)
                    .lineLimit(1)
            }
            .frame(width: 210, alignment: .trailing)
            .help("Modèle, système, RAM physique et durée d'activité (sysctl, kern.boottime).")

            // Poignée de dépliage : la surface des jauges détaillées.
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    app.monitorExpanded.toggle()
                }
            } label: {
                Image(systemName: (app.monitorExpanded ? "chevron.up" : "chevron.down").mmSafeSymbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(app.monitorExpanded ? .white : Color.mmSecondaryLabel)
                    .frame(width: 26, height: 26)
                    .background(
                        ZStack {
                            Circle().fill(Color.mmLabel.opacity(0.07))
                            if app.monitorExpanded {
                                Circle().fill(Theme.gradient(Color.blue))
                            }
                        }
                    )
            }
            .buttonStyle(.plain)
            .help(app.monitorExpanded
                ? "Replier les jauges détaillées (⌘⇧M)"
                : "Déplier les jauges détaillées : anneaux, courbes, fiche matériel (⌘⇧M)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Color.mmWindowBackground.opacity(0.001))
        .mmGlass(cornerRadius: 16, kind: .bar)
        .contentShape(Rectangle())
        .onTapGesture {
            // Le bandeau entier est cliquable, pas seulement la chevron.
            withAnimation(.easeInOut(duration: 0.22)) {
                app.monitorExpanded.toggle()
            }
        }
        .help("Surveillance en continu : un clic déplie les jauges complètes (⌘⇧M).")
        .padding(.horizontal, 24)
    }

    // -------------------------------------------------------------------------
    //  Sélecteur des quatre espaces
    // -------------------------------------------------------------------------

    /// Sélecteur : quatre espaces de travail, chacun en pastille « verre liquide ».
    ///
    /// Le sélecteur ne montre plus les huit destinations d'un coup : quatre
    /// espaces ici, la documentation réunie dans le tiroir « ? » en tête, et la
    /// surveillance dans le bandeau ambiant au-dessus. La phrase de guidage
    /// rappelle ce que l'espace actif permet de faire, avant même de le lire.
    private var spaceSelector: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(AppTab.spaces) { tab in
                    SpacePill(tab: tab, isOn: app.tab == tab && !app.docsOpen) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            app.go(tab)
                        }
                    }
                }
            }
            // Groupe centré : étirer quatre pastilles sur toute la largeur de la
            // fenêtre créait des vides de 300 points entre deux espaces.
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)

            // Guidage : la phrase de l'espace courant (ou du document ouvert).
            HStack(spacing: 6) {
                Image(systemName: ("lightbulb").mmSafeSymbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(app.tab.accent)
                Text(app.tab.guidance)
                    .font(.system(size: 11))
                    .foregroundColor(Color.mmSecondaryLabel)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // -------------------------------------------------------------------------
    //  Tiroir de documentation
    // -------------------------------------------------------------------------

    /// Tiroir « ? » : Aide, FAQ et À propos, ouvert depuis l'en-tête.
    ///
    /// Ces trois surfaces ne sont pas des espaces de travail — on les consulte
    /// ponctuellement. Les empiler dans un tiroir garde le sélecteur à quatre
    /// entrées et évite de choisir entre « Purge » et « FAQ » à chaque lancement.
    @ViewBuilder
    private var docsDrawer: some View {
        if app.docsOpen {
            HStack(spacing: 10) {
                Image(systemName: ("book").mmSafeSymbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.mmSecondaryLabel)
                Text("Documentation")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.mmSecondaryLabel)

                ForEach(AppTab.docs) { tab in
                    Button {
                        app.openDocs(tab)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: (tab.icon).mmSafeSymbol)
                                .font(.system(size: 10, weight: .semibold))
                            Text(tab.shortTitle)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            ZStack {
                                Capsule().fill(Color.mmLabel.opacity(0.07))
                                if app.tab == tab {
                                    Capsule().fill(Theme.gradient(tab.accent))
                                }
                            }
                        )
                        .foregroundColor(app.tab == tab ? .white : Color.mmLabel)
                    }
                    .buttonStyle(.plain)
                    .help(tab.helpText)
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { app.closeDocs() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: ("xmark").mmSafeSymbol)
                            .font(.system(size: 9, weight: .bold))
                        Text("Fermer")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Color.mmSecondaryLabel)
                }
                .buttonStyle(.plain)
                .help("Refermer le tiroir et retrouver l'espace de travail (⌘⇧H)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .mmGlass(cornerRadius: 14, kind: .card)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // -------------------------------------------------------------------------
    //  Contenu par onglet
    // -------------------------------------------------------------------------

    /// Affiche le contenu de l'espace (ou du document) sélectionné, puis le journal.
    ///
    /// La page « Surveillance » complète reste une destination à part entière —
    /// elle est atteignable par `--tab=surveillance`, les menus et le bandeau
    /// déplié — mais n'apparaît plus dans le sélecteur : son contenu est
    /// exactement la surface que le bandeau déplie, et l'afficher deux fois
    /// chargerait la fenêtre.
    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Le bandeau déplié pose les jauges **au-dessus** de l'espace en
                // cours : la navigation ne bouge pas, on lit et on agit sans
                // changer de page.
                if app.monitorExpanded && app.tab != .surveillance {
                    monitoringGrid
                }

                switch app.tab {
                case .surveillance:
                    if !app.monitorExpanded {
                        monitoringGrid
                    } else {
                        spaceContent
                    }
                default:
                    spaceContent
                }

                logPanel
            }
            .padding(24)
        }
    }

    /// Contenu de la destination courante, hors jauges de surveillance.
    @ViewBuilder
    private var spaceContent: some View {
        switch app.tab {
        case .surveillance:
            EmptyView()
        case .purge:
            PurgeView()
        case .performance:
            PerformanceView()
        case .applications:
            AppsView()
        case .security:
            SecurityView()
        case .help:
            HelpTabView()
        case .faq:
            FAQTabView()
        case .about:
            AboutTabView()
        }
    }

    // -------------------------------------------------------------------------
    //  Grille de surveillance
    // -------------------------------------------------------------------------

    /// Grille 2 colonnes de cartes de surveillance + carte d'historique.
    private var monitoringGrid: some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                GaugeCard(
                    title: "Processeur",
                    subtitle: monitor.cpuName,
                    icon: "cpu",
                    color: .blue,
                    ratio: monitor.cpuUsage,
                    footer: "\(monitor.coreCount) cœurs · \(monitor.cpuDetail)"
                )

                GaugeCard(
                    title: "Mémoire",
                    subtitle: "\(monitor.totalMemoryGB)",
                    icon: "memorychip",
                    color: .purple,
                    ratio: monitor.memoryUsage,
                    footer: monitor.memoryDetail
                )

                DiskCard(
                    title: "Stockage",
                    icon: "externaldrive",
                    color: .green,
                    ratio: monitor.diskUsage,
                    footer: monitor.diskDetail
                )

                SystemCard(
                    title: "Système",
                    osInfo: monitor.osInfo,
                    model: monitor.modelInfo,
                    uptime: monitor.uptime
                )
            }

            // Courbes d'évolution CPU & RAM.
            HistoryChartCard(
                cpuSamples: monitor.cpuHistory,
                memorySamples: monitor.memoryHistory
            )
        }
    }

    // -------------------------------------------------------------------------
    //  Journal
    // -------------------------------------------------------------------------

    /// Panneau « Journal » : historique texte des actions effectuées.
    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Journal", systemImage: "list.bullet.rectangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.mmSecondaryLabel)
                Spacer()
                if !monitor.log.isEmpty {
                    Button("Effacer") { monitor.clearLog() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(Color.mmSecondaryLabel)
                        .help("Vider le journal des actions")
                }
            }

            ScrollView {
                Text(monitor.log.isEmpty ? "Aucune action pour le moment." : monitor.log)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color.mmSecondaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .padding(10)
            }
            .frame(maxHeight: 150)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.gray.opacity(0.08))
            )
        }
    }

    // -------------------------------------------------------------------------
    //  Pied de page
    // -------------------------------------------------------------------------

    /// Barre de statut inférieure (état courant + version de l'application).
    private var footer: some View {
        HStack {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .shadow(color: .green.opacity(0.7), radius: 3)
            Text(monitor.statusMessage)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.mmSecondaryLabel)
            Spacer()
            Text("v\(AppInfo.version) · 100 % natif · auteur : \(AppInfo.author)")
                .font(.system(size: 10))
                .foregroundColor(Color.mmTertiaryLabel)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .mmGlass(cornerRadius: 0, kind: .bar)
    }
}

// ============================================================================
//  MARK: - Éléments de navigation
// ============================================================================

/// Pastille d'un espace de travail : tuile « Liquid Glass » + libellé court.
///
/// L'icône vient des planches fournies, détourées et composées en tuiles
/// auto-suffisantes (`assets/icons/tuiles`, embarquées dans le bundle) ; si la
/// ressource manque, `MMBrandIcon` redessine la pastille en vecteur. Le libellé
/// passe en gras quand l'espace est actif, seule indication textuelle de l'état
/// sélectionné.
struct SpacePill: View {
    /// Espace représenté.
    let tab: AppTab
    /// L'espace est-il celui qui tient la scène ?
    let isOn: Bool
    /// Action déclenchée au clic.
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                MMBrandIcon(tile: tab.brandTile, accent: tab.accent, size: 40,
                            fallbackSymbol: tab.icon, isOn: isOn)
                    // La tuile bitmap ne change pas d'aspect selon l'état : sans
                    // ce voile, les quatre pastilles rivalisaient d'intensité et
                    // l'espace actif ne se distinguait plus que par son liseré.
                    .opacity(isOn ? 1 : 0.72)
                Text(tab.shortTitle)
                    .font(.system(size: 12, weight: isOn ? .bold : .medium))
                    .foregroundColor(isOn ? tab.accent : Color.mmSecondaryLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            // La tuile s'allume : sans fond, seule la pastille indiquait l'espace
            // actif et les quatre libellés flottaient sur le même plan.
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.mmLabel.opacity(isOn ? 0.09 : 0.03))
                    if isOn {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(tab.accent.opacity(0.55), lineWidth: 1)
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tab.helpText)
        .accessibility(label: Text("\(tab.title) — \(tab.helpText)"))
    }
}

/// Mini-jauge du bandeau ambiant : libellé, valeur, barre de pression, détail.
///
/// Elle tient le rôle de la carte `GaugeCard` dans un volume de quelques lignes
/// — assez pour un coup d'œil, sans obligations de dépliage. Les seuils de
/// couleur sont les mêmes que ceux du moteur mémoire (`MemorySnapshot`) afin
/// qu'un même état rende la même teinte d'un bout à l'autre de l'interface.
struct StripMetric: View {
    /// Libellé de la mesure (« Processeur », « Mémoire », « Stockage »).
    let title: String
    /// Symbole SF de la mesure.
    let symbol: String
    /// Ratio de 0.0 à 1.0.
    let ratio: Double
    /// Valeur condensée affichée en gras (« 42 % »).
    let value: String
    /// Détail lisible (nbre de cœurs, Go utilisés, espace libre…).
    let detail: String
    /// Couleur de la barre et de l'icône.
    let color: Color

    /// Seuil à partir duquel la pression devient orange, puis rouge.
    private var stateColor: Color {
        switch min(max(ratio, 0), 1) {
        case ..<0.60: return color
        case ..<0.80: return .orange
        default:      return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: (symbol).mmSafeSymbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(stateColor)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color.mmTertiaryLabel)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Color.mmLabel)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.mmLabel.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [stateColor.opacity(0.55), stateColor],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, proxy.size.width * min(max(ratio, 0), 1)))
                        .animation(.easeOut(duration: 0.5), value: ratio)
                }
            }
            .frame(height: 6)

            Text(detail)
                .font(.system(size: 10))
                .foregroundColor(Color.mmSecondaryLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("\(title) — \(detail)")
    }
}

// ============================================================================
//  MARK: - Cartes de surveillance
// ============================================================================

/// Carte affichant une jauge annulaire animée autour d'un pourcentage.
///
/// Elle est utilisée pour le **processeur** et la **mémoire** : un anneau
/// coloré dont la progression reflète le ratio (0 → 100 %) surmonté d'une
/// valeur numérique centrale.
struct GaugeCard: View {
    /// Libellé de la carte (ex. « Processeur »).
    let title: String
    /// Sous-titre descriptif (ex. modèle du CPU).
    let subtitle: String
    /// Symbole SF iconographique.
    let icon: String
    /// Couleur d'accentuation de la jauge.
    let color: Color
    /// Ratio de remplissage entre 0.0 et 1.0.
    let ratio: Double
    /// Pied de carte : informations complémentaires.
    let footer: String

    var body: some View {
        HStack(spacing: 16) {
            // Anneau de progression animé.
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: ratio)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: ratio)

                // Valeur centrale en pourcentage.
                VStack(spacing: 0) {
                    Text("\(Int(ratio * 100))")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("%")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color.mmSecondaryLabel)
                }
            }
            .frame(width: 66, height: 66)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: (icon).mmSafeSymbol)
                        .foregroundColor(color)
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Color.mmSecondaryLabel)
                    .lineLimit(1)
                    .help(subtitle)
                Text(footer)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(color)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .mmGlass(cornerRadius: 18, kind: .card)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.mmSeparator.opacity(0.7), lineWidth: 1)
        )
    }
}

/// Carte disque avec barre de progression horizontale.
///
/// La barre est remplie en fonction du taux d'occupation du volume de démarrage ;
/// un dégradé coloré et une valeur en pourcentage complètent l'affichage.
struct DiskCard: View {
    /// Libellé de la carte (ex. « Stockage »).
    let title: String
    /// Symbole SF illustrant le disque.
    let icon: String
    /// Couleur d'accentuation.
    let color: Color
    /// Ratio d'occupation entre 0.0 et 1.0.
    let ratio: Double
    /// Texte récapitulatif (espace utilisé / disponible).
    let footer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // En-tête : icône, titre, pourcentage.
            HStack {
                Image(systemName: (icon).mmSafeSymbol)
                    .foregroundColor(color)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text("\(Int(ratio * 100)) %")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }

            // Barre de progression.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.15))
                    Capsule()
                        .fill(
                            LinearGradient(colors: [color, color.opacity(0.7)],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: geo.size.width * ratio)
                        .animation(.easeOut(duration: 0.6), value: ratio)
                }
            }
            .frame(height: 8)

            Text(footer)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.mmSecondaryLabel)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    /// Fond de carte : verre AppKit partagé (voir MMCardBackground).
    private var cardBackground: some View {
        MMCardBackground()
    }
}

/// Carte récapitulant les informations statiques du système.
///
/// Affiche le modèle de Mac, la version macOS et la durée d'activité depuis
/// le dernier démarrage.
struct SystemCard: View {
    /// Libellé de la carte (ex. « Système »).
    let title: String
    /// Version du système d'exploitation.
    let osInfo: String
    /// Modèle commercial de l'ordinateur.
    let model: String
    /// Durée d'activité depuis le démarrage.
    let uptime: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // En-tête de la carte.
            HStack {
                Image(systemName: ("desktopcomputer").mmSafeSymbol)
                    .foregroundColor(.orange)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                Spacer()
            }

            infoRow(label: "Modèle", value: model)
                .help("Modèle commercial détecté via system_profiler")
            infoRow(label: "Version", value: osInfo)
                .help("Version du système d'exploitation macOS")
            infoRow(label: "Activité", value: uptime)
                .help("Durée écoulée depuis le dernier démarrage")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    /// Ligne étiquette / valeur.
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.mmSecondaryLabel)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }

    /// Fond de carte : verre AppKit partagé (voir MMCardBackground).
    private var cardBackground: some View {
        MMCardBackground()
    }
}

// ============================================================================
//  MARK: - Carte d'historique (sparklines CPU & RAM)
//  ============================================================================

/// Carte regroupant les graphiques d'évolution CPU & RAM.
///
/// Chaque courbe (« sparkline ») représente les mesures collectées lors des
/// deux dernières minutes (échantillon toutes les 2 secondes).
struct HistoryChartCard: View {
    /// Série d'échantillons CPU (ratio 0...1).
    let cpuSamples: [Double]
    /// Série d'échantillons mémoire (ratio 0...1).
    let memorySamples: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Historique temps réel", systemImage: "waveform.path.ecg")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text("2 dernières minutes")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.mmTertiaryLabel)
            }

            HistoryChart(samples: cpuSamples, color: .blue, title: "Processeur")
            HistoryChart(samples: memorySamples, color: .purple, title: "Mémoire")
        }
        .padding(18)
        .background(cardBackground)
    }

    /// Fond de carte : verre AppKit partagé (voir MMCardBackground).
    private var cardBackground: some View {
        MMCardBackground()
    }
}

/// Courbe de tendance dessinée à partir d'une série d'échantillons.
///
/// La courbe affiche le dernier pourcentage à droite et trace l'évolution
/// des valeurs (0 → 100 %) de gauche à droite.
struct HistoryChart: View {
    /// Échantillons de données (ratio 0...1).
    let samples: [Double]
    /// Couleur de la courbe et de la ligne de référence.
    let color: Color
    /// Libellé de la série (ex. « Processeur »).
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.mmSecondaryLabel)
                Spacer()
                if let last = samples.last {
                    Text("\(Int(last * 100)) %")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(color)
                }
            }

            GeometryReader { geo in
                ZStack {
                    // Ligne de référence en haut (100 %).
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: 0))
                        p.addLine(to: CGPoint(x: geo.size.width, y: 0))
                    }
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)

                    // Courbe de tendance elle-même.
                    SparklinePath(samples: samples)
                        .stroke(
                            LinearGradient(
                                colors: [color, color.opacity(0.5)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                        )
                        .animation(.easeOut(duration: 0.4), value: samples)
                }
            }
            .frame(height: 34)
        }
    }
}

/// Forme géométrique dessinant le tracé d'une « sparkline ».
///
/// Chaque échantillon est projeté horizontalement (écart constant) et
/// verticalement selon sa valeur (0 % en bas, 100 % en haut).
struct SparklinePath: Shape {
    /// Série de valeurs (ratio 0...1).
    let samples: [Double]

    /// Construit le chemin de la courbe dans le rectangle fourni.
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard samples.count >= 2 else { return path }

        let width = rect.width
        let height = rect.height
        let usableHeight = height * 0.9
        let bottom = height * 0.95
        let stepX = width / CGFloat(max(samples.count - 1, 1))

        for (index, sample) in samples.enumerated() {
            let x = CGFloat(index) * stepX
            let y = bottom - CGFloat(min(max(sample, 0), 1)) * usableHeight
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

// ============================================================================
//  MARK: - Carte « rappel hebdomadaire »
// ============================================================================

/// Interrupteur du **rappel hebdomadaire** de nettoyage.
///
/// Déplacé ici de l'ancien onglet « Nettoyage » : la fonctionnalité (une
/// notification chaque dimanche à 10 h, réglée dans `SystemMonitor`) reste
/// accessible, mais depuis l'onglet Purge, qui est devenu le vrai poste de
/// nettoyage. L'état est persisté dans `UserDefaults`.
struct ReminderCard: View {
    /// Service observé (porte le réglage et programme la notification).
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        SectionCard(title: "Rappel hebdomadaire",
                    subtitle: "Une notification chaque dimanche à 10 h ; y cliquer lance le nettoyage express.",
                    systemImage: "bell.badge.fill",
                    accent: .pink,
                    trailing: {
                        Pill(text: monitor.remindersEnabled ? "activé" : "désactivé",
                             color: monitor.remindersEnabled ? .pink : .gray)
                    }) {
            Toggle(isOn: $monitor.remindersEnabled) {
                HStack(spacing: 8) {
                    Image(systemName: (monitor.remindersEnabled ? "bell.badge.fill" : "bell.slash").mmSafeSymbol)
                        .font(.system(size: 15))
                        .foregroundColor(monitor.remindersEnabled ? Color.pink : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Me rappeler de nettoyer")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Dimanche · 10 h · notification système (aucune donnée envoyée)")
                            .font(.system(size: 11))
                            .foregroundColor(Color.mmSecondaryLabel)
                    }
                    Spacer()
                }
            }
            .toggleStyle(.switch)
            .help("Active ou désactive le rappel hebdomadaire de nettoyage (dimanche 10 h)")
        }
    }
}

// ============================================================================
//  MARK: - Délégué du cycle de vie de l'application
// ============================================================================

/// Pont entre le cycle de vie SwiftUI et le singleton de la barre de menus.
///
/// Ce délégué légère délègue l'initialisation réelle au `MenuBarDelegate.shared`
/// (création de la status item, des notifications, du minuteur) et autorise
/// l'application à rester active dans la barre de menus après fermeture de la
/// fenêtre.
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    /// Délègue le démarrage au singleton de la barre de menus.
    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBarDelegate.shared.applicationDidFinishLaunching(notification)

        // `--appearance=dark|light` force le mode Sombre/Clair de la fenêtre
        // sans toucher au réglage système de l'utilisateur.
        if let appearance = ShotCapture.requestedAppearance() {
            NSApp.appearance = appearance
        }

        // Mode capture : `--shots[=DIR]` photographie chaque destination après
        // avoir réellement balayé, puis quitte. En dehors de ce mode, rien ne change.
        if let directory = ShotCapture.requestedDirectory() {
            // La fenêtre doit être montée dans la hiérarchie AppKit avant de
            // pouvoir être résolue et redimensionnée.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                ShotCapture.run(in: directory)
            }
        }

        // Signaler les SF Symbols que le système ne connaît pas. Une icône
        // remplacée se voit à l'écran, mais pas son absence : sans cette ligne
        // dans le journal, un repli silencieux passerait pour un rendu normal.
        // Le délai laisse le temps aux vues de résoudre leurs symboles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            let degraded = MMSymbol.degradedNames
            if degraded.isEmpty {
                SystemMonitor.shared.appendLog("Icônes : aucun SF Symbol absent de ce macOS.")
            } else {
                SystemMonitor.shared.appendLog("Icônes : \(degraded.count) symbole(s) absent(s) de ce macOS, remplacés — \(degraded.joined(separator: ", ")).")
            }
            // Même logique pour les visuels de marque bitmap : une tuile
            // manquante ne casse rien (repli vectoriel), mais elle ne doit pas
            // passer pour le rendu attendu. Les six ressources sont sondées ici
            // plutôt qu'au rendu des vues : le relevé porte donc sur le pack
            // complet, pas seulement sur ce qui était à l'écran à 2,5 s
            // (limite qui, elle, reste vraie pour les SF Symbols ci-dessus).
            let attendues = ["AppIcon", "moniteur-systeme", "purge", "performance",
                             "applications", "securite"]
            attendues.forEach { _ = MMBrandArt.image($0) }
            let absentes = MMBrandArt.manquantes
            if absentes.isEmpty {
                SystemMonitor.shared.appendLog("Visuels de marque : icône et tuiles chargées depuis le bundle.")
            } else {
                SystemMonitor.shared.appendLog("Visuels de marque : ressource(s) absente(s) du bundle — \(absentes.joined(separator: ", ")). Pastilles vectorielles utilisées à la place.")
            }
        }
    }

    /// Permet à l'application de continuer de tourner dans la barre de menus.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

// ============================================================================
//  MARK: - Point d'entrée de l'application
// ============================================================================

/// Point d'entrée de l'application macOS.
///
/// Déclare la fenêtre principale, intègre le délégué du cycle de vie (barre de
/// menus) et un menu « Actions » dont les raccourcis ouvrent réellement la
/// section concernée **et** lancent le travail associé :
///   • ⌘⇧N — nettoyage express ;   • ⌘⇧O — optimisation express ;
///   • ⌘⇧P — balayage complet de la Purge ;     • ⌘⇧R — purge de la RAM ;
///   • ⌘⇧A — inventaire des applications ;      • ⌘⇧M — inventaire des extensions ;
///   • ⌘⇧S — balayage des données de navigation ; • ⌘⇧H — onglet Aide.
///
/// L'application accepte aussi deux modes utilitaires en ligne de commande :
/// `--tab=xxx` pour démarrer sur un onglet précis et `--shots=DIR` pour
/// photographier chaque onglet après avoir réellement balayé (voir ShotCapture).
@main
struct MonitorMyMacApp: App {
    /// Adaptateur du délégué du cycle de vie de l'application.
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("MonitorMyMac") {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}

            // Raccourcis clavier utilitaires.
            CommandMenu("Actions") {
                Button("Nettoyage express") {
                    SystemMonitor.shared.runCleanup()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .help("Les quatre collectes automatiques : /tmp au-delà de 60 min, caches utilisateur au-delà de 2 h, journaux système au-delà de 24 h, puis vidage de la corbeille. Les trois premières vont à la corbeille (réversible) ; la dernière est définitive.")

                Button("Repérer les fichiers volumineux") {
                    SystemMonitor.shared.runOptimization()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .help("Dresse la liste des fichiers de plus de 100 Mo dans Téléchargements, Documents et Bureau (6 par dossier), sans rien supprimer : aucune place n'est libérée ici, le libellé « optimisation » serait trompeur. Supprimez vous-même dans le Finder ce que la liste révèle.")

                Divider()

                Button("Balayer la purge (7 familles)") {
                    AppState.shared.go(.purge)
                    PurgeModel.shared.scan()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .help("Ouvre l'espace Purge et relance les sept collectes : caches utilisateur, logs et diagnostics, restes de mises à jour, fichiers volumineux et anciens, doublons (SHA-256), corbeilles et traductions inutilisées. Lecture seule — rien n'est supprimé sans une coche explicite.")

                Button("Purger la RAM") {
                    AppState.shared.go(.performance)
                    PerformanceModel.shared.purgeMemory()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .help("`/usr/sbin/purge` : macOS demande une authentification administrateur, la commande est réservée à root. Le gain mesuré s'affiche dans l'espace Performance.")

                Divider()

                Button("Inventorier les applications") {
                    AppState.shared.go(.applications)
                    AppsModel.shared.scanApps()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .help("Parcourt /Applications, /Applications/Utilities, ~/Applications, ~/Downloads et /System/Applications : nom, identifiant, version, taille, dernier accès, origine App Store, signature de code et exécution en cours. Prérequis de l'analyse anti-malware, qui compare les bundles inventoriés.")

                Button("Inventorier les extensions") {
                    AppState.shared.go(.applications)
                    AppsModel.shared.scanExtensions()
                }
                .keyboardShortcut("x", modifiers: [.command, .shift])
                .help("Lit `pluginkit` et les dossiers d'extensions des navigateurs : greffons macOS, widgets et modules de Safari, Chrome ou Firefox. Lecture seule, aucun greffon n'est désactivé ni retiré.")

                Button("Balayer les données de navigation") {
                    AppState.shared.go(.security)
                    SecurityModel.shared.scanTraces()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .help("Mesure cookies, historiques, caches et stockage local des navigateurs installés. Les navigateurs encore ouverts sont signalés mais épargnés : leurs bases sont verrouillées.")
            }

            // Le second menu reste court : `@ViewBuilder` accepte dix enfants au
            // maximum, et mélanger navigation et actions alourdirait le menu.
            CommandMenu("Navigation") {
                Button("Espace 1 · Purge") { AppState.shared.go(.purge) }
                    .keyboardShortcut("1", modifiers: [.command, .shift])
                Button("Espace 2 · Performance") { AppState.shared.go(.performance) }
                    .keyboardShortcut("2", modifiers: [.command, .shift])
                Button("Espace 3 · Applications") { AppState.shared.go(.applications) }
                    .keyboardShortcut("3", modifiers: [.command, .shift])
                Button("Espace 4 · Sécurité") { AppState.shared.go(.security) }
                    .keyboardShortcut("4", modifiers: [.command, .shift])
                Divider()
                Button("Jauges de surveillance") { AppState.shared.monitorExpanded.toggle() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Tiroir de documentation") {
                    if AppState.shared.docsOpen {
                        AppState.shared.closeDocs()
                    } else {
                        AppState.shared.openDocs(.help)
                    }
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Aide") { AppState.shared.openDocs(.help) }
                Button("FAQ") { AppState.shared.openDocs(.faq) }
                Button("À propos") { AppState.shared.openDocs(.about) }
            }
        }
    }
}