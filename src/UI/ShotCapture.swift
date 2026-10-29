// ============================================================================
//  ShotCapture.swift — coque applicative : onglets, état global, auto-capture.
//
//  Auteur : Martial Zinsou
//
//  Ce fichier regroupe trois choses que l'application doit partager :
//    1. `AppTab`      — les huit destinations de la fenêtre (quatre espaces de
//                       travail, la page Surveillance complète et trois pages de
//                       documentation), avec titre, icône, accent, aide‑bulle et
//                       phrase de guidage ;
//    2. `AppState`    — la destination courante, l'état du tiroir de
//                       documentation et celui du bandeau de surveillance, plus
//                       la fenêtre hôte : le menu « Actions », celui de la barre
//                       système et le sélecteur SwiftUI partagent ce seul état ;
//    3. `ShotCapture` — le mode `--shots=DIR` : l'application lance les VRAIS
//                       balayages de chaque destination, attend leur fin réelle,
//                       puis photographie sa propre fenêtre via AppKit.
//                       `--appearance=dark|light` force le mode rendu.
//
//  Pourquoi AppKit et pas `ImageRenderer` ? `ImageRenderer` n'est pas disponible
//  avec le SDK utilisé ici (macOS 13.3 / Swift 5.8). La paire
//  `bitmapImageRepForCachingDisplay(in:)` + `cacheDisplay(in:to:)` capture en
//  revanche le rendu réel de la fenêtre, pixel pour pixel, sans capture d'écran
//  système ni droit supplémentaire.
// ============================================================================

import SwiftUI
import AppKit

// ============================================================================
//  1. Les huit onglets
// ============================================================================

/// Les onglets de la fenêtre principale, dans l'ordre d'affichage.
enum AppTab: String, CaseIterable, Identifiable {
    case surveillance
    case purge
    case performance
    case applications
    case security
    case help
    case faq
    case about

    var id: String { rawValue }

    /// Libellé visible dans la barre d'onglets.
    var title: String {
        switch self {
        case .surveillance: return "Surveillance"
        case .purge:        return "Purge"
        case .performance:  return "Performance"
        case .applications: return "Applications"
        case .security:     return "Sécurité"
        case .help:         return "Aide"
        case .faq:          return "FAQ"
        case .about:        return "À propos"
        }
    }

    /// Symbole SF de l'onglet.
    var icon: String {
        switch self {
        case .surveillance: return "gauge.medium"
        case .purge:        return "bubbles.and.sparkles.fill"
        case .performance:  return "bolt.circle.fill"
        case .applications: return "square.grid.2x2.fill"
        case .security:     return "lock.shield.fill"
        case .help:         return "questionmark.circle.fill"
        case .faq:          return "text.bubble.fill"
        case .about:        return "info.circle.fill"
        }
    }

    /// Tuile « Liquid Glass » de la destination, sans extension de fichier.
    ///
    /// Visuel de marque uniquement : sélecteur d'espaces, en-tête, badge
    /// « À propos ». Les surfaces de documentation n'en ont pas — elles
    /// n'apparaissent que dans le tiroir « ? », en petit, où un SF Symbol se
    /// lit mieux qu'une image. Une tuile absente du bundle n'est pas une panne :
    /// `MMBrandIcon` revient à la pastille vectorielle.
    var brandTile: String {
        switch self {
        case .surveillance: return "moniteur-systeme"
        case .purge:        return "purge"
        case .performance:  return "performance"
        case .applications: return "applications"
        case .security:     return "securite"
        case .help, .faq, .about: return ""
        }
    }

    /// Couleur d'accent (utilisée par la pastille du sélecteur).
    var accent: Color {
        switch self {
        case .surveillance: return .blue
        case .purge:        return .pink
        case .performance:  return .orange
        case .applications: return .purple
        case .security:     return .mmCyan
        case .help:         return .green
        case .faq:          return .mmTeal
        case .about:        return .mmIndigo
        }
    }

    /// Bulle d'aide : ce que l'onglet fait réellement.
    var helpText: String {
        switch self {
        case .surveillance:
            return "CPU, mémoire, disque et matériel mesurés en direct (top, vm_stat, sysctl, df)."
        case .purge:
            return "Sept familles balayées sur le disque : caches, logs, restes de mise à jour, traductions, volumineux/anciens, doublons SHA‑256, corbeilles."
        case .performance:
            return "Purge RAM mesurée, processus gourmands, éléments de démarrage et scripts de maintenance."
        case .applications:
            return "Inventaire, désinstallation complète, mises à jour centralisées et extensions (pluginkit + navigateurs)."
        case .security:
            return "Données de navigation, analyse anti‑malware par signatures locales, quarantaine réversible et broyeur."
        case .help:
            return "Fonctionnement de chaque famille, commandes réellement appelées et limites assumées, captures d'écran à l'appui."
        case .faq:
            return "Réponses courtes aux questions que le comportement du code pose vraiment."
        case .about:
            return "Identité, architecture des sources, commandes utilisées et refus de l'application."
        }
    }

    // ------------------------------------------------------------------------
    //  Navigation : 4 espaces + bandeau ambiant + tiroir de documentation
    // ------------------------------------------------------------------------

    /// Les quatre espaces de travail, dans l'ordre du sélecteur.
    ///
    /// Surveillance n'est plus un onglet à part : ses mesures tiennent dans le
    /// bandeau ambiant, visible en permanence en tête de fenêtre, et un clic
    /// dessus déplie les jauges complètes sans quitter l'espace où l'on est.
    /// La page entière reste accessible (`--tab=surveillance`, menus, ⌘⇧M).
    static let spaces: [AppTab] = [.purge, .performance, .applications, .security]

    /// Les trois surfaces de documentation, réunies dans le tiroir « ? ».
    static let docs: [AppTab] = [.help, .faq, .about]

    var isSpace: Bool { Self.spaces.contains(self) }
    var isDoc: Bool { Self.docs.contains(self) }

    /// Libellé court du sélecteur (un mot quand c'est possible).
    var shortTitle: String {
        switch self {
        case .surveillance: return "Surveillance"
        case .purge:        return "Purge"
        case .performance:  return "Performance"
        case .applications: return "Applications"
        case .security:     return "Sécurité"
        case .help:         return "Aide illustrée"
        case .faq:          return "FAQ"
        case .about:        return "À propos"
        }
    }

    /// Phrase de guidage affichée sous le sélecteur : ce qu'on peut faire ici.
    var guidance: String {
        switch self {
        case .surveillance:
            return "Mesures brutes : les jauges complètes, l'évolution CPU/RAM et la fiche matériel."
        case .purge:
            return "Cochez ce qui doit partir, famille par famille — la corbeille reste le geste par défaut."
        case .performance:
            return "Libérez la mémoire, identifiez les processus gourmands, contrôlez le démarrage et les scripts."
        case .applications:
            return "Désinstallez sans résidus, comparez les canaux de mise à jour, gérez greffons et extensions."
        case .security:
            return "Effacez les traces choisies, analysez les applications, broyez ce qui doit l'être."
        case .help:
            return "Comment chaque famille fonctionne, ce que l'application ne fait pas, captures d'écran à l'appui."
        case .faq:
            return "Réponses courtes, tirées du comportement réel du code."
        case .about:
            return "Qui a écrit quoi, sur quelle machine, avec quelles commandes — et ce qui est refusé."
        }
    }

    /// Nom du fichier PNG produit par le mode capture.
    var shotName: String {
        switch self {
        case .surveillance: return "01-surveillance"
        case .purge:        return "02-purge"
        case .performance:  return "03-performance"
        case .applications: return "04-applications"
        case .security:     return "05-securite"
        case .help:         return "06-aide"
        case .faq:          return "07-faq"
        case .about:        return "08-apropos"
        }
    }

    /// Accepte `--tab=surveillance`, `--tab=securite`, `--tab=aide`…
    static func fromSlug(_ raw: String) -> AppTab? {
        let needle = raw.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
        switch needle {
        case "surveillance", "moniteur", "monitor":            return .surveillance
        case "purge", "nettoyage", "stockage":                 return .purge
        case "performance", "optimisation", "ram":             return .performance
        case "applications", "apps", "extensions":             return .applications
        case "securite", "security", "confidentialite":        return .security
        case "aide", "help", "doc", "documentation":           return .help
        case "faq", "questions":                               return .faq
        case "apropos", "about", "infos":                      return .about
        default:                                               return nil
        }
    }

    /// Le bandeau doit-il s'ouvrir déplié ? Drapeau `--monitor=expanded`.
    ///
    /// Sert aux captures de documentation (la surface complète des jauges doit
    /// être photographiable sans geste manuel) et à quiconque lance l'application
    /// en mode moniteur.
    static func monitorExpandedFromCommandLine() -> Bool {
        for arg in CommandLine.arguments {
            let parts = arg.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2, parts[0] == "--monitor", ["expanded", "deplie", "déplié", "jauges"].contains(parts[1].lowercased()) {
                return true
            }
        }
        return false
    }

    /// Onglet demandé sur la ligne de commande (`--tab=`), ou `nil` si absent.
    ///
    /// Sans drapeau, l'application s'ouvre sur le premier espace de travail
    /// (`Purge`) plutôt que sur la surveillance : les mesures restent visibles
    /// dans le bandeau ambiant, et l'utilisateur arrive directement là où l'on
    /// agit.
    static func fromCommandLine() -> AppTab? {
        for arg in CommandLine.arguments {
            let parts = arg.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2, parts[0] == "--tab", let tab = fromSlug(parts[1]) {
                return tab
            }
        }
        return nil
    }
}

// ============================================================================
//  2. État global de la coque
// ============================================================================

/// Onglet courant, état du tiroir de documentation et de la bande de
/// surveillance — et fenêtre hôte, accessibles depuis les menus AppKit.
///
/// Les menus (barre de menus et menu « Actions ») ne vivent pas dans la
/// hiérarchie SwiftUI : ils ont besoin d'un point d'entrée unique pour ouvrir
/// une section précise de l'interface.
///
/// La navigation est volontairement courte : quatre espaces de travail, un
/// bandeau ambiant pour la surveillance, un tiroir pour la documentation. Un
/// utilisateur atteint n'importe quelle fonction en un clic, deux au plus pour
/// la documentation.
final class AppState: ObservableObject {

    /// Instance partagée (les menus l'utilisent hors de SwiftUI).
    static let shared = AppState()

    /// Onglet affiché.
    @Published var tab: AppTab = AppTab.fromCommandLine() ?? .purge

    /// Tiroir de documentation ouvert (Aide / FAQ / À propos).
    @Published var docsOpen = false

    /// La bande de surveillance est-elle dépliée en jauges complètes ?
    /// Ouverte d'emblée par `--monitor=expanded`.
    @Published var monitorExpanded = AppTab.monitorExpandedFromCommandLine()

    /// Dernier espace de travail visité, pour y revenir à la fermeture du tiroir.
    private(set) var lastSpace: AppTab = .purge

    /// Fenêtre principale, résolue dès que la vue est montée dans une NSWindow.
    weak var hostWindow: NSWindow?

    /// Bascule sur un onglet et amène la fenêtre au premier plan.
    ///
    /// Ouvrir un espace ferme le tiroir de documentation ; ouvrir une page de
    /// documentation lève le tiroir et mémorise l'espace d'origine.
    func go(_ tab: AppTab) {
        self.tab = tab
        if tab.isSpace {
            lastSpace = tab
            docsOpen = false
        } else if tab.isDoc {
            docsOpen = true
        }
        showMainWindow()
    }

    /// Ouvre le tiroir de documentation sur la page demandée.
    func openDocs(_ tab: AppTab) {
        docsOpen = true
        go(tab)
    }

    /// Referme le tiroir et rend l'espace de travail précédent.
    func closeDocs() {
        docsOpen = false
        go(lastSpace)
    }

    /// Rend la fenêtre principale visible et active.
    func showMainWindow() {
        guard let window = hostWindow ?? NSApp.windows.first(where: { $0.contentView != nil }) else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init() {}
}

/// Vue transparente qui ne sert qu'à récupérer la `NSWindow` qui l'héberge.
struct WindowResolver: NSViewRepresentable {

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // La fenêtre n'existe qu'au prochain battement de la boucle principale.
        DispatchQueue.main.async {
            AppState.shared.hostWindow = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if AppState.shared.hostWindow == nil {
                AppState.shared.hostWindow = nsView.window
            }
        }
    }
}

// ============================================================================
//  3. Mode capture d'écran (--shots=DIR)
// ============================================================================

/// Photographie la propre fenêtre de l'application, onglet par onglet.
///
/// Le déroulement est volontairement « réel » : chaque balayage est lancé par
/// le modèle concerné, on attend la fin effective du travail (mesurée, pas
/// simulée), puis on capture. Les PNG obtenus sont donc des captures exactes
/// de ce que voit l'utilisateur sur CETTE machine.
enum ShotCapture {

    /// Apparence imposée par `--appearance=dark|light`, ou `nil` (suivi système).
    ///
    /// Le mode Clair/Sombre n'est pas un réglage de l'application : il vient de
    /// l'utilisateur. Ce drapeau sert uniquement à vérifier, captures à
    /// l'appui, que les couleurs sémantiques (`NSColor.labelColor`, les verre
    /// d'`NSVisualEffectView`, les dégradés des pastilles) rendent correctement
    /// dans les deux modes sans version dédiée du rendu.
    static func requestedAppearance() -> NSAppearance? {
        for arg in CommandLine.arguments {
            let parts = arg.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0] == "--appearance" else { continue }
            switch parts[1].lowercased() {
            case "dark", "sombre":            return NSAppearance(named: .darkAqua)
            case "light", "clair":            return NSAppearance(named: .aqua)
            default:                          continue
            }
        }
        return nil
    }

    /// Répertoire demandé par `--shots=DIR` (ou `docs/screenshots` pour `--shots` seul).
    static func requestedDirectory() -> URL? {
        var explicit: String?
        var bare = false
        for arg in CommandLine.arguments {
            if arg == "--shots" { bare = true; continue }
            let parts = arg.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2, parts[0] == "--shots" { explicit = parts[1] }
        }
        guard bare || explicit != nil else { return nil }
        if let explicit, !explicit.isEmpty {
            return URL(fileURLWithPath: (explicit as NSString).expandingTildeInPath)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/screenshots")
    }

    /// Taille de fenêtre imposée pendant la capture (images homogènes).
    static let contentSize = NSSize(width: 1320, height: 880)

    /// Délai maximal de balayage toléré par onglet, en secondes.
    ///
    /// La purge est la plus lente : ses sept familles disposent chacune de
    /// 22 s de budget. Au‑delà, on capture l'état atteint, sans inventer.
    private static func scanBudget(for tab: AppTab) -> TimeInterval {
        switch tab {
        case .purge:        return 170
        case .applications: return 90
        case .security:     return 110
        case .performance:  return 45
        default:            return 20
        }
    }

    /// Lance la séquence complète puis quitte l'application.
    ///
    /// Appelé par le délégué après l'apparition de la fenêtre. Tout se passe
    /// sur la file principale, avec `asyncAfter` : aucune attente bloquante,
    /// l'interface continue de se mettre à jour pendant les balayages.
    @MainActor
    static func run(in directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let window = windowForCapture() else {
            FileHandle.standardError.write(Data("ShotCapture : aucune fenêtre trouvée.\n".utf8))
            NSApp.terminate(nil)
            return
        }
        window.setContentSize(contentSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Le drapeau `--appearance=` permet de photographier le même rendu en
        // mode Clair et en mode Sombre sans changer le réglage système.
        if let appearance = requestedAppearance() {
            NSApp.appearance = appearance
            log("apparence forcée : \(appearance.name.rawValue)")
        }
        log("captures dans \(directory.path)")

        let pending = AppTab.allCases
        captureNext(pending: pending, directory: directory, window: window)
    }

    // -------------------------------------------------------------------------

    /// File d'attente : un onglet à la fois (balayage → attente → capture).
    @MainActor
    private static func captureNext(pending: [AppTab], directory: URL, window: NSWindow) {
        guard let tab = pending.first else {
            log("terminées — \(directory.path)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.terminate(nil) }
            return
        }
        let rest = Array(pending.dropFirst())
        log("\(tab.title) : balayage réel…")
        // `go` plutôt qu'une affectation brute : c'est lui qui lève le tiroir de
        // documentation pour les pages Aide / FAQ / À propos.
        AppState.shared.go(tab)
        prime(tab)

        let deadline = Date().addingTimeInterval(scanBudget(for: tab))
        waitIdle(tab: tab, deadline: deadline) {
            // Laisse SwiftUI poser le rendu des résultats avant de photographier.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                let saved = self.capture(tab: tab, window: window, directory: directory)
                self.log(saved == nil
                    ? "\(tab.title) : capture échouée (vue non rendue)."
                    : "\(tab.title) : \(saved!.lastPathComponent)")
                self.captureNext(pending: rest, directory: directory, window: window)
            }
        }
    }

    /// Lance les vrais balayages dont l'onglet a besoin.
    private static func prime(_ tab: AppTab) {
        let monitor = SystemMonitor.shared
        switch tab {
        case .surveillance:
            monitor.refreshDeviceInfo()
            monitor.refreshMetrics()
        case .purge:
            PurgeModel.shared.scan()
        case .performance:
            PerformanceModel.shared.refreshAll()
        case .applications:
            AppsModel.shared.scanApps()
            AppsModel.shared.scanExtensions()
            AppsModel.shared.auditUpdates()
        case .security:
            // L'analyse de menaces s'appuie sur l'inventaire : on le d'abord.
            AppsModel.shared.scanApps()
            AppsModel.shared.scanExtensions()
            SecurityModel.shared.scanTraces()
            SecurityModel.shared.scanThreats(apps: AppsModel.shared.apps,
                                             plugins: AppsModel.shared.plugins)
        case .help, .faq, .about:
            break
        }
    }

    /// Modèle occupé ? (un seul coup d'œil synchrone, sans boucle).
    private static func isBusy(_ tab: AppTab) -> Bool {
        switch tab {
        case .surveillance:
            return false
        case .purge:
            let m = PurgeModel.shared
            return m.isScanning || m.isActing
        case .performance:
            return PerformanceModel.shared.isBusy
        case .applications:
            return AppsModel.shared.isBusy
        case .security:
            return SecurityModel.shared.isBusy || AppsModel.shared.isBusy
        case .help, .faq, .about:
            return false
        }
    }

    /// Attend (sans bloquer la boucle principale) la fin réelle des balayages.
    private static func waitIdle(tab: AppTab, deadline: Date, completion: @escaping () -> Void) {
        func poll() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !isBusy(tab) || Date() > deadline { completion(); return }
                poll()
            }
        }
        // Laisse la task de démarrage être effectivement programmée.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !isBusy(tab) { completion(); return }
            poll()
        }
    }

    // -------------------------------------------------------------------------

    /// Fenêtre à photographier : celle de l'app, sinon la première avec contenu.
    @MainActor
    private static func windowForCapture() -> NSWindow? {
        return AppState.shared.hostWindow
            ?? NSApp.windows.first { $0.contentView != nil && $0.isVisible }
            ?? NSApp.windows.first { $0.contentView != nil }
    }

    /// Capture le contenu réel de la fenêtre en PNG.
    @MainActor
    private static func capture(tab: AppTab, window: NSWindow, directory: URL) -> URL? {
        guard let content = window.contentView else { return nil }
        content.layoutSubtreeIfNeeded()
        let bounds = NSRect(origin: .zero, size: content.bounds.size)
        guard let rep = content.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        content.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        let url = directory.appendingPathComponent("\(tab.shotName).png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            log("écriture refusée : \(error.localizedDescription)")
            return nil
        }
    }

    /// Trace lisible dans la console (le script de build l'affiche).
    private static func log(_ line: String) {
        FileHandle.standardError.write(Data("capture — \(line)\n".utf8))
    }
}
