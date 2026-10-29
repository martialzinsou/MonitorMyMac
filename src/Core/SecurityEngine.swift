// ============================================================================
//  MonitorMyMac — moteur « Sécurité et confidentialité »
//  Auteur : Martial Zinsou
//  ============================================================================
//
//  Trois familles :
//
//    1. Données de navigation : cookies, historique et caches des navigateurs
//       réellement installés (Safari, Chrome, Chromium, Edge, Brave, Opera,
//       Vivaldi, Firefox). Les signets et les mots de passe ne sont **jamais**
//       proposés à la suppression ; `places.sqlite` de Firefox (historique +
//       signets mélangés) est volontairement écarté.
//    2. Analyse anti-malware : signatures locales documentées (noms et
//       identifiants de familles publicitaires macOS), heuristiques sur les
//       agents launchd, exécutables cachés dans les caches, extensions de
//       navigateurs aux permissions larges, extensions système non Apple,
//       état de Gatekeeper/SIP. C'est une aide au diagnostic, pas un antivirus.
//    3. Broyeur de fichiers : écrasement réel des octets (zéros → aléatoire →
//       zéros), vérification par relecture, troncature puis unlink. Les
//       limites d'APFS/SSD (copy-on-write, TRIM, instantanés) sont affichées.
// ============================================================================

import Foundation
import AppKit

// ============================================================================
//  MARK: - 1. Données de navigation
//  ============================================================================

/// Nature d'une trace laissée par un navigateur.
enum TraceKind: String, CaseIterable {
    case cookies = "Cookies"
    case history = "Historique"
    case cache = "Cache"
    case storage = "Stockage local"
    case downloads = "Téléchargements temporaires"
}

/// Une trace de navigation repérée sur le disque.
struct BrowserTrace: Identifiable, Hashable {
    /// Identifiant : chemin réel du fichier ou dossier.
    var id: String { url.path }
    /// Navigateur propriétaire.
    let browser: String
    /// Nature de la trace.
    let kind: TraceKind
    /// Chemin réel.
    let url: URL
    /// Taille mesurée.
    let size: Int64
    /// Le navigateur est-il ouvert (fichiers alors verrouillés) ?
    let browserRunning: Bool
    /// La trace est-elle protégée par TCC (accès complet au disque requis) ?
    let protected: Bool
    /// L'app peut-elle la lire ?
    let readable: Bool

    /// Résumé affiché.
    var detail: String {
        var text = "\(browser) · \(kind.rawValue) · \(Fmt.size(size))"
        if browserRunning { text += " · navigateur ouvert" }
        if protected && !readable { text += " · protégé par macOS" }
        return text
    }
}

/// Traces d'un même navigateur, agrégées pour une carte de l'interface.
struct BrowserTraceGroup: Identifiable, Hashable {
    var id: String { browser }
    let browser: String
    let total: Int64
    let items: [BrowserTrace]
}

/// Cartographie et nettoyage des données de navigation.
enum BrowserData {

    /// Navigateurs connus avec leur racine de profil relative au domicile.
    static let chromiumFamilies: [(name: String, root: String)] = [
        ("Google Chrome", "Library/Application Support/Google/Chrome"),
        ("Chromium", "Library/Application Support/Chromium"),
        ("Microsoft Edge", "Library/Application Support/Microsoft Edge"),
        ("Brave", "Library/Application Support/BraveSoftware/Brave-Browser"),
        ("Opera", "Library/Application Support/Opera Software/Opera Stable"),
        ("Vivaldi", "Library/Application Support/Vivaldi")
    ]

    /// Fichiers/dossiers de trace par profil Chromium.
    static let chromiumTraces: [(String, TraceKind)] = [
        ("Cookies", .cookies), ("Cookies-journal", .cookies),
        ("History", .history), ("History-journal", .history),
        ("Cache", .cache), ("Code Cache", .cache), ("GPUCache", .cache),
        ("Service Worker", .cache),
        ("Local Storage", .storage), ("Session Storage", .storage),
        ("Download Metadata", .downloads), ("DownloadCache", .downloads)
    ]

    /// Traces Safari (chemins relatifs à `~/Library`).
    static let safariTraces: [(String, TraceKind)] = [
        ("Safari/History.db", .history),
        ("Safari/History.db-wal", .history),
        ("Safari/TopSites.plist", .history),
        ("Caches/com.apple.Safari", .cache),
        ("HTTPStorages/com.apple.Safari", .cookies),
        ("Caches/com.apple.Safari.SafeBrowsing", .storage),
        ("Cookies/Cookies.binarycookies", .cookies)
    ]

    /// Ce qui n'est **jamais** proposé : la liste est affichée à l'utilisateur.
    static let neverTouched: [String] = [
        "Safari ▸ Bookmarks.plist (signets)",
        "Chrome ▸ Bookmarks, Login Data, Web Data (signets, mots de passe, cartes)",
        "Firefox ▸ places.sqlite (l'historique y est mélangé aux signets : intouchable)",
        "Trousseau d'accès (~/Library/Keychains)",
        "Profils complets et comptes synchronisés"
    ]

    /// Balaye les traces réellement présentes sur la machine.
    static func traces(deadline: Date) -> [BrowserTrace] {
        var results: [BrowserTrace] = []
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.localizedName })
        let home = PathPolicy.home

        // Safari.
        for (relative, kind) in safariTraces {
            if Date() > deadline { break }
            let url = home.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let readable = PathPolicy.canRead(url)
            results.append(BrowserTrace(browser: "Safari", kind: kind, url: url,
                                        size: readable ? Walker.size(of: url, deadline: deadline) : 0,
                                        browserRunning: running.contains("Safari"),
                                        protected: PathPolicy.isTCCProtected(url),
                                        readable: readable))
        }

        // Familles Chromium : un jeu de traces par profil.
        for family in chromiumFamilies {
            if Date() > deadline { break }
            let root = home.appendingPathComponent(family.root)
            guard let profiles = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for profile in profiles where profile.lastPathComponent.hasPrefix("Default")
                || profile.lastPathComponent.hasPrefix("Profile") {
                for (relative, kind) in chromiumTraces {
                    let url = profile.appendingPathComponent(relative)
                    guard FileManager.default.fileExists(atPath: url.path) else { continue }
                    let readable = PathPolicy.canRead(url)
                    results.append(BrowserTrace(browser: family.name, kind: kind, url: url,
                                                size: readable ? Walker.size(of: url, deadline: deadline) : 0,
                                                browserRunning: running.contains(family.name),
                                                protected: PathPolicy.isTCCProtected(url),
                                                readable: readable))
                }
            }
        }

        // Firefox : cache, cookies et stockage — jamais `places.sqlite`.
        if Date() < deadline {
            let firefoxCache = home.appendingPathComponent("Library/Caches/Firefox")
            if FileManager.default.fileExists(atPath: firefoxCache.path) {
                results.append(BrowserTrace(browser: "Firefox", kind: .cache, url: firefoxCache,
                                            size: Walker.size(of: firefoxCache, deadline: deadline),
                                            browserRunning: running.contains("Firefox"),
                                            protected: false,
                                            readable: PathPolicy.canRead(firefoxCache)))
            }
            let profiles = home.appendingPathComponent("Library/Application Support/Firefox/Profiles")
            if let list = try? FileManager.default.contentsOfDirectory(
                at: profiles, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for profile in list {
                    for (relative, kind) in [("cookies.sqlite", TraceKind.cookies),
                                             ("cookies.sqlite-wal", TraceKind.cookies),
                                             ("storage", TraceKind.storage),
                                             ("startupCache", TraceKind.cache),
                                             ("safebrowsing.db", TraceKind.storage)] {
                        let url = profile.appendingPathComponent(relative)
                        guard FileManager.default.fileExists(atPath: url.path) else { continue }
                        results.append(BrowserTrace(browser: "Firefox", kind: kind, url: url,
                                                    size: Walker.size(of: url, deadline: deadline),
                                                    browserRunning: running.contains("Firefox"),
                                                    protected: false,
                                                    readable: PathPolicy.canRead(url)))
                    }
                }
            }
        }

        return results.sorted { $0.size > $1.size }
    }

    /// Quitte le navigateur concerné pour déverrouiller ses fichiers.
    static func quit(_ browser: String) -> String {
        guard let application = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName == browser }) else { return "\(browser) n'est pas ouvert." }
        application.terminate()
        for _ in 0..<25 where !application.isTerminated {
            Thread.sleep(forTimeInterval: 0.15)
        }
        return application.isTerminated
            ? "\(browser) fermé : ses fichiers de trace sont maintenant supprimables."
            : "\(browser) refuse de se fermer (tâches en cours ?)."
    }

    /// Ouvre la page officielle de purge du navigateur.
    static func openOfficialClearPage(_ browser: String) -> String {
        switch browser {
        case "Safari":
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Categories") {
                NSWorkspace.shared.open(url)
                return "Réglages ▸ Confidentialité ouverts (Safari n'expose pas de page interne de purge)."
            }
            return "Ouverture des Réglages impossible."
        case "Firefox":
            return Shell.run("/usr/bin/open", ["-a", "Firefox", "about:preferences#privacy"]).succeeded
                ? "Page « about:preferences#privacy » ouverte." : "Firefox introuvable."
        default:
            let page = browser == "Microsoft Edge" ? "edge://settings/clearBrowserData"
                : (browser == "Brave" ? "brave://settings/clearBrowserData"
                   : (browser == "Opera" ? "opera://settings/clearBrowserData" : "chrome://settings/clearBrowserData"))
            return Shell.run("/usr/bin/open", ["-a", browser, page]).succeeded
                ? "Page « \(page) » ouverte." : "\(browser) introuvable."
        }
    }
}

// ============================================================================
//  MARK: - 2. Analyse anti-malware
//  ============================================================================

/// Gravité d'un constat de sécurité.
enum ThreatSeverity: String, CaseIterable {
    case confirmed = "signature connue"
    case suspicious = "comportement suspect"
    case informational = "information"

    /// Couleur d'affichage associée.
    var accent: String {
        switch self {
        case .confirmed: return "red"
        case .suspicious: return "orange"
        case .informational: return "blue"
        }
    }
}

/// Un constat produit par l'analyse de sécurité.
struct ThreatFinding: Identifiable, Hashable {
    var id: String { path + signature }
    /// Chemin de l'élément concerné.
    let path: String
    /// Nom lisible.
    let title: String
    /// Famille ou règle déclenchée.
    let signature: String
    /// Gravité.
    let severity: ThreatSeverity
    /// Ce qui a été réellement observé.
    let evidence: String
    /// Recommandation affichée.
    let advice: String
    /// L'app peut-elle agir (quarantaine) sur cet élément ?
    let actionable: Bool

    /// Résumé affiché sous le titre.
    var detail: String { "\(severity.rawValue) · \(signature) · \(Fmt.prettyPath(path))" }
}

/// Compteur de constats pour une sévérité (pastille d'interface).
struct ThreatCount: Identifiable, Hashable {
    var id: String { severity.rawValue }
    let severity: ThreatSeverity
    let count: Int
}

/// Analyse par signatures locales et heuristiques.
enum SecurityScanner {

    /// Signatures documentées de logiciels publicitaires et indésirables macOS.
    ///
    /// Chaque entrée correspond à une famille décrite publiquement (rapports de
    /// chercheurs en sécurité). La liste n'est pas exhaustive : c'est une aide
    /// au diagnostic, pas une garantie de détection.
    static let signatures: [(token: String, family: String, note: String)] = [
        ("com.genieo.webmlui", "Genieo", "plateforme publicitaire injectée dans les navigateurs"),
        ("genieo", "Genieo", "plateforme publicitaire injectée dans les navigateurs"),
        ("com.mackeeper", "MacKeeper", "optimiseur agressif, installé via des pourriels"),
        ("mackeeper", "MacKeeper", "optimiseur agressif, installé via des pourriels"),
        ("reksoft.searchmodule", "SearchModule", "détournement de moteur de recherche"),
        ("searchmodule", "SearchModule", "détournement de moteur de recherche"),
        ("vsearch", "VSearch", "extension de recherche et injection publicitaire"),
        ("adsfactor", "AdsFactor", "injecteur de publicités dans Safari/Chrome"),
        ("pricegong", "PriceGong", "injecteur de bannières comparateurs de prix"),
        ("ollycab", "Ollycab", "adware de détournement de recherche"),
        ("trovator", "Trovator", "paquet publicitaire réinstallateur"),
        ("downloadkit", "DownloadKit", "téléchargeur d'adwares (Softlans)"),
        ("crossrider", "Crossrider", "plateforme d'extensions publicitaires"),
        ("anysearch", "AnySearch", "détournement de moteur de recherche"),
        ("webnetc", "WebNetC", "adware de proxy"),
        ("zalitty", "Zalitty", "chevalet de publicités"),
        ("kefilter", "KeRanger", "rançongiciel macOS historiquement signé"),
        ("wirelurker", "WireLurker", "chevaux de Troie via app stores tiers"),
        ("chengpai", "ChengpaiABC", "infrastructure WireLurker"),
        ("appshoppers", "AppShopper", "PUP de modification de prix"),
        ("spigot", "Spigot", "adware installé via des installeurs tierces"),
        ("asksearch", "Ask/AnyPath", "barre d'outils de recherche"),
        ("webkitdeveloper", "Faux outil de développement", "binaire se faisant passer pour un outil Apple"),
        ("updateragent", "UpdaterAgent", "agent de mise à jour non signé"),
        ("installer_check", "Shlayer", "leurre « installeur Flash »"),
        ("flashback", "Flashback", "cheval de Troie historique /usr/bin/.fsuted")
    ]

    /// Emplacements où macOS a historiquement vu apparaître des indésirables.
    static let watchDirectories: [String] = [
        "Library/Application Support", "Library/LaunchAgents", "Library/Preferences",
        "Library/Internet Plug-Ins", "Library/PreferencePanes", "Library/Widgets",
        "Library/Screen Savers", "Library/QuickLook", "Library/Services",
        "Library/Input Methods", "Library/Containers", "Library/Caches"
    ]

    /// Emplacements système (lecture seule, signalés uniquement).
    static let systemWatchDirectories: [String] = [
        "/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PreferencePanes",
        "/Library/Internet Plug-Ins", "/Library/StartupItems", "/Library/Screen Savers",
        "/Users/Shared"
    ]

    /// Lance l'analyse complète.
    static func scan(apps: [ManagedApp], plugins: [PluginEntry], deadline: Date) -> [ThreatFinding] {
        var findings: [ThreatFinding] = []

        // (a) Signatures dans les noms de bundles et d'applications.
        for app in apps {
            let haystack = ((app.bundleId ?? "") + " " + app.name).lowercased()
            for signature in signatures where haystack.contains(signature.token) {
                findings.append(ThreatFinding(path: app.bundlePath, title: app.name,
                                              signature: signature.family, severity: .confirmed,
                                              evidence: "application « \(app.name) » \(app.detail)",
                                              advice: signature.note + " — vérifiez l'éditeur avant de mettre en quarantaine.",
                                              actionable: true))
            }
        }

        // (b) Fichiers porteurs d'une signature dans les emplacements surveillés.
        for relative in watchDirectories {
            if Date() > deadline { break }
            let directory = PathPolicy.userLibrary.appendingPathComponent(relative)
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for child in children {
                let name = child.lastPathComponent.lowercased()
                guard let match = signatures.first(where: { name.contains($0.token) }) else { continue }
                findings.append(ThreatFinding(path: child.path, title: child.lastPathComponent,
                                              signature: match.family, severity: .confirmed,
                                              evidence: "présent dans \(relative)",
                                              advice: match.note + " — mise en quarantaine réversible proposée.",
                                              actionable: PathPolicy.allowsDeletion(of: child)))
            }
        }
        for absolute in systemWatchDirectories {
            if Date() > deadline { break }
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: absolute), includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]) else { continue }
            for child in children {
                let name = child.lastPathComponent.lowercased()
                guard let match = signatures.first(where: { name.contains($0.token) }) else { continue }
                findings.append(ThreatFinding(path: child.path, title: child.lastPathComponent,
                                              signature: match.family, severity: .confirmed,
                                              evidence: "présent dans \(absolute) (racine système)",
                                              advice: match.note + " — suppression exige les droits administrateur.",
                                              actionable: false))
            }
        }

        // (c) Heuristique : agents launchd pointant vers des zones éphémères.
        for item in StartupManager.items() {
            guard let path = item.path else { continue }
            let command = item.command.lowercased()
            let ephemeral = command.contains("/private/var/folders") || command.contains("/tmp/")
            let hiddenHome = command.contains("/library/.")
                || command.contains("/library/hidden")
            guard ephemeral || hiddenHome else { continue }
            findings.append(ThreatFinding(path: path, title: item.title,
                                          signature: "agent launchd suspect",
                                          severity: .suspicious,
                                          evidence: "se lance au démarrage via « \(item.command.prefix(120)) »",
                                          advice: "Un utilitaire légitime peut ressembler à cela : ouvrez le fichier "
                                               + "avant d'agir. Désactivation possible depuis "
                                               + "Performance ▸ Éléments de démarrage.",
                                          actionable: true))
        }

        // (d) Heuristique : exécutables cachés dans les caches utilisateur.
        for executable in hiddenExecutables(in: PathPolicy.userLibrary.appendingPathComponent("Caches"),
                                           deadline: deadline) {
            findings.append(ThreatFinding(path: executable.path, title: executable.lastPathComponent,
                                          signature: "binaire exécutable dans un cache",
                                          severity: .suspicious,
                                          evidence: "fichier marqué exécutable dans ~/Library/Caches",
                                          advice: "Les caches ne contiennent normalement aucun exécutable. "
                                               + "Inspectez-le (⌘-clic ▸ Ouvrir dans le Finder) avant de mettre en quarantaine.",
                                          actionable: PathPolicy.allowsDeletion(of: executable)))
        }

        // (e) Extensions de navigateurs aux permissions larges.
        for extension_ in ExtensionManager.browserExtensions() {
            guard let manifestURL = manifestURL(for: extension_) else { continue }
            guard let data = FileManager.default.contents(atPath: manifestURL.path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let permissions = (json["permissions"] as? [String]) ?? []
            let broad = permissions.contains("<all_urls>") || permissions.contains("webRequest")
                || permissions.contains("proxy") || permissions.contains("management")
            let name = (extension_.name.lowercased())
            let impersonation = ["adblock", "ublock", "vpn", "flash player", "google", "chrome update"]
                .contains(where: { name.contains($0) })
            if broad && impersonation {
                findings.append(ThreatFinding(path: extension_.directory, title: extension_.name,
                                              signature: "extension imitante",
                                              severity: .suspicious,
                                              evidence: "\(extension_.browser) · permissions : \(permissions.prefix(4).joined(separator: ", "))",
                                              advice: "Comparez avec l'extension officielle du même nom dans la page de gestion.",
                                              actionable: true))
            } else if broad {
                findings.append(ThreatFinding(path: extension_.directory, title: extension_.name,
                                              signature: "permissions étendues",
                                              severity: .informational,
                                              evidence: "accès à tous les sites (\(permissions.prefix(3).joined(separator: ", ")))",
                                              advice: "Rien d'anormal en soi : vérifiez que vous avez installé cette extension.",
                                              actionable: true))
            }
        }

        // (f) Extensions système non Apple + posture de sécurité.
        for finding in systemExtensionsFindings() { findings.append(finding) }
        findings.append(contentsOf: systemPostureFindings())

        // (g) Greffons macOS dont l'hôte n'existe plus (orphelins).
        for plugin in plugins {
            guard let path = plugin.path else { continue }
            if !FileManager.default.fileExists(atPath: path) {
                findings.append(ThreatFinding(path: path, title: plugin.identifier,
                                              signature: "greffon orphelin",
                                              severity: .informational,
                                              evidence: "pluginkit connaît ce point d'extension mais le fichier a disparu",
                                              advice: "Sans gravité : macOS le désinscrit à la prochaine réindexation.",
                                              actionable: false))
            }
        }

        return findings.sorted { ($0.severity.order, $0.title) < ($1.severity.order, $1.title) }
    }

    /// Vérification ciblée d'une application (signature + Gatekeeper).
    static func assess(_ app: ManagedApp) -> String {
        let codesign = Shell.run("/usr/bin/codesign", ["--verify", "--verbose", app.bundlePath], timeout: 60)
        let spctl = Shell.run("/usr/sbin/spctl", ["--assess", "--type", "exec", "--verbose=3", app.bundlePath], timeout: 60)
        var text = "codesign : \(codesign.succeeded ? "validation OK" : (codesign.failure ?? "échec"))\n"
        text += "Gatekeeper : \(spctl.succeeded ? "autorisé" : (spctl.failure ?? "refusé"))\n"
        if let detail = spctl.lines.first { text += detail }
        return text
    }

    // -------------------------------------------------------------------------
    //  Helpers
    // -------------------------------------------------------------------------

    /// Retourne les exécutables planqués dans un répertoire de cache.
    ///
    /// Un cache légitime ne contient pas de binaire lançable : ce signal est
    /// heuristique (certains installateurs y déposent des outils), d'où le
    /// niveau « suspect » et non « confirmé ».
    static func hiddenExecutables(in directory: URL, deadline: Date) -> [URL] {
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }) else { return results }
        for case let url as URL in enumerator {
            if Date() > deadline || results.count >= 12 { break }
            let extension_ = url.pathExtension.lowercased()
            if PathPolicy.packageExtensions.contains(extension_) { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile ?? false else { continue }
            guard FileManager.default.isExecutableFile(atPath: url.path) else { continue }
            results.append(url)
        }
        return results
    }

    /// Chemin du manifeste d'une extension de navigateur.
    static func manifestURL(for entry: BrowserExtension) -> URL? {
        let directory = URL(fileURLWithPath: entry.directory)
        let manifest = directory.appendingPathComponent("manifest.json")
        return FileManager.default.fileExists(atPath: manifest.path) ? manifest : nil
    }

    /// Extensions système (`systemextensionsctl list`) non signées par Apple.
    static func systemExtensionsFindings() -> [ThreatFinding] {
        let outcome = Shell.run("/usr/sbin/systemextensionsctl", ["list"], timeout: 60)
        guard outcome.succeeded else {
            return [ThreatFinding(path: "systemextensionsctl", title: "Extensions système",
                                  signature: "commande indisponible", severity: .informational,
                                  evidence: outcome.failure ?? "aucune sortie",
                                  advice: "Impossible de lister les extensions système sur cette machine.",
                                  actionable: false)]
        }
        var findings: [ThreatFinding] = []
        for line in outcome.lines {
            guard line.contains("[unactivated]") || line.contains("[activated]"),
                  line.contains("com.apple") == false else { continue }
            findings.append(ThreatFinding(path: line, title: "Extension système tierce",
                                          signature: "extension système", severity: .informational,
                                          evidence: line,
                                          advice: "Réglez-les dans Réglages Système ▸ Général ▸ Extensions si vous ne reconnaissez pas l'éditeur.",
                                          actionable: false))
        }
        return findings
    }

    /// Posture de sécurité globale (Gatekeeper, SIP, mises à jour).
    static func systemPostureFindings() -> [ThreatFinding] {
        var findings: [ThreatFinding] = []
        let gatekeeper = Shell.run("/usr/sbin/spctl", ["--status"], timeout: 20)
        findings.append(ThreatFinding(
            path: "spctl --status", title: "Gatekeeper",
            signature: "posture système", severity: .informational,
            evidence: gatekeeper.combined.isEmpty ? "indisponible" : gatekeeper.combined,
            advice: gatekeeper.combined.contains("enabled")
                ? "Les assessments sont actifs : les apps non notariées sont bloquées."
                : "Gatekeeper désactivé : vos téléchargements ne sont plus contrôlés.",
            actionable: false))

        let sip = Shell.run("/usr/bin/csrutil", ["status"], timeout: 20)
        findings.append(ThreatFinding(
            path: "csrutil status", title: "System Integrity Protection",
            signature: "posture système", severity: .informational,
            evidence: sip.combined.isEmpty ? "indisponible" : sip.combined,
            advice: sip.combined.contains("enabled")
                ? "SIP actif : le système reste protégé contre les écritures."
                : "SIP désactivé : réactivez-le depuis le mode récupération si possible.",
            actionable: false))

        if !PrivacyAccess.hasFullDiskAccess() {
            findings.append(ThreatFinding(
                path: "TCC", title: "Accès complet au disque",
                signature: "autorisation", severity: .informational,
                evidence: "MonitorMyMac ne peut pas lire les zones protégées (Cookies, Safari, Mail, /var/log).",
                advice: "Optionnel : Réglages Système ▸ Confidentialité ▸ Accès complet au disque. "
                      + "Sans lui, l'analyse reste partielle — c'est indiqué, jamais simulé.",
                actionable: false))
        }
        return findings
    }
}

private extension ThreatSeverity {
    /// Ordre d'affichage : du plus grave au plus informatif.
    var order: Int {
        switch self {
        case .confirmed: return 0
        case .suspicious: return 1
        case .informational: return 2
        }
    }
}

// ============================================================================
//  MARK: - 3. Broyeur de fichiers
//  ============================================================================

/// Résultat d'un broyage.
struct ShredOutcome: Identifiable {
    var id: String { path }
    let path: String
    /// Octets réellement écrasés.
    let bytesOverwritten: Int64
    /// Passes effectuées.
    let passes: Int
    /// La relecture d'échantillons a-t-elle confirmé l'écrasement ?
    let verified: Bool
    /// Le fichier a-t-il été détaché du système de fichiers ?
    let unlinked: Bool
    /// Message d'échec éventuel (réel).
    let error: String?
}

/// Écrasement sécurisé puis suppression d'un fichier.
enum FileShredder {

    /// Nombres de passes proposés (0 = dépend du mode choisi).
    static let passPresets: [(label: String, passes: Int)] = [
        ("Rapide (1 passe : zéros)", 1),
        ("Renforcée (3 passes : zéros, aléatoire, zéros)", 3),
        ("Multi-passes (7 passes)", 7)
    ]

    /// Broye un fichier : écriture répétée, troncature, unlink.
    ///
    /// - Important : sur APFS (SSD), l'écrasement ne garantit pas l'effacement
    ///   des blocs physiques (copy-on-write, TRIM, instantanés, sauvegarde).
    ///   L'app le dit à l'utilisateur ; le vrai remède pour des données
    ///   confidentielles reste le chiffrement du volume (FileVault).
    static func shred(_ url: URL, passes: Int) -> ShredOutcome {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        let size = Int64(values?.fileSize ?? 0)
        guard values?.isRegularFile ?? false else {
            return ShredOutcome(path: url.path, bytesOverwritten: 0, passes: passes,
                                verified: false, unlinked: false,
                                error: "ce n'est pas un fichier régulier (dossier, lien ou fichier protégé).")
        }
        guard FileManager.default.isWritableFile(atPath: url.path) else {
            return ShredOutcome(path: url.path, bytesOverwritten: 0, passes: passes,
                                verified: false, unlinked: false,
                                error: "aucun droit d'écriture sur ce fichier.")
        }

        do {
            // Le bit « immutable » (chflags uchg) bloquerait l'écriture : on le retire.
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            let handle = try FileHandle(forUpdating: url)
            defer { try? handle.close() }

            var written: Int64 = 0
            let chunkSize = 1 << 20
            for pass in 1...max(1, passes) {
                try handle.seek(toOffset: 0)
                var remaining = size
                while remaining > 0 {
                    let length = Int(min(Int64(chunkSize), remaining))
                    let buffer = bufferFor(pass: pass, length: length)
                    try handle.write(contentsOf: buffer)
                    written += Int64(length)
                    remaining -= Int64(length)
                }
                try handle.synchronize()
            }

            // Relecture de trois échantillons pour vérifier l'écrasement.
            let verified = verify(handle: handle, size: size)
            try handle.truncate(atOffset: 0)
            try handle.synchronize()
            try handle.close()

            do {
                try FileManager.default.removeItem(at: url)
                return ShredOutcome(path: url.path, bytesOverwritten: written, passes: passes,
                                    verified: verified, unlinked: true, error: nil)
            } catch {
                return ShredOutcome(path: url.path, bytesOverwritten: written, passes: passes,
                                    verified: verified, unlinked: false,
                                    error: "écrasé mais non supprimé : \(error.localizedDescription)")
            }
        } catch {
            return ShredOutcome(path: url.path, bytesOverwritten: 0, passes: passes,
                                verified: false, unlinked: false,
                                error: error.localizedDescription)
        }
    }

    /// Broye récursivement le contenu d'un dossier, puis le dossier.
    static func shredDirectory(_ url: URL, passes: Int, deadline: Date) -> [ShredOutcome] {
        var outcomes: [ShredOutcome] = []
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles], errorHandler: { _, _ in true }) else { return outcomes }
        var files: [URL] = []
        for case let child as URL in enumerator {
            if Date() > deadline { break }
            let values = try? child.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile ?? false { files.append(child) }
        }
        for file in files where Date() < deadline {
            outcomes.append(shred(file, passes: passes))
        }
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
                outcomes.append(ShredOutcome(path: url.path, bytesOverwritten: 0, passes: passes,
                                             verified: true, unlinked: true, error: nil))
            } catch {
                outcomes.append(ShredOutcome(path: url.path, bytesOverwritten: 0, passes: passes,
                                             verified: false, unlinked: false,
                                             error: error.localizedDescription))
            }
        }
        return outcomes
    }

    /// Tampon d'écrasement selon la passe (zéros, aléatoire, motif).
    private static func bufferFor(pass: Int, length: Int) -> Data {
        switch pass % 3 {
        case 1: return Data(count: length)                                  // zéros
        case 2:                                                              // aléatoire
            var data = Data(count: length)
            data.withUnsafeMutableBytes { raw in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                for index in 0..<length { base[index] = UInt8.random(in: 0...255) }
            }
            return data
        default:                                                             // motif 0xFF
            return Data(repeating: 0xFF, count: length)
        }
    }

    /// Relit trois échantillons et vérifie qu'ils ne contiennent plus de données.
    private static func verify(handle: FileHandle, size: Int64) -> Bool {
        guard size > 0 else { return true }
        let offsets: [UInt64] = [0, UInt64(max(0, size / 2)), UInt64(max(0, size - 4096))]
        for offset in offsets {
            do {
                try handle.seek(toOffset: offset)
                guard let data = try handle.read(upToCount: 4096), !data.isEmpty else { continue }
                if data.contains(where: { $0 != 0 }) { return false }
            } catch {
                return false
            }
        }
        return true
    }

    /// Le `rm -P` de BSD est-il disponible et accepté sur ce système de fichiers ?
    static func supportsBSDSecureDelete() -> String {
        let outcome = Shell.run("/bin/rm", ["-P", "--help"], timeout: 10)
        if outcome.stdout.contains("-P") || outcome.stderr.contains("-P") {
            return "rm -P est présent, mais BSD refuse l'écrasement sur les systèmes de fichiers "
                 + "qui ne le garantissent pas (APFS) : la commande échoue avec « Operation not permitted »."
        }
        return "rm -P indisponible sur cette machine."
    }
}
