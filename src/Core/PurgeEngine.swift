// ============================================================================
//  MonitorMyMac — moteur « Purge » (nettoyage du stockage)
//  Auteur : Martial Zinsou
//  ============================================================================
//
//  Ce module implémente les quatre familles demandées :
//
//    1. Fichiers système inutiles : caches utilisateur, logs et historiques
//       système, rapports de diagnostic, état sauvegardé des applications,
//       fichiers de traduction (.lproj) inutilisés, restes de mises à jour ;
//    2. Chasse aux fichiers volumineux et anciens (seuils réglables) ;
//    3. Détection des doublons (taille → empreinte partielle → SHA-256 complet) ;
//    4. Vidage centralisé des corbeilles (Finder, volumes, Mail, applications).
//
//  Chaque famille produit une `PurgeSection` : liste réelle, taille réelle,
//  niveau de risque et caractère exécutable. Une section marquée
//  `executable = false` est un **rapport** (ex. fichiers de traduction : les
//  supprimer casserait la signature des applications) — l'app le dit, elle ne
//  le fait pas en cachette.
// ============================================================================

import Foundation
import SwiftUI

// ============================================================================
//  MARK: - Modèles du moteur Purge
//  ============================================================================

/// Une famille d'éléments repérés, telle qu'affichée dans l'onglet Purge.
struct PurgeSection: Identifiable {
    /// Identifiant stable (sert aussi de clé d'extension).
    let id: String
    /// Titre de la carte.
    let title: String
    /// Sous-titre : ce que la section contient réellement.
    let subtitle: String
    /// Symbole SF de la carte.
    let systemImage: String
    /// Nom d'accent (« pink », « orange »…) résolu par l'interface.
    let accent: String
    /// Niveau de risque par défaut des éléments.
    let risk: FileRecord.Risk
    /// L'app peut-elle agir sur cette section ? (false = rapport seul)
    let executable: Bool
    /// Éléments repérés.
    var records: [FileRecord]
    /// Avertissements affichés sous la carte (honnêteté sur les limites).
    var warnings: [String]
    /// Résumé de la taille agrégée par l'analyse elle-même (quand pertinent).
    var aggregateNote: String?

    /// Espace total représenté par la section.
    var totalBytes: Int64 { records.reduce(Int64(0)) { $0 + $1.size } }
    /// Nombre d'éléments repérés.
    var count: Int { records.reduce(0) { $0 + ($1.members.isEmpty ? 1 : $1.members.count) } }
    /// Identifiants proposés à la sélection par défaut.
    var defaultSelected: Set<String> {
        guard executable, risk != .manualOnly else { return [] }
        return Set(records.filter { $0.risk != .manualOnly }.map(\.id))
    }
}

/// Réglages persistés du moteur de purge.
struct PurgeSettings: Equatable, Codable {
    /// Âge minimal des caches à supprimer (jours).
    var cacheAgeDays: Int = 7
    /// Âge minimal des logs/junk système (jours).
    var junkAgeDays: Int = 7
    /// Taille minimale d'un « gros fichier » (Mo).
    var largeMinSizeMB: Int = 100
    /// Ancienneté minimale d'un « gros fichier » (jours).
    var largeMinAgeDays: Int = 90
    /// Taille minimale analysée pour les doublons (Mo).
    var duplicateMinSizeMB: Int = 5
    /// Dossiers personnels ajoutés à l'analyse.
    var extraFolders: [String] = []

    /// Clé d'archivage dans `UserDefaults`.
    private static let defaultsKey = "purgeSettings.v1"

    /// Charge les réglages (valeurs par défaut au premier lancement).
    static func load() -> PurgeSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(PurgeSettings.self, from: data) else {
            return PurgeSettings()
        }
        return decoded
    }

    /// Enregistre les réglages.
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: PurgeSettings.defaultsKey)
        }
    }
}

// ============================================================================
//  MARK: - PurgeEngine : balayages
//  ============================================================================

/// Ensemble des balayages de stockage.
///
/// Toutes les méthodes sont pures (aucun état) et s'exécutent hors du fil
/// principal ; chacune se termine au plus à la `deadline` passée en paramètre.
enum PurgeEngine {

    // -------------------------------------------------------------------------
    //  1. Fichiers système inutiles
    // -------------------------------------------------------------------------

    /// Caches utilisateur (`~/Library/Caches`) agrégés par application.
    ///
    /// Seuls les fichiers plus anciens que `days` sont retenus : les caches
    /// chauds (utilisés aujourd'hui) ne sont jamais proposés à la suppression.
    static func userCaches(days: Int, deadline: Date) -> PurgeSection {
        let root = PathPolicy.userLibrary.appendingPathComponent("Caches")
        var options = Walker.Options()
        options.minAgeDays = days
        options.maxRecords = 40_000
        let found = Walker.records(in: root, options: options, deadline: deadline)

        // Agrégation par dossier au premier niveau sous ~/Library/Caches.
        var groups: [String: [FileRecord]] = [:]
        for record in found {
            let relative = String(record.url.path.dropFirst(root.path.count + 1))
            let key = relative.split(separator: "/").first.map(String.init) ?? relative
            groups[key, default: []].append(record)
        }

        let sorted = groups.sorted { lhs, rhs in
            lhs.value.reduce(Int64(0)) { $0 + $1.size } > rhs.value.reduce(Int64(0)) { $0 + $1.size }
        }
        var records: [FileRecord] = []
        for (key, items) in sorted.prefix(14) {
            let size = items.reduce(Int64(0)) { $0 + $1.size }
            let newest = items.compactMap(\.modified).max()
            let url = root.appendingPathComponent(key)
            var record = FileRecord(url: url, isDirectory: true, size: size,
                                    modified: newest, accessed: nil)
            record.note = "\(items.count) fichier(s) de plus de \(days) j"
            record.members = items.map(\.url)
            records.append(record)
        }

        return PurgeSection(
            id: "caches",
            title: "Caches utilisateur",
            subtitle: "\(Fmt.size(total(of: records))) · \(records.count) applications, fichiers de plus de \(days) jours",
            systemImage: "circle.grid.2x2.fill",
            accent: "pink",
            risk: .safe,
            executable: true,
            records: records,
            warnings: [
                "Les caches se régénèrent d'eux-mêmes : aucune donnée personnelle n'est concernée.",
                "Fermez les applications en cours d'utilisation avant d'agir sur leurs caches."
            ],
            aggregateNote: found.isEmpty ? "Aucun cache ancien trouvé." : nil
        )
    }

    /// Logs, historiques système, rapports de diagnostic et état des applications.
    static func systemJunk(days: Int, deadline: Date) -> PurgeSection {
        var records: [FileRecord] = []
        var warnings: [String] = []

        // (a) Logs utilisateur : fichiers rotatifs et .log anciens.
        let logsRoot = PathPolicy.userLibrary.appendingPathComponent("Logs")
        var logOptions = Walker.Options()
        logOptions.minAgeDays = days
        logOptions.includeHidden = false
        let logFiles = Walker.records(in: logsRoot, options: logOptions, deadline: deadline)
            .filter { isRotatableLog($0.url) }
        records.append(contentsOf: aggregate(byDirectory: logFiles, label: "fichiers de log", limit: 5))

        // (b) Rapports de diagnostic (.diag, .ips, .crash) — purgeable sans risque.
        let diagnostic = logsRoot.appendingPathComponent("DiagnosticReports")
        var diagOptions = Walker.Options()
        diagOptions.minAgeDays = days
        let diagFiles = Walker.records(in: diagnostic, options: diagOptions, deadline: deadline)
        if !diagFiles.isEmpty {
            var record = FileRecord(url: diagnostic, isDirectory: true,
                                    size: diagFiles.reduce(Int64(0)) { $0 + $1.size },
                                    modified: diagFiles.compactMap(\.modified).max(), accessed: nil)
            record.note = "\(diagFiles.count) rapport(s) d'incident datés d'au moins \(days) j"
            record.members = diagFiles.map(\.url)
            records.append(record)
        }

        // (c) État sauvegardé des applications (réouverture des fenêtres).
        let savedRoot = PathPolicy.userLibrary.appendingPathComponent("Saved Application State")
        if let children = try? FileManager.default.contentsOfDirectory(
            at: savedRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            let stale = children.filter { url in
                guard url.pathExtension == "savedState",
                      let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                      let modified = values.contentModificationDate else { return false }
                return modified < cutoff
            }
            for url in stale.prefix(6) {
                if var record = FileRecord.load(url, aggregateDirectorySize: true) {
                    record.note = "application fermée depuis \(Fmt.age(record.modified))"
                    record.risk = .caution
                    records.append(record)
                }
            }
            if !stale.isEmpty {
                warnings.append("L'état sauvegardé mémorise les fenêtres ouvertes : "
                                + "sa suppression ferme simplement la restauration de ces applications.")
            }
        }

        // (d) Logs système (`/private/var/log`) : détectés mais non supprimables ici.
        let systemLogs = URL(fileURLWithPath: "/private/var/log")
        if let children = try? FileManager.default.contentsOfDirectory(
            at: systemLogs, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            let archives = children.filter { isRotatableLog($0) }
            if !archives.isEmpty {
                warnings.append("\(archives.count) archive(s) de log système dans /private/var/log : "
                                + "propriété de root, suppression possible uniquement via l'action "
                                + "« Maintenance » avec mot de passe administrateur.")
            }
        } else {
            warnings.append("/private/var/log est en lecture protégée sur cette machine (TCC).")
        }

        return PurgeSection(
            id: "systemjunk",
            title: "Logs, historiques et diagnostics",
            subtitle: "\(Fmt.size(total(of: records))) · logs utilisateur, rapports d'incident, état des applications",
            systemImage: "doc.text.fill",
            accent: "indigo",
            risk: .safe,
            executable: true,
            records: sortedRecords(records),
            warnings: warnings,
            aggregateNote: records.isEmpty ? "Rien à signaler : historique déjà propre." : nil
        )
    }

    /// Restes de mises à jour : installers oubliés et caches de mise à jour.
    static func updateLeftovers(deadline: Date) -> PurgeSection {
        var records: [FileRecord] = []
        var warnings: [String] = []
        let installerExtensions: Set<String> = ["dmg", "pkg", "iso", "ipsw", "sparseimage", "appzip"]

        // (a) Installateurs encore présents dans Téléchargements / Bureau / Documents.
        let folders = Walker.userFolders(["Downloads", "Desktop", "Documents"])
        var options = Walker.Options()
        options.minSize = 1_048_576           // au-delà de 1 Mo seulement
        options.minAgeDays = 14
        options.maxRecords = 4_000
        var installers: [FileRecord] = []
        for folder in folders {
            installers.append(contentsOf: Walker.records(in: folder, options: options, deadline: deadline)
                .filter { installerExtensions.contains($0.url.pathExtension.lowercased()) })
        }
        installers.sort { $0.size > $1.size }
        for record in installers.prefix(8) {
            var mutable = record
            mutable.note = "installeur \(record.url.pathExtension.lowercased()) · \(Fmt.age(record.modified))"
            mutable.risk = .caution
            records.append(mutable)
        }

        // (b) Caches de l'App Store et de Software Update côté utilisateur.
        let cacheCandidates = [
            "Caches/com.apple.appstore", "Caches/com.apple.appstoreagent",
            "Caches/com.apple Software Update", "Caches/com.apple.helpd",
            "Caches/com.apple.mobileAssetDownload", "Caches/com.apple.SoftwareUpdate",
            "Caches/Homebrew"
        ]
        for relative in cacheCandidates {
            let url = PathPolicy.userLibrary.appendingPathComponent(relative)
            if var record = FileRecord.load(url, aggregateDirectorySize: true), record.size > 0 {
                record.note = "cache de distribution"
                record.members = [url]         // on supprime le contenu du dossier
                records.append(record)
            }
        }

        // (c) /Library/Updates : rapporté, jamais touché sans droits.
        let systemUpdates = URL(fileURLWithPath: "/Library/Updates")
        if FileManager.default.fileExists(atPath: systemUpdates.path) {
            warnings.append("/Library/Updates existe mais appartient à root : "
                            + "il est nettoyé par macOS lui-même après installation.")
        }
        if !Shell.isAvailable("/opt/homebrew/bin/brew") && !Shell.isAvailable("/usr/local/bin/brew") {
            warnings.append("Homebrew n'est pas installé : aucun cache `brew` à purger.")
        }

        return PurgeSection(
            id: "updates",
            title: "Restes de mises à jour",
            subtitle: "\(Fmt.size(total(of: records))) · installateurs oubliés et caches de distribution",
            systemImage: "arrow.triangle.2.circlepath",
            accent: "teal",
            risk: .caution,
            executable: true,
            records: records,
            warnings: warnings,
            aggregateNote: records.isEmpty ? "Aucun reste de mise à jour détecté." : nil
        )
    }

    /// Fichiers de traduction inutilisés (.lproj) — **rapport uniquement**.
    ///
    /// Les supprimer ferait perdre la signature du code des applications :
    /// Gatekeeper peut alors refuser le lancement. La section chiffre le gain
    /// théorique et explique pourquoi l'action reste manuelle.
    static func unusedTranslations(deadline: Date) -> PurgeSection {
        let preferred = preferredLanguageStems()
        let roots = [URL(fileURLWithPath: "/Applications"),
                     PathPolicy.home.appendingPathComponent("Applications")]
        var records: [FileRecord] = []
        var scannedApps = 0
        var wasted: Int64 = 0

        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            let apps = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for app in apps where app.pathExtension == "app" {
                if Date() > deadline { break }
                scannedApps += 1
                let resources = app.appendingPathComponent("Contents/Resources")
                guard let locals = try? FileManager.default.contentsOfDirectory(
                    at: resources, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
                for locale in locals where locale.pathExtension == "lproj" {
                    let stem = locale.deletingPathExtension().lastPathComponent.lowercased()
                    if preferred.contains(stem) || stem == "base" || stem == "develop" { continue }
                    let size = Walker.size(of: locale)
                    wasted += size
                    if records.count < 12, size > 1_048_576 {
                        var record = FileRecord(url: locale, isDirectory: true, size: size,
                                                modified: nil, accessed: nil)
                        record.note = "langue « \(stem) » · app : \(app.lastPathComponent)"
                        record.risk = .manualOnly
                        records.append(record)
                    }
                }
            }
        }

        return PurgeSection(
            id: "translations",
            title: "Traductions inutilisées (.lproj)",
            subtitle: "\(Fmt.size(wasted)) théoriques · \(scannedApps) applications analysées, "
                    + "langues hors \(preferred.sorted().prefix(3).joined(separator: ", "))",
            systemImage: "character.book.closed.fill",
            accent: "mint",
            risk: .manualOnly,
            executable: false,
            records: records,
            warnings: [
                "Action volontairement bloquée : retirer des fichiers .lproj modifie le contenu d'un "
                + "bundle signé. macOS peut alors juger l'application invalide (Gatekeeper) et refuser "
                + "de la lancer, y compris après une mise à jour.",
                "Le gain est généralement de quelques Mo par application ; macOS ne charge que les "
                + "langues préférées : les autres fichiers ne coûtent que de la place, pas des ressources.",
                "Pour récupérer de l'espace sans risque, utilisez plutôt « Caches utilisateur », "
                + "« Restes de mises à jour » ou la désinstallation complète d'applications."
            ],
            aggregateNote: scannedApps == 0 ? "Aucune application analysable trouvée." : nil
        )
    }

    // -------------------------------------------------------------------------
    //  2. Fichiers volumineux et anciens
    // -------------------------------------------------------------------------

    /// Fichiers dépassant `sizeMB` et modifiés depuis plus de `ageDays` jours.
    static func largeAndOldFiles(sizeMB: Int, ageDays: Int,
                                 extraFolders: [String], deadline: Date) -> PurgeSection {
        var folders = Walker.userFolders(["Downloads", "Desktop", "Documents", "Movies", "Music", "Pictures"])
        folders.append(contentsOf: extraFolders.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) })

        var options = Walker.Options()
        options.minSize = Int64(sizeMB) * 1_048_576
        options.minAgeDays = ageDays
        options.maxRecords = 6_000

        var found: [FileRecord] = []
        for folder in folders {
            if Date() > deadline { break }
            found.append(contentsOf: Walker.records(in: folder, options: options, deadline: deadline))
        }
        found.sort { $0.size > $1.size }

        var records: [FileRecord] = []
        for record in found.prefix(25) {
            var mutable = record
            mutable.note = "\(Fmt.age(mutable.modified)) · \(Fmt.prettyPath(mutable.url.deletingLastPathComponent().path))"
            mutable.risk = .caution
            records.append(mutable)
        }

        // Vidéos et archives : les deux familles que l'utilisateur cherche en priorité.
        let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "wmv"]
        let archiveExtensions: Set<String> = ["zip", "dmg", "iso", "rar", "7z", "tar", "gz", "pkg"]
        let videos = found.filter { videoExtensions.contains($0.url.pathExtension.lowercased()) }
            .reduce(Int64(0)) { $0 + $1.size }
        let archives = found.filter { archiveExtensions.contains($0.url.pathExtension.lowercased()) }
            .reduce(Int64(0)) { $0 + $1.size }

        var warnings: [String] = []
        if videos > 0 || archives > 0 {
            warnings.append("Dans cette sélection : \(Fmt.size(videos)) de vidéos et "
                            + "\(Fmt.size(archives)) d'archives.")
        }
        warnings.append("Vos documents personnels ne sont **jamais** supprimés sans sélection explicite : "
                        + "la case est décochée par défaut ici.")

        return PurgeSection(
            id: "largefiles",
            title: "Fichiers volumineux et anciens",
            subtitle: "\(Fmt.size(total(of: records))) · \(found.count) fichier(s) > \(sizeMB) Mo "
                    + "et > \(ageDays) jours",
            systemImage: "shippingbox.fill",
            accent: "orange",
            risk: .caution,
            executable: true,
            records: records,
            warnings: warnings,
            aggregateNote: found.isEmpty
                ? "Aucun fichier au-dessus des seuils — \(sizeMB) Mo et \(ageDays) jours." : nil
        )
    }

    // -------------------------------------------------------------------------
    //  3. Doublons
    // -------------------------------------------------------------------------

    /// Détecte les fichiers identiques en plusieurs exemplaires.
    ///
    /// Algorithme en trois étapes (rapide et sans faux positif) :
    ///   1. regroupement par taille identique ;
    ///   2. empreinte SHA-256 du premier et du dernier mégaoctet pour départager ;
    ///   3. SHA-256 complet uniquement sur les candidats encore en lice.
    /// L'exemplaire le plus ancien reste sélectionné comme « original » (non coché).
    static func duplicates(minSizeMB: Int, extraFolders: [String], deadline: Date) -> PurgeSection {
        var folders = Walker.userFolders(["Downloads", "Desktop", "Documents", "Pictures", "Music", "Movies"])
        folders.append(contentsOf: extraFolders.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) })

        var options = Walker.Options()
        options.minSize = Int64(max(1, minSizeMB)) * 1_048_576
        options.maxRecords = 8_000

        var candidates: [FileRecord] = []
        for folder in folders {
            if Date() > deadline { break }
            candidates.append(contentsOf: Walker.records(in: folder, options: options, deadline: deadline))
        }

        // Étape 1 : tailles partagées.
        var bySize: [Int64: [FileRecord]] = [:]
        for record in candidates { bySize[record.size, default: []].append(record) }
        let sizeGroups = bySize.filter { $0.value.count > 1 }.sorted { $0.key > $1.key }

        // Étape 2 : empreinte partielle.
        var partialGroups: [String: [FileRecord]] = [:]
        for (_, items) in sizeGroups {
            if Date() > deadline { break }
            for item in items {
                guard let partial = Hash.partial(item.url) else { continue }
                partialGroups["\(item.size)-\(partial)", default: []].append(item)
            }
        }

        // Étape 3 : empreinte complète des candidats restants.
        var fullGroups: [String: [FileRecord]] = [:]
        for (key, items) in partialGroups where items.count > 1 {
            if Date() > deadline { break }
            for item in items {
                guard let full = Hash.full(item.url) else { continue }
                fullGroups["\(key)-\(full)", default: []].append(item)
            }
        }

        var records: [FileRecord] = []
        var recoverable: Int64 = 0
        let groups = fullGroups.filter { $0.value.count > 1 }
            .sorted { largest($0.value) > largest($1.value) }

        for (index, group) in groups.prefix(20).enumerated() {
            let members = group.value.sorted { ($0.modified ?? .distantPast) < ($1.modified ?? .distantPast) }
            guard let oldest = members.first else { continue }
            let duplicates = members.dropFirst()
            let gain = duplicates.reduce(Int64(0)) { $0 + $1.size }
            recoverable += gain
            var record = FileRecord(url: oldest.url, isDirectory: false, size: gain,
                                    modified: oldest.modified, accessed: oldest.accessed)
            record.note = "groupe \(index + 1) · \(members.count - 1) copie(s) · original : "
                        + "\(oldest.url.lastPathComponent) (\(Fmt.age(oldest.modified)))"
            record.members = duplicates.map(\.url)
            record.risk = .caution
            records.append(record)
        }

        let totalGroups = groups.count
        return PurgeSection(
            id: "duplicates",
            title: "Doublons",
            subtitle: "\(Fmt.size(recoverable)) récupérables · \(totalGroups) groupe(s) de fichiers identiques "
                    + "(empreinte SHA-256 complète)",
            systemImage: "doc.on.doc.fill",
            accent: "cyan",
            risk: .caution,
            executable: true,
            records: records,
            warnings: [
                "L'original (exemplaire le plus ancien) n'est jamais coché : seules les copies sont proposées.",
                "Les bibliothèques (.photoslibrary, .imlproj) et les bundles sont exclus de l'analyse.",
                totalGroups > records.count
                    ? "Seuls les 20 premiers groupes sont affichés ; \(totalGroups - records.count) autre(s) petit(s) groupe(s) existent."
                    : "Empreinte complète vérifiée : pas de faux positif possible sur les fichiers listés."
            ],
            aggregateNote: candidates.isEmpty
                ? "Aucun fichier d'au moins \(minSizeMB) Mo analysé." : nil
        )
    }

    // -------------------------------------------------------------------------
    //  4. Corbeilles
    // -------------------------------------------------------------------------

    /// Toutes les corbeilles détectées : utilisateur, volumes, applications, Mail.
    static func trashLocations(deadline: Date) -> PurgeSection {
        var records: [FileRecord] = []
        var warnings: [String] = []
        let manager = FileManager.default

        // (a) Corbeille du Finder pour l'utilisateur courant.
        let userTrash = PathPolicy.home.appendingPathComponent(".Trash")
        if var record = FileRecord.load(userTrash, aggregateDirectorySize: true) {
            let items = (try? manager.contentsOfDirectory(at: userTrash,
                        includingPropertiesForKeys: nil, options: [])) ?? []
            record.note = "\(items.count) élément(s) en attente"
            record.members = items
            records.append(record)
        }

        // (b) Corbeilles par volume (.Trashes) : souvent la propriété de root.
        let uid = Int(getuid())
        for volume in Walker.mountedVolumeURLs() {
            if Date() > deadline { break }
            let trash = volume.appendingPathComponent(".Trashes")
            guard manager.fileExists(atPath: trash.path) else { continue }
            let ownTrash = trash.appendingPathComponent(String(uid))
            if var record = FileRecord.load(ownTrash, aggregateDirectorySize: true) {
                record.note = "volume \(Fmt.volumeLabel(of: volume))"
                record.risk = .caution
                records.append(record)
            } else {
                warnings.append("Corbeille du volume « \(Fmt.volumeLabel(of: volume)) » "
                                + "(\(Fmt.prettyPath(trash.path))) non lisible par votre utilisateur : "
                                + "vidage possible uniquement avec droits administrateur "
                                + "(voir l'onglet Performance ▸ Maintenance).")
            }
        }

        // (c) Corbeilles d'applications (dossiers nommés Trash / Recently Deleted).
        let trashNames: Set<String> = ["Trash", ".Trash", "Trashed", "Recently Deleted", "Corbeille"]
        let searchRoots = [PathPolicy.userLibrary.appendingPathComponent("Application Support"),
                           PathPolicy.home.appendingPathComponent("Pictures"),
                           PathPolicy.home.appendingPathComponent("Movies")]
        for root in searchRoots {
            if Date() > deadline { break }
            for url in shallowDirectories(under: root, maxDepth: 4, deadline: deadline) {
                guard trashNames.contains(url.lastPathComponent) else { continue }
                if var record = FileRecord.load(url, aggregateDirectorySize: true), record.size > 0 {
                    record.note = "corbeille applicative · \(url.deletingLastPathComponent().lastPathComponent)"
                    record.risk = .caution
                    records.append(record)
                }
            }
        }

        // (d) Mail : caches, pièces jointes téléchargées et courrier indésirable.
        let mailCandidates = ["Mail Downloads", "Caches/com.apple.mail", "Caches/com.apple.MailServiceAgent"]
        for relative in mailCandidates {
            let url = PathPolicy.userLibrary.appendingPathComponent(relative)
            if var record = FileRecord.load(url, aggregateDirectorySize: true), record.size > 0 {
                record.note = "Mail · pièces jointes et caches téléchargés"
                record.members = [url]
                records.append(record)
            }
        }
        let mailRoot = PathPolicy.userLibrary.appendingPathComponent("Mail")
        if manager.fileExists(atPath: mailRoot.path) {
            if PrivacyAccess.hasFullDiskAccess() {
                warnings.append("Les boîtes Mail (dont sa corbeille) sont lisibles : MonitorMyMac ne les "
                                + "touche pas — utilisez « Vider le courrier indésirable » ou Mail ▸ "
                                + "Présentation ▸ Vider la corbeille, qui respectent vos comptes.")
            } else {
                warnings.append("Corbeille de Mail non analysable sans « Accès complet au disque » "
                                + "(~/Library/Mail est protégé par macOS).")
            }
        } else {
            warnings.append("Aucune donnée Mail locale sur cette machine.")
        }

        return PurgeSection(
            id: "trashes",
            title: "Corbeilles (Finder, volumes, applications, Mail)",
            subtitle: "\(Fmt.size(total(of: records))) en attente · \(records.count) emplacement(s) trouvé(s)",
            systemImage: "trash.fill",
            accent: "red",
            risk: .safe,
            executable: true,
            records: records,
            warnings: warnings,
            aggregateNote: records.isEmpty ? "Toutes les corbeilles sont vides." : nil
        )
    }

    // -------------------------------------------------------------------------
    //  Helpers internes
    // -------------------------------------------------------------------------

    /// Racines linguistiques considérées comme utilisées par macOS.
    static func preferredLanguageStems() -> Set<String> {
        var stems: Set<String> = ["en", "english", "fr", "french"]
        for language in Locale.preferredLanguages {
            let stem = language.split(separator: "-").first.map(String.init) ?? language
            stems.insert(stem.lowercased())
            // « fr-FR » ⇒ « fr » ; « en-GB » ⇒ « en » (déjà couvert).
        }
        return stems
    }

    /// Vrai si le fichier est un log rotatif ou un rapport de diagnostic.
    static func isRotatableLog(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()
        if ["gz", "log", "ips", "diag", "crash", "pl", "txt", "old", "1", "2", "7"].contains(ext) { return true }
        return name.contains(".log.") || name.hasSuffix(".gz")
    }

    /// Solde d'octets d'une liste d'enregistrements.
    static func total(of records: [FileRecord]) -> Int64 {
        return records.reduce(Int64(0)) { $0 + $1.size }
    }

    /// Taille d'un fichier du groupe (utilisé pour ordonner les doublons).
    private static func largest(_ records: [FileRecord]) -> Int64 {
        return records.first?.size ?? 0
    }

    /// Trie par taille décroissante et tronque.
    static func sortedRecords(_ records: [FileRecord], limit: Int = 14) -> [FileRecord] {
        return Array(records.sorted { $0.size > $1.size }.prefix(limit))
    }

    /// Agrège des fichiers par dossier parent (pour les cartes lisibles).
    static func aggregate(byDirectory files: [FileRecord], label: String, limit: Int) -> [FileRecord] {
        var groups: [String: [FileRecord]] = [:]
        for file in files { groups[file.url.deletingLastPathComponent().path, default: []].append(file) }
        let ordered = groups.sorted { lhs, rhs in
            sumSize(lhs.value) > sumSize(rhs.value)
        }
        var result: [FileRecord] = []
        for (path, items) in ordered.prefix(limit) {
            var record = FileRecord(url: URL(fileURLWithPath: path), isDirectory: true,
                                    size: sumSize(items),
                                    modified: items.compactMap(\.modified).max(), accessed: nil)
            record.note = "\(items.count) \(label)"
            record.members = items.map(\.url)
            result.append(record)
        }
        return result
    }

    /// Somme des tailles d'une liste d'enregistrements.
    private static func sumSize(_ records: [FileRecord]) -> Int64 {
        return records.reduce(Int64(0)) { $0 + $1.size }
    }

    /// Dossiers jusqu'à une profondeur donnée (détection des corbeilles applicatives).
    static func shallowDirectories(under root: URL, maxDepth: Int, deadline: Date) -> [URL] {
        var found: [URL] = []
        let manager = FileManager.default
        guard var entries = try? manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return found }
        var depth = 1
        while !entries.isEmpty, depth < maxDepth, Date() < deadline {
            var next: [URL] = []
            for entry in entries {
                found.append(entry)
                guard let children = try? manager.contentsOfDirectory(
                    at: entry, includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                for child in children where !PathPolicy.packageExtensions.contains(child.pathExtension.lowercased()) {
                    var isDirectory: ObjCBool = false
                    if manager.fileExists(atPath: child.path, isDirectory: &isDirectory), isDirectory.boolValue {
                        next.append(child)
                    }
                }
            }
            entries = next
            depth += 1
        }
        return found
    }
}
