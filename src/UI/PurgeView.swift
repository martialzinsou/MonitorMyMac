// ============================================================================
//  MonitorMyMac — onglet Purge (nettoyage du stockage)
//  Auteur : Martial Zinsou
//  ============================================================================
//
//  Quatre familles demandées, toutes traitées ici :
//    • fichiers système inutiles (caches, logs, restes de mises à jour,
//      traductions de langues inutilisées) ;
//    • fichiers volumineux et anciens ;
//    • doublons (empreinte SHA-256) ;
//    • corbeilles centralisées (Finder, volumes, applications, Mail).
//
//  Le principe reste le même partout : **balayer, examiner, choisir, agir**.
//  Rien n'est supprimé sans case cochée, et la corbeille est le mode par défaut.
// ============================================================================

import SwiftUI

/// Onglet « Purge ».
struct PurgeView: View {
    @ObservedObject private var model = PurgeModel.shared
    @ObservedObject private var monitor = SystemMonitor.shared

    /// Sections dépliées (affichage complet des listes).
    @State private var expanded: Set<String> = []
    /// Réglages fins visibles ou cachés.
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 16) {
            headline
            if showSettings { settingsCard }
            ForEach(model.sections) { section in
                PurgeSectionCard(section: section, expanded: $expanded)
            }
            if model.sections.isEmpty && !model.isScanning {
                emptyCard
            }
            actionCard
            // Le rappel hebdomadaire, hérité de la première version, vit ici :
            // c'est dans cet onglet que le nettoyage se pilote.
            ReminderCard(monitor: monitor)
        }
        .onAppear {
            // Le premier affichage déclenche un balayage, comme l'onglet Surveillance.
            if model.sections.isEmpty && !model.isScanning && !model.isActing {
                model.scan()
            }
        }
    }

    // -------------------------------------------------------------------------
    //  En-tête : ce qui est récupérable, progression
    // -------------------------------------------------------------------------

    private var headline: some View {
        SectionCard(title: "Balayage du stockage",
                    subtitle: "Caches, journaux et diagnostics, restes de mises à jour, gros fichiers anciens, doublons, corbeilles et traductions inutilisées.",
                    systemImage: "bubbles.and.sparkles.fill",
                    accent: .pink,
                    trailing: {
                        HStack(spacing: 8) {
                            ToolButton(title: "Réglages", systemImage: "slider.horizontal.3",
                                       color: .gray, disabled: model.isActing,
                                       help: "Seuils de l'analyse : âge et taille à partir desquels un fichier est signalé, familles à balayer, dossiers supplémentaires. Modifier ces valeurs ne supprime rien.") {
                                withAnimation(.easeInOut(duration: 0.2)) { showSettings.toggle() }
                            }
                            ToolButton(title: model.isScanning ? "Balayage…" : "Balayer",
                                       systemImage: "magnifyingglass", color: .pink,
                                       busy: model.isScanning, disabled: model.isActing,
                                       help: "Lit réellement le disque pour les sept familles (caches, logs, restes de mise à jour, traductions, volumineux/anciens, doublons SHA-256, corbeilles) et affiche les tailles allouées mesurées. Aucune suppression : c'est la coche, puis le bouton « Supprimer », qui agissent.") {
                                model.scan()
                            }
                        }
                    }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    StatChip(value: Fmt.size(model.selectedBytes),
                             label: "sélectionné (\(model.selectedCount) élém.)",
                             color: .pink)
                    StatChip(value: Fmt.size(model.sections.reduce(0) { $0 + $1.totalBytes }),
                             label: "signalé au total", color: .purple)
                    StatChip(value: Fmt.size(model.sessionFreed),
                             label: "libéré pendant la session", color: .green)
                }
                StatusLine(text: model.progress + (model.sections.isEmpty ? "" : " · \(model.lastScanSummary)"),
                           busy: model.isScanning)
                if model.isScanning {
                    ProgressView().progressViewStyle(LinearProgressViewStyle(tint: .pink))
                }
                HonestyNotes(notes: [
                    "Les traductions de langues sont **repérées mais jamais supprimées** par l'app : retirer un .lproj casse la signature du code et Gatekeeper refuse alors l'application."
                ], color: .blue)
            }
        }
    }

    // -------------------------------------------------------------------------
    //  Réglages
    // -------------------------------------------------------------------------

    private var settingsCard: some View {
        SectionCard(title: "Seuils d'analyse",
                    subtitle: "Plus les seuils sont bas, plus le balayage est long et propose d'éléments.",
                    systemImage: "slider.horizontal.3", accent: .gray) {
            VStack(alignment: .leading, spacing: 12) {
                threshold("Âge des caches", value: $model.settings.cacheAgeDays,
                          range: 0...60, unit: "jours",
                          help: "Un cache plus récent que ce seuil est considéré comme « chaud » et ignoré.")
                threshold("Âge des journaux système", value: $model.settings.junkAgeDays,
                          range: 0...90, unit: "jours",
                          help: "Diagnostiques, logs et .savedState plus anciens que ce seuil.")
                threshold("Taille d'un gros fichier", value: $model.settings.largeMinSizeMB,
                          range: 10...2000, unit: "Mo",
                          help: "Seuil de taille de la chasse aux fichiers volumineux.")
                threshold("Ancienneté d'un gros fichier", value: $model.settings.largeMinAgeDays,
                          range: 7...720, unit: "jours",
                          help: "Un fichier volumineux récemment modifié est normalement encore utile.")
                threshold("Taille minimale des doublons", value: $model.settings.duplicateMinSizeMB,
                          range: 1...500, unit: "Mo",
                          help: "En dessous, le coût de hachage ne se justifie pas.")

                Divider()

                HStack {
                    Text("Dossiers personnels ajoutés")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    ToolButton(title: "Ajouter…", systemImage: "folder.badge.plus", color: .blue,
                               help: "Étend l'analyse des fichiers volumineux et anciens à un dossier de votre choix, lu avec `FileManager` sous votre utilisateur. Un dossier du système refusé par la politique de sécurité est annoncé, pas balayé en silence.") {
                        model.addFolder()
                    }
                }
                if model.settings.extraFolders.isEmpty {
                    Text("Aucun : l'analyse porte sur Téléchargements, Documents, Bureau, Images, Musiques et Vidéos.")
                        .font(.system(size: 10))
                        .foregroundColor(Color.mmSecondaryLabel)
                } else {
                    ForEach(model.settings.extraFolders, id: \.self) { path in
                        HStack {
                            Image(systemName: ("folder").mmSafeSymbol)
                                .font(.system(size: 10))
                                .foregroundColor(Color.mmSecondaryLabel)
                            Text(Fmt.prettyPath(path))
                                .font(.system(size: 10, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                model.removeFolder(path)
                            } label: {
                                Image(systemName: ("xmark.circle.fill").mmSafeSymbol)
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.mmSecondaryLabel)
                            }
                            .buttonStyle(.plain)
                            .help("Retirer ce dossier de l'analyse (ne supprime rien)")
                        }
                    }
                }
            }
        }
    }

    /// Curseur + valeur pour un seuil entier.
    private func threshold(_ title: String, value: Binding<Int>, range: ClosedRange<Int>,
                           unit: String, help: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(value.wrappedValue) \(unit)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.pink)
            }
            Slider(value: Binding(get: { Double(value.wrappedValue) },
                                  set: { value.wrappedValue = Int($0) }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                .controlSize(.small)
                .accentColor(.pink)
            Text(help)
                .font(.system(size: 10))
                .foregroundColor(Color.mmTertiaryLabel)
        }
        .help(help)
    }

    // -------------------------------------------------------------------------
    //  Zone d'action
    // -------------------------------------------------------------------------

    private var actionCard: some View {
        SectionCard(title: "Appliquer",
                    subtitle: "Seules les cases cochées sont traitées. La politique de sécurité refuse en plus tout ce qui appartient à macOS.",
                    systemImage: "wand.and.stars", accent: .pink) {
            VStack(alignment: .leading, spacing: 12) {
                ModeSelector(mode: $model.mode)

                HStack(spacing: 10) {
                    Button {
                        model.act()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: (model.mode.freesImmediately ? "xmark.bin.fill" : "trash.fill").mmSafeSymbol)
                            Text(model.selectedCount == 0
                                 ? "Aucun élément sélectionné"
                                 : "Supprimer \(model.selectedCount) élément(s) · \(Fmt.size(model.selectedBytes))")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Theme.gradient(model.selectedCount == 0 ? Color.gray : .pink))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.selectedCount == 0 || model.isActing || model.isScanning)
                    .help(model.mode.freesImmediately
                        ? "Traite les \(model.selectedCount) élément(s) cochés par effacement direct : pas de corbeille, pas de retour en arrière. La politique de sécurité refuse /System, /usr, /bin, /sbin, /private/var/db, les mails, le trousseau et les messages."
                        : "Déplace les \(model.selectedCount) élément(s) cochés vers la corbeille (`FileManager.trashItem`) : réversible tant qu'elle n'est pas vidée. La politique de sécurité refuse /System, /usr, /bin, /sbin, /private/var/db, les mails, le trousseau et les messages.")

                    Spacer()

                    // Rappelle le nettoyage « intelligent » en un clic, hérité de la barre de menus.
                    ToolButton(title: "Nettoyage express", systemImage: "sparkles", color: .purple,
                               busy: monitor.isProcessing,
                               help: "Les quatre collectes automatiques — /tmp au-delà de 60 min, caches utilisateur au-delà de 2 h, journaux système au-delà de 24 h, puis vidage de la corbeille. Les trois premières vont à la corbeille (réversible) ; la dernière est définitive. Aucun fichier personnel n'est concerné.") {
                        monitor.runCleanup()
                    }
                }

                if model.isActing {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView().progressViewStyle(LinearProgressViewStyle(tint: .pink))
                        StatusLine(text: model.progress)
                    }
                }

                if let report = model.lastReport {
                    ReportCard(report: report, mode: model.mode)
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    //  Avant le premier balayage
    // -------------------------------------------------------------------------

    private var emptyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: ("hourglass").mmSafeSymbol)
                        .foregroundColor(Color.mmSecondaryLabel)
                    Text("Balayage en préparation")
                        .font(.system(size: 13, weight: .bold))
                }
                Text("Les sept familles sont analysées l'une après l'autre, avec une limite de 22 secondes chacune pour ne jamais bloquer l'interface. Les doublons sont les plus longs : ils exigent une empreinte SHA-256.")
                    .font(.system(size: 11))
                    .foregroundColor(Color.mmSecondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                ToolButton(title: "Lancer le balayage", systemImage: "magnifyingglass", color: .pink,
                           help: "Mesure les sept familles sur le disque avant d'afficher quoi que ce soit : sans ce relevé, aucune taille n'est inventée.") {
                    model.scan()
                }
            }
        }
    }
}

// ============================================================================
//  Carte d'une section de balayage
// ============================================================================

/// Une famille analysée : en-tête chiffré, lignes cochables, avertissements.
///
/// Vue séparée de `PurgeView` : la hiérarchie SwiftUI reste petite et
/// l'inférence des génériques `SectionCard` ne sature plus le compilateur.
struct PurgeSectionCard: View {
    let section: PurgeSection
    @Binding var expanded: Set<String>
    @ObservedObject private var model = PurgeModel.shared

    /// Lignes visibles avant le bouton « afficher la suite ».
    private let rowLimit = 10

    var body: some View {
        SectionCard(title: section.title,
                    subtitle: section.subtitle,
                    systemImage: section.systemImage,
                    accent: Theme.accent(section.accent),
                    trailing: { headerControls }) {
            VStack(alignment: .leading, spacing: 8) {
                recordRows
                if let note = section.aggregateNote {
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundColor(Color.mmSecondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HonestyNotes(notes: section.warnings)
                if section.id == "trashes" {
                    trashExtras
                }
            }
        }
    }

    /// Pastilles de compte + boutons de sélection rapide.
    private var headerControls: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(spacing: 6) {
                Pill(text: "\(section.count) élém.", color: Theme.accent(section.accent))
                Pill(text: Fmt.size(section.totalBytes),
                     systemImage: section.executable ? "arrow.down.circle" : "eye",
                     color: .gray)
            }
            if section.executable {
                HStack(spacing: 6) {
                    ToolButton(title: "Tout", systemImage: "checkmark",
                               color: Theme.accent(section.accent),
                               help: "Coche tous les éléments supprimables de cette famille. Les éléments marqués « à vérifier » ou refusés par la politique de sécurité restent décochés : cocher n'efface rien, seul le bouton du bas agit.") {
                        model.setSelection(section, on: true)
                    }
                    ToolButton(title: "Rien", systemImage: "xmark", color: .gray,
                               help: "Décoche toute la famille. C'est l'état par défaut de l'application : rien n'est sélectionné à l'avance.") {
                        model.setSelection(section, on: false)
                    }
                }
            } else {
                Pill(text: "rapport seul", systemImage: "doc.text.magnifyingglass", color: .orange)
            }
        }
    }

    /// Lignes de résultats, repliées au-delà de `rowLimit`.
    @ViewBuilder
    private var recordRows: some View {
        if section.records.isEmpty {
            Text("Rien à signaler ici sur cette machine.")
                .font(.system(size: 11))
                .foregroundColor(Color.mmSecondaryLabel)
        } else {
            ForEach(visible) { record in
                RecordRow(record: record,
                          isSelected: Binding(get: { model.isSelected(record) },
                                              set: { _ in model.toggle(record) }),
                          membersHidden: record.members.count > 1 ? record.members.count : 0)
            }
            if section.records.count > rowLimit {
                Button(expanded.contains(section.id) ? "Réduire la liste" : "Afficher les \(section.records.count - rowLimit) élément(s) restant(s)") {
                    withAnimation {
                        if expanded.contains(section.id) {
                            expanded.subtract([section.id])
                        } else {
                            expanded.formUnion([section.id])
                        }
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.accent(section.accent))
                .help(expanded.contains(section.id)
                    ? "Replier la liste et retrouver le balayage en un coup d'œil."
                    : "Afficher tous les éléments de la famille, y compris ceux masqués pour tenir la page lisible.")
            }
        }
    }

    private var visible: [FileRecord] {
        if expanded.contains(section.id) || section.records.count <= rowLimit {
            return section.records
        }
        return Array(section.records.prefix(rowLimit))
    }

    /// Actions officielles pour les corbeilles (Mail, volumes externes).
    private var trashExtras: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 8) {
                ToolButton(title: "Vider le courrier indésirable de Mail",
                           systemImage: "envelope.open", color: .blue,
                           disabled: model.isActing,
                           help: "Envoie `empty junk mail` à Mail par AppleScript : c'est Mail qui vide sa propre corbeille de courrier indésirable, l'application ne touche à aucun fichier de ~/Library/Mail. macOS peut demander l'autorisation « Automation ».") {
                    model.emptyMailJunk()
                }
                ToolButton(title: "Corbeilles des volumes (admin)",
                           systemImage: "externaldrive.badge.xmark", color: .red,
                           disabled: model.isActing,
                           help: "Vide /Volumes/*/.Trashes, les corbeilles de racine que le Finder utilisateur n'affiche pas. Ces dossiers appartiennent à root : `osascript … with administrator privileges` affiche la fenêtre de mot de passe du système, et l'annulation est consignée comme échec.") {
                    model.emptyVolumeTrashesWithAdmin()
                }
            }
            Text("Ces deux actions passent par des voies officielles : AppleScript « empty junk mail » pour Mail (l'autorisation « Automation » peut être demandée) et l'invite d'authentification macOS pour les corbeilles de volumes, qui appartiennent à root.")
                .font(.system(size: 10))
                .foregroundColor(Color.mmSecondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
            if let output = model.lastAdminOutput, !output.isEmpty {
                Text(output)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color.mmSecondaryLabel)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)))
            }
        }
    }
}
