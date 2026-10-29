// ============================================================================
//  MonitorMyMac — thème et composants d'interface partagés
//  Auteur : Martial Zinsou
//  ============================================================================
//
//  Tous les onglets (Purge, Performance, Applications, Sécurité, Aide, FAQ,
//  À propos) utilisent les mêmes briques : carte en matériau translucide,
//  en-tête de section, pilule, ligne d'élément cochable, sélecteur de mode,
//  rapport d'opération et bandeau d'honnêteté.
//
//  Contrainte d'environnement : cible de déploiement macOS 11.0 (Big Sur),
//  compilée avec le SDK macOS 13.3. Sont donc proscrits : `Chart`,
//  `ContentUnavailableView`, `@Observable`, `foregroundStyle`, `Material`
//  comme `ShapeStyle`, `AnyShapeStyle`, `Gauge`, `Color.teal/cyan/indigo/mint/
//  brown`, `.textSelection`. Les sections « Compat macOS 11 » de ce fichier
//  fournissent l'équivalent 11 de chacun — ou un garde `#available` quand
//  l'API améliore seulement le confort (sélection du texte).
// ============================================================================

import SwiftUI
import AppKit

// ============================================================================
//  MARK: - Couleurs
// ============================================================================

/// Résout les noms d'accent fournis par les moteurs (qui ne doivent pas
/// dépendre de SwiftUI) en couleurs réelles.
enum Theme {

    /// Couleur associée à un nom d'accent (« pink », « orange »…).
    static func accent(_ name: String) -> Color {
        switch name.lowercased() {
        case "pink": return .pink
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "mint": return .mmMint
        case "teal": return .mmTeal
        case "cyan": return .mmCyan
        case "blue": return .blue
        case "indigo": return .mmIndigo
        case "purple": return .purple
        case "brown": return .mmBrown
        default: return .accentColor
        }
    }

    /// Couleur d'un niveau de risque.
    static func color(for risk: FileRecord.Risk) -> Color {
        switch risk {
        case .safe: return .green
        case .caution: return .orange
        case .manualOnly: return .red
        }
    }

    /// Couleur d'un état mémoire, depuis le libellé produit par le moteur.
    ///
    /// Le moteur ne connaît que des chaînes (il n'importe pas SwiftUI) ; c'est
    /// ici que la pression devient une teinte. Les seuils vivent dans
    /// `MemorySnapshot.stateLabel`, ce qui évite deux sources de vérité.
    static func memoryState(_ label: String) -> Color {
        switch label {
        case "confortable": return .green
        case "normale": return .yellow
        case "tendue": return .orange
        default: return .red
        }
    }

    /// Dégradé d'une pastille d'action.
    static func gradient(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color, color.opacity(0.72)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// ============================================================================
//  MARK: - Compat macOS 11
// ============================================================================

/// Couleurs sémantiques d'AppKit exposées à SwiftUI.
///
/// Sur macOS 12+, `Color.primary` / `.secondary` / `.tertiary` rendent le même
/// service, mais `.tertiary` n'existe pas du tout avant macOS 12 et le passage
/// par `NSColor` garantit en plus une adaptation exacte au mode Clair/Sombre —
/// y compris pour les libellés désactivés, que la palette SwiftUI ne couvre pas.
/// `Color(NSColor)` est disponible depuis macOS 10.15 ; c'est `Color(nsColor:)`
/// (macOS 12) qui est proscrit ici.
extension Color {
    static let mmLabel = Color(NSColor.labelColor)
    static let mmSecondaryLabel = Color(NSColor.secondaryLabelColor)
    static let mmTertiaryLabel = Color(NSColor.tertiaryLabelColor)
    static let mmQuaternaryLabel = Color(NSColor.quaternaryLabelColor)
    static let mmSeparator = Color(NSColor.separatorColor)
    static let mmWindowBackground = Color(NSColor.windowBackgroundColor)
    static let mmControlBackground = Color(NSColor.controlBackgroundColor)

    /// `Color.indigo` n'existe qu'à partir de macOS 12. `NSColor.systemIndigo`,
    /// lui, est disponible depuis macOS 11 et reste une couleur dynamique :
    /// l'accent se corrige tout seul en mode Sombre.
    static let mmIndigo = Color(NSColor.systemIndigo)

    /// Idem pour `Color.teal` (macOS 12) : `NSColor.systemTeal` existe depuis 11.
    static let mmTeal = Color(NSColor.systemTeal)

    /// `Color.mint` et `Color.brown` sont eux aussi macOS 12 ; les couleurs
    /// système `NSColor.systemMint` / `systemBrown` existent depuis macOS 11.
    static let mmMint = Color(NSColor.systemMint)
    static let mmBrown = Color(NSColor.systemBrown)

    /// `Color.cyan` est macOS 12, et `NSColor.systemCyan` aussi : aucune
    /// couleur système ne rend le service sur Big Sur. Cette teinte RVB
    /// reprend la valeur claire du système ; le cyan reste une couleur
    /// d'accent, pas un indicateur d'état, donc une teinte fixe est acceptable.
    static let mmCyan = Color(red: 90.0 / 255.0, green: 200.0 / 255.0, blue: 250.0 / 255.0)
}

/// Fond en verre translucide rendu par AppKit.
///
/// `Material.ultraThinMaterial` n'est utilisable comme `ShapeStyle` (donc dans
/// `.fill(...)` ou `.background(...)`) qu'à partir de macOS 12. `NSVisualEffectView`,
/// lui, existe depuis macOS 10.11 : c'est le vrai flou du système, le même que
/// celui des panneaux natifs, et il s'adapte tout seul au mode Clair/Sombre.
/// C'est aussi ce qui donne la réfraction « verre liquide » recherchée, sans
/// dependre du SDK 13.
struct GlassBackground: NSViewRepresentable {

    /// Qualité de verre, du plus discret au plus présent.
    enum Kind {
        /// Carte de contenu : flou léger dans la fenêtre.
        case card
        /// Bandeau et barres : verre d'en-tête.
        case bar
        /// Surface de marque (sélecteur d'espaces, À propos) : verre marqué.
        case hero

        var material: NSVisualEffectView.Material {
            switch self {
            case .card: return .sidebar
            case .bar: return .headerView
            case .hero: return .underWindowBackground
            }
        }
    }

    var kind: Kind = .card
    var cornerRadius: CGFloat = 18

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        // `.withinWindow` floute ce qui précède *dans* la fenêtre : c'est le
        // comportement attendu d'une carte, alors que `.behindWindow` flouterait
        // le bureau et rendrait le texte illisible selon le fond d'écran.
        view.blendingMode = .withinWindow
        view.state = .active
        view.isEmphasized = kind == .hero
        view.material = kind.material
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = kind.material
        view.isEmphasized = kind == .hero
        view.layer?.cornerRadius = cornerRadius
    }
}

extension View {

    /// Pose un verre AppKit derrière la vue, dans un rectangle arrondi.
    func mmGlass(cornerRadius: CGFloat = 18, kind: GlassBackground.Kind = .card) -> some View {
        background(
            GlassBackground(kind: kind, cornerRadius: cornerRadius)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        )
    }

    /// Raccourci de lisibilité : `.foregroundColor(...)` est l'appel macOS 11 ;
    /// l'API `foregroundStyle` correspondante n'existe qu'à partir de macOS 12.
    func mmForeground(_ color: Color) -> some View {
        foregroundColor(color)
    }

    /// Sélection du texte à la souris, là où le système la propose.
    ///
    /// `.textSelection(.enabled)` est une API macOS 12 : appelée directement,
    /// elle interdit la compilation sous une cible de déploiement 11.0. Ce
    /// modulateur la place derrière `#available`, donc la sélection s'active
    /// sur Monterey et plus récent, et le texte reste consultable sur Big Sur.
    /// Les blocs bruts affichent en plus un `CopyButton`, qui fonctionne depuis
    /// macOS 10.6 : la copie reste possible même sans sélection.
    @ViewBuilder func mmTextSelection() -> some View {
        if #available(macOS 12.0, *) {
            textSelection(.enabled)
        } else {
            self
        }
    }

    /// Bulle d'aide conditionnelle : une aide vide ne doit pas afficher une
    /// infobulle vide au survol.
    func mmHelp(_ text: String) -> some View {
        modifier(MMHelpModifier(text: text))
    }
}

/// `.help(...)` appliqué seulement quand le libellé existe.
///
/// Un `if` dans le corps d'une vue changerait le type de la branche (et donc le
/// layout) ; un `Modifier` garde une chaîne de modificateurs stable.
private struct MMHelpModifier: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        if text.isEmpty {
            content
        } else {
            content.help(text)
        }
    }
}

/// Jauge de charge en barre, dessinée à la main.
///
/// `Gauge` et son style `accessoryLinearCapacity` demandent macOS 13. Cette
/// version n'utilise que des formes disponibles depuis macOS 11 et rend
/// exactement la même information : pourcentage, barre dégradée et libellé
/// d'état. Le dégradé suit la pression, pas la valeur affichée — une barre à
/// 60 % en vert n'est pas la même nouvelle qu'à 60 % en rouge.
struct PressureBar: View {
    /// 0…1
    let ratio: Double
    /// Libellé court affiché sous la barre (« normale », « tendue »…).
    let stateLabel: String
    /// Couleur d'accent de l'état, alignée sur `stateLabel`.
    let stateColor: Color

    private var clamped: Double { min(max(ratio, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.percent(clamped))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.mmLabel)
                Spacer(minLength: 0)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.mmLabel.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [stateColor.opacity(0.55), stateColor],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, proxy.size.width * clamped))
                }
            }
            .frame(height: 8)
            Text(stateLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(stateColor)
        }
    }
}

/// Fond de carte partagé : verre AppKit, voile, bordure et ombre.
///
/// Trois vues de la coque duplicaient ce calcul ; le centraliser évite qu'un
/// onglet garde un matériau macOS 12 pendant que les autres passent au verre.
struct MMCardBackground: View {
    var cornerRadius: CGFloat = 18
    var kind: GlassBackground.Kind = .card

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return shape
            .fill(Color.mmLabel.opacity(0.03))
            .background(GlassBackground(kind: kind, cornerRadius: cornerRadius)
                .clipShape(shape))
            .overlay(shape.stroke(Color.mmSeparator.opacity(0.7), lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
    }
}

/// Écrit un texte dans le presse-papiers et le confirme visuellement.
///
/// Les blocs multilignes (sortie brute de `softwareupdate`, console des
/// scripts, rapport d'analyse) restent du `Text` SwiftUI : `.textSelection`
/// n'existe qu'à partir de macOS 12, et un `NSTextField` qui revient à la
/// ligne ne se dimensionne pas de façon fiable dans une `ScrollView` sans
/// SDK plus récent. Le presse-papiers, lui, est disponible depuis macOS 10.6
/// — copier-coller fonctionne donc sur toutes les versions ciblées.
struct CopyButton: View {
    let text: String
    var title: String = "Copier"
    var color: Color = .gray

    @State private var copied = false

    var body: some View {
        Button(action: copy) {
            HStack(spacing: 4) {
                Image(systemName: (copied ? "checkmark" : "doc.on.doc").mmSafeSymbol)
                    .font(.system(size: 9))
                Text(copied ? "Copié" : title)
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .buttonStyle(.borderless)
        .foregroundColor(copied ? .green : color)
        .help(copied
            ? "Le contenu est dans le presse-papiers."
            : "Copie le contenu brut du bloc dans le presse-papiers, sans sélection à la souris.")
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        // `declareTypes` renvoie le nombre de types retenus (un `Int`), pas un
        // booléen : comparer à zéro est la seule écriture valable sous la cible 11.
        let claimed = pasteboard.declareTypes([.string], owner: nil) > 0
        copied = claimed && pasteboard.setString(text, forType: .string)
        if copied {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
        }
    }
}

// MARK: - Texte enrichi sans AttributedString

/// Morceau de texte enrichi reconnu par le parseur minimal du projet.
enum MMRichPiece {
    case plain(String)
    case bold(String)
    case code(String)
}

/// Reconnaît `**gras**` et le code entre accents graves dans une chaîne.
///
/// `AttributedString(markdown:)` est une API macOS 12. Les notes d'honnêteté
/// n'utilisent que deux constructions markdown, donc un parseur d'une
/// trentaine de lignes rend le même résultat sur Big Sur, sans `#available`
/// ni version dégradée.
func mmParseRichText(_ source: String) -> [MMRichPiece] {
    var pieces: [MMRichPiece] = []
    var plain = ""
    var cursor = source.startIndex

    func flushPlain() {
        if !plain.isEmpty {
            pieces.append(.plain(plain))
            plain = ""
        }
    }

    while cursor < source.endIndex {
        let rest = source[cursor...]
        if rest.hasPrefix("**"),
           let closing = source.range(of: "**", range: source.index(cursor, offsetBy: 2)..<source.endIndex) {
            // Le texte déjà accumulé doit précéder le morceau gras : sans ce
            // vidage, « Les traductions sont **repérées** » rendait
            // « repéréesLes traductions sont ».
            flushPlain()
            pieces.append(.bold(String(source[source.index(cursor, offsetBy: 2)..<closing.lowerBound])))
            cursor = closing.upperBound
            continue
        }
        if source[cursor] == "`",
           let closing = source.range(of: "`", range: source.index(after: cursor)..<source.endIndex) {
            flushPlain()
            pieces.append(.code(String(source[source.index(after: cursor)..<closing.lowerBound])))
            cursor = closing.upperBound
            continue
        }
        plain.append(source[cursor])
        cursor = source.index(after: cursor)
    }
    flushPlain()
    return pieces
}

/// Compose un `Text` dont chaque morceau porte déjà sa police.
///
/// La police est cuite dans le `Text` plutôt que posée par le conteneur :
/// appliquer `.font(...)` à un texte concaténé écrase les graisses et les
/// polices monospaces des morceaux, ce qui ferait disparaître le gras et le
/// code des notes d'honnêteté.
func mmRichText(_ source: String, baseSize: CGFloat = 11, codeSize: CGFloat? = nil) -> Text {
    let mono = codeSize ?? max(baseSize - 1, 8)
    return mmParseRichText(source).reduce(Text("")) { acc, piece in
        switch piece {
        case .plain(let value):
            return acc + Text(value).font(.system(size: baseSize))
        case .bold(let value):
            return acc + Text(value).font(.system(size: baseSize, weight: .semibold))
        case .code(let value):
            return acc + Text(value).font(.system(size: mono, design: .monospaced))
        }
    }
}

// ============================================================================
//  MARK: - Compatibilité des SF Symbols
// ============================================================================

/// Sondage des noms de SF Symbols, avec repli.
///
/// Un nom que le système ne connaît pas ne provoque aucune erreur :
/// `Image(systemName:)` rend simplement rien. Comme beaucoup de glyphes ont
/// été introduits après macOS 11 et que le compilateur ne le signale pas
/// (c'est une ressource, pas une API), l'interface risquerait d'afficher des
/// dizaines de cases vides sur Big Sur. Chaque nom est donc testé une fois
/// (`NSImage(systemSymbolName:)` renvoie `nil` quand le glyphe manque) et
/// remplacé par un symbole de la génération iOS 13 / macOS 11, toujours
/// présent. Le résultat est mémorisé, et l'appel ne se fait que sur le fil
/// principal (les `body` SwiftUI et le mode capture y tournent).
enum MMSymbol {

    /// Repli choisi d'après le premier segment du nom demandé ; chaque valeur
    /// de droite est un glyphe présent depuis macOS 11.
    private static let fallbacks: [String: String] = [
        "gauge": "speedometer",
        "bubbles": "sparkles",
        "puzzlepiece": "puzzlepiece",
        "doc": "doc",
        "character": "textformat",
        "calendar": "calendar",
        "exclamationmark": "exclamationmark.triangle",
        "arrow": "arrow.2.squarepath",
        "rectangle": "rectangle",
        "square": "square.grid.2x2",
        "circle": "circle",
        "circlebadge": "circle",
        "camera": "camera",
        "externaldrive": "internaldrive",
        "internaldrive": "internaldrive",
        "folder": "folder",
        "bell": "bell",
        "hand": "hand.raised",
        "text": "message",
        "list": "list.bullet",
        "ladybug": "ladybug",
        "flame": "flame",
        "macbook": "desktopcomputer",
        "checkmark": "checkmark",
        "trash": "trash",
        "sparkles": "sparkles",
        "chart": "chart.bar",
        "memorychip": "memorychip",
        "cpu": "cpu",
        "wrench": "wrench",
        "hammer": "hammer",
        "bolt": "bolt",
        "shield": "shield",
        // `shredder` n'apparaît qu'avec les jeux SF Symbols récents : sans cette
        // ligne, le bouton « Broyer » retombait sur le glyphe de dernier recours
        // (`circle`), c'est-à-dire un rond vide de sens. `trash.slash.fill` est du
        // premier jeu et dit la même chose : détruire, et non jeter.
        "shredder": "trash.slash.fill",
        "questionmark": "questionmark.circle",
        "info": "info.circle",
        "magnifyingglass": "magnifyingglass",
        "safari": "safari",
        "envelope": "mail",
        "person": "person",
        "network": "network",
        "clock": "clock",
        "timer": "clock",
        // `box` n'existe pas dans les jeux SF Symbols de macOS 13 (vérifié au
        // sondage) : cette ligne envoyait donc `shippingbox.and.arrow.backward.fill`
        // — absent de Big Sur — dans un repli lui-même absent, donc au rond de
        // dernier recours. `shippingbox` est du premier jeu et dit la même chose.
        "shippingbox": "shippingbox",
        "bandage": "cross.case",
        "lock": "lock",
        "eraser": "pencil",
        "hourglass": "hourglass",
        "pause": "pause",
        "play": "play"
    ]

    /// Nom demandé → nom réellement rendu.
    private static var resolved: [String: String] = [:]

    /// Noms tombés en repli sur cette machine (journal de capture).
    static private(set) var degraded: [String] = []

    /// Le nom à passer à `Image(systemName:)`.
    static func safe(_ name: String) -> String {
        if let known = resolved[name] { return known }
        let chosen = resolve(name)
        resolved[name] = chosen
        if chosen != name { degraded.append(name) }
        return chosen
    }

    /// Les symboles que le système courant ne sait pas dessiner.
    static var degradedNames: [String] { degraded }

    private static func resolve(_ name: String) -> String {
        if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil { return name }
        let head = name.split(separator: ".").first.map(String.init) ?? name
        if let mapped = fallbacks[head],
           NSImage(systemSymbolName: mapped, accessibilityDescription: nil) != nil {
            return mapped
        }
        // Un repli peut être pire que le nom qu'il remplace : `box` n'existe pas
        // alors que `shippingbox`, son tronc, existe. Avant de tomber sur un rond
        // vide de sens, le tronc tente donc sa chance.
        if head != name, NSImage(systemSymbolName: head, accessibilityDescription: nil) != nil {
            return head
        }
        // Dernier recours : un glyphe du tout premier jeu (macOS 10.15).
        return NSImage(systemSymbolName: "circle", accessibilityDescription: nil) != nil ? "circle" : name
    }
}

extension String {
    /// Nom de SF Symbol garanti dessiné par le système courant.
    var mmSafeSymbol: String { MMSymbol.safe(self) }
}

// ============================================================================
//  MARK: - Pastilles « Liquid Glass »
// ============================================================================

/// Pastille en verre liquide dessinée en vecteur.
///
/// Le fond est un vrai `NSVisualEffectView` — donc une vraie réfraction, qui
/// suit le mode Clair/Sombre — recouvert d'un dégradé d'accent, d'un reflet
/// spéculaire venu du haut et d'un double contour (miroité dedans, ombre fine
/// dehors). Aucune API macOS 12+, net à toutes les tailles, et teinté
/// automatiquement contrairement à des PNG importés.
struct MSGlassIcon: View {
    let symbol: String
    let accent: Color
    var size: CGFloat = 46
    var isOn: Bool = false

    var body: some View {
        let radius = size * 0.28
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack {
            GlassBackground(kind: .hero, cornerRadius: radius)
                .frame(width: size, height: size)
                .clipShape(shape)
            shape.fill(LinearGradient(
                colors: [accent.opacity(isOn ? 0.88 : 0.26),
                         accent.opacity(isOn ? 0.52 : 0.08)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.fill(LinearGradient(
                colors: [Color.white.opacity(isOn ? 0.30 : 0.20), Color.white.opacity(0.02)],
                startPoint: .top, endPoint: .center))
            Image(systemName: symbol.mmSafeSymbol)
                .font(.system(size: size * 0.40, weight: .semibold))
                .foregroundColor(isOn ? .white : accent)
            shape.strokeBorder(Color.white.opacity(0.45), lineWidth: 0.8)
            shape.strokeBorder(Color.black.opacity(0.12), lineWidth: 0.4)
        }
        .frame(width: size, height: size)
        .shadow(color: accent.opacity(isOn ? 0.42 : 0.18), radius: size * 0.16, y: size * 0.08)
    }
}

// ============================================================================
//  MARK: - Art de marque « Liquid Glass » (PNG embarqués)
// ============================================================================

/// Chargement des visuels de marque bitmap, avec relevé des absences.
///
/// Les tuiles viennent de `assets/icons/tuiles/`, copiées dans
/// `Contents/Resources/Icons/` par `build.sh` ; l'icône d'application vient de
/// `Contents/Resources/AppIcon.icns`. Les deux sont produits par
/// `tools/extract_icons.py` et `tools/make_app_icon.py` à partir des planches
/// « Liquid Glass » de `assets/icon-sheets/`.
///
/// Un PNG absent n'est pas une panne : `MMBrandIcon` retombe sur la pastille
/// vectorielle `MSGlassIcon`. Mais un repli silencieux ressemble à un rendu
/// normal, donc chaque nom raté est mémorisé et publié au journal de lancement
/// (`manquantes`), comme le font déjà les SF Symbols.
///
/// Le cache est verrouillé : le mode capture et les menus peuvent résoudre une
/// vue hors du fil principal, et un dictionnaire partagé sans verrou est un
/// plantage aléatoire, pas un détail de performance.
enum MMBrandArt {
    private static var cache: [String: NSImage?] = [:]
    private static var relevees: [String] = []
    private static let verrou = NSLock()

    /// Noms demandés et non trouvés dans le bundle, dans l'ordre de rencontre.
    static var manquantes: [String] {
        verrou.lock(); defer { verrou.unlock() }
        return relevees
    }

    static func image(_ nom: String) -> NSImage? {
        verrou.lock(); defer { verrou.unlock() }
        if let deja = cache[nom] { return deja }
        let chargee = charger(nom)
        cache[nom] = chargee
        if chargee == nil { relevees.append(nom) }
        return chargee
    }

    private static func charger(_ nom: String) -> NSImage? {
        let bundle = Bundle.main
        let candidats = [
            bundle.url(forResource: nom, withExtension: "png", subdirectory: "Icons"),
            bundle.url(forResource: nom, withExtension: "png"),
            bundle.url(forResource: nom, withExtension: "icns"),
        ]
        for cas in candidats {
            guard let url = cas, let image = NSImage(contentsOf: url),
                  image.size.width > 0 else { continue }
            return image
        }
        return nil
    }
}

/// Pastille de marque dessinée par un PNG des planches, avec repli vectoriel.
///
/// Réservé aux **visuels de marque** — logo d'en-tête, pastilles des quatre
/// espaces, badge « À propos ». Les icônes fonctionnelles (boutons, lignes de
/// résultat, menus) restent des SF Symbols : un PNG ne se teint pas et ne suit
/// pas le mode Clair/Sombre, alors que la tuile, elle, est auto-suffisante
/// (verre sombre + liseré) et rend donc pareil dans les deux thèmes.
struct MMBrandIcon: View {
    /// Nom du fichier embarqué, sans extension (« purge », « AppIcon »…).
    let tile: String
    let accent: Color
    var size: CGFloat = 46
    /// Glyphe de dernier recours si la tuile n'est pas dans le bundle.
    var fallbackSymbol: String = "circle"
    var isOn: Bool = false

    var body: some View {
        Group {
            if let art = MMBrandArt.image(tile) {
                Image(nsImage: art)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    // La tuile est déjà un carré arrondi : cette coupe ne fait
                    // que garantir le rayon d'affichage quelle que soit la
                    // ressource (l'icône .icns, par exemple, n'a pas la même
                    // proportion de marge).
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.235, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
                            .strokeBorder(accent.opacity(isOn ? 0.95 : 0.0), lineWidth: 1.6)
                    )
                    .shadow(color: accent.opacity(isOn ? 0.45 : 0.20),
                            radius: size * 0.16, y: size * 0.08)
                    .accessibility(hidden: true)
            } else {
                MSGlassIcon(symbol: fallbackSymbol, accent: accent, size: size, isOn: isOn)
            }
        }
        .frame(width: size, height: size)
    }
}

// ============================================================================
//  MARK: - Cartes
// ============================================================================

/// Conteneur arrondi en matériau translucide, bordure discrète.
struct Card<Content: View>: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .mmGlass(cornerRadius: 18, kind: .card)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.04))
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.mmSeparator.opacity(0.6), lineWidth: 1)
            )
    }
}

/// Carte avec en-tête (icône, titre, sous-titre), actions à droite et corps.
struct SectionCard<Trailing: View, Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    var trailing: Trailing
    var content: Content

    init(title: String, subtitle: String, systemImage: String, accent: Color,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() },
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accent = accent
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.gradient(accent))
                            .frame(width: 34, height: 34)
                        Image(systemName: (systemImage).mmSafeSymbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 14, weight: .bold))
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(Color.mmSecondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    trailing
                }
                content
            }
        }
    }
}

// ============================================================================
//  MARK: - Petits éléments
// ============================================================================

/// Pilule informative (icône + texte, fond discret).
struct Pill: View {
    let text: String
    var systemImage: String? = nil
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage = systemImage {
                Image(systemName: (systemImage).mmSafeSymbol)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.13)))
        .foregroundColor(color)
    }
}

/// Pastille statistique (valeur + libellé) alignée en ligne.
struct StatChip: View {
    let value: String
    let label: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Color.mmSecondaryLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Groupe d'avertissements : ce que l'application n'a *pas* pu faire, et pourquoi.
struct HonestyNotes: View {
    let notes: [String]
    var color: Color = .orange

    var body: some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(notes, id: \.self) { note in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: ("exclamationmark.triangle.fill").mmSafeSymbol)
                            .font(.system(size: 10))
                            .foregroundColor(color)
                        // Les notes écrivent certains mots en `**gras**` : sans cette
                        // étape, SwiftUI afficherait les astérisques telles quelles.
                        mmRichText(note, baseSize: 11, codeSize: 10)
                            .foregroundColor(Color.mmSecondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(0.09))
            )
        }
    }
}

/// Ligne d'état (progression, message vide) centrée et discrète.
struct StatusLine: View {
    let text: String
    var busy: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if busy {
                ProgressView().controlSize(.small)
            }
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(Color.mmSecondaryLabel)
            Spacer()
        }
    }
}

// ============================================================================
//  MARK: - Sélecteur de mode de suppression
// ============================================================================

/// Choix « Corbeille (réversible) / Effacement direct ».
struct ModeSelector: View {
    @Binding var mode: DeletionMode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Mode de suppression")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.mmSecondaryLabel)
            Picker("", selection: $mode) {
                ForEach(DeletionMode.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
            .help("Comment les éléments cochés seront traités. « Corbeille » passe par `FileManager.trashItem` : réversible, mais l'espace n'est rendu qu'au vidage. « Effacement direct » supprime sur le champ, sans filet.")
            Text(mode.freesImmediately
                 ? "Effacement immédiat : non réversible, l'espace est rendu tout de suite."
                 : "Fichier déplacé vers la corbeille : réversible, l'espace n'est libéré qu'après vidage.")
                .font(.system(size: 10))
                .foregroundColor(mode.freesImmediately ? Color.orange : Color.secondary)
        }
    }
}

// ============================================================================
//  MARK: - Ligne d'élément (fichier, dossier, groupe)
// ============================================================================

/// Une coche, un nom, un chemin, une taille et le commentaire du moteur.
struct RecordRow: View {
    let record: FileRecord
    @Binding var isSelected: Bool
    var membersHidden: Int = 0

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Toggle(isOn: $isSelected) { EmptyView() }
                .toggleStyle(.checkbox)
                .help(record.deletable
                      ? "Inclure cet élément à l'opération"
                      : "Élément protégé : la suppression est refusée")

            Image(systemName: (record.isDirectory ? "folder.fill" : docIcon).mmSafeSymbol)
                .font(.system(size: 12))
                .foregroundColor(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(record.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    if record.risk != .safe {
                        Pill(text: record.risk.label, color: Theme.color(for: record.risk))
                    }
                    if !record.deletable {
                        Pill(text: "protégé", systemImage: "lock.fill", color: .red)
                    }
                }
                Text(record.displayPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color.mmTertiaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let note = record.note {
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundColor(Color.mmSecondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if membersHidden > 0 {
                    Text("\(membersHidden) élément(s) réel(s) derrière cette ligne · "
                         + "modifié \(Fmt.age(record.modified))")
                        .font(.system(size: 10))
                        .foregroundColor(Color.mmTertiaryLabel)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.size(record.size))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                if record.modified != nil {
                    Text(Fmt.date(record.modified))
                        .font(.system(size: 9))
                        .foregroundColor(Color.mmTertiaryLabel)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.07) : Color.clear)
        )
    }

    /// Symbole adapté à l'extension du fichier.
    private var docIcon: String {
        switch record.url.pathExtension.lowercased() {
        case "app": return "app.dashed"
        case "dmg", "pkg", "iso": return "opticaldiscdrive"
        case "mp4", "mov", "m4v": return "film"
        case "zip", "tar", "gz": return "doc.zipper"
        case "png", "jpg", "jpeg", "tiff", "heic": return "photo"
        case "pdf": return "doc.richtext"
        default: return "doc"
        }
    }
}

// ============================================================================
//  MARK: - Rapport d'opération
// ============================================================================

/// Restitue fidèlement un `DeletionReport` : supprimés, échecs, blocages.
struct ReportCard: View {
    let report: DeletionReport
    let mode: DeletionMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: (report.clean ? "checkmark.seal.fill" : "exclamationmark.triangle.fill").mmSafeSymbol)
                    .foregroundColor(report.clean ? .green : .orange)
                Text(report.summary)
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Pill(text: mode.rawValue, systemImage: mode.freesImmediately ? "bolt" : "trash")
            }
            if !mode.freesImmediately && report.freedBytes > 0 {
                Text("Rappel : en mode corbeille, ces octets ne sont rendus qu'après vidage de la corbeille.")
                    .font(.system(size: 10))
                    .foregroundColor(Color.mmSecondaryLabel)
            }
            if !report.failures.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Échecs réels (\(report.failures.count))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.red)
                    ForEach(report.failures.prefix(4), id: \.path) { failure in
                        Text("• \(Fmt.prettyPath(failure.path)) — \(failure.message)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color.mmSecondaryLabel)
                            .lineLimit(2)
                    }
                }
            }
            if !report.blocked.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Refusés par la politique de sécurité (\(report.blocked.count))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.orange)
                    ForEach(report.blocked.prefix(4), id: \.path) { blocked in
                        Text("• \(Fmt.prettyPath(blocked.path)) — \(blocked.reason)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color.mmSecondaryLabel)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.gray.opacity(0.08))
        )
    }
}

// ============================================================================
//  MARK: - Boutons d'action
// ============================================================================

/// Bouton compact de barre d'outils (icône + libellé).
struct ToolButton: View {
    let title: String
    let systemImage: String
    var color: Color = .accentColor
    var busy: Bool = false
    var disabled: Bool = false
    /// Bulle d'aide : ce que le bouton fait réellement, et ce qu'il ne fait pas.
    ///
    /// Toutes les commandes de l'application en portent une ; un libellé court
    /// (« Broyer », « Quarantaine ») laisse supposer une action plus large que
    /// celle qui est exécutée.
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: (systemImage).mmSafeSymbol).font(.system(size: 10, weight: .bold))
                }
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(color.opacity(disabled ? 0.08 : 0.16)))
            .foregroundColor(disabled ? Color.secondary : color)
        }
        .buttonStyle(.plain)
        .disabled(disabled || busy)
        .mmHelp(help)
    }
}

// ============================================================================
//  MARK: - Captures d'écran embarquées
// ============================================================================

/// Affiche une capture d'écran réelle du projet, si elle est embarquée.
///
/// Les PNG proviennent de `docs/screenshots/` et sont copiés dans le bundle
/// par `build.sh`. Sans eux, le composant n'invente rien : il explique
/// précisément comment les produire (`./build.sh --shots`).
struct AppScreenshot: View {
    let name: String
    let caption: String
    var maxHeight: CGFloat = 250

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let image = Self.image(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: maxHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            } else {
                HStack(spacing: 8) {
                    Image(systemName: ("camera.metering.center.weighted").mmSafeSymbol)
                        .foregroundColor(Color.mmSecondaryLabel)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Capture « \(name).png » non embarquée dans cette version.")
                            .font(.system(size: 11, weight: .semibold))
                        Text("À produire avec : ./build.sh --shots (l'application réelle génère ses propres captures).")
                            .font(.system(size: 10))
                            .foregroundColor(Color.mmSecondaryLabel)
                    }
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.gray.opacity(0.08))
                )
            }
            Text(caption)
                .font(.system(size: 10))
                .foregroundColor(Color.mmSecondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Charge le PNG depuis le bundle, puis depuis le dépôt si l'app tourne sans bundle.
    static func image(named name: String) -> NSImage? {
        let candidates = [
            Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Screenshots"),
            Bundle.main.url(forResource: name, withExtension: "png"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("docs/screenshots/\(name).png"),
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Documents/MonitorMyMac/docs/screenshots/\(name).png")
        ]
        for url in candidates where url != nil {
            if let image = NSImage(contentsOf: url!) { return image }
        }
        return nil
    }

    /// Liste des captures réellement disponibles (utilisée par l'Aide).
    static func availableNames() -> [String] {
        let known = ["01-surveillance", "02-purge", "03-performance", "04-applications",
                     "05-securite", "06-aide", "07-faq", "08-apropos"]
        return known.filter { image(named: $0) != nil }
    }
}
