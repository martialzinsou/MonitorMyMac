// ============================================================================
//  MonitorMyMac — onglet Applications (désinstallation, mises à jour, extensions)
//  Auteur : Martial Zinsou
//  ============================================================================
//
//  Trois familles demandées :
//    • désinstallation complète : bundle + préférences + caches + résidus
//      réels de ~/Library, avec autorisation explicite du bundle ;
//    • mise à jour centralisée : `softwareupdate --list` (sortie brute
//      conservée), `brew outdated` si Homebrew existe, App Store et canaux
//      non vérifiables listés à part ;
//    • extensions : greffons et widgets via `pluginkit`, extensions de
//      navigateurs lues dans leurs profils réels.
// ============================================================================

import SwiftUI

/// Onglet « Applications ».
struct AppsView: View {
    @ObservedObject private var model = AppsModel.shared

    var body: some View {
        VStack(spacing: 16) {
            AppsInventoryCard()
            AppsResidualsCard()
            AppsUninstallCard()
            AppsUpdatesCard()
            AppsExtensionsCard()
        }
        .onAppear {
            if model.apps.isEmpty && !model.isBusy { model.scanApps() }
        }
    }
}

// ============================================================================
//  Inventaire
// ============================================================================

/// Liste triée par taille, avec filtre texte et sélection de désinstallation.
struct AppsInventoryCard: View {
    @ObservedObject private var model = AppsModel.shared

    var body: some View {
        SectionCard(title: "Applications installées",
                    subtitle: model.message,
                    systemImage: "square.grid.2x2.fill",
                    accent: .blue,
                    trailing: {
                        HStack(spacing: 6) {
                            Pill(text: "\(model.apps.count) apps", color: .blue)
                            Pill(text: Fmt.size(model.totalAppBytes), systemImage: "internaldrive", color: .gray)
                            ToolButton(title: model.isBusy ? "Balayage…" : "Réinventorier",
                                       systemImage: "arrow.clockwise", color: .blue,
                                       busy: model.isBusy,
                                       help: "Relit /Applications, ~/Applications et les volumes montés via `NSRunningApplication` et `FileManager` : taille réelle du bundle, dernière ouverture, éditeur.") {
                                model.scanApps()
                            }
                        }
                    }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: ("magnifyingglass").mmSafeSymbol)
                        .font(.system(size: 11))
                        .foregroundColor(Color.mmTertiaryLabel)
                    TextField("Filtrer par nom (« Safari », « Adobe »…)", text: $model.filter)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)))

                if model.visibleApps.isEmpty {
                    Text(model.apps.isEmpty
                         ? "Inventaire en cours — l'analyse des bundles peut prendre une minute."
                         : "Aucune application ne correspond à « \(model.filter) ».")
                        .font(.system(size: 11))
                        .foregroundColor(Color.mmSecondaryLabel)
                }
                ForEach(model.visibleApps.prefix(14)) { app in
                    AppsAppRow(app: app)
                }
                if model.visibleApps.count > 14 {
                    Text("… \(model.visibleApps.count - 14) autre(s) dans le tri par taille. Affinez le filtre pour les voir.")
                        .font(.system(size: 10))
                        .foregroundColor(Color.mmTertiaryLabel)
                }
                HonestyNotes(notes: [
                    "Les applications d'/System/Applications (Safari, Mail, Photos…) sont listées en lecture seule : elles font partie de macOS et sont protégées par la SSV.",
                    "Un bundle du Mac App Store peut être désinstallé, mais sa réinstallation passe par l'App Store avec votre identifiant Apple."
                ], color: .blue)
            }
        }
    }
}

/// Une ligne d'application : coche, identité, actions.
struct AppsAppRow: View {
    let app: ManagedApp
    @ObservedObject private var model = AppsModel.shared

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            if app.isSystemLocation {
                Image(systemName: ("lock.rectangle").mmSafeSymbol)
                    .font(.system(size: 13))
                    .foregroundColor(Color.mmTertiaryLabel)
                    .frame(width: 18)
                    .help("Application système : désinstallation refusée par la politique de sécurité")
            } else {
                Toggle(isOn: Binding(get: { model.uninstallSelection.contains(app.id) },
                                     set: { _ in model.toggleUninstall(app) })) {
                    EmptyView()
                }
                .toggleStyle(.checkbox)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    if app.isRunning {
                        Pill(text: "en cours", systemImage: "circle.fill", color: .green)
                    }
                    if app.fromAppStore {
                        Pill(text: "App Store", color: .blue)
                    }
                    if !app.codeSigned {
                        Pill(text: "non signé", systemImage: "exclamationmark.shield", color: .red)
                    }
                    if app.isSystemLocation {
                        Pill(text: "macOS", systemImage: "lock.fill", color: .gray)
                    }
                }
                Text(app.detail)
                    .font(.system(size: 10))
                    .foregroundColor(Color.mmTertiaryLabel)
                    .lineLimit(1)
                Text(Fmt.prettyPath(app.bundlePath))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color.mmTertiaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            HStack(spacing: 5) {
                ToolButton(title: "Résidus", systemImage: "doc.viewfinder", color: .purple,
                           help: "Liste les préférences, caches, sauvegardes d'état et greffons qui portent l'identifiant de l'application. Lecture seule : rien n'est supprimé par ce bouton.") {
                    model.inspect(app)
                }
                ToolButton(title: "Finder", systemImage: "folder", color: .gray,
                           help: "Ouvre le Finder sur l'emplacement du bundle, sans rien sélectionner d'autre ni modifier.") {
                    model.revealInFinder(app)
                }
                if !app.isSystemLocation {
                    ToolButton(title: "Quarantaine", systemImage: "shippingbox.and.arrow.backward.fill",
                               color: .orange, busy: false, disabled: model.isBusy) {
                        model.quarantine(app)
                    }
                    .help("Déplace le bundle dans la quarantaine de MonitorMyMac : réversible, sans suppression.")
                }
            }
        }
        .padding(.vertical, 3)
    }
}

// ============================================================================
//  Résidus
// ============================================================================

/// Éléments cachés trouvés pour l'application examinée.
struct AppsResidualsCard: View {
    @ObservedObject private var model = AppsModel.shared

    var body: some View {
        SectionCard(title: model.inspectedApp.map { "Résidus de « \($0.name) »" } ?? "Résidus d'une application",
                    subtitle: model.inspectedApp == nil
                        ? "Choisissez « Résidus » sur une application pour lister ses préférences, caches, sauvegardes et extensions."
                        : "Ces fichiers restent sur le disque après la suppression du bundle : ce sont eux qu'une désinstallation « complète » doit traiter.",
                    systemImage: "doc.badge.gearshape",
                    accent: .purple,
                    trailing: {
                        if model.inspectedApp != nil {
                            ToolButton(title: "Supprimer les résidus cochés", systemImage: "trash",
                                       color: .red, busy: model.isBusy,
                                       help: "Traite uniquement les résidus cochés de l'application examinée, selon le mode choisi (corbeille par défaut). Le bundle de l'application n'est pas touché par ce bouton.") {
                                model.deleteSelectedResiduals()
                            }
                        }
                    }) {
            VStack(alignment: .leading, spacing: 6) {
                if model.inspectedApp == nil {
                    Text("Aucune application examinée.")
                        .font(.system(size: 11))
                        .foregroundColor(Color.mmSecondaryLabel)
                } else if model.residuals.isEmpty {
                    Text("Aucun résidu trouvé dans les emplacements standards (Application Support, Caches, Preferences, Saved Application State, Logs, HTTPStorages, WebKit, Group Containers, Containers, LaunchAgents).")
                        .font(.system(size: 11))
                        .foregroundColor(Color.mmSecondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(model.residuals) { record in
                        RecordRow(record: record,
                                  isSelected: Binding(get: { model.residualSelection.contains(record.id) },
                                                      set: { _ in
                            if model.residualSelection.contains(record.id) {
                                model.residualSelection.remove(record.id)
                            } else {
                                model.residualSelection.insert(record.id)
                            }
                        }))
                    }
                    HonestyNotes(notes: [
                        "Les conteneurs Sandbox (`~/Library/Containers/<id>`) sont montrés mais cochés seulement s'ils portent l'identifiant exact de l'app : un conteneur partagé ne doit jamais disparaître avec une seule application.",
                        "« Application Support » d'un éditeur commun (Google, Microsoft…) n'est supprimé que si le chemin correspond au bundle de l'app, jamais au dossier parent."
                    ], color: .blue)
                }
            }
        }
    }
}

// ============================================================================
//  Désinstallation
// ============================================================================

/// Barre d'action de désinstallation complète.
struct AppsUninstallCard: View {
    @ObservedObject private var model = AppsModel.shared

    var body: some View {
        SectionCard(title: "Désinstallation complète",
                    subtitle: "Ferme l'application, retire le bundle et, si vous le demandez, les résidus utilisateur repérés.",
                    systemImage: "xmark.bin.fill",
                    accent: .red) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $model.includeResiduals) {
                    Text("Inclure les résidus utilisateur (préférences, caches, sauvegardes)")
                        .font(.system(size: 11, weight: .medium))
                }
                .toggleStyle(.checkbox)

                ModeSelector(mode: $model.mode)

                HStack(spacing: 10) {
                    Button {
                        model.uninstallSelected()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: ("xmark.bin.fill").mmSafeSymbol)
                            Text(model.uninstallSelection.isEmpty
                                 ? "Aucune application cochée"
                                 : "Désinstaller \(model.uninstallSelection.count) app(s) · \(Fmt.size(model.uninstallFootprint))")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Theme.gradient(model.uninstallSelection.isEmpty ? Color.gray : .red))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.uninstallSelection.isEmpty || model.isBusy)
                    .help("Ferme proprement chaque application sélectionnée, puis déplace son bundle selon le mode choisi (corbeille par défaut). Avec l'option cochée, les résidus portant le même identifiant suivent. Un bundle de /Applications n'est autorisé à la suppression que pendant cette fenêtre, puis l'autorisation est retirée.")
                    Spacer()
                }
                HonestyNotes(notes: [
                    "Un bundle n'est autorisé à la suppression que pendant la fenêtre de désinstallation (`PathPolicy.approveUninstall`), puis l'autorisation est retirée : aucun autre chemin ne bénéficie de cette ouverture.",
                    "Une application ouverte par Launchpad avec SIP actif, ou installée par un pkg système dans /Library/Application Support, peut refuser la suppression : le rapport affiche alors l'erreur réelle de macOS."
                ])
                StatusLine(text: model.message, busy: model.isBusy)
            }
        }
    }
}

// ============================================================================
//  Mises à jour
// ============================================================================

/// Audit des canaux de mise à jour réellement interrogeables.
struct AppsUpdatesCard: View {
    @ObservedObject private var model = AppsModel.shared

    var body: some View {
        SectionCard(title: "Mises à jour logicielles",
                    subtitle: "Ce que la machine accepte réellement d'être interrogé hors connexion App Store.",
                    systemImage: "arrow.triangle.2.circlepath",
                    accent: .green,
                    trailing: {
                        ToolButton(title: model.isBusy ? "Contrôle…" : "Contrôler",
                                   systemImage: "play.circle", color: .green,
                                   busy: model.isBusy,
                                   help: "`softwareupdate --list` pour le système, `brew outdated` si Homebrew est installé, et comparaison des versions pour le reste. L'application télécharge et installe rigoureusement rien.") {
                            model.auditUpdates()
                        }
                    }) {
            VStack(alignment: .leading, spacing: 10) {
                updateGroup("Apple (`softwareupdate --list`)", items: model.updates.apple.map { "\($0.label) — \($0.title)" },
                            empty: "Aucune mise à jour Apple proposée (`softwareupdate --format` n'existe pas sur macOS 13 : la sortie brute est conservée ci-dessous).")
                updateGroup("Homebrew (`brew outdated`)",
                            items: model.updates.brew.map { "\($0.label) — \($0.title)" },
                            empty: model.updates.brewMissing
                                ? "Homebrew n'est pas installé sur cette machine (`/opt/homebrew` et `/usr/local` testés)."
                                : "Homebrew ne signale rien : formule à jour.")
                if !model.updates.appStoreApps.isEmpty {
                    updateGroup("Mac App Store — mise à jour par l'App Store uniquement",
                                items: model.updates.appStoreApps,
                                empty: "")
                }
                if !model.updates.manualReview.isEmpty {
                    updateGroup("Canaux non vérifiables hors application (à contrôler vous-même)",
                                items: model.updates.manualReview.prefix(40).map { $0 },
                                empty: "")
                }

                if !model.updates.appleRaw.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("Sortie brute de `softwareupdate --list`")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color.mmSecondaryLabel)
                            Spacer()
                            CopyButton(text: model.updates.appleRaw)
                        }
                        ScrollView {
                            Text(model.updates.appleRaw)
                                .font(.system(size: 10, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .mmTextSelection()
                                .padding(10)
                        }
                        .frame(maxHeight: 140)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.06)))
                    }
                }
                HonestyNotes(notes: [
                    "MonitorMyMac ne télécharge et n'installe rien : installer une mise à jour Apple exige `softwareupdate --install` avec droits administrateur, et l'App Store impose son propre flux authentifié.",
                    "Le contrôle Apple peut demander quelques dizaines de secondes (le démon contacte le serveur de mise à jour)."
                ], color: .blue)
            }
        }
    }

    /// Groupe « titre + lignes » réutilisé pour chaque canal.
    private func updateGroup(_ title: String, items: [String], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if items.isEmpty {
                if !empty.isEmpty {
                    Text(empty)
                        .font(.system(size: 10))
                        .foregroundColor(Color.mmSecondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                    Pill(text: "\(items.count)", color: .green)
                }
                ForEach(items.prefix(12), id: \.self) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: ("arrow.up.circle.fill").mmSafeSymbol)
                            .font(.system(size: 9))
                            .foregroundColor(.green)
                        Text(item)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color.mmSecondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if items.count > 12 {
                    Text("+ \(items.count - 12) autre(s)")
                        .font(.system(size: 10))
                        .foregroundColor(Color.mmTertiaryLabel)
                }
            }
        }
    }
}

// ============================================================================
//  Extensions
// ============================================================================

/// Extensions regroupées par navigateur (structure : `ForEach` a besoin d'une
/// identité, ce qu'un tuple ne fournit pas).
struct BrowserGroup: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let items: [BrowserExtension]
}

/// Greffons et widgets macOS (`pluginkit`) + extensions de navigateurs.
struct AppsExtensionsCard: View {
    @ObservedObject private var model = AppsModel.shared

    /// Extensions de navigateur regroupées par navigateur.
    private var browsers: [BrowserGroup] {
        var buckets: [String: [BrowserExtension]] = [:]
        for entry in model.visibleBrowserExtensions {
            buckets[entry.browser, default: []].append(entry)
        }
        return buckets
            .map { BrowserGroup(name: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        SectionCard(title: "Extensions, greffons et widgets",
                    subtitle: model.plugins.isEmpty
                        ? "Lecture de `pluginkit -m -A -v` et des profils de navigateurs."
                        : "\(model.plugins.count) greffons macOS · \(model.widgetCount) widget(s) · \(model.browserExtensions.count) extension(s) de navigateurs.",
                    systemImage: "puzzlepiece.extension.fill",
                    accent: .mmIndigo,
                    trailing: {
                        ToolButton(title: model.isBusy ? "Lecture…" : "Relever",
                                   systemImage: "arrow.2.squarepath", color: .mmIndigo,
                                   busy: model.isBusy,
                                   help: "`pluginkit -m -A -v`, `systemextensionsctl list` et la lecture des manifestes `extensions.json` / `manifest.json` des navigateurs. Aucun fichier n'est modifié par ce relevé.") {
                            model.scanExtensions()
                        }
                    }) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Greffons et widgets système")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.mmSecondaryLabel)
                if model.visiblePlugins.isEmpty {
                    Text("Aucun greffon relevé — lancez « Relever ».")
                        .font(.system(size: 11))
                        .foregroundColor(Color.mmSecondaryLabel)
                }
                ForEach(model.visiblePlugins.prefix(10)) { plugin in
                    HStack(spacing: 8) {
                        Image(systemName: (plugin.isWidget ? "rectangle.on.rectangle.angled" : "puzzlepiece.extension").mmSafeSymbol)
                            .font(.system(size: 11))
                            .foregroundColor(plugin.state == .enabled ? .green : .secondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(plugin.host)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Text(plugin.detail)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(Color.mmTertiaryLabel)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        ToolButton(title: plugin.state == .enabled ? "Désactiver" : "Activer",
                                   systemImage: plugin.state == .enabled ? "slash.circle" : "checkmark.circle",
                                   color: plugin.state == .enabled ? .orange : .green,
                                   busy: false, disabled: model.isBusy,
                                   help: "`pluginkit -e use|ignore -i <identifiant>` : le greffon reste sur le disque, macOS cesse seulement de le proposer. L'état affiché est relu après l'action.") {
                            model.setPlugin(plugin, on: plugin.state != .enabled)
                        }
                        ToolButton(title: "Invalider", systemImage: "arrow.counterclockwise",
                                   color: .gray, busy: false, disabled: model.isBusy) {
                            model.invalidate(plugin)
                        }
                        .help("`pluginkit -e invalidate` : retire le greffon de l'enregistrement. Réversible en relançant l'application hôte.")
                    }
                    .padding(.vertical, 2)
                }
                if model.visiblePlugins.count > 10 {
                    Text("Filtre « \(model.filter) » : \(model.visiblePlugins.count) greffon(s) correspondant, 10 affichés.")
                        .font(.system(size: 10))
                        .foregroundColor(Color.mmTertiaryLabel)
                }

                Divider()

                Text("Extensions de navigateurs")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.mmSecondaryLabel)
                ForEach(browsers) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(group.name)
                                .font(.system(size: 11, weight: .semibold))
                            Pill(text: "\(group.items.count)", color: .mmIndigo)
                            Spacer()
                            ToolButton(title: "Page de gestion", systemImage: "safari", color: .blue,
                                       help: "Ouvre l'éditeur d'extensions du navigateur (`chrome://extensions`, `about:addons`…). C'est la voie officielle : une extension retirée à la main depuis le navigateur garde son dossier, et inversement.") {
                                model.openManagement(for: group.name)
                            }
                            ToolButton(title: "Retirer la liste", systemImage: "xmark.bin", color: .red,
                                       busy: false,
                                       disabled: model.isBusy || group.items.contains { $0.browserRunning },
                                       help: "Déplace le dossier de l'extension selon le mode choisi (corbeille par défaut). Un navigateur ouvert bloque l'action : ses fichiers sont verrouillés et seraient laissés à l'état de tiers.") {
                                model.uninstallBrowserExtensions(group.items)
                            }
                        }
                        ForEach(group.items.prefix(8)) { entry in
                            HStack(spacing: 7) {
                                Image(systemName: (entry.browserRunning ? "play.circle" : "shippingbox").mmSafeSymbol)
                                    .font(.system(size: 9))
                                    .foregroundColor(entry.browserRunning ? Color.orange : Color.secondary)
                                Text(entry.name)
                                    .font(.system(size: 10, weight: .medium))
                                Spacer()
                                Text("v\(entry.version)")
                                    .font(.system(size: 9))
                                    .foregroundColor(Color.mmTertiaryLabel)
                            }
                            .padding(.leading, 4)
                        }
                        if group.items.count > 8 {
                            Text("+ \(group.items.count - 8) autre(s)")
                                .font(.system(size: 9))
                                .foregroundColor(Color.mmTertiaryLabel)
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.07)))
                }
                HonestyNotes(notes: [
                    "« Retirer la liste » supprime le dossier de l'extension sur le disque : le navigateur doit être fermé, sinon l'action est refusée et le bouton reste grisé.",
                    "Safari refuse la lecture de ses extensions par une app tierce (protection TCC) : seules les extensions Chrome, Firefox, Edge, Brave, Arc, Opera et Vivaldi sont énumérées.",
                    "Activer/désactiver un greffon via `pluginkit -e use|ignore` prend effet au prochain lancement de l'hôte ; macOS peut rétablir l'état « par défaut »."
                ], color: .blue)
                StatusLine(text: model.message, busy: model.isBusy)
            }
        }
    }
}
