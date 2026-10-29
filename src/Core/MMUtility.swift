// ============================================================================
//  MonitorMyMac — socle technique partagé (module « Core »)
//  Auteur : Martial Zinsou
//  ============================================================================
//
//  Ce fichier fournit les briques utilisées par tous les moteurs de l'app :
//
//    • Shell        — exécution de commandes système (avec ou sans droits
//      administrateur) et récupération fidèle de leur sortie réelle ;
//    • Fmt          — formats lisibles (octets, dates, durées) en français ;
//    • PathPolicy   — garde-fous : la liste des chemins que l'app a le droit
//      — ou non — de supprimer ;
//    • FileRecord   — description d'un élément repéré au balayage ;
//    • Walker       — parcours de répertoires borné dans le temps ;
//    • DeleteOps    — suppression (corbeille réversible ou effacement direct) ;
//    • Hash         — empreinte SHA-256 (partielle puis complète) pour la
//      détection de doublons ;
//    • Quarantine   — mise en quarantaine réversible utilisée par l'anti-malware.
//
//  PRINCIPES DE SÉCURITÉ APPLIQUÉS PARTOUT
//  ---------------------------------------
//  1. Rien n'est supprimé sans balayage préalable : l'utilisateur voit toujours
//     la liste, la taille réelle et le risque avant d'agir.
//  2. Par défaut, toute suppression passe par la **corbeille** (réversible).
//  3. Les chemins déclarés sensibles (système, mails, trousseaux, iCloud…) sont
//     bloqués par `PathPolicy`, même si l'utilisateur les sélectionne.
//  4. Les opérations qui exigent les droits administrateur sont annoncées
//     comme telles et passent par une invite macOS officielle (`osascript`).
// ============================================================================

import Foundation
import AppKit
import CryptoKit

// ============================================================================
//  MARK: - Shell : exécution de commandes système
//  ============================================================================

/// Résultat brut d'une commande exécutée sur la machine.
///
/// La sortie réelle du programme (stdout/stderr) et son code de retour sont
/// conservés tels quels : l'interface les affiche pour que l'utilisateur voie
/// exactement ce que macOS a répondu — y compris en cas d'échec.
struct ShellOutcome {
    /// Code de retour du processus (-1 si le lancement a échoué).
    let exitCode: Int32
    /// Sortie standard, telle que produite par la commande.
    let stdout: String
    /// Sortie d'erreur, telle que produite par la commande.
    let stderr: String

    /// La commande s'est-elle terminée avec succès (code 0) ?
    var succeeded: Bool { exitCode == 0 }

    /// Sortie combinée stdout + stderr, pratique pour l'affichage.
    var combined: String {
        let a = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (a.isEmpty, b.isEmpty) {
        case (true, true): return ""
        case (false, true): return a
        case (true, false): return b
        default: return a + "\n" + b
        }
    }

    /// Message d'échec lisible (nil si la commande a réussi).
    var failure: String? {
        if succeeded { return nil }
        if exitCode == -1 { return stderr.isEmpty ? "Lancement impossible." : stderr }
        if stderr.contains("-128") || combined.contains("User canceled") {
            return "Annulé par l'utilisateur (mot de passe administrateur non saisi)."
        }
        let text = combined
        return text.isEmpty ? "Code de retour \(exitCode)." : text
    }

    /// Lignes de sortie, sans lignes vides (pour le parsing).
    var lines: [String] {
        combined.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    /// Sortie tronquée pour l'affichage dans une carte.
    var excerpt: String {
        let text = combined
        if text.count <= 2000 { return text }
        return String(text.prefix(2000)) + "\n… (sortie tronquée)"
    }
}

/// Exécute des commandes système de façon contrôlée.
///
/// `Process` est lancé avec deux `Pipe` lus en continu (évite tout blocage quand
/// la sortie dépasse la capacité du tampon) et surveillés par une garde de
/// temps : au-delà du délai, le processus est arrêté et la partie déjà lue est
/// conservée.
enum Shell {

    /// Lance une commande et retourne sa sortie réelle.
    ///
    /// - Parameters:
    ///   - launchPath: chemin absolu de l'exécutable (`/usr/bin/pluginkit`…).
    ///   - arguments: arguments passés tels quels (aucun shell intermédiaire).
    ///   - timeout: délai maximum en secondes (0 = sans limite).
    static func run(_ launchPath: String,
                    _ arguments: [String],
                    timeout: TimeInterval = 90) -> ShellOutcome {
        guard FileManager.default.isExecutableFile(atPath: launchPath) else {
            return ShellOutcome(exitCode: -1, stdout: "",
                                stderr: "Commande introuvable : \(launchPath)")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        var outData = Data()
        var errData = Data()
        let lock = NSLock()

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            lock.lock(); outData.append(chunk); lock.unlock()
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            lock.lock(); errData.append(chunk); lock.unlock()
        }

        // `terminationHandler` + sémaphore plutôt que `waitUntilExit()` :
        // cette dernière **relance la boucle d'événements** quand elle est
        // appelée depuis le fil principal. SwiftUI peut alors reconstruire une
        // vue pendant l'attente et rappeler le singleton en cours de création —
        // reentrée dans `dispatch_once`, donc plantage immédiat de l'app.
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            return ShellOutcome(exitCode: -1, stdout: "",
                                stderr: "Lancement impossible : \(error.localizedDescription)")
        }

        // Garde-fou temps réel : évite qu'une commande bloquante gèle l'interface.
        if timeout > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
            }
        }
        let budget: DispatchTime = timeout > 0 ? .now() + timeout + 5 : .now() + 3600
        if finished.wait(timeout: budget) == .timedOut, process.isRunning {
            process.terminate()
        }
        // Laisse aux gestionnaires de lecture le temps de pousser le dernier bloc.
        Thread.sleep(forTimeInterval: 0.05)
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        return ShellOutcome(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    /// Exécute une commande shell **avec droits administrateur**.
    ///
    /// Utilise la mécanisme macOS officiel `do shell script … with administrator
    /// privileges` : la fenêtre de mot de passe du système s'affiche, aucun
    /// mot de passe n'est stocké par l'app. Si l'utilisateur annule, l'échec
    /// est remonté honnêtement dans `failure`.
    static func runWithAdmin(_ shellCommand: String, timeout: TimeInterval = 600) -> ShellOutcome {
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges with prompt \"MonitorMyMac souhaite exécuter une maintenance système.\""
        return run("/usr/bin/osascript", ["-e", source], timeout: timeout)
    }

    /// Exécute un script AppleScript (utilisé pour Finder, Mail, System Events).
    static func appleScript(_ source: String, timeout: TimeInterval = 120) -> ShellOutcome {
        return run("/usr/bin/osascript", ["-e", source], timeout: timeout)
    }

    /// Le binaire existe-t-il et est-il exécutable sur cette machine ?
    static func isAvailable(_ launchPath: String) -> Bool {
        return FileManager.default.isExecutableFile(atPath: launchPath)
    }
}

// ============================================================================
//  MARK: - Fmt : formats lisibles en français
//  ============================================================================

/// Mise en forme lisible des nombres, tailles et dates.
enum Fmt {

    /// Formate une taille en octets (« 1,5 Go », « 324 Mo »).
    static func size(_ bytes: Int64) -> String {
        // ByteCountFormatter traduit 0 en « Zéro ko », ce qui fait tiquer.
        if bytes <= 0 { return "0 octet" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.zeroPadsFractionDigits = false
        return formatter.string(fromByteCount: max(0, bytes))
    }

    /// Formate une taille courte pour les pastilles (« 1,5 Go »), en binaire.
    static func shortSize(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 octet" }
        let value = Double(max(0, bytes))
        let units = [("o", 1.0), ("Ko", 1_024.0), ("Mo", 1_048_576.0),
                     ("Go", 1_073_741_824.0), ("To", 1_099_511_627_776.0)]
        for unit in units.reversed() where value >= unit.1 {
            return String(format: value / unit.1 >= 100 ? "%.0f %@" : "%.1f %@",
                          value / unit.1, unit.0)
        }
        return String(format: "%.0f o", value)
    }

    /// Formate une date au format court français.
    static func date(_ date: Date?) -> String {
        guard let date = date else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// Âge d'un fichier en langage naturel (« il y a 3 j », « il y a 8 sem. »).
    static func age(_ date: Date?) -> String {
        guard let date = date else { return "—" }
        let days = Int(Date().timeIntervalSince(date) / 86_400)
        if days < 0 { return "aujourd'hui" }
        if days == 0 { return "aujourd'hui" }
        if days == 1 { return "hier" }
        if days < 31 { return "il y a \(days) j" }
        if days < 365 { return "il y a \(days / 30) sem." }
        return "il y a \(days / 365) an(s)"
    }

    /// Formatte un ratio en pourcentage entier (« 42 % »).
    static func percent(_ ratio: Double) -> String {
        return String(format: "%.0f %%", max(0, min(1, ratio)) * 100)
    }

    /// Nom du volume d'un chemin (utile pour les corbeilles par volume).
    static func volumeLabel(of url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.volumeNameKey])
        return values?.volumeName ?? url.pathComponents.first ?? "/"
    }

    /// Chemin raccourci avec « ~ » pour le dossier maison.
    static func prettyPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }
}

// ============================================================================
//  MARK: - PathPolicy : garde-fous de suppression
//  ============================================================================

/// Définit ce que l'application a le droit — ou non — de supprimer.
///
/// Ces règles sont appliquées **au moment de l'action**, pas seulement au
/// balayage : un élément sélectionné dans l'interface mais refusé ici ne sera
/// jamais supprimé. Elles protègent le système, les mails, les trousseaux et
/// les données iCloud de l'utilisateur.
enum PathPolicy {

    /// Dossier maison de l'utilisateur courant.
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Bibliothèque utilisateur (`~/Library`).
    static var userLibrary: URL { home.appendingPathComponent("Library") }

    /// Préfixes absolus interdits (système et données protégées).
    static let deniedPrefixes: [String] = [
        "/System", "/usr", "/bin", "/sbin", "/etc", "/private/etc",
        "/private/var/db", "/private/var/root", "/Volumes", "/Library",
        "/Applications", "/Applications/Utilities", "/opt",
        "/private/var/vm", "/private/var/log", "/private/tmp"
    ]

    /// Sous-chemins de `~/Library` interdits (données personnelles irremplaçables).
    static let deniedHomeSubpaths: [String] = [
        "Library/Mail", "Library/Keychains", "Library/Messages", "Library/Calendars",
        "Library/Contacts", "Library/Preferences/com.apple.loginitems.plist",
        "Library/Application Support/MobileSync", "Library/Application Support/CloudDocs",
        "Library/Application Support/com.apple.idsync", "Library/Passbook",
        "Library/Health", "Library/HomeKit", "Library/ReminderKit",
        "Library/Containers/com.apple.icloudmailagent/Data/Library/Mail",
        "Library/Application Support/AddressBook", "Library/Saved Application State/com.apple.finder.savedState"
    ]

    /// Extensions de packages qu'un balayage ne doit jamais traverser.
    static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "plugin", "appex", "xpc", "qlgenerator",
        "kext", "mdimporter", "spotlight importer", "photoslibrary",
        "imlproj", "moml", "dmg", "pkg", "retry", "keychain",
        "kdbx", "note", "pages", "numbers", "key", "otl", "rwdesign",
        "sketch", "xd", "omni", "bitbox", "gbproj", "approject"
    ]

    /// Le chemin est-il autorisé à la suppression par l'app ?
    static func allowsDeletion(of url: URL) -> Bool {
        return reason(for: url) == nil
    }

    /// Chemins explicitement approuvés par une désinstallation validée.
    ///
    /// Un bundle de `/Applications` n'est supprimable **que** si l'utilisateur a
    /// confirmé la désinstallation complète dans l'onglet Applications : le
    /// chemin est ajouté ici pour la durée de l'opération puis retiré.
    private static var approvedForUninstall: Set<String> = []
    private static let approvalLock = NSLock()

    /// Approuve un chemin pour une désinstallation explicite.
    static func approveUninstall(_ url: URL) {
        approvalLock.lock()
        approvedForUninstall.insert(url.path)
        approvalLock.unlock()
    }

    /// Révoque toutes les approbations de désinstallation.
    static func revokeUninstallApprovals() {
        approvalLock.lock()
        approvedForUninstall.removeAll()
        approvalLock.unlock()
    }

    /// Le chemin (ou un de ses parents) a-t-il été approuvé ?
    private static func isApproved(_ path: String) -> Bool {
        approvalLock.lock()
        defer { approvalLock.unlock() }
        if approvedForUninstall.contains(path) { return true }
        for approved in approvedForUninstall where path.hasPrefix(approved + "/") { return true }
        return false
    }

    /// Explique pourquoi la suppression est refusée (nil = autorisée).
    static func reason(for url: URL) -> String? {
        let path = url.path

        // 0. Le système lui-même n'est jamais négociable, approbation ou non.
        for hard in ["/System", "/usr", "/bin", "/sbin", "/private/var/db"]
        where path.hasPrefix(hard) {
            return "Composant de macOS : aucune application ne doit le supprimer."
        }

        // 0bis. Désinstallation validée par l'utilisateur dans l'onglet Applications.
        if isApproved(path) { return nil }

        // 1. Jamais en dehors du domicile utilisateur hors fichiers temporaires.
        let isTmp = path.hasPrefix("/private/tmp") || path.hasPrefix("/tmp")
        let isVolumeTrash = path.hasPrefix("/Volumes") && path.contains("/.Trashes")
        if !path.hasPrefix(home.path) && !isTmp && !isVolumeTrash {
            for allowed in allowedOutsideHome where path.hasPrefix(allowed) { return nil }
            return "Hors du dossier utilisateur — droits administrateur requis."
        }

        // 2. Préfixes système interdits.
        for denied in deniedPrefixes where path.hasPrefix(denied) {
            // /private/tmp reste autorisé via la règle « fichiers temporaires ».
            if (denied == "/private/tmp" || denied == "/private/var/log"), isTmp { continue }
            if denied == "/Volumes", path.contains("/.Trashes/") {
                return "Corbeille d'un volume externe : elle appartient à root, "
                     + "une élévation de droits est nécessaire."
            }
            return "Zone système protégée (\(denied)) — droits administrateur requis."
        }

        // 3. Données personnelles irremplaçables sous ~/Library.
        if path.hasPrefix(home.path) {
            let relative = String(path.dropFirst(home.path.count + 1))
            for denied in deniedHomeSubpaths where relative.hasPrefix(denied) {
                return "Données personnelles protégées (\(denied))."
            }
            // Un élément directement dans ~/ (Documents, Téléchargements…) est
            // autorisé mais sera signalé comme « données utilisateur ».
        }

        return nil
    }

    /// Chemins hors domicile que certains modules peuvent balayer/supprimer
    /// (uniquement après élévation de droits, jamais en suppression directe).
    static let allowedOutsideHome: [String] = [
        "/private/tmp", "/private/var/folders", "/tmp"
    ]

    /// L'élément est-il une donnée personnelle de l'utilisateur (Documents…) ?
    static func isUserData(_ url: URL) -> Bool {
        let relative = String(url.path.dropFirst(home.path.count + 1))
        let personalRoots = ["Documents", "Downloads", "Desktop", "Pictures", "Music", "Movies"]
        return personalRoots.contains(where: { relative.hasPrefix($0 + "/") || relative == $0 })
    }

    /// Le chemin est-il protégé par TCC (accès complet au disque requis) ?
    static func isTCCProtected(_ url: URL) -> Bool {
        let path = url.path
        let protected = [
            userLibrary.appendingPathComponent("Safari").path,
            userLibrary.appendingPathComponent("Cookies").path,
            userLibrary.appendingPathComponent("Mail").path,
            userLibrary.appendingPathComponent("Messages").path,
            userLibrary.appendingPathComponent("Application Support/com.apple.mobileAssetDesktop").path,
            "/Library/Application Support/com.apple.TCC",
            "/Library/Mail",
            "/private/var/log"
        ]
        return protected.contains { path.hasPrefix($0) }
    }

    /// Vérifie réellement si l'app peut lire un chemin (test d'accès honnête).
    static func canRead(_ url: URL) -> Bool {
        return FileManager.default.isReadableFile(atPath: url.path)
    }
}

// ============================================================================
//  MARK: - FileRecord : élément repéré par un balayage
//  ============================================================================

/// Un fichier (ou dossier) trouvé au balayage, avec ses métadonnées réelles.
struct FileRecord: Identifiable, Hashable {
    /// Identifiant stable : le chemin absolu.
    var id: String { url.path }
    /// URL de l'élément.
    let url: URL
    /// S'agit-il d'un dossier ?
    let isDirectory: Bool
    /// Taille réelle (octets) — pour un dossier, taille agrégée au moment du scan.
    let size: Int64
    /// Date de dernière modification.
    let modified: Date?
    /// Date de dernier accès (peut être désactivée par le système).
    let accessed: Date?
    /// Commentaire affiché dans l'interface (groupe de doublons, âge, app mère…).
    var note: String?
    /// Niveau de risque perçu par l'utilisateur (pilule colorée).
    var risk: Risk = .safe
    /// Membres réels derrière un élément agrégé (dossier de cache, groupe de
    /// doublons, corbeille) : c'est cette liste qui est supprimée, pas le parent.
    var members: [URL] = []

    /// Trois niveaux de risque affichés dans l'interface.
    enum Risk: Int, Comparable {
        case safe, caution, manualOnly
        static func < (lhs: Risk, rhs: Risk) -> Bool { lhs.rawValue < rhs.rawValue }
        var label: String {
            switch self {
            case .safe: return "sans risque"
            case .caution: return "à vérifier"
            case .manualOnly: return "manuel uniquement"
            }
        }
    }

    /// Enregistre les métadonnées d'une URL (nil si illisible).
    static func load(_ url: URL, aggregateDirectorySize: Bool = false) -> FileRecord? {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .totalFileAllocatedSizeKey,
                                         .fileSizeKey, .contentModificationDateKey,
                                         .contentAccessDateKey, .isRegularFileKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        let isDirectory = values.isDirectory ?? false
        var size: Int64 = 0
        if isDirectory {
            size = aggregateDirectorySize ? Walker.size(of: url) : 0
        } else {
            size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return FileRecord(url: url, isDirectory: isDirectory, size: size,
                          modified: values.contentModificationDate,
                          accessed: values.contentAccessDate)
    }

    /// Nom lisible (nom de fichier, ou nom du package).
    var displayName: String { url.lastPathComponent }
    /// Chemin raccourci pour l'affichage.
    var displayPath: String { Fmt.prettyPath(url.path) }
    /// Vrai si la suppression est autorisée par la politique de sécurité.
    var deletable: Bool { PathPolicy.allowsDeletion(of: url) }
}

// ============================================================================
//  MARK: - Walker : parcours de répertoires borné
//  ============================================================================

/// Parcours de l'arborescence avec budget de temps et exclusion des packages.
///
/// Tous les balayages passent par ici : ils sont plafonnés en durée
/// (`deadline`) pour garder l'interface réactive, et n'entrent jamais dans les
/// bundles (.app, .photoslibrary, .kext…) sauf demande explicite.
enum Walker {

    /// Options de parcours.
    struct Options {
        /// Entrer dans les bundles (utilisé par le scan des .lproj).
        var enterPackages = false
        /// Inclure les fichiers cachés (commençant par « . »).
        var includeHidden = false
        /// Nombre maximum d'éléments remontés.
        var maxRecords = 20_000
        /// Taille minimale retenue (octets).
        var minSize: Int64 = 0
        /// Ancienneté minimale (jours) sur la date de modification.
        var minAgeDays: Int = 0
        /// Ne remonter que des fichiers (défaut) ou aussi des dossiers.
        var filesOnly = true
    }

    /// Parcourt `root` et retourne les éléments qui respectent les options.
    ///
    /// - Parameters:
    ///   - root: répertoire de départ.
    ///   - options: filtres et limites.
    ///   - deadline: date limite de calcul (au-delà, on s'arrête proprement).
    static func records(in root: URL,
                        options: Options = Options(),
                        deadline: Date = Date().addingTimeInterval(25)) -> [FileRecord] {
        var results: [FileRecord] = []
        guard PathPolicy.canRead(root) else { return results }

        let keys: Set<URLResourceKey> = [.isDirectoryKey, .totalFileAllocatedSizeKey,
                                         .fileSizeKey, .contentModificationDateKey,
                                         .contentAccessDateKey, .isRegularFileKey,
                                         .isPackageKey, .isSymbolicLinkKey]
        var flags: FileManager.DirectoryEnumerationOptions = []
        if !options.includeHidden { flags.insert(.skipsHiddenFiles) }

        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: flags,
            errorHandler: { _, _ in return true }   // on ignore les erreurs unitaires
        )
        guard let enumerator = enumerator else { return results }

        let cutoff: Date? = options.minAgeDays > 0
            ? Calendar.current.date(byAdding: .day, value: -options.minAgeDays, to: Date())
            : nil

        for case let url as URL in enumerator {
            if Date() > deadline { break }
            if results.count >= options.maxRecords { break }

            let values = try? url.resourceValues(forKeys: keys)
            let isDirectory = values?.isDirectory ?? false
            // Un « paquet » (app, framework, .photoslibrary…) est une arborescence
            // dont le contenu n'appartient pas à l'utilisateur : on ne le traverse
            // jamais. Les paquets reconnus par Launch Services sont déjà écartés
            // par .skipsPackageDescendants ; l'extension sert de filet supplémentaire.
            let isPackage = PathPolicy.packageExtensions.contains(url.pathExtension.lowercased())

            if isDirectory {
                if isPackage && !options.enterPackages {
                    enumerator.skipDescendants()
                    continue
                }
                if isPackage && options.enterPackages { continue }   // on veut les enfants
                if options.filesOnly { continue }
                if url.path.hasPrefix(root.path) == false { continue }
            } else if !(values?.isRegularFile ?? true) {
                // Symlinks, tubes, sockets : jamais supprimés ici.
                if values?.isSymbolicLink == true { continue }
                continue
            }

            let size = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            if isDirectory {
                guard size >= options.minSize else { continue }
            } else if size < options.minSize {
                continue
            }
            let modified = values?.contentModificationDate
            if let cutoff = cutoff, let modified = modified, modified > cutoff { continue }

            results.append(FileRecord(url: url, isDirectory: isDirectory, size: size,
                                      modified: modified, accessed: values?.contentAccessDate))
            if isDirectory { enumerator.skipDescendants() }
        }
        return results
    }

    /// Calcule la taille occupée par un chemin (fichier ou dossier complet).
    ///
    /// Utilise la taille allouée réelle (bloc disque), ce qui correspond à
    /// l'espace effectivement libéré.
    static func size(of url: URL, deadline: Date? = nil) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey])
        if (values?.isDirectory ?? false) == false {
            return Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        var total: Int64 = 0
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys),
            options: .skipsHiddenFiles, errorHandler: { _, _ in true }) else { return 0 }
        for case let child as URL in enumerator {
            if let deadline = deadline, Date() > deadline { break }
            let childValues = try? child.resourceValues(forKeys: keys)
            if childValues?.isRegularFile ?? false {
                total += Int64(childValues?.totalFileAllocatedSize ?? childValues?.fileSize ?? 0)
            }
        }
        return total
    }

    /// Somme les tailles d'une liste d'URL.
    static func totalSize(_ urls: [URL]) -> Int64 {
        return urls.reduce(Int64(0)) { $0 + size(of: $1) }
    }

    /// Répertoires standards du domicile utilisateur (Téléchargements…).
    static func userFolders(_ names: [String]) -> [URL] {
        return names.map { PathPolicy.home.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Tous les volumes montés (pour les corbeilles par volume).
    static func mountedVolumeURLs() -> [URL] {
        return FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey],
                                                    options: [.skipHiddenVolumes]) ?? []
    }
}

// ============================================================================
//  MARK: - DeleteOps : suppression contrôlée
//  ============================================================================

/// Mode d'action d'une opération de purge.
enum DeletionMode: String, CaseIterable, Identifiable {
    /// Déplace vers la corbeille : réversible, recommandé.
    case trash = "Corbeille (réversible)"
    /// Efface directement : l'espace est libéré immédiatement, non réversible.
    case permanent = "Effacement direct"
    var id: String { rawValue }
    /// Le mode libère-t-il l'espace immédiatement ?
    var freesImmediately: Bool { self == .permanent }
}

/// Résultat détaillé et honnête d'une opération de suppression.
struct DeletionReport {
    /// Chemins effectivement supprimés.
    var removed: [String] = []
    /// Octets récupérés (taille allouée réelle).
    var freedBytes: Int64 = 0
    /// Erreurs rencontrées, chemin + message système.
    var failures: [(path: String, message: String)] = []
    /// Éléments refusés par la politique de sécurité.
    var blocked: [(path: String, reason: String)] = []

    /// Nombre d'éléments supprimés.
    var count: Int { removed.count }
    /// L'opération est-elle totalement propre ?
    var clean: Bool { failures.isEmpty && blocked.isEmpty }

    /// Fusionne un autre rapport dans celui-ci.
    mutating func merge(_ other: DeletionReport) {
        removed.append(contentsOf: other.removed)
        freedBytes += other.freedBytes
        failures.append(contentsOf: other.failures)
        blocked.append(contentsOf: other.blocked)
    }

    /// Résumé d'une ligne pour le journal.
    var summary: String {
        var text = "\(count) élément(s) · \(Fmt.size(freedBytes)) récupérés"
        if !failures.isEmpty { text += " · \(failures.count) échec(s)" }
        if !blocked.isEmpty { text += " · \(blocked.count) bloqué(s)" }
        return text
    }
}

/// Applique une suppression en respectant la politique de sécurité.
enum DeleteOps {

    /// Supprime une liste d'URL selon le mode choisi.
    ///
    /// Chaque chemin est d'abord validé par `PathPolicy` ; les refus sont listés
    /// dans le rapport (jamais supprimés en silence). Les erreurs système sont
    /// remontées avec leur message réel.
    static func apply(_ urls: [URL], mode: DeletionMode) -> DeletionReport {
        var report = DeletionReport()
        let manager = FileManager.default

        for url in urls {
            if let reason = PathPolicy.reason(for: url) {
                report.blocked.append((url.path, reason))
                continue
            }
            let size = Walker.size(of: url)
            var error: NSError?
            var ok: Bool

            switch mode {
            case .trash:
                // API officielle `trashItem` : envoi réel à la corbeille, synchrone.
                do {
                    var placed: NSURL?
                    try manager.trashItem(at: url, resultingItemURL: &placed)
                    ok = true
                } catch let caught {
                    error = caught as NSError
                    ok = false
                }
            case .permanent:
                do {
                    try manager.removeItem(at: url)
                    ok = true
                } catch let caught {
                    error = caught as NSError
                    ok = false
                }
            }

            if ok {
                report.removed.append(url.path)
                report.freedBytes += size
            } else {
                let message = error?.localizedDescription ?? "erreur inconnue"
                report.failures.append((url.path, message))
            }
        }
        return report
    }

    /// Supprime le contenu d'un dossier sans supprimer le dossier lui-même.
    ///
    /// Comportement attendu pour les caches : le dossier de cache reste en place
    /// (l'application le réutilise), seuls ses enfants disparaissent.
    static func applyToContents(of directory: URL, mode: DeletionMode) -> DeletionReport {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants])) ?? []
        return apply(children, mode: mode)
    }

    /// Attente bornée : la corbeille macOS peut être lente sur les gros volumes.
    ///
    /// - Parameter url: chemin à surveiller jusqu'à disparition.
    static func waitUntilGone(_ url: URL, timeout: TimeInterval = 6) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !FileManager.default.fileExists(atPath: url.path) { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return !FileManager.default.fileExists(atPath: url.path)
    }

    /// Vide réellement une corbeille (utilisée par le module « Corbeilles »).
    static func emptyTrashDirectory(_ trash: URL, mode: DeletionMode) -> DeletionReport {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: trash, includingPropertiesForKeys: nil, options: [])) ?? []
        var report = DeletionReport()
        // Une corbeille contient souvent des doublons de nom : on garde le mode
        // demandé mais on évite de renvoyer les éléments dans la même corbeille.
        if mode == .trash {
            for item in contents {
                let size = Walker.size(of: item)
                do {
                    try FileManager.default.removeItem(at: item)
                    report.removed.append(item.path)
                    report.freedBytes += size
                } catch let error {
                    report.failures.append((item.path, error.localizedDescription))
                }
            }
            return report
        }
        return apply(contents, mode: .permanent)
    }
}

// ============================================================================
//  MARK: - Hash : empreinte de fichier pour la détection de doublons
//  ============================================================================

/// Calcul d'empreinte SHA-256, en deux temps pour rester rapide.
///
/// 1. empreinte **partielle** (début + fin du fichier) : élimine immédiatement
///    les fichiers de même taille mais de contenu différent ;
/// 2. empreinte **complète** uniquement sur les candidats restants : garantit
///    l'absence de faux positifs avant toute proposition de suppression.
enum Hash {

    /// SHA-256 des `head` premiers et `tail` derniers octets.
    static func partial(_ url: URL, head: Int = 1 << 20, tail: Int = 1 << 20) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var digest = SHA256()
        do {
            try handle.seek(toOffset: 0)
            if let data = try handle.read(upToCount: head), !data.isEmpty {
                digest.update(data: data)
            }
            let size = handle.seekToEndOfFile()
            if size > UInt64(tail) {
                try handle.seek(toOffset: size - UInt64(tail))
                if let data = try handle.read(upToCount: tail), !data.isEmpty {
                    digest.update(data: data)
                }
            }
            return digest.finalize().map { String(format: "%02x", $0) }.joined()
        } catch {
            return nil
        }
    }

    /// SHA-256 complet, lu par blocs de 1 Mio (mémoire bornée).
    static func full(_ url: URL, chunk: Int = 1 << 20) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var digest = SHA256()
        while autoreleasepool(invoking: {
            guard let data = try? handle.read(upToCount: chunk), !data.isEmpty else {
                return false
            }
            digest.update(data: data)
            return true
        }) {}
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

// ============================================================================
//  MARK: - Quarantine : mise en quarantaine réversible
// ============================================================================

/// Stockage temporaire des éléments suspects, avant suppression définitive.
///
/// L'anti-malware ne détruit jamais rien de son propre chef : il déplace
/// l'élément dans `Quarantine/` avec un manifeste JSON, ce qui permet un retour
/// en arrière complet si l'utilisateur estime avoir eu un faux positif.
enum Quarantine {

    /// Dossier de quarantaine de l'application.
    static var directory: URL {
        let url = PathPolicy.home
            .appendingPathComponent("Library/Application Support/MonitorMyMac/Quarantine")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Met un élément en quarantaine ; retourne son nouvel emplacement.
    static func isolate(_ url: URL) -> URL? {
        guard PathPolicy.allowsDeletion(of: url) else { return nil }
        let stamp = ISO8601DateFormatter().string(from: Date())
        let name = url.lastPathComponent
        let target = directory.appendingPathComponent("\(stamp)_\(name)")
        do {
            try FileManager.default.moveItem(at: url, to: target)
            writeManifest(for: target, origin: url)
            return target
        } catch {
            return nil
        }
    }

    /// Liste les éléments en quarantaine.
    static func items() -> [FileRecord] {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return children.filter { !$0.lastPathComponent.hasPrefix("manifest_") }
            .compactMap { FileRecord.load($0, aggregateDirectorySize: true) }
    }

    /// Restaure un élément quarantainé vers son chemin d'origine.
    static func restore(_ quarantined: URL) -> Bool {
        guard let origin = readOrigin(for: quarantined) else { return false }
        do {
            try FileManager.default.createDirectory(at: origin.deletingLastPathComponent(),
                                                   withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: quarantined, to: origin)
            return true
        } catch {
            return false
        }
    }

    // -------------------------------------------------------------------------
    //  Manifeste (chemin d'origine + date)
    // -------------------------------------------------------------------------

    private static func writeManifest(for placed: URL, origin: URL) {
        let payload = ["placed": placed.path, "origin": origin.path,
                       "date": ISO8601DateFormatter().string(from: Date())]
        let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
        let file = directory.appendingPathComponent("manifest_\(placed.lastPathComponent).json")
        try? data?.write(to: file)
    }

    private static func readOrigin(for placed: URL) -> URL? {
        let file = directory.appendingPathComponent("manifest_\(placed.lastPathComponent).json")
        guard let data = FileManager.default.contents(atPath: file.path),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let origin = dict["origin"] else { return nil }
        return URL(fileURLWithPath: origin)
    }
}

// ============================================================================
//  MARK: - Helpers UI partagés
// ============================================================================

/// Petite structure pour afficher un résultat sous forme de ligne clé/valeur.
struct StatLine: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let systemImage: String
}

/// Registre des autorisations TCC manquantes, pour afficher un bouton
/// « Ouvrir les Réglages Système » au bon endroit.
enum PrivacyAccess {

    /// L'app dispose-t-elle de l'accès complet au disque ?
    ///
    /// Test réel et non intrusif : on tente de lister un répertoire protégé.
    static func hasFullDiskAccess() -> Bool {
        let probe = PathPolicy.userLibrary.appendingPathComponent("Cookies")
        if let handle = try? FileHandle(forReadingFrom: probe.appendingPathComponent("Cookies.binarycookies")) {
            try? handle.close()
            return true
        }
        let safari = PathPolicy.userLibrary.appendingPathComponent("Safari")
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: safari.path, isDirectory: &isDir), isDir.boolValue {
            if let items = try? FileManager.default.contentsOfDirectory(atPath: safari.path), !items.isEmpty {
                return true
            }
        }
        return false
    }

    /// Ouvre le panneau « Accès complet au disque » des Réglages Système.
    static func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        if let url = url { NSWorkspace.shared.open(url) }
    }

    /// Ouvre le panneau « Automation » des Réglages Système.
    static func openAutomationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        if let url = url { NSWorkspace.shared.open(url) }
    }
}
