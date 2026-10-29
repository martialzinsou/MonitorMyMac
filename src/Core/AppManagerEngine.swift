// ============================================================================
//  MonitorMyMac — moteur « Applications » (apps et extensions)
//  Auteur : Martial Zinsou
//  ============================================================================
//
//  Trois familles :
//
//    1. Désinstallation complète : inventaire réel des bundles, puis recherche
//       des résidus dans les emplacements standard de ~/Library. L'app ne
//       supprime un bundle dans /Applications qu'après une **autorisation
//       explicite** enregistrée dans `PathPolicy.approvedForUninstall`, et
//       /System reste interdit dans tous les cas.
//    2. Mises à jour : `softwareupdate --list` (sortie brute conservée),
//       `brew outdated` si Homebrew est présent, réception App Store détectée
//       par `_MASReceipt`. Ce qui ne peut pas être vérifié hors ligne est
//       annoncé comme tel (les apps tierces via Sparkle).
//    3. Extensions : `pluginkit` (états réel, activation/désactivation),
//       widgets (`com.apple.widget-extension`), extensions de navigateurs
//       (manifestes Chrome/Edge/Brave/Opera/Vivaldi/Chromium, extensions.json
//       de Firefox, extensions Safari) avec ouverture de la page de gestion et
//       désinstallation propre.
// ============================================================================

import Foundation
import AppKit

// ============================================================================
//  MARK: - Inventaire des applications
//  ============================================================================

/// Une application installée, décrite à partir de son bundle réel.
struct ManagedApp: Identifiable, Hashable {
    /// Identifiant : chemin du bundle.
    var id: String { bundlePath }
    /// Nom lisible (CFBundleName ou nom du fichier).
    let name: String
    /// Identifiant de bundle (nil si absent du Info.plist).
    let bundleId: String?
    /// Version courte (CFBundleShortVersionString).
    let version: String
    /// Numérotation de build.
    let build: String?
    /// Chemin absolu du bundle.
    let bundlePath: String
    /// Taille réelle du bundle.
    let sizeBytes: Int64
    /// Dernier accès connu au bundle (indicatif : la date d'accès peut être désactivée).
    let lastAccess: Date?
    /// L'app est-elle en cours d'exécution ?
    let isRunning: Bool
    /// Provient-elle du Mac App Store (présence de `_MASReceipt`) ?
    let fromAppStore: Bool
    /// Possède une signature de code (`Contents/_CodeSignature`) ?
    let codeSigned: Bool
    /// Emplacement système (Safari, Mail…) : jamais désinstallable.
    let isSystemLocation: Bool

    /// Chemin du bundle en URL.
    var url: URL { URL(fileURLWithPath: bundlePath) }

    /// Résumé affiché dans la liste.
    var detail: String {
        var text = "v\(version)"
        if let build = build { text += " (\(build))" }
        text += " · \(Fmt.size(sizeBytes))"
        if let lastAccess = lastAccess { text += " · vu \(Fmt.age(lastAccess))" }
        if fromAppStore { text += " · App Store" }
        if !codeSigned { text += " · non signé" }
        return text
    }
}

/// Inventaire des applications installées.
enum AppsScanner {

    /// Racines analysées, avec leur statut système.
    static func scan(deadline: Date) -> [ManagedApp] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { app -> String? in
            guard let url = app.bundleURL else { return nil }
            return url.path
        })
        let roots: [(URL, Bool)] = [
            (URL(fileURLWithPath: "/Applications"), false),
            (URL(fileURLWithPath: "/Applications/Utilities"), false),
            (PathPolicy.home.appendingPathComponent("Applications"), false),
            (PathPolicy.home.appendingPathComponent("Downloads"), false),
            (URL(fileURLWithPath: "/System/Applications"), true)
        ]
        var apps: [ManagedApp] = []
        for (root, isSystem) in roots {
            if Date() > deadline { break }
            let children = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for url in children where url.pathExtension == "app" {
                guard var app = describe(url, running: running, system: isSystem) else { continue }
                // La taille est bornée dans le temps ; 0 signifie « non mesurée ».
                app = ManagedApp(name: app.name, bundleId: app.bundleId, version: app.version,
                                 build: app.build, bundlePath: app.bundlePath,
                                 sizeBytes: Walker.size(of: url, deadline: deadline),
                                 lastAccess: app.lastAccess, isRunning: app.isRunning,
                                 fromAppStore: app.fromAppStore, codeSigned: app.codeSigned,
                                 isSystemLocation: app.isSystemLocation)
                apps.append(app)
            }
        }
        return apps.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Décrit un bundle choisi manuellement par l'utilisateur.
    ///
    /// Sert au broyeur/à la vérification de signature quand l'application n'est
    /// pas dans l'inventaire (dossier téléchargé, volume externe…).
    static func app(at url: URL) -> ManagedApp? {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.path })
        let system = url.path.hasPrefix("/System")
        guard var app = describe(url, running: running, system: system) else { return nil }
        let deadline = Date().addingTimeInterval(8)
        app = ManagedApp(name: app.name, bundleId: app.bundleId, version: app.version,
                         build: app.build, bundlePath: app.bundlePath,
                         sizeBytes: Walker.size(of: url, deadline: deadline),
                         lastAccess: app.lastAccess, isRunning: app.isRunning,
                         fromAppStore: app.fromAppStore, codeSigned: app.codeSigned,
                         isSystemLocation: app.isSystemLocation)
        return app
    }

    /// Lit le Info.plist d'un bundle et complète les informations.
    private static func describe(_ url: URL, running: Set<String>, system: Bool) -> ManagedApp? {
        let info = url.appendingPathComponent("Contents/Info.plist")
        let dictionary = NSDictionary(contentsOf: info)
        let values = try? url.resourceValues(forKeys: [.contentAccessDateKey])
        let name = (dictionary?[kCFBundleNameKey as String] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return ManagedApp(
            name: name,
            bundleId: dictionary?[kCFBundleIdentifierKey as String] as? String,
            version: (dictionary?["CFBundleShortVersionString"] as? String) ?? "—",
            build: dictionary?[kCFBundleVersionKey as String] as? String,
            bundlePath: url.path,
            sizeBytes: 0,
            lastAccess: values?.contentAccessDate,
            isRunning: running.contains(url.path),
            fromAppStore: FileManager.default.fileExists(
                atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path),
            codeSigned: FileManager.default.fileExists(
                atPath: url.appendingPathComponent("Contents/_CodeSignature/CodeResources").path),
            isSystemLocation: system
        )
    }
}

// ============================================================================
//  MARK: - Désinstallation complète (résidus)
//  ============================================================================

/// Emplacements explorés pour retrouver les traces d'une application.
enum ResidualScanner {

    /// Emplacements où le nom du résidu doit **égaler** le jeton (évite
    /// d'endommager un dossier partagé comme `Application Support/Google`).
    static let strictLocations: Set<String> = [
        "Application Support", "Caches", "Logs", "Containers", "WebKit",
        "Application Scripts", "Cookies"
    ]

    /// Emplacements où une correspondance partielle est acceptable
    /// (préfixes d'identifiant, conteneurs groupés, plist de préférences).
    static let libraryLocations: [String] = [
        "Application Support", "Caches", "Preferences", "Saved Application State",
        "Logs", "Containers", "HTTPStorages", "WebKit", "Application Scripts",
        "LaunchAgents", "Group Containers", "Application Support/CrashReporter",
        "Caches/com.apple.nsurlsessiond/Downloads"
    ]

    /// Retourne les résidus réels (fichiers et dossiers) d'une application.
    static func residuals(for app: ManagedApp) -> [FileRecord] {
        var found: [FileRecord] = []
        var seen: Set<String> = []
        let tokens = matchTokens(for: app)

        for location in libraryLocations {
            let strict = strictLocations.contains(location)
            let directory = PathPolicy.userLibrary.appendingPathComponent(location)
            guard FileManager.default.fileExists(atPath: directory.path),
                  let children = try? FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for child in children where matches(child, tokens: tokens, strict: strict) {
                guard !seen.contains(child.path) else { continue }
                seen.insert(child.path)
                if var record = FileRecord.load(child, aggregateDirectorySize: true) {
                    record.note = "résidu · \(location)"
                    record.members = record.isDirectory ? [child] : []
                    record.risk = .caution
                    found.append(record)
                }
            }
        }

        // Emplacements système : signalés, jamais supprimés sans droits.
        for location in ["Application Support", "LaunchAgents", "LaunchDaemons", "PrivilegedHelperTools"] {
            let directory = URL(fileURLWithPath: "/Library/\(location)")
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for child in children where child.lastPathComponent.lowercased()
                .contains(app.bundleId?.lowercased() ?? app.name.lowercased()) {
                var record = FileRecord(url: child, isDirectory: true, size: 0,
                                        modified: nil, accessed: nil)
                record.note = "composant système (/Library/\(location)) — droits administrateur requis"
                record.risk = .manualOnly
                found.append(record)
            }
        }

        return found.sorted { $0.size > $1.size }
    }

    /// Teste un nom de résidu contre les jetons de l'application.
    ///
    /// En mode strict, seules l'égalité (ou l'égalité avec l'extension attendue)
    /// sont acceptées : cela protège les dossiers partagés entre plusieurs
    /// applications d'un même éditeur.
    static func matches(_ url: URL, tokens: [String], strict: Bool) -> Bool {
        let name = url.lastPathComponent.lowercased()
        for token in tokens where !token.isEmpty {
            if strict {
                if name == token { return true }
                if name == token + ".plist" || name == token + ".savedstate" { return true }
            } else {
                if name.hasPrefix(token) || name.contains(token) { return true }
            }
        }
        return false
    }

    /// Jetons de recherche : identifiant de bundle et nom, tronqués.
    static func matchTokens(for app: ManagedApp) -> [String] {
        var tokens: [String] = []
        if let bundleId = app.bundleId, bundleId.count > 4 {
            tokens.append(bundleId.lowercased())
            // « com.vendor.appname » → « appname » quand il est assez distinctif.
            let pieces = bundleId.lowercased().split(separator: ".").map(String.init)
            if let last = pieces.last, last.count >= 4 { tokens.append(last) }
        }
        let shortName = app.name.lowercased()
        if shortName.count >= 4 { tokens.append(shortName) }
        return tokens
    }

    /// Espace cumulé des résidus utilisateur (hors composants système).
    static func userResidualSize(_ residuals: [FileRecord]) -> Int64 {
        return residuals.filter { $0.risk != .manualOnly }.reduce(Int64(0)) { $0 + $1.size }
    }
}

// ============================================================================
//  MARK: - Mises à jour
//  ============================================================================

/// Une mise à jour détectée sur la machine.
struct AvailableUpdate: Identifiable, Hashable {
    var id: String { label }
    /// Libellé technique (`softwareupdate`) ou nom du formule Homebrew.
    let label: String
    /// Description lisible retournée par la commande.
    let title: String
    /// Source (« Apple », « Homebrew »).
    let source: String
}

/// Résultat complet du contrôle de mises à jour.
struct UpdateAudit {
    /// Mises à jour Apple détectées.
    var apple: [AvailableUpdate] = []
    /// Mises à jour Homebrew détectées.
    var brew: [AvailableUpdate] = []
    /// Sortie brute de `softwareupdate --list` (preuve affichée à l'utilisateur).
    var appleRaw: String = ""
    /// Sortie brute de `brew outdated` si disponible.
    var brewRaw: String?
    /// Vrai si Homebrew est absent de la machine.
    var brewMissing: Bool = false
    /// Apps du Mac App Store installées (mise à jour via l'App Store uniquement).
    var appStoreApps: [String] = []
    /// Apps tierces sans canal de mise à jour vérifiable hors ligne.
    var manualReview: [String] = []
}

/// Contrôle des mises à jour logicielles.
enum UpdateProber {

    /// Lance le contrôle complet (peut prendre plusieurs dizaines de secondes).
    static func audit(apps: [ManagedApp]) -> UpdateAudit {
        var report = UpdateAudit()

        // 1. Mises à jour Apple : sortie réelle de `softwareupdate --list`.
        let outcome = Shell.run("/usr/sbin/softwareupdate", ["--list"], timeout: 180)
        report.appleRaw = outcome.failure ?? outcome.combined
        if outcome.succeeded {
            for line in outcome.lines {
                let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: "*- "))
                guard !trimmed.isEmpty,
                      trimmed.contains("Label"),
                      !trimmed.contains("Software Update Tool"),
                      !trimmed.contains("Finding available software"),
                      !trimmed.lowercased().contains("no updates") else { continue }
                let rawLabel = trimmed.split(separator: ",").first.map(String.init) ?? trimmed
                let label = rawLabel.replacingOccurrences(of: "Label:", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespaces)
                report.apple.append(AvailableUpdate(label: label, title: trimmed, source: "Apple"))
            }
        }

        // 2. Homebrew : uniquement s'il est réellement installé.
        let brewPath = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { Shell.isAvailable($0) }
        if let brewPath = brewPath {
            let brew = Shell.run(brewPath, ["outdated", "--quiet"], timeout: 120)
            report.brewRaw = brew.failure ?? brew.combined
            if brew.succeeded {
                report.brew = brew.lines.map {
                    AvailableUpdate(label: $0, title: $0, source: "Homebrew")
                }
            }
        } else {
            report.brewMissing = true
        }

        // 3. Canaux non vérifiables hors ligne : listés honnêtement.
        report.appStoreApps = apps.filter { $0.fromAppStore && !$0.isSystemLocation }.map(\.name)
        report.manualReview = apps.filter { !$0.fromAppStore && !$0.isSystemLocation }
            .sorted { $0.sizeBytes > $1.sizeBytes }.prefix(12).map { "\($0.name) (\($0.version))" }
        return report
    }

    /// Installe une mise à jour Apple identifiée (avec authentification macOS).
    static func install(_ update: AvailableUpdate) -> ShellOutcome {
        let escaped = update.label.replacingOccurrences(of: "\"", with: "\\\"")
        return Shell.runWithAdmin("softwareupdate -i \"\(escaped)\" --verbose", timeout: 1_800)
    }

    /// Ouvre le panneau Réglages Système ▸ Mise à jour logicielle.
    static func openSoftwareUpdatePane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.softwareupdate") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Ouvre l'application App Store (mise à jour des apps Store).
    static func openAppStore() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/App Store.app"))
    }
}

// ============================================================================
//  MARK: - Extensions, widgets et greffons
//  ============================================================================

/// État d'un greffon renvoyé par `pluginkit`.
enum PluginState: String {
    case enabled = "activé"
    case disabled = "désactivé"
    case `default` = "par défaut"

    /// Interprète le préfixe de ligne (`+`, `-`, rien) de `pluginkit -m`.
    static func parse(marker: String) -> PluginState {
        switch marker {
        case "+": return .enabled
        case "-": return .disabled
        default: return .default
        }
    }
}

/// Un greffon/extension enregistré auprès de macOS.
struct PluginEntry: Identifiable, Hashable {
    /// Identifiant de l'extension.
    var id: String { identifier }
    let identifier: String
    let version: String
    /// Chemin du `.appex` si `pluginkit` l'a fourni.
    let path: String?
    let state: PluginState
    /// Point d'extension (`com.apple.widget-extension`…).
    let point: String?
    /// Nom de l'application hôte.
    let host: String

    /// Vrai s'il s'agit d'un widget.
    var isWidget: Bool { point == "com.apple.widget-extension" }

    /// Résumé affiché.
    var detail: String {
        var text = "\(identifier) v\(version) · \(state.rawValue)"
        if let point = point { text += " · \(point.replacingOccurrences(of: "com.apple.", with: ""))" }
        if isWidget { text += " · widget" }
        return text
    }
}

/// Une extension de navigateur trouvée sur le disque.
struct BrowserExtension: Identifiable, Hashable {
    var id: String { directory }
    /// Navigateur propriétaire (« Google Chrome », « Firefox »…).
    let browser: String
    /// Nom déclaré dans le manifeste.
    let name: String
    let version: String
    /// Dossier de l'extension sur le disque.
    let directory: String
    /// Identifiant technique (clé Chrome, GUID Firefox…).
    let identifier: String
    /// Navigateur en cours d'exécution (la désinstallation doit attendre).
    let browserRunning: Bool

    var detail: String { "\(browser) v\(version) · \(Fmt.prettyPath(directory))" }
}

/// Lecture et pilotage des extensions macOS et navigateurs.
enum ExtensionManager {

    /// Greffons enregistrés (`pluginkit -m -A -v`), avec leur état réel.
    static func plugins(limit: Int = 400) -> [PluginEntry] {
        let outcome = Shell.run("/usr/bin/pluginkit", ["-m", "-A", "-v"], timeout: 60)
        guard outcome.succeeded else { return [] }
        var entries: [PluginEntry] = []

        for line in outcome.stdout.split(separator: "\n").map(String.init) {
            guard !line.isEmpty, !line.hasPrefix("No") else { continue }
            let marker = String(line.prefix(1))
            let body = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            let fields = body.split(separator: "\t").map(String.init)
            guard let head = fields.first else { continue }
            let identifier = head.components(separatedBy: "(").first ?? head
            var version = "?"
            if let openParen = head.firstIndex(of: "("), let closeParen = head.firstIndex(of: ")") {
                version = String(head[head.index(after: openParen)..<closeParen])
            }
            let path = fields.count >= 4 ? fields.last : nil
            let host = (path.flatMap { hostAppName(from: $0) })
                ?? (identifier.components(separatedBy: ".").dropLast().last ?? "système")
            entries.append(PluginEntry(identifier: identifier, version: version, path: path,
                                       state: PluginState.parse(marker: marker),
                                       point: pointIdentifier(for: path), host: host))
            if entries.count >= limit { break }
        }
        // Les widgets d'abord : c'est ce que l'utilisateur cherche en général.
        return entries.sorted { ($0.isWidget ? 0 : 1, $0.host) < ($1.isWidget ? 0 : 1, $1.host) }
    }

    /// Active ou désactive un greffon via `pluginkit -e use|ignore`.
    static func setEnabled(_ plugin: PluginEntry, on: Bool) -> String {
        let outcome = Shell.run("/usr/bin/pluginkit",
                                ["-e", on ? "use" : "ignore", "-i", plugin.identifier], timeout: 30)
        if outcome.succeeded {
            return "\(plugin.identifier) : \(on ? "activé" : "désactivé") via pluginkit."
        }
        return outcome.failure ?? "pluginkit a refusé la modification."
    }

    /// Désenregistre un greffon (`pluginkit -e invalidate`) : réversible,
    /// macOS le réinscrit à la prochaine ouverture de l'app hôte.
    static func invalidate(_ plugin: PluginEntry) -> String {
        let outcome = Shell.run("/usr/bin/pluginkit",
                                ["-e", "invalidate", "-i", plugin.identifier], timeout: 30)
        return outcome.succeeded
            ? "\(plugin.identifier) : enregistrement invalidé (l'app hôte le réinscrira si elle le relance)."
            : (outcome.failure ?? "invalidation impossible.")
    }

    /// Extensions des navigateurs installés sur le disque.
    static func browserExtensions() -> [BrowserExtension] {
        var results: [BrowserExtension] = []
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.localizedName })

        // Familles Chromium : un dossier Extensions/<id>/<version>/manifest.json.
        let chromium: [(browser: String, root: String)] = [
            ("Google Chrome", "Library/Application Support/Google/Chrome"),
            ("Chromium", "Library/Application Support/Chromium"),
            ("Microsoft Edge", "Library/Application Support/Microsoft Edge"),
            ("Brave", "Library/Application Support/BraveSoftware/Brave-Browser"),
            ("Opera", "Library/Application Support/Opera Software/Opera Stable"),
            ("Vivaldi", "Library/Application Support/Vivaldi")
        ]
        for family in chromium {
            let root = PathPolicy.home.appendingPathComponent(family.root)
            guard let profiles = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for profile in profiles where profile.lastPathComponent.hasPrefix("Default")
                || profile.lastPathComponent.hasPrefix("Profile") {
                let extensionsRoot = profile.appendingPathComponent("Extensions")
                guard let ids = try? FileManager.default.contentsOfDirectory(
                    at: extensionsRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
                for id in ids where id.lastPathComponent.count == 32 {
                    let versions = (try? FileManager.default.contentsOfDirectory(
                        at: id, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                    for versionFolder in versions {
                        let manifest = versionFolder.appendingPathComponent("manifest.json")
                        guard let data = FileManager.default.contents(atPath: manifest.path),
                              let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        let name = (dictionary["name"] as? String)
                            ?? (dictionary["short_name"] as? String)
                            ?? id.lastPathComponent
                        let version = (dictionary["version"] as? String) ?? "?"
                        results.append(BrowserExtension(browser: family.browser, name: name,
                                                        version: version,
                                                        directory: versionFolder.path,
                                                        identifier: id.lastPathComponent,
                                                        browserRunning: running.contains(family.browser)))
                    }
                }
            }
        }

        // Firefox : extensions.json dans chaque profil.
        let firefoxRoot = PathPolicy.userLibrary.appendingPathComponent("Application Support/Firefox/Profiles")
        if let profiles = try? FileManager.default.contentsOfDirectory(
            at: firefoxRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for profile in profiles {
                let file = profile.appendingPathComponent("extensions.json")
                guard let data = FileManager.default.contents(atPath: file.path),
                      let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let addons = dictionary["addons"] as? [[String: Any]] else { continue }
                for addon in addons {
                    let name = (addon["defaultLocale"] as? [String: Any])?["name"] as? String
                        ?? addon["name"] as? String ?? "?"
                    let version = addon["version"] as? String ?? "?"
                    let path = addon["path"] as? String ?? ""
                    results.append(BrowserExtension(browser: "Firefox", name: name, version: version,
                                                    directory: PathPolicy.home
                                                        .appendingPathComponent("Library/Application Support/Firefox/Profiles")
                                                        .appendingPathComponent(path).path,
                                                    identifier: addon["id"] as? String ?? name,
                                                    browserRunning: running.contains("Firefox")))
                }
            }
        }

        // Safari : legacy .safariextz + conteneurs d'extensions d'app.
        let safariLegacy = PathPolicy.userLibrary.appendingPathComponent("Safari/Extensions")
        if let items = try? FileManager.default.contentsOfDirectory(
            at: safariLegacy, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for item in items where item.pathExtension == "safariextz" {
                results.append(BrowserExtension(browser: "Safari", name: item.deletingPathExtension().lastPathComponent,
                                                version: "legacy", directory: item.path,
                                                identifier: item.lastPathComponent,
                                                browserRunning: running.contains("Safari")))
            }
        }
        return results.sorted { ($0.browser, $0.name) < ($1.browser, $1.name) }
    }

    /// Ouvre la page de gestion des extensions du navigateur demandé.
    ///
    /// Passe par `open -a` : le navigateur s'ouvre sur sa propre page interne.
    /// C'est la seule méthode officiellement prise en charge pour activer ou
    /// désactiver une extension (les fichiers de préférence sont chiffrés).
    static func openManagementPage(for browser: String) -> String {
        let pages: [String: String] = [
            "Google Chrome": "chrome://extensions/",
            "Chromium": "chrome://extensions/",
            "Microsoft Edge": "edge://extensions/",
            "Brave": "brave://extensions/",
            "Opera": "opera://extensions/",
            "Vivaldi": "vivaldi://extensions/",
            "Firefox": "about:addons",
            "Safari": "x-apple.settings:/com.apple.preferences.extensions"
        ]
        guard let page = pages[browser] else { return "Page de gestion indisponible pour \(browser)." }
        if browser == "Safari" {
            if let url = URL(string: page) {
                NSWorkspace.shared.open(url)
                return "Réglages Safari ▸ Extensions ouvert."
            }
            return "Réglages Safari introuvables."
        }
        let outcome = Shell.run("/usr/bin/open", ["-a", browser, page], timeout: 30)
        return outcome.succeeded
            ? "Page « \(page) » ouverte dans \(browser)."
            : (outcome.failure ?? "Ouverture impossible.")
    }

    /// Désinstalle une extension de navigateur (déplace son dossier).
    static func uninstall(_ extensionEntry: BrowserExtension, mode: DeletionMode) -> String {
        if extensionEntry.browserRunning {
            return "Fermez d'abord \(extensionEntry.browser) : ses fichiers sont verrouillés pendant l'exécution."
        }
        let url = URL(fileURLWithPath: extensionEntry.directory)
        let report = DeleteOps.apply([url], mode: mode)
        if report.count > 0 { return "\(extensionEntry.name) retiré de \(extensionEntry.browser)." }
        if let blocked = report.blocked.first { return "Suppression refusée : \(blocked.reason)" }
        return report.failures.first?.message ?? "Suppression impossible."
    }

    // -------------------------------------------------------------------------
    //  Helpers de parsing
    // -------------------------------------------------------------------------

    /// Extrait la partie d'une chaîne avant un caractère donné.
    private static func hostAppName(from path: String) -> String? {
        let components = path.components(separatedBy: "/")
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return components[index].replacingOccurrences(of: ".app", with: "")
    }

    /// Point d'extension lu dans le Info.plist du `.appex` (si lisible).
    private static func pointIdentifier(for path: String?) -> String? {
        guard let path = path, path.hasSuffix(".appex") else { return nil }
        let info = URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist")
        guard let dictionary = NSDictionary(contentsOf: info),
              let extension_ = dictionary["NSExtension"] as? [String: Any] else { return nil }
        return extension_["NSExtensionPointIdentifier"] as? String
    }
}
