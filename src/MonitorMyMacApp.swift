// ============================================================================
//  MonitorMyMac — Application native macOS (SwiftUI)
//  Auteur : Martial Zinsou
//  ============================================================================
//
//  ARCHITECTURE GÉNÉRALE
//  ---------------------
//
//  MonitorMyMac est une application macOS 100 % native écrite en Swift + SwiftUI.
//  Elle propose trois grandes familles de fonctions :
//
//    • SURVEILLANCE  — affiche en temps réel les statistiques de la machine :
//      processeur, mémoire vive, stockage et informations système.
//    • NETTOYAGE     — supprime en toute sécurité les fichiers inutiles :
//      caches, fichiers temporaires, logs système et corbeille.
//    • OPTIMISATION  — recherche les fichiers volumineux (> 100 Mo) afin de
//      libérer de l'espace disque.
//
//  L'application propose également :
//      • une icône dans la barre de menus macOS (taux CPU en direct) ;
//      • des graphiques d'historique (courbes de tendance CPU & RAM) ;
//      • des rappels hebdomadaires de nettoyage par notifications.
//
//  COMPILATION (sans Xcode) :
//  -------------------------
//      swiftc -parse-as-library src/MonitorMyMacApp.swift \
//          -framework SwiftUI -framework AppKit -framework UserNotifications \
//          -o MonitorMyMac.app/Contents/MacOS/MonitorMyMac
//
//  PRÉREQUIS : macOS 10.15 ou supérieur (Intel ou Apple Silicon).
//
//  STRUCTURE DU FICHIER :
//  ----------------------
//    1. SystemMonitor      — service observable (singleton) au cœur de l'app.
//    2. CPU / Memory / Disk— collecteurs de métriques système.
//    3. Device             — informations statiques (modèle, macOS, uptime).
//    4. Cleaner            — opérations de nettoyage et d'optimisation.
//    5. Reminder           — rappels hebdomadaires via UserNotifications.
//    6. MenuBarDelegate    — icône de barre de menus + menu + notifications.
//    7. ContentView        — interface principale (en-tête, onglets, journal).
//    8. Cartes UI          — GaugeCard, DiskCard, SystemCard, HistoryChartCard.
//    9. Vues d'action      — CleanupView, OptimizationView, HelpView, Aide.
//   10. Point d'entrée     — struct MonitorMyMacApp (@main).
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

    /// Actualise les métriques dynamiques (CPU, RAM, disque) et l'historique.
    ///
    /// Méthode publique appelée à chaque tick du minuteur, mais aussi manuellement
    /// via le bouton « Actualiser ». Elle met à jour les ratios et détails
    /// affichés par les cartes, enrichit les historiques (bornés à 60 points)
    /// puis rafraîchit le texte de l'icône de la barre de menus.
    func refreshMetrics() {
        cpuUsage = CPU.usage()
        memoryUsage = Memory.usage()
        diskUsage = Disk.usage()
        cpuDetail = String(format: "%.0f %%", cpuUsage * 100)
        memoryDetail = Memory.detail()
        diskDetail = Disk.detail()

        // Enregistre les échantillons pour les graphiques d'évolution.
        cpuHistory.append(cpuUsage)
        memoryHistory.append(memoryUsage)
        if cpuHistory.count > historyCapacity { cpuHistory.removeFirst(cpuHistory.count - historyCapacity) }
        if memoryHistory.count > historyCapacity { memoryHistory.removeFirst(memoryHistory.count - historyCapacity) }

        // Met à jour l'icône et le menu de la barre d'état.
        MenuBarDelegate.shared.updateQuickStats()
    }

    /// Actualise les informations statiques de la machine.
    ///
    /// Les informations « statiques » (modèle, version macOS, mémoire totale,
    /// uptime, processeur) ne changent pas avec le temps ; elles sont donc
    /// rechargées uniquement au lancement ou sur action manuelle.
    func refreshDeviceInfo() {
        osInfo = Device.osVersion()
        modelInfo = Device.macModel()
        cpuName = Device.cpuModel()
        coreCount = Device.cpuCount()
        totalMemoryGB = Device.memoryGB()
        uptime = Device.uptime()
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

        let tasks: [(String, () -> Int)] = [
            ("Fichiers temporaires (/tmp)", { Cleaner.tempFiles() }),
            ("Caches utilisateur", { Cleaner.userCaches() }),
            ("Logs système", { Cleaner.systemLogs() }),
            ("Corbeille", { Cleaner.trash() })
        ]

        for (label, task) in tasks {
            let count = task()
            appendLog("  ✦ \(label) : \(count) élément(s) supprimé(s)")
        }

        appendLog("")
        statusMessage = "Nettoyage terminé ✓"
        isProcessing = false
    }

    /// Recherche les fichiers volumineux (> 100 Mo) afin de libérer de l'espace.
    ///
    /// La recherche porte sur les dossiers Téléchargements, Documents et Bureau.
    /// Les résultats sont affichés dans le journal ; la suppression reste à la
    /// discrétion de l'utilisateur (aucun fichier personnel n'est supprimé).
    func runOptimization() {
        guard !isProcessing else { return }
        isProcessing = true
        statusMessage = "Recherche des gros fichiers…"

        appendLog("═══════════ OPTIMISATION ═══════════")

        let files = Cleaner.largeFiles()
        if files.isEmpty {
            appendLog("Aucun fichier supérieur à 100 Mo trouvé.")
            appendLog("")
        } else {
            appendLog("Fichiers volumineux (> 100 Mo) :")
            for file in files {
                appendLog("  • \(file)")
            }
            appendLog("")
            appendLog("Astuce : effacez-les dans le Finder pour libérer de l'espace.")
        }

        statusMessage = "Optimisation terminée ✓"
        isProcessing = false
    }

    /// Vide entièrement le journal des actions.
    func clearLog() {
        log = ""
    }

    /// Ajoute une ligne au journal (saut de ligne automatique).
    private func appendLog(_ line: String) {
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

    /// Construit un texte lisible décrivant la mémoire (ex. « 6,2/16,0 Go »).
    static func detail() -> String {
        let used = Int64(Double(Device.memsize() ?? 0) * usage())
        let total = Int64((Device.memsize() ?? 0)) / 1
        let usedGB = Double(used) / 1_073_741_824
        let totalGB = Double(total) / 1_073_741_824
        return String(format: "%.1f Go utilisés sur %.1f Go", usedGB, totalGB)
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
        return "\(fields[2]) utilisés / \(fields[1]) disponibles"
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

    /// Supprime les fichiers temporaires de `/tmp` plus anciens que 60 minutes.
    /// - Returns: nombre de fichiers supprimés.
    static func tempFiles() -> Int {
        delete(in: "/tmp", patterns: ["*"], olderThanMinutes: 60)
    }

    /// Supprime les caches utilisateur (`.cache` / `.log`) plus anciens que 2 h.
    /// - Returns: nombre de fichiers supprimés.
    static func userCaches() -> Int {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return 0 }
        return delete(in: caches.path, patterns: ["*.cache", "*.log"], olderThanMinutes: 120)
    }

    /// Supprime les logs système de plus de 24 h (selon les permissions).
    /// - Returns: nombre de fichiers supprimés (0 si droits insuffisants).
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
    private static func delete(in directory: String, patterns: [String], olderThanMinutes minutes: Int) -> Int {
        guard FileManager.default.fileExists(atPath: directory) else { return 0 }
        var removed = 0
        for pattern in patterns {
            for file in find(directory, patterns: [pattern], olderThanMinutes: minutes) {
                do {
                    try FileManager.default.removeItem(atPath: file)
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
        appItem.image = NSImage(systemSymbolName: "macbook.and.iphone", accessibilityDescription: "")
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
        menu.addItem(cleanItem)

        let optimizeItem = NSMenuItem(title: "⚡  Optimisation rapide", action: #selector(quickOptimize), keyEquivalent: "o")
        menu.addItem(optimizeItem)

        menu.addItem(.separator())

        // — Sortie de l'application.
        let quitItem = NSMenuItem(title: "Quitter", action: #selector(quitApp), keyEquivalent: "q")
        menu.addItem(quitItem)

        return menu
    }

    // -------------------------------------------------------------------------
    //  Mise à jour des statistiques
    // -------------------------------------------------------------------------

    /// Met à jour le texte de l'icône et les lignes de statistiques du menu.
    ///
    /// L'icône affiche le taux CPU (ex. « 23% ») ; l'infobulle et le menu
    /// affichent CPU, RAM et disque. Cette méthode est appelée à chaque rafraîchissement.
    func updateQuickStats() {
        guard let button = statusItem?.button else { return }
        let monitor = SystemMonitor.shared
        button.title = String(format: " %d%%", Int(monitor.cpuUsage * 100))
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
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
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
///   1. un **en-tête** élégant (logo, titre, bouton d'aide, actualisation) ;
///   2. un **sélecteur d'onglets** (Surveillance / Nettoyage / Optimisation) ;
///   3. le **contenu** de l'onglet sélectionné ;
///   4. le **journal** des actions ;
///   5. un **pied de page** avec le statut courant.
struct ContentView: View {

    /// Instance partagée du service de métriques (singleton).
    @StateObject private var monitor = SystemMonitor.shared
    /// Onglet sélectionné (par défaut : Surveillance ; `--tab=` en ligne de commande).
    @State private var selectedTab: Tab = ContentView.defaultTab()
    /// Affiche ou masque la fenêtre d'aide.
    @State private var showHelp = false

    /// Les trois onglets disponibles.
    enum Tab: String, CaseIterable {
        /// Surveillance des métriques système en temps réel.
        case surveillance = "Surveillance"
        /// Nettoyage des caches, fichiers temporaires, logs et corbeille.
        case nettoyage = "Nettoyage"
        /// Optimisation : recherche des fichiers volumineux.
        case optimisation = "Optimisation"

        /// Onglet demandé via l'argument `--tab=xxx` (usage avancé / captures).
        /// Exemples : `--tab=nettoyage`, `--tab=optimisation`.
        static func fromCommandLine() -> Tab? {
            let args = CommandLine.arguments
            for arg in args {
                let parts = arg.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2, parts[0] == "--tab" {
                    return Tab(rawValue: parts[1].lowercased().capitalized)
                }
            }
            return nil
        }
    }

    /// Onglet initial au lancement (surveillance par défaut).
    static func defaultTab() -> Tab {
        return Tab.fromCommandLine() ?? .surveillance
    }

    var body: some View {
        ZStack {
            // Fond subtil adaptatif (clair / sombre automatique).
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor).opacity(0.95),
                    Color.accentColor.opacity(0.06)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                tabSelector
                content
                footer
            }
        }
        .frame(minWidth: 720, minHeight: 620)
        .onAppear {
            // Si lancé avec `--help`, ouvre la fenêtre d'aide automatiquement.
            showHelp = CommandLine.arguments.contains("--help")
            // Démarre (ou relance) le rafraîchissement automatique des métriques.
            monitor.startLiveUpdates()
        }
        .sheet(isPresented: $showHelp) {
            // Fenêtre d'aide illustrée accessible depuis l'en-tête.
            HelpView()
        }
    }

    // -------------------------------------------------------------------------
    //  En-tête élégant
    // -------------------------------------------------------------------------

    /// En-tête : logo dégradé, titre de l'application, boutons d'aide
    /// et d'actualisation manuelle.
    private var header: some View {
        HStack(spacing: 14) {
            // Logo de l'application.
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                Image(systemName: "macbook.and.iphone")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
            }
            .shadow(color: Color.purple.opacity(0.35), radius: 8, y: 4)

            // Titre et sous-titre.
            VStack(alignment: .leading, spacing: 2) {
                Text("MonitorMyMac")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("Surveillez, nettoyez et optimisez votre Mac en un clin d’œil")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Indicateur d'activité pendant une opération de maintenance.
            if monitor.isProcessing {
                ProgressView()
                    .controlSize(.small)
            }

            // Bouton d'aide (ouvre la fenêtre d'aide illustrée).
            Button {
                showHelp = true
            } label: {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Aide et guide d'utilisation")

            // Bouton d'actualisation manuelle.
            Button {
                monitor.refreshDeviceInfo()
                monitor.refreshMetrics()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.bordered)
            .help("Actualiser immédiatement les statistiques")
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    // -------------------------------------------------------------------------
    //  Sélecteur d'onglets
    // -------------------------------------------------------------------------

    /// Barre d'onglets avec animation douce et icônes illustratives.
    private var tabSelector: some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: icon(for: tab))
                        Text(tab.rawValue)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(
                            selectedTab == tab
                                ? Color.accentColor
                                : Color.gray.opacity(0.12)
                        )
                    )
                    .foregroundStyle(selectedTab == tab ? .white : .primary)
                }
                .buttonStyle(.plain)
                .help(helpText(for: tab))
            }
        }
    }

    /// Sélectionne le symbole SF associé à un onglet.
    private func icon(for tab: Tab) -> String {
        switch tab {
        case .surveillance: return "gauge.with.dots.needle.50percent"
        case .nettoyage: return "bubbles.and.sparkles"
        case .optimisation: return "bolt.circle.fill"
        }
    }

    /// Description contextuelle (bulle d'aide) pour chaque onglet.
    private func helpText(for tab: Tab) -> String {
        switch tab {
        case .surveillance:
            return "Consultation en temps réel du processeur, de la mémoire et du disque."
        case .nettoyage:
            return "Supprime les caches, fichiers temporaires, logs système et la corbeille."
        case .optimisation:
            return "Recherche les fichiers volumineux afin de libérer de l'espace disque."
        }
    }

    // -------------------------------------------------------------------------
    //  Contenu par onglet
    // -------------------------------------------------------------------------

    /// Affiche le contenu de l'onglet sélectionné puis le journal en dessous.
    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch selectedTab {
                case .surveillance:
                    monitoringGrid
                case .nettoyage:
                    CleanupView(monitor: monitor)
                case .optimisation:
                    OptimizationView(monitor: monitor)
                }

                logPanel
            }
            .padding(24)
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
                    .foregroundStyle(.secondary)
                Spacer()
                if !monitor.log.isEmpty {
                    Button("Effacer") { monitor.clearLog() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .help("Vider le journal des actions")
                }
            }

            ScrollView {
                Text(monitor.log.isEmpty ? "Aucune action pour le moment." : monitor.log)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
            Spacer()
            Text("v2.1.0 · 100 % natif · auteur : Martial Zinsou")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
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
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 66, height: 66)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(subtitle)
                Text(footer)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(color)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
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
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text("\(Int(ratio * 100)) %")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
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
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    /// Fond de carte arrondi avec ombre légère.
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
            )
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
                Image(systemName: "desktopcomputer")
                    .foregroundStyle(.orange)
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
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }

    /// Fond de carte arrondi avec ombre légère.
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
            )
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
                    .foregroundStyle(.tertiary)
            }

            HistoryChart(samples: cpuSamples, color: .blue, title: "Processeur")
            HistoryChart(samples: memorySamples, color: .purple, title: "Mémoire")
        }
        .padding(18)
        .background(cardBackground)
    }

    /// Fond de carte arrondi avec ombre légère.
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
            )
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
                    .foregroundStyle(.secondary)
                Spacer()
                if let last = samples.last {
                    Text("\(Int(last * 100)) %")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
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
//  MARK: - Vues d'action (nettoyage / optimisation)
//  ============================================================================

/// Bouton d'action élégant et réutilisable.
///
/// Présente une icône colorée, un titre, un sous-titre et une flèche, le tout
/// dans une carte arrondie avec ombre portée.
struct ActionButton: View {
    /// Titre principal de l'action.
    let title: String
    /// Sous-titre descriptif.
    let subtitle: String
    /// Symbole SF de l'action.
    let icon: String
    /// Couleur de l'icône et du dégradé.
    let color: Color
    /// Bloc exécuté au clic.
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Pastille iconographique colorée.
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(colors: [color, color.opacity(0.75)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
                .shadow(color: color.opacity(0.35), radius: 6, y: 3)

                // Texte de l'action.
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// ============================================================================
//  MARK: - Onglet Nettoyage
// ============================================================================

/// Contenu de l'onglet **Nettoyage**.
///
/// Propose le bouton « Nettoyage intelligent » (caches, fichiers temporaires,
/// logs système, corbeille), trois indicateurs détaillant la portée du
/// nettoyage et l'interrupteur des rappels hebdomadaires.
struct CleanupView: View {
    /// Service observé (métriques et actions).
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        VStack(spacing: 16) {
            ActionButton(
                title: "Nettoyage intelligent",
                subtitle: "Caches, fichiers temporaires, logs système et corbeille",
                icon: "bubbles.and.sparkles.fill",
                color: .pink
            ) {
                monitor.runCleanup()
            }

            // Indicateurs descriptifs de la portée du nettoyage.
            HStack(spacing: 12) {
                tipRow(icon: "clock.badge.checkmark", text: "Temp > 60 min")
                tipRow(icon: "folder.badge.gearshape", text: "Caches > 2 h")
                tipRow(icon: "trash", text: "Corbeille vidée")
            }

            // Interrupteur des rappels hebdomadaires.
            reminderToggle
        }
    }

    /// Interrupteur d'activation du **rappel hebdomadaire** de nettoyage.
    ///
    /// Lorsque activé, une notification est programmée chaque dimanche à 10 h.
    private var reminderToggle: some View {
        Toggle(isOn: $monitor.remindersEnabled) {
            HStack(spacing: 8) {
                Image(systemName: monitor.remindersEnabled ? "bell.badge.fill" : "bell.badge")
                    .font(.system(size: 15))
                    .foregroundStyle(monitor.remindersEnabled ? Color.pink : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rappel hebdomadaire de nettoyage")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Une notification chaque dimanche à 10 h")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.gray.opacity(0.07))
            )
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 2)
        .help("Active ou désactive le rappel hebdomadaire de nettoyage (dimanche 10 h)")
    }

    /// Petite pastille descriptive utilisée sous le bouton principal.
    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.pink)
                .font(.system(size: 12))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.gray.opacity(0.08)))
    }
}

// ============================================================================
//  MARK: - Onglet Optimisation
// ============================================================================

/// Contenu de l'onglet **Optimisation**.
///
/// Propose le bouton « Analyse de l'espace » (recherche des fichiers
/// volumineux) accompagné de trois pastilles descriptives.
struct OptimizationView: View {
    /// Service observé (métriques et actions).
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        VStack(spacing: 16) {
            ActionButton(
                title: "Analyse de l'espace",
                subtitle: "Recherche les fichiers volumineux (> 100 Mo) dans vos dossiers",
                icon: "bolt.fill",
                color: .orange
            ) {
                monitor.runOptimization()
            }

            // Indicateurs descriptifs.
            HStack(spacing: 12) {
                tipRow(icon: "rectangle.fill.on.rectangle.fill", text: "Gros fichiers détectés")
                tipRow(icon: "arrow.up.right.circle", text: "Espace récupérable")
                tipRow(icon: "checkmark.seal", text: "Sans risque pour vos données")
            }
        }
    }

    /// Petite pastille descriptive utilisée sous le bouton principal.
    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
                .font(.system(size: 12))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.gray.opacity(0.08)))
    }
}

// ============================================================================
//  MARK: - Aide illustrée
// ============================================================================

/// Fenêtre d'aide modale décrivant chaque fonctionnalité de l'application.
///
/// L'aide est organisée en sections illustrées par des symboles SF :
/// surveillance, nettoyage, optimisation, barre de menus et rappels.
struct HelpView: View {
    /// Fermeture de la fenêtre d'aide.
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Titre de la fenêtre.
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 40, height: 40)
                    Image(systemName: "macbook.and.iphone")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading) {
                    Text("Aide et guide d'utilisation")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("Découvrez tout ce que MonitorMyMac peut faire pour vous")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .help("Auteur : Martial Zinsou")
                }
                Spacer()
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    helpSection(
                        icon: "gauge.with.dots.needle.50percent",
                        color: .blue,
                        title: "Surveillance en temps réel",
                        description: "Le tableau de bord actualise automatiquement le processeur, la mémoire vive et l'espace disque toutes les 2 secondes. Les courbes d'historique au bas de la page montrent l'évolution CPU et RAM sur les 2 dernières minutes."
                    )
                    helpSection(
                        icon: "bubbles.and.sparkles.fill",
                        color: .pink,
                        title: "Nettoyage intelligent",
                        description: "Un clic supprime en toute sécurité les fichiers temporaires (/tmp > 60 min), les caches utilisateur (.cache et .log > 2 h), les logs système (> 24 h) et vide la corbeille. Aucun fichier personnel n'est touché."
                    )
                    helpSection(
                        icon: "bolt.fill",
                        color: .orange,
                        title: "Optimisation de l'espace",
                        description: "« Analyse de l'espace » liste les fichiers de plus de 100 Mo dans vos dossiers Téléchargements, Documents et Bureau. Vous pouvez ensuite décider vous-même de les supprimer dans le Finder."
                    )
                    helpSection(
                        icon: "menubar.rectangle",
                        color: .green,
                        title: "Barre de menus",
                        description: "Une icône reste visible en haut de l'écran avec le taux CPU en direct. Le menu donne accès aux statistiques, à un Nettoyage rapide (⌘⇧N) et à une Optimisation rapide (⌘⇧O), même fenêtre fermée."
                    )
                    helpSection(
                        icon: "bell.badge.fill",
                        color: .purple,
                        title: "Rappels hebdomadaires",
                        description: "Activez le rappel dans l'onglet Nettoyage : une notification chaque dimanche à 10 h vous suggère un nettoyage. Cliquer sur la notification lance immédiatement le nettoyage automatique."
                    )
                }
                .padding(.vertical, 4)
            }

            Divider()

            HStack {
                Text("Créé par Martial Zinsou · 100 % natif macOS")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520, height: 540)
    }

    /// Section d'aide : icône + titre + description.
    private func helpSection(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
/// menus) et ajoute un menu « Actions » avec des raccourcis clavier pratiques :
///   • ⌘⇧N — Nettoyage rapide ;
///   • ⌘⇧O — Optimisation rapide.
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
            // Raccourcis clavier utilitaires.
            CommandMenu("Actions") {
                Button("Nettoyage rapide") {
                    SystemMonitor.shared.runCleanup()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Optimisation rapide") {
                    SystemMonitor.shared.runOptimization()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }
}