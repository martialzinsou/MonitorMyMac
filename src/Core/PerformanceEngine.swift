// ============================================================================
//  MonitorMyMac — moteur « Performance » (optimisation des performances)
//  Auteur : Martial Zinsou
//  ============================================================================
//
//  Quatre familles, comme demandé :
//
//    1. Libération de la mémoire vive : mesure réelle (`vm_stat`, `sysctl`),
//       puis `purge` exécuté avec droits administrateur et comparaison
//       avant/après chiffrée ;
//    2. Éléments de démarrage : LaunchAgents/LaunchDaemons (utilisateur et
//       système) + éléments « Ouverture » de System Events, désactivation
//       **réversible** (suffixe .mmm-off) et déchargement launchd réel ;
//    3. Scripts de maintenance : Spotlight, autorisations, Launch Services,
//       cache DNS, scripts périodiques, logs système — chaque commande est
//       affichée avec sa sortie réelle et son code de retour ;
//    4. Applications gourmandes : CPU/RAM par processus (`ps`) et énergie
//       (`top -o power`), fermeture propre des applications concernées.
// ============================================================================

import Foundation
import AppKit

// ============================================================================
//  MARK: - Snapshot mémoire
//  ============================================================================

/// Instantané détaillé de la mémoire vive, calculé à partir de sources réelles.
struct MemorySnapshot {
    /// Mémoire physique totale.
    let total: Int64
    /// Pages actives (utilisées maintenant).
    let active: Int64
    /// Pages inactives (récupérables).
    let inactive: Int64
    /// Pages libres.
    let free: Int64
    /// Mémoire câblée (noyau, non libérable).
    let wired: Int64
    /// Mémoire compressée.
    let compressed: Int64
    /// swapping utilisé.
    let swapUsed: Int64
    /// Swap total disponible.
    let swapTotal: Int64

    /// Mémoire « utilisée » macOS-like (active + câblée + compressée).
    var used: Int64 { active + wired + compressed }
    /// Partie réellement récupérable sans fermer d'application.
    var purgeable: Int64 { inactive + free }
    /// Pression mémoire (0 → 1).
    var pressure: Double { total > 0 ? Double(used) / Double(total) : 0 }

    /// Libellé d'état pour l'interface.
    var stateLabel: String {
        switch pressure {
        case ..<0.55: return "confortable"
        case ..<0.78: return "normale"
        case ..<0.92: return "tendue"
        default: return "critique"
        }
    }

    /// Instantané neutre, utilisé avant la première mesure réelle.
    ///
    /// Un singleton d'interface ne doit **jamais** exécuter une commande au
    /// moment de sa création : `PerformanceModel.shared` est initialisé pendant
    /// que SwiftUI construit une vue, et `Shell` attend la fin du processus.
    /// Cette valeur vide évite tout travail bloquant dans l'initialiseur.
    static let empty = MemorySnapshot(total: 0, active: 0, inactive: 0, free: 0,
                                      wired: 0, compressed: 0, swapUsed: 0, swapTotal: 0)

    /// Lecture réelle des compteurs (`vm_stat`, taille physique, échange).
    static func read() -> MemorySnapshot {
        let stats = Memory.vmStat() ?? [:]
        let pageSize = Int64(systemPageSize())
        let pages = { (key: String) -> Int64 in Int64(stats[key] ?? 0) * pageSize }
        let total = Int64(ProcessInfo.processInfo.physicalMemory)

        // Swap : `sysctl vm.swapusage` → « total = 1024.00M used = 312.25M free = 711.75M »
        let swap = Shell.run("/usr/sbin/sysctl", ["-n", "vm.swapusage"])
        var swapTotal: Int64 = 0
        var swapUsed: Int64 = 0
        if swap.succeeded {
            swapTotal = parseSizeToken(swap.stdout, key: "total")
            swapUsed = parseSizeToken(swap.stdout, key: "used")
        }

        return MemorySnapshot(
            total: total,
            active: pages("Pages active"),
            inactive: pages("Pages inactive"),
            free: pages("Pages free"),
            wired: pages("Pages wired down"),
            compressed: pages("Pages occupied by compressor"),
            swapUsed: swapUsed,
            swapTotal: swapTotal
        )
    }

    /// Taille de page réelle du système (4 Ko sur Intel, 16 Ko sur Apple Silicon).
    private static func systemPageSize() -> Int {
        let outcome = Shell.run("/usr/sbin/sysctl", ["-n", "hw.pagesize"], timeout: 5)
        return Int(outcome.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 4096
    }

    /// Interprète une taille (« 312.25M ») dans une sortie sysctl.
    private static func parseSizeToken(_ text: String, key: String) -> Int64 {
        guard let range = text.range(of: key) else { return 0 }
        let tail = text[range.upperBound...]
        let scanner = tail.trimmingCharacters(in: .alphanumerics.inverted)
        var number = ""
        for character in scanner {
            if character.isNumber || character == "." { number.append(character) } else { break }
        }
        let unit = scanner.dropFirst(number.count).first
        let value = Double(number) ?? 0
        switch unit {
        case "G": return Int64(value * 1_073_741_824)
        case "M": return Int64(value * 1_048_576)
        case "K": return Int64(value * 1_024)
        default: return Int64(value)
        }
    }
}

// ============================================================================
//  MARK: - Processus gourmands
//  ============================================================================

/// Un processus identifié comme consommateur de CPU, de RAM ou de batterie.
struct ProcessEntry: Identifiable, Hashable {
    /// Identifiant système (pid).
    var id: Int32 { pid }
    let pid: Int32
    /// Nom affiché (commande `ps`).
    let name: String
    /// Pourcentage CPU (moyenne glissante de `ps`).
    let cpu: Double
    /// Pourcentage mémoire.
    let memory: Double
    /// Mémoire résidente (octets).
    let residentBytes: Int64
    /// Utilisateur propriétaire du processus (colonne `user` de `ps`).
    let user: String
    /// Estimation d'énergie (`top -o power`), nil si la commande a échoué.
    var energy: Double?
    /// Vrai si une application graphique correspond au processus.
    var isGuiApplication: Bool

    /// Nom d'application déduit (regroupe les helpers : « Chrome Helper » → « Google Chrome »).
    var ownerName: String {
        let cleaned = name
            .replacingOccurrences(of: " Helper", with: "")
            .replacingOccurrences(of: " (Renderer)", with: "")
            .replacingOccurrences(of: " (GPU)", with: "")
            .replacingOccurrences(of: " (Plugin)", with: "")
        return cleaned
    }

    /// Libellé de consommation pour la liste.
    var detail: String {
        var text = String(format: "%.0f %% CPU · %.1f %% RAM · %@", cpu, memory, Fmt.size(residentBytes))
        if let energy = energy { text += String(format: " · énergie %.1f", energy) }
        return text
    }

    /// Peut-on agir sur ce processus depuis notre session ?
    ///
    /// Règle réelle : un utilisateur ne peut tuer que ses propres processus
    /// (`ps` indique le propriétaire) ; les apps graphiques de la session sont
    /// fermables proprement via `NSRunningApplication`.
    var killable: Bool { user == NSUserName() || isGuiApplication }

    /// Message expliquant une fermeture impossible.
    var blockReason: String {
        return "Processus appartenant à « \(user) » : une authentification administrateur serait nécessaire."
    }
}

/// Une application et l'ensemble de ses processus (helpers regroupés).
///
/// Structure plutôt que tuple : l'interface a besoin d'une identité Stable pour
/// `ForEach` et ne peut pas utiliser de clé sur un tuple.
struct AppConsumption: Identifiable, Hashable {
    var id: String { name }
    /// Nom agrégé (« Google Chrome », « kernel_task »…).
    let name: String
    /// CPU cumulé des processus (somme des pourcentages `ps`).
    let cpu: Double
    /// Mémoire résidente cumulée.
    let bytes: Int64
    /// Identifiants de processus regroupés.
    let pids: [Int32]
    /// Au moins un processus est une application graphique fermeable proprement.
    let gui: Bool
}

/// Collecte des processus les plus consommateurs.
enum ProcessProbe {

    /// Top des consommateurs CPU/RAM via `ps` (une seule mesure, ~0,2 s).
    static func topConsumers(limit: Int = 18) -> [ProcessEntry] {
        let outcome = Shell.run("/bin/ps",
                                ["-Aceo", "pid=,user=,pcpu=,pmem=,rss=,comm=", "-r"], timeout: 20)
        guard outcome.succeeded else { return [] }
        let guiPids = Set(NSWorkspace.shared.runningApplications.map { Int32($0.processIdentifier) })
        var entries: [ProcessEntry] = []

        for line in outcome.stdout.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 5,
                                   omittingEmptySubsequences: true).map(String.init)
            guard fields.count == 6, let pid = Int32(fields[0]),
                  let cpu = Double(fields[2]), let mem = Double(fields[3]),
                  let rss = Int64(fields[4]) else { continue }
            entries.append(ProcessEntry(pid: pid, name: fields[5], cpu: cpu, memory: mem,
                                        residentBytes: rss * 1_024, user: fields[1], energy: nil,
                                        isGuiApplication: guiPids.contains(pid)))
            if entries.count >= limit { break }
        }
        return entries
    }

    /// Top des consommateurs de batterie via `top -o power` (2 échantillons).
    ///
    /// Retourne un dictionnaire pid → énergie. Vide si la commande n'est pas
    /// disponible sur la machine : l'interface affiche alors « — » au lieu
    /// d'inventer une valeur.
    static func energyByPid() -> [Int32: Double] {
        let outcome = Shell.run("/usr/bin/top",
                                ["-l", "2", "-s", "1", "-n", "30", "-o", "power",
                                 "-stats", "pid,command,power"], timeout: 20)
        guard outcome.succeeded else { return [:] }
        var result: [Int32: Double] = [:]
        var sample = 0
        for rawLine in outcome.stdout.split(separator: "\n").map(String.init) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("PID") { sample += 1; continue }
            guard sample >= 2 else { continue }          // seul le 2ᵉ échantillon est fiable
            let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let pid = Int32(fields.first ?? ""), fields.count >= 3,
                  let value = Double(fields.last ?? "") else { continue }
            result[pid] = value
        }
        return result
    }

    /// Regroupe les processus par application (helpers inclus).
    static func groupedByApplication(_ entries: [ProcessEntry]) -> [AppConsumption] {
        var buckets: [String: (cpu: Double, bytes: Int64, pids: [Int32], gui: Bool)] = [:]
        for entry in entries {
            var bucket = buckets[entry.ownerName] ?? (0, 0, [], false)
            bucket.cpu += entry.cpu
            bucket.bytes += entry.residentBytes
            bucket.pids.append(entry.pid)
            bucket.gui = bucket.gui || entry.isGuiApplication
            buckets[entry.ownerName] = bucket
        }
        return buckets
            .map { AppConsumption(name: $0.key, cpu: $0.value.cpu, bytes: $0.value.bytes,
                                  pids: $0.value.pids, gui: $0.value.gui) }
            .sorted { $0.cpu > $1.cpu }
    }

    /// Ferme proprement un processus (terminaison douce puis forcée pour les apps).
    ///
    /// - Returns: message d'état réel (succès ou erreur système).
    @discardableResult
    static func terminate(_ entry: ProcessEntry) -> String {
        if entry.isGuiApplication,
           let application = NSRunningApplication(processIdentifier: entry.pid) {
            let gentle = application.terminate()
            for _ in 0..<20 {
                if application.isTerminated { return "Application fermée proprement." }
                Thread.sleep(forTimeInterval: 0.15)
            }
            if gentle {
                application.forceTerminate()
                return application.isTerminated
                    ? "Application fermée (les tâches en cours ont été interrompues)."
                    : "Fermeture refusée par macOS."
            }
        }
        if kill(entry.pid, SIGTERM) == 0 { return "Signal SIGTERM envoyé (pid \(entry.pid))." }
        if kill(entry.pid, SIGKILL) == 0 { return "Signal SIGKILL envoyé (pid \(entry.pid))." }
        return "Fermeture impossible : droits insuffisants (processus appartenant probablement à root)."
    }
}

// ============================================================================
//  MARK: - Éléments de démarrage
//  ============================================================================

/// Type d'élément de démarrage détecté.
enum LoginItemKind: String {
    case userAgent = "Agent de l'utilisateur"
    case systemAgent = "Agent système"
    case daemon = "Démon système"
    case sessionItem = "Ouverture de session"
}

/// Un élément qui se lance au démarrage (ou à l'ouverture de session).
struct LoginItem: Identifiable, Hashable {
    var id: String { path ?? "\(kind.rawValue)-\(label)" }
    /// Étiquette (`Label` du plist ou nom de l'élément).
    let label: String
    /// Nom lisible de l'application concernée.
    let title: String
    /// Ce qui sera réellement lancé.
    let command: String
    /// Chemin du fichier plist (nil pour les éléments de System Events).
    let path: String?
    /// Catégorie.
    let kind: LoginItemKind
    /// L'élément est-il actuellement chargé dans launchd ?
    let loaded: Bool
    /// Désactivé par MonitorMyMac (suffixe .mmm-off) ?
    let disabledByApp: Bool
    /// L'app peut-elle le désactiver sans droits administrateur ?
    let manageable: Bool
    /// Utilisateur propriétaire de l'élément (`UserName` du plist).
    let owner: String?

    /// Résumé affiché sous le titre.
    var detail: String {
        var text = "\(kind.rawValue)"
        if let path = path { text += " · \(Fmt.prettyPath(path))" }
        if loaded { text += " · chargé" } else if disabledByApp { text += " · désactivé par MonitorMyMac" }
        else { text += " · non chargé" }
        if let owner = owner, owner != NSUserName() { text += " · \(owner)" }
        return text
    }
}

/// Lit et modifie les éléments de démarrage.
enum StartupManager {

    /// Suffixe appliqué aux plist désactivés (launchd n'en tient pas compte).
    static let disabledSuffix = ".mmm-off"

    /// Dossier de sauvegarde interne (manifeste des désactivations).
    static var stateDirectory: URL {
        let url = PathPolicy.home
            .appendingPathComponent("Library/Application Support/MonitorMyMac/Startup")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Éléments actuellement chargés (`launchctl list`).
    static func loadedLabels() -> Set<String> {
        let outcome = Shell.run("/bin/launchctl", ["list"], timeout: 20)
        guard outcome.succeeded else { return [] }
        var labels: Set<String> = []
        for line in outcome.stdout.split(separator: "\n").dropFirst() {
            let fields = line.split(separator: "\t").map(String.init)
            if let label = fields.last, !label.isEmpty { labels.insert(label) }
        }
        return labels
    }

    /// Balayage complet : LaunchAgents utilisateur/système, LaunchDaemons,
    /// et éléments « Ouverture » connus de System Events.
    static func items() -> [LoginItem] {
        var result: [LoginItem] = []
        let loaded = loadedLabels()

        let sources: [(kind: LoginItemKind, url: URL, manageable: Bool)] = [
            (.userAgent, PathPolicy.userLibrary.appendingPathComponent("LaunchAgents"), true),
            (.systemAgent, URL(fileURLWithPath: "/Library/LaunchAgents"), false),
            (.daemon, URL(fileURLWithPath: "/Library/LaunchDaemons"), false)
        ]

        for source in sources {
            let children = (try? FileManager.default.contentsOfDirectory(
                at: source.url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for url in children where url.lastPathComponent.hasSuffix(".plist")
                || url.lastPathComponent.hasSuffix(disabledSuffix) {
                if let item = parse(plist: url, kind: source.kind, loaded: loaded, manageable: source.manageable) {
                    result.append(item)
                }
            }
        }

        // Éléments d'ouverture gérés par macOS (System Events) : lecture seule
        // si l'autorisation « Automation » n'est pas accordée.
        let session = Shell.appleScript(
            "tell application \"System Events\" to get the name of every login item", timeout: 30)
        if session.succeeded {
            for name in session.stdout.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) })
            where !name.isEmpty {
                result.append(LoginItem(label: name, title: name, command: "ouverture de session macOS",
                                        path: nil, kind: .sessionItem, loaded: true,
                                        disabledByApp: false, manageable: true, owner: NSUserName()))
            }
        } else {
            result.append(LoginItem(label: "Session (System Events)",
                                    title: "Éléments d'ouverture macOS",
                                    command: session.failure ?? "introuvable",
                                    path: nil, kind: .sessionItem, loaded: false,
                                    disabledByApp: false, manageable: false, owner: nil))
        }

        return result.sorted { $0.title.lowercased() < $1.title.lowercased() }
    }

    /// Convertit un plist launchd en `LoginItem`.
    private static func parse(plist url: URL, kind: LoginItemKind,
                              loaded: Set<String>, manageable: Bool) -> LoginItem? {
        guard let dictionary = NSDictionary(contentsOf: url) else { return nil }
        let disabled = url.lastPathComponent.hasSuffix(disabledSuffix)
        let base = disabled
            ? String(url.lastPathComponent.dropLast(disabledSuffix.count))
            : url.lastPathComponent
        let fileName = (base as NSString).deletingPathExtension
        let label = (dictionary["Label"] as? String) ?? fileName
        var command = ""
        if let program = dictionary["Program"] as? String {
            command = program
        } else if let arguments = dictionary["ProgramArguments"] as? [String] {
            command = arguments.joined(separator: " ")
        }
        let runAtLoad = (dictionary["RunAtLoad"] as? Bool) ?? false
        let title = inferTitle(from: url.lastPathComponent, command: command)
        let displayName = disabled ? "\(title) — désactivé" : title
        return LoginItem(label: label, title: displayName,
                         command: command.isEmpty ? "(non précisé)" : command + (runAtLoad ? " · RunAtLoad" : ""),
                         path: url.path, kind: kind,
                         loaded: loaded.contains(label) && !disabled,
                         disabledByApp: disabled,
                         manageable: manageable,
                         owner: dictionary["UserName"] as? String)
    }

    /// Déduit un nom d'application lisible depuis le fichier ou la commande.
    private static func inferTitle(from fileName: String, command: String) -> String {
        if let range = command.range(of: "/Applications/") {
            let tail = command[range.lowerBound...].components(separatedBy: "/")
            if let app = tail.first(where: { $0.hasSuffix(".app") }) {
                return app.replacingOccurrences(of: ".app", with: "")
            }
        }
        var name = fileName
        if name.hasSuffix(disabledSuffix) { name = String(name.dropLast(disabledSuffix.count)) }
        if name.hasSuffix(".plist") { name = String(name.dropLast(6)) }
        return name
    }

    /// Désactive un élément : décharge launchd puis renomme le plist.
    static func disable(_ item: LoginItem) -> String {
        guard let path = item.path else {
            let outcome = Shell.appleScript(
                "tell application \"System Events\" to delete login item \"\(item.label)\"", timeout: 30)
            return outcome.succeeded ? "Élément d'ouverture retiré." : (outcome.failure ?? "échec")
        }
        let url = URL(fileURLWithPath: path)
        if item.kind == .userAgent {
            _ = Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(item.label)"], timeout: 20)
        }
        let target = url.appendingPathExtension("mmm-off")
        do {
            try FileManager.default.moveItem(at: url, to: target)
            try Data("désactivé le \(Date())\n".utf8)
                .write(to: stateDirectory.appendingPathComponent(item.label + ".note"))
            return "Désactivé (plist renommé en \(target.lastPathComponent)) — réversible."
        } catch {
            return "Désactivation impossible : \(error.localizedDescription)"
        }
    }

    /// Réactive un élément précédemment désactivé.
    static func enable(_ item: LoginItem) -> String {
        guard let path = item.path, path.hasSuffix(disabledSuffix) else {
            return "Aucun plist désactivé à réactiver pour cet élément."
        }
        let url = URL(fileURLWithPath: path)
        let target = url.deletingPathExtension()
        do {
            try FileManager.default.moveItem(at: url, to: target)
            if item.kind == .userAgent {
                _ = Shell.run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", target.path], timeout: 20)
            }
            return "Réactivé (\(target.lastPathComponent)) et rechargé dans launchd."
        } catch {
            return "Réactivation impossible : \(error.localizedDescription)"
        }
    }
}

// ============================================================================
//  MARK: - Scripts de maintenance
//  ============================================================================

/// Une commande de maintenance système, avec son état d'exécution réel.
struct MaintenanceTask: Identifiable {
    let id: String
    /// Titre de l'action.
    let title: String
    /// Ce que fait réellement la commande (explication honnête).
    let explanation: String
    /// Commande shell exacte.
    let command: String
    /// Droits administrateur nécessaires ?
    let needsAdmin: AdminRequirement
    /// Exécutée ?
    var ran = false
    /// Réussie ?
    var succeeded = false
    /// Sortie brute de la commande.
    var output = ""
    /// Libellé d'aide pour l'interface.
    let systemImage: String
}

/// Niveau d'autorisation exigé par une tâche de maintenance.
enum AdminRequirement: String {
    case no = "sans droits particuliers"
    case yes = "avec droits administrateur"
    case maybe = "selon la propriété des fichiers"
}

/// Bibliothèque de scripts de maintenance macOS.
///
/// Les commandes sont celles, officielles, de `/usr/sbin`. Aucune n'est
/// simulée : leur sortie réelle est conservée et affichée, y compris quand
/// macOS répond que l'opération est dépréciée ou refusée.
enum MaintenanceScripts {

    /// Liste des tâches proposées dans l'onglet Performance.
    static func tasks() -> [MaintenanceTask] {
        return [
            MaintenanceTask(
                id: "spotlight-status",
                title: "Vérifier l'indexation Spotlight",
                explanation: "Interroge `mdutil -s -a` : indique si l'indexation est active sur chaque volume. Lecture seule.",
                command: "mdutil -s -a",
                needsAdmin: .no,
                systemImage: "magnifyingglass.circle.fill"
            ),
            MaintenanceTask(
                id: "spotlight-reindex",
                title: "Réindexer Spotlight",
                explanation: "`mdutil -E /` détruit puis reconstruit l'index de recherche. Utile quand Spotlight ne trouve plus des fichiers ; la reconstruction peut durer plusieurs dizaines de minutes en arrière-plan.",
                command: "mdutil -E /",
                needsAdmin: .yes,
                systemImage: "arrow.counterclockwise"
            ),
            MaintenanceTask(
                id: "verify-volume",
                title: "Vérifier le volume de démarrage",
                explanation: "`diskutil verifyVolume /` contrôle la structure APFS sans rien modifier.",
                command: "diskutil verifyVolume /",
                needsAdmin: .no,
                systemImage: "checkmark.shield.fill"
            ),
            MaintenanceTask(
                id: "repair-permissions",
                title: "Réparer les autorisations des fichiers système",
                explanation: "`diskutil repairPermissions /` rétablit les droits attendus des composants Apple et de /Library. Depuis APFS, macOS répare automatiquement la plupart des droits : la commande est dépréciée, sa sortie réelle est affichée telle quelle.",
                command: "diskutil repairPermissions /",
                needsAdmin: .yes,
                systemImage: "lock.rotation"
            ),
            MaintenanceTask(
                id: "launch-services",
                title: "Reconstruire la base Launch Services",
                explanation: "`lsregister -R -domain …` réindexe les associations de fichiers et les applications par défaut (répare « Ouvre avec » et les doublons de launchservicesd).",
                command: "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Support/lsregister -R -domain local -domain system -domain user",
                needsAdmin: .maybe,
                systemImage: "square.stack.3d.up.fill"
            ),
            MaintenanceTask(
                id: "dns-cache",
                title: "Purger le cache DNS",
                explanation: "`dscacheutil -flushcache` puis `killall -HUP mDNSResponder` : force la résolution fraîche des noms (utile après un changement de réseau ou de proxy).",
                command: "dscacheutil -flushcache; killall -HUP mDNSResponder; echo cache DNS purgé",
                needsAdmin: .yes,
                systemImage: "network"
            ),
            MaintenanceTask(
                id: "periodic",
                title: "Exécuter les scripts périodiques",
                explanation: "`periodic daily/weekly/monthly` exécute les tâches d'entretien prévues par macOS (rotation des logs, nettoyage /tmp).",
                command: "periodic daily; periodic weekly; periodic monthly; echo scripts périodiques exécutés",
                needsAdmin: .yes,
                systemImage: "calendar.badge.clock"
            ),
            MaintenanceTask(
                id: "system-logs",
                title: "Purger les logs système archivés",
                explanation: "Supprime les archives `.gz`/`.old` et journaux de plus de 7 jours dans `/private/var/log` (répond à la section « historiques système » de la Purge).",
                command: "find /private/var/log -maxdepth 2 \\( -name '*.gz' -o -name '*.old' -o -name '*.log' \\) -mtime +7 -delete; echo logs système purgés",
                needsAdmin: .yes,
                systemImage: "doc.badge.gearshape"
            ),
            MaintenanceTask(
                id: "volume-trashes",
                title: "Vider les corbeilles des volumes",
                explanation: "Vide `/Volumes/*/.Trashes` : ces corbeilles appartiennent à root et sont invisibles du Finder utilisateur (répond à la section « corbeilles » de la Purge).",
                command: "for d in /Volumes/*/.Trashes; do [ -d \"$d\" ] && rm -rf \"$d\"/*; done; echo corbeilles de volumes vidées",
                needsAdmin: .yes,
                systemImage: "trash.slash.fill"
            )
        ]
    }

    /// Exécute une tâche et retourne une copie enrichie de la sortie réelle.
    static func run(_ task: MaintenanceTask) -> MaintenanceTask {
        var executed = task
        let outcome = task.needsAdmin == .no
            ? Shell.run("/bin/bash", ["-c", task.command], timeout: 240)
            : Shell.runWithAdmin(task.command, timeout: 600)
        executed.ran = true
        executed.succeeded = outcome.succeeded
        executed.output = outcome.failure ?? outcome.excerpt
        if executed.output.isEmpty { executed.output = "Terminé sans sortie (code 0)." }
        return executed
    }
}
