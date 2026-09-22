// ============================================================================
//  MonitorMyMac — Application native macOS (SwiftUI)
//  Version: 2.0.0
//
//  Un outil élégant et convivial pour surveiller, nettoyer et optimiser
//  son Mac en toute simplicité.
//
//  Compilation :
//    swiftc src/MonitorMyMacApp.swift -framework SwiftUI \
//      -o MonitorMyMac.app/Contents/MacOS/MonitorMyMac
// ============================================================================

import SwiftUI
import AppKit
import UserNotifications
import Foundation

// ============================================================================
//  MARK: - Service système (CPU, mémoire, disque, nettoyage)
// ============================================================================

/// Représente une statistique de charge (ratio 0...1).
struct Metric {
    let ratio: Double
    let detail: String
}

/// Service métier : collecte des métriques et opérations de maintenance.
final class SystemMonitor: ObservableObject {

    /// Instance partagée (barre de menus + interface).
    static let shared = SystemMonitor()

    // Métriques exposées à l'interface
    @Published var cpuUsage: Double = 0
    @Published var cpuDetail: String = "En attente…"
    @Published var memoryUsage: Double = 0
    @Published var memoryDetail: String = "En attente…"
    @Published var diskUsage: Double = 0
    @Published var diskDetail: String = "En attente…"
    @Published var osInfo: String = "macOS"
    @Published var modelInfo: String = "—"
    @Published var cpuName: String = "—"
    @Published var coreCount: String = "—"
    @Published var totalMemoryGB: String = "—"
    @Published var uptime: String = "—"
    @Published var log: String = ""
    @Published var statusMessage: String = "Prêt"
    @Published var isProcessing = false
    @Published var cpuHistory: [Double] = []
    @Published var memoryHistory: [Double] = []
    @Published var remindersEnabled: Bool {
        didSet {
            UserDefaults.standard.set(remindersEnabled, forKey: "weeklyReminderEnabled")
            if remindersEnabled {
                Reminder.scheduleWeeklyCleanup()
            } else {
                Reminder.cancelWeeklyCleanup()
            }
        }
    }

    // Gestion du rafraîchissement en direct
    private var refreshTimer: Timer?
    /// Nombre maximal de points d'historique (2 minutes à 2 s = 60 points).
    private let historyCapacity = 60

    private init() {
        remindersEnabled = UserDefaults.standard.bool(forKey: "weeklyReminderEnabled")
    }

    // -------------------------------------------------------------------------
    //  Démarrage et rafraîchissement live
    // -------------------------------------------------------------------------

    func startLiveUpdates() {
        refreshDeviceInfo()
        refreshMetrics()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshMetrics()
            self?.refreshMenuBar()
        }
    }

    /// Actualisation de toutes les métriques.
    func refreshMetrics() {
        cpuUsage = CPU.usage()
        memoryUsage = Memory.usage()
        diskUsage = Disk.usage()
        cpuDetail = String(format: "%.0f %%", cpuUsage * 100)
        memoryDetail = Memory.detail()
        diskDetail = Disk.detail()

        cpuHistory.append(cpuUsage)
        memoryHistory.append(memoryUsage)
        if cpuHistory.count > historyCapacity { cpuHistory.removeFirst(cpuHistory.count - historyCapacity) }
        if memoryHistory.count > historyCapacity { memoryHistory.removeFirst(memoryHistory.count - historyCapacity) }

        // Rafraîchit le texte de la barre de menus.
        MenuBarDelegate.shared.updateQuickStats()
    }

    // -------------------------------------------------------------------------
    //  Gestion de la barre de menus
    // -------------------------------------------------------------------------

    func refreshMenuBar() {
        MenuBarDelegate.shared.updateQuickStats()
    }

    /// Actualisation des informations "statiques" de la machine.
    func refreshDeviceInfo() {
        osInfo = Device.osVersion()
        modelInfo = Device.macModel()
        cpuName = Device.cpuModel()
        coreCount = Device.cpuCount()
        totalMemoryGB = Device.memoryGB()
        uptime = Device.uptime()
    }

    // -------------------------------------------------------------------------
    //  Nettoyage & optimisation
    // -------------------------------------------------------------------------

    /// Exécute les opérations de nettoyage (caches, temp, logs, corbeille).
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

    /// Recherche les gros fichiers (> 100 Mo) à l'emplacement courant.
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

    /// Vide la sortie de journal.
    func clearLog() {
        log = ""
    }

    private func appendLog(_ line: String) {
        if log.isEmpty {
            log = line
        } else {
            log += "\n" + line
        }
    }
}

// ============================================================================
//  MARK: - Collectionneurs de données
// ============================================================================

/// Mesure le taux d'utilisation du processeur via `top`.
enum CPU {
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
        // Valeur comme "47" → % idle
        value = min(max(value / 100, 0), 1)
        return 1 - value
    }

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

/// Les statistiques de mémoire vérifiées à partir de `vm_stat` et `sysctl`.
enum Memory {
    static func usage() -> Double {
        guard let memsize = Device.memsize(), let stats = vmStat() else { return 0 }
        let pageSize: Double = 4096
        let free = (stats["Pages free"] ?? 0) + (stats["Pages inactive"] ?? 0)
        let total = Double(memsize)
        let used = total - free * pageSize
        let ratio = used / total
        return min(max(ratio, 0), 1)
    }

    static func detail() -> String {
        let used = Int64(Double(Device.memsize() ?? 0) * usage())
        let total = Int64((Device.memsize() ?? 0)) / 1
        let usedGB = Double(used) / 1_073_741_824
        let totalGB = Double(total) / 1_073_741_824
        return String(format: "%.1f Go utilisés sur %.1f Go", usedGB, totalGB)
    }

    /// Parse la sortie de `vm_stat` en dictionnaire.
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
                    // Certaines valeurs sont formatées "1." (terminaison de blocs)
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

/// Utilisation du disque dur intervenant à partir de `df`.
enum Disk {
    static func usage() -> Double {
        guard let line = rootLine() else { return 0 }
        // Format : Filesystem Size Used Avail Capacity ...
        let fields = line.split(separator: " ").map(String.init)
        guard fields.count > 4, let capacity = fields[4].dropLast().first, let pct = Double(String(capacity)) else { return 0 }
        return min(max(pct / 100, 0), 1)
    }

    static func detail() -> String {
        guard let line = rootLine() else { return "—" }
        let fields = line.split(separator: " ").map(String.init)
        guard fields.count > 3 else { return "—" }
        return "\(fields[2]) utilisés / \(fields[1]) disponibles"
    }

    /// Première ligne correspondant au volume racine.
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
            if lines.count > 1 { return lines[1] } // saute l'entête
            return nil
        } catch {
            return nil
        }
    }
}

/// Informations statiques sur la machine.
enum Device {
    static func osVersion() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    static func memsize() -> UInt64? {
        return ProcessInfo.processInfo.physicalMemory
    }

    static func cpuModel() -> String {
        sysctlString("machdep.cpu.brand_string") ?? "—"
    }

    static func cpuCount() -> String {
        "\(ProcessInfo.processInfo.activeProcessorCount)"
    }

    static func memoryGB() -> String {
        let mem = ProcessInfo.processInfo.physicalMemory
        return String(format: "%.0f Go", Double(mem) / 1_073_741_824)
    }

    static func macModel() -> String {
        let output = sys("/usr/sbin/system_profiler", ["SPHardwareDataType"])
        for line in output.components(separatedBy: "\n") where line.contains("Model Name") {
            return line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "Model Name:", with: "")
        }
        return "Mac"
    }

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
            // Extraire la durée "up X days, HH:MM"
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

/// Opérations de nettoyage et optimisation.
enum Cleaner {
    /// Fichiers temporaires dans /tmp, plus anciens que 60 minutes.
    static func tempFiles() -> Int {
        delete(in: "/tmp", patterns: ["*"], olderThanMinutes: 60)
    }

    /// Caches utilisateur (.cache / .log) plus anciens que 2 heures.
    static func userCaches() -> Int {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return 0 }
        return delete(in: caches.path, patterns: ["*.cache", "*.log"], olderThanMinutes: 120)
    }

    /// Logs système (plus de 24 h) — selon les permissions.
    static func systemLogs() -> Int {
        delete(in: "/private/var/log", patterns: ["*.log"], olderThanMinutes: 1440)
    }

    /// Vide la corbeille de l'utilisateur.
    static func trash() -> Int {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        guard let items = try? FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil) else { return 0 }
        var removed = 0
        for item in items {
            do {
                try FileManager.default.removeItem(at: item)
                removed += 1
            } catch {
                // ignoré (fichier verrouillé ou en cours d'utilisation)
            }
        }
        return removed
    }

    /// Gros fichiers (> 100 Mo) dans les dossiers courants.
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
    //  Helpers génériques
    // -------------------------------------------------------------------------

    private static func delete(in directory: String, patterns: [String], olderThanMinutes minutes: Int) -> Int {
        guard FileManager.default.fileExists(atPath: directory) else { return 0 }
        var removed = 0
        for pattern in patterns {
            for file in find(directory, patterns: [pattern], olderThanMinutes: minutes) {
                do {
                    try FileManager.default.removeItem(atPath: file)
                    removed += 1
                } catch {
                    // permission ou verrou
                }
            }
        }
        return removed
    }

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
                // ignoré
            }
        }
        return result
    }
}

// ============================================================================
//  MARK: - Rappels de nettoyage (notifications)
// ============================================================================

/// Service de rappels hebdomadaires via UserNotifications.
enum Reminder {

    private static let identifier = "monitormymac.weekly.cleanup"

    /// Demande l'autorisation d'envoyer des notifications.
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Programme un rappel hebdomadaire (dimanche 10 h) si autorisé.
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

            var date = DateComponents()
            date.weekday = 1  // dimanche (1)
            date.hour = 10
            date.minute = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }

    /// Annule le rappel hebdomadaire.
    static func cancelWeeklyCleanup() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

// ============================================================================
//  MARK: - Barre de menus (status item)
// ============================================================================

/// Gère l'icône et le menu de la barre d'état macOS.
final class MenuBarDelegate: NSObject, NSMenuDelegate, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    /// Instance partagée utilisée par l'interface et l'application.
    static let shared = MenuBarDelegate()

    private var statusItem: NSStatusItem?
    private let cpuMenuItem = NSMenuItem(title: "CPU —", action: nil, keyEquivalent: "")
    private let ramMenuItem = NSMenuItem(title: "RAM —", action: nil, keyEquivalent: "")
    private let diskMenuItem = NSMenuItem(title: "Disque —", action: nil, keyEquivalent: "")
    private let statusMenuItem = NSMenuItem(title: "Statut : Prêt", action: nil, keyEquivalent: "")
    private var menuBarTimer: Timer?

    // -------------------------------------------------------------------------
    //  Démarrage de l'application (NSApplicationDelegate)
    // -------------------------------------------------------------------------

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        UNUserNotificationCenter.current().delegate = self
        SystemMonitor.shared.startLiveUpdates()
    }

    // -------------------------------------------------------------------------
    //  Création de l'élément d'état
    // -------------------------------------------------------------------------

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

    /// Construit le menu déroulant de la barre d'état.
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let appItem = NSMenuItem(title: "MonitorMyMac", action: #selector(openMainWindow), keyEquivalent: "")
        appItem.image = NSImage(systemSymbolName: "macbook.and.iphone", accessibilityDescription: "")
        menu.addItem(appItem)
        menu.addItem(.separator())

        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        updateStatusMenuItems()
        for item in [cpuMenuItem, ramMenuItem, diskMenuItem] {
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let cleanItem = NSMenuItem(title: "🧹  Nettoyage rapide", action: #selector(quickCleanup), keyEquivalent: "n")
        menu.addItem(cleanItem)

        let optimizeItem = NSMenuItem(title: "⚡  Optimisation rapide", action: #selector(quickOptimize), keyEquivalent: "o")
        menu.addItem(optimizeItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quitter", action: #selector(quitApp), keyEquivalent: "q")
        menu.addItem(quitItem)

        return menu
    }

    // -------------------------------------------------------------------------
    //  Mise à jour des statistiques dans la barre de menus
    // -------------------------------------------------------------------------

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

    private func updateStatusMenuItems() {
        cpuMenuItem.isEnabled = false
        ramMenuItem.isEnabled = false
        diskMenuItem.isEnabled = false
    }

    // -------------------------------------------------------------------------
    //  Actions du menu
    // -------------------------------------------------------------------------

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    @objc private func quickCleanup() {
        SystemMonitor.shared.runCleanup()
        scheduleMenuBarRefresh()
    }

    @objc private func quickOptimize() {
        SystemMonitor.shared.runOptimization()
        scheduleMenuBarRefresh()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    /// Rafraîchit le menu après une action rapide.
    private func scheduleMenuBarRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.updateQuickStats()
        }
    }

    // -------------------------------------------------------------------------
    //  Observation du menu (à l'ouverture)
    // -------------------------------------------------------------------------

    func menuWillOpen(_ menu: NSMenu) {
        updateQuickStats()
    }

    // -------------------------------------------------------------------------
    //  Notifications (UNUserNotificationCenterDelegate)
    // -------------------------------------------------------------------------

    /// L'utilisateur clique sur un rappel : lance le nettoyage.
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
//  MARK: - Vue principale
// ============================================================================

/// Application élégante : cartes d'informations et actions conviviales.
struct ContentView: View {

    @StateObject private var monitor = SystemMonitor.shared
    @State private var selectedTab: Tab = .surveillance

    enum Tab: String, CaseIterable {
        case surveillance = "Surveillance"
        case nettoyage = "Nettoyage"
        case optimisation = "Optimisation"
    }

    var body: some View {
        ZStack {
            // Fond subtil adaptatif
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
            monitor.startLiveUpdates()
        }
    }

    // -------------------------------------------------------------------------
    //  En-tête élégant
    // -------------------------------------------------------------------------

    private var header: some View {
        HStack(spacing: 14) {
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

            VStack(alignment: .leading, spacing: 2) {
                Text("MonitorMyMac")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("Surveillez, nettoyez et optimisez votre Mac en un clin d’œil")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if monitor.isProcessing {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                monitor.refreshDeviceInfo()
                monitor.refreshMetrics()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.bordered)
            .help("Actualiser immédiatement")
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    // -------------------------------------------------------------------------
    //  Sélecteur d'onglets
    // -------------------------------------------------------------------------

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
            }
        }
    }

    private func icon(for tab: Tab) -> String {
        switch tab {
        case .surveillance: return "gauge.with.dots.needle.50percent"
        case .nettoyage: return "bubbles.and.sparkles"
        case .optimisation: return "bolt.circle.fill"
        }
    }

    // -------------------------------------------------------------------------
    //  Contenu par onglet
    // -------------------------------------------------------------------------

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

            HistoryChartCard(
                cpuSamples: monitor.cpuHistory,
                memorySamples: monitor.memoryHistory
            )
        }
    }

    // -------------------------------------------------------------------------
    //  Journal
    // -------------------------------------------------------------------------

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
            Text("v2.1.0 · 100 % natif")
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

/// Carte avec jauge annulaire animée.
struct GaugeCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let ratio: Double
    let footer: String

    var body: some View {
        HStack(spacing: 16) {
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

/// Carte disque avec barre de progression.
struct DiskCard: View {
    let title: String
    let icon: String
    let color: Color
    let ratio: Double
    let footer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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

/// Carte informative sur le système.
struct SystemCard: View {
    let title: String
    let osInfo: String
    let model: String
    let uptime: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "desktopcomputer")
                    .foregroundStyle(.orange)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                Spacer()
            }

            infoRow(label: "Modèle", value: model)
            infoRow(label: "Version", value: osInfo)
            infoRow(label: "Activité", value: uptime)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                )
        )
    }

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
}

// ============================================================================
//  MARK: - Carte d'historique (sparklines CPU & RAM)
// ============================================================================

/// Carte regroupant les graphiques d'évolution CPU / RAM.
struct HistoryChartCard: View {
    let cpuSamples: [Double]
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
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

/// Courbe de tendance dessinée à partir d'une série d'échantillons.
struct HistoryChart: View {
    let samples: [Double]
    let color: Color
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
                let width = geo.size.width
                let height = geo.size.height
                let baseline = height * 0.92

                ZStack {
                    // Ligne de référence à 100 %
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: baseline - baseline))
                        p.addLine(to: CGPoint(x: width, y: baseline - baseline))
                    }
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)

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

/// Trace le chemin d'une courbe sparkline pour une série de valeurs.
struct SparklinePath: Shape {
    let samples: [Double]

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
            // scale : la valeur va de 0 à 1, 1 étant en haut de la chart
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
//  MARK: - Vues d'actions (nettoyage / optimisation)
// ============================================================================

/// Bouton d'action élégant réutilisable.
struct ActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
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

/// Onglet Nettoyage.
struct CleanupView: View {
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

            HStack(spacing: 12) {
                tipRow(icon: "clock.badge.checkmark", text: "Temp > 60 min")
                tipRow(icon: "folder.badge.gearshape", text: "Caches > 2 h")
                tipRow(icon: "trash", text: "Corbeille vidée")
            }

            reminderToggle
        }
    }

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
    }

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

/// Onglet Optimisation.
struct OptimizationView: View {
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

            HStack(spacing: 12) {
                tipRow(icon: "rectangle.fill.on.rectangle.fill", text: "Gros fichiers détectés")
                tipRow(icon: "arrow.up.right.circle", text: "Espace récupérable")
                tipRow(icon: "checkmark.seal", text: "Sans risque pour vos données")
            }
        }
    }

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
//  MARK: - Délégué du cycle de vie de l'application
// ============================================================================

/// Pont entre le cycle de vie SwiftUI et le singleton de la barre de menus.
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBarDelegate.shared.applicationDidFinishLaunching(notification)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // L'application continue de vivre dans la barre de menus.
        return false
    }
}

// ============================================================================
//  MARK: - Point d'entrée de l'application
// ============================================================================

@main
struct MonitorMyMacApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("MonitorMyMac") {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
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