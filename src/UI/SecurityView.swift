// ============================================================================
//  MonitorMyMac — onglet Sécurité (navigation, anti-malware, broyeur)
//  Auteur : Martial Zinsou
//  ============================================================================
//
//  Trois familles demandées :
//    • suppression des données de navigation (cookies, historiques, caches)
//      de tous les navigateurs réellement détectés ;
//    • analyse anti-malware par signatures documentées + heuristiques, avec
//      quarantaine réversible plutôt que suppression immédiate ;
//    • broyeur de fichiers (écrasement multi-passes puis unlink), avec
//      l'avertissement honnête sur APFS/SSD et FileVault.
// ============================================================================

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Onglet « Sécurité ».
struct SecurityView: View {
    var body: some View {
        VStack(spacing: 16) {
            SecurityTracesCard()
            SecurityMalwareCard()
            SecurityQuarantineCard()
            SecuritySignatureCard()
            SecurityShredderCard()
        }
    }
}

// ============================================================================
//  1. Données de navigation
// ============================================================================

/// Traces par navigateur, avec sélection et effacement.
struct SecurityTracesCard: View {
    @ObservedObject private var model = SecurityModel.shared

    var body: some View {
        SectionCard(title: "Données de navigation",
                    subtitle: "Cookies, historiques, caches et stockage local des navigateurs installés — mesure réelle sur le disque.",
                    systemImage: "network.badge.shield.half.filled",
                    accent: .mmCyan,
                    trailing: {
                        HStack(spacing: 6) {
                            Pill(text: "\(model.traces.count) traces", color: .mmCyan)
                            Pill(text: Fmt.size(model.selectedTraceBytes), systemImage: "tray.full", color: .gray)
                            ToolButton(title: model.isBusy ? "Balayage…" : "Balayer",
                                       systemImage: "magnifyingglass", color: .mmCyan,
                                       busy: model.isBusy,
                                       help: "Recense les traces réelles des navigateurs installés (historiques, caches, cookies). Rien n'est effacé : le balayage mesure seulement.") {
                                model.scanTraces()
                            }
                        }
                    }) {
            VStack(alignment: .leading, spacing: 10) {
                if !model.runningBrowsers.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: ("exclamationmark.arrow.triangle.2.circlepath").mmSafeSymbol)
                            .foregroundColor(.orange)
                        Text("Navigateur(s) ouvert(s) : \(model.runningBrowsers.joined(separator: ", ")) — leurs fichiers sont verrouillés et ne seront pas effacés. Fermez-les, ou fermez-les proprement ici.")
                            .font(.system(size: 11))
                            .foregroundColor(Color.mmSecondaryLabel)
                        Spacer()
                        ToolButton(title: "Fermer", systemImage: "power", color: .orange,
                                   busy: false, disabled: model.isBusy,
                                   help: "Demande aux navigateurs ouverts de se quitter proprement (AppleScript, puis NSRunningApplication). Un navigateur ouvert verrouille sa base SQLite : sans cette fermeture, ses traces seraient comptées mais pas effaçables.") {
                            for browser in model.runningBrowsers {
                                message(BrowserData.quit(browser))
                            }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.1)))
                }

                if model.traces.isEmpty {
                    Text("Aucune trace mesurée : lancez le balayage.")
                        .font(.system(size: 11))
                        .foregroundColor(Color.mmSecondaryLabel)
                }
                ForEach(model.tracesByBrowser) { group in
                    tracesGroup(group)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Ce que l'app ne touche volontairement pas :")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color.mmSecondaryLabel)
                    ForEach(BrowserData.neverTouched, id: \.self) { item in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: ("hand.raised.fill").mmSafeSymbol)
                                .font(.system(size: 9))
                                .foregroundColor(.red)
                            Text(item)
                                .font(.system(size: 10))
                                .foregroundColor(Color.mmSecondaryLabel)
                        }
                    }
                }
                HonestyNotes(notes: [
                    "Sans « Accès complet au disque », les répertoires protégés (~/Library/Safari, Cookies, ~/Library/Mail, /private/var/log) sont déclarés illisibles au lieu d'être inventés : le bouton ci-contre ouvre le panneau concerné des Réglages.",
                    "L'effacement retire les fichiers du profil : l'historique affiché dans certaines interfaces n'est vidé qu'au redémarrage du navigateur."
                ], color: .blue)
                HStack(spacing: 8) {
                    ToolButton(title: "Accès complet au disque", systemImage: "lock.open.fill",
                               color: .gray,
                               help: "Ouvre le panneau « Confidentialité et sécurité > Accès complet au disque » des Réglages système. L'application ne demande aucun droit toute seule : c'est macOS, et vous, qui décidez.") {
                        PrivacyAccess.openFullDiskAccessSettings()
                    }
                    Button {
                        model.clearSelectedTraces()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: ("eraser").mmSafeSymbol)
                            Text("Effacer les traces cochées (\(model.traceSelection.count))")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.gradient(model.traceSelection.isEmpty ? Color.gray : .mmCyan))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.traceSelection.isEmpty || model.isBusy)
                    .mmHelp("Supprime les fichiers de trace effectivement cochés, et eux seuls. Les navigateurs encore ouverts sont épargnés : leurs bases sont verrouillées par macOS.")
                    Spacer()
                }
                ModeSelector(mode: $model.mode)
                StatusLine(text: model.message, busy: model.isBusy)
            }
        }
        .onAppear {
            if model.traces.isEmpty && !model.isBusy { model.scanTraces() }
        }
    }

    /// Groupe d'un navigateur : en-tête + lignes cochables.
    private func tracesGroup(_ group: BrowserTraceGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(group.browser)
                    .font(.system(size: 11, weight: .semibold))
                Pill(text: Fmt.size(group.total), color: .mmCyan)
                Spacer()
                ToolButton(title: "Page officielle", systemImage: "safari", color: .blue,
                           help: "Ouvre la page d'assistance du navigateur pour ce groupe : ce que l'app ne peut pas toucher sans casser la base de l'application, vous pouvez l'effacer vous-même depuis l'éditeur.") {
                    message(BrowserData.openOfficialClearPage(group.browser))
                }
                ToolButton(title: group.items.allSatisfy { model.traceSelection.contains($0.id) } ? "Tout décocher" : "Tout cocher",
                           systemImage: "checkmark.rectangle", color: .gray,
                           help: "Sélectionne, ou deselect, toutes les traces de ce navigateur. Cocher n'efface rien : il faut encore le bouton « Effacer les traces cochées ».") {
                    toggle(group.items)
                }
            }
            ForEach(group.items) { trace in
                HStack(spacing: 8) {
                    Toggle(isOn: Binding(get: { model.traceSelection.contains(trace.id) },
                                         set: { _ in toggle(trace) })) {
                        EmptyView()
                    }
                    .toggleStyle(.checkbox)
                    .disabled(!trace.readable)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(trace.kind.rawValue) — \(Fmt.prettyPath(trace.url.path))")
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(trace.detail)
                            .font(.system(size: 9))
                            .foregroundColor(Color.mmTertiaryLabel)
                    }
                    Spacer()
                    Text(Fmt.size(trace.size))
                        .font(.system(size: 10, weight: .semibold))
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.07)))
    }

    private func toggle(_ trace: BrowserTrace) {
        guard trace.readable else {
            model.message = "Trace illisible (protection macOS) : \(Fmt.prettyPath(trace.url.path))"
            return
        }
        if model.traceSelection.contains(trace.id) { model.traceSelection.remove(trace.id) }
        else { model.traceSelection.insert(trace.id) }
    }

    private func toggle(_ group: [BrowserTrace]) {
        let allOn = group.allSatisfy { model.traceSelection.contains($0.id) }
        if allOn {
            model.traceSelection.subtract(Set(group.map(\.id)))
        } else {
            model.traceSelection.formUnion(Set(group.filter { $0.readable }.map(\.id)))
        }
    }

    /// Publie un message du moteur dans la barre d'état de la carte.
    private func message(_ text: String) {
        model.message = text
        SystemMonitor.shared.appendLog("Sécurité : \(text)")
    }
}

// ============================================================================
//  2. Analyse anti-malware
// ============================================================================

/// Signatures connues, heuristiques et posture système.
struct SecurityMalwareCard: View {
    @ObservedObject private var model = SecurityModel.shared
    @ObservedObject private var apps = AppsModel.shared

    var body: some View {
        SectionCard(title: "Analyse anti-malware",
                    subtitle: "Signatures documentées de malwares/adwares macOS, exécutables planqués dans des caches, extensions système non Apple, posture SIP/Gatekeeper.",
                    systemImage: "ladybug.fill",
                    accent: .red,
                    trailing: {
                        ToolButton(title: model.isBusy ? "Analyse…" : "Analyser",
                                   systemImage: "magnifyingglass.circle", color: .red,
                                   busy: model.isBusy,
                                   help: "Compare les applications, les greffons et les éléments de démarrage à une base de signatures locales (adwares et extensions indésirables connus). Aucune connexion réseau, aucun fichier envoyé : l'app n'est pas un antivirus certifié.") {
                            model.scanThreats(apps: apps.apps, plugins: apps.plugins)
                        }
                    }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(model.severityCounts) { entry in
                        Button {
                            withAnimation {
                                model.severityFilter = (model.severityFilter == entry.severity) ? nil : entry.severity
                            }
                        } label: {
                            VStack(spacing: 1) {
                                Text("\(entry.count)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                Text(entry.severity.rawValue)
                                    .font(.system(size: 9))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(color(for: entry.severity).opacity(
                                        model.severityFilter == entry.severity ? 0.28 : 0.12))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .help("Touchez une sévérité pour filtrer la liste.")

                if model.findings.isEmpty {
                    Text("Aucune analyse lancée. Les applications doivent être inventoriées au préalable (espace Applications) pour que la signature des bundles soit contrôlée.")
                        .font(.system(size: 11))
                        .foregroundColor(Color.mmSecondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                } else if model.visibleFindings.isEmpty {
                    Text("Aucun constat pour ce filtre.")
                        .font(.system(size: 11))
                        .foregroundColor(Color.mmSecondaryLabel)
                }
                ForEach(model.visibleFindings.prefix(20)) { finding in
                    findingRow(finding)
                }
                if model.visibleFindings.count > 20 {
                    Text("+ \(model.visibleFindings.count - 20) constat(s) masqué(s).")
                        .font(.system(size: 10))
                        .foregroundColor(Color.mmTertiaryLabel)
                }
                HonestyNotes(notes: [
                    "Ce n'est pas un antivirus certifié : la détection repose sur des signatures locales documentées et des heuristiques. Un échantillon inconnu peut passer. Aucun laboratoire n'a audité ce moteur.",
                    "Le mouvement par défaut est la **quarantaine réversible** (déplacement dans le dossier de l'app, manifeste JSON d'origine) : la suppression directe reste un choix explicite."
                ])
            }
        }
    }

    private func findingRow(_ finding: ThreatFinding) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: (icon(for: finding.severity)).mmSafeSymbol)
                .font(.system(size: 13))
                .foregroundColor(color(for: finding.severity))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(finding.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Pill(text: finding.severity.rawValue, color: color(for: finding.severity))
                }
                Text(finding.detail)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color.mmTertiaryLabel)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(finding.evidence)
                    .font(.system(size: 10))
                    .foregroundColor(Color.mmSecondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                Text(finding.advice)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(color(for: finding.severity))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if finding.actionable {
                VStack(alignment: .trailing, spacing: 5) {
                    ToolButton(title: "Quarantaine", systemImage: "shippingbox.and.arrow.backward.fill",
                               color: .orange, busy: false, disabled: model.isBusy,
                               help: "Déplace l'élément dans le dossier de quarantaine de l'application, avec un manifeste JSON qui garde son chemin d'origine. Réversible par « Restaurer ».") {
                        model.quarantine(finding)
                    }
                    ToolButton(title: "Supprimer", systemImage: "trash", color: .red,
                               busy: false, disabled: model.isBusy,
                               help: "Suppression définitive, sans passer par la corbeille : à réserver aux éléments déjà vérifiés en quarantaine. Passez plutôt par « Quarantaine » si un doute subsiste.") {
                        model.delete(finding)
                    }
                }
            } else {
                Pill(text: "action manuelle", systemImage: "hand.raised", color: .gray)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.06)))
    }

    private func color(for severity: ThreatSeverity) -> Color {
        switch severity {
        case .confirmed: return .red
        case .suspicious: return .orange
        case .informational: return .blue
        }
    }

    private func icon(for severity: ThreatSeverity) -> String {
        switch severity {
        case .confirmed: return "exclamationmark.octagon.fill"
        case .suspicious: return "questionmark.diamond.fill"
        case .informational: return "info.circle.fill"
        }
    }
}

// ============================================================================
//  3. Quarantaine
// ============================================================================

/// Contenu du dossier de quarantaine, avec restauration et purge.
struct SecurityQuarantineCard: View {
    @ObservedObject private var model = SecurityModel.shared

    var body: some View {
        SectionCard(title: "Quarantaine de MonitorMyMac",
                    subtitle: "Éléments déplacés (et non supprimés) : ils restent restaurables à leur chemin d'origine.",
                    systemImage: "shippingbox.fill",
                    accent: .mmBrown,
                    trailing: {
                        HStack(spacing: 6) {
                            ToolButton(title: "Recharger", systemImage: "arrow.clockwise", color: .gray,
                                       help: "Relit le dossier de quarantaine et ses manifestes : si vous avez déplacé ou supprimé les fichiers vous-même dans le Finder, la liste reflète l'état réel et non l'état mémorisé.") {
                                model.refreshQuarantine()
                            }
                            ToolButton(title: "Purger", systemImage: "xmark.bin.fill", color: .red,
                                       busy: false, disabled: model.quarantined.isEmpty || model.isBusy,
                                       help: "Supprime définitivement tout le contenu du dossier de quarantaine. Irréversible : « Restaurer » n'est plus possible après ce geste.") {
                                model.purgeQuarantine()
                            }
                        }
                    }) {
            VStack(alignment: .leading, spacing: 6) {
                if model.quarantined.isEmpty {
                    Text("Aucun élément en quarantaine.")
                        .font(.system(size: 11))
                        .foregroundColor(Color.mmSecondaryLabel)
                }
                ForEach(model.quarantined) { record in
                    HStack(spacing: 8) {
                        Image(systemName: ("shippingbox").mmSafeSymbol)
                            .font(.system(size: 11))
                            .foregroundColor(Color.mmSecondaryLabel)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(record.displayName)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Text(record.note ?? Fmt.prettyPath(record.url.path))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(Color.mmTertiaryLabel)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Text(Fmt.size(record.size))
                            .font(.system(size: 10))
                            .foregroundColor(Color.mmSecondaryLabel)
                        ToolButton(title: "Restaurer", systemImage: "arrow.uturn.backward.circle",
                                   color: .green, busy: false, disabled: model.isBusy,
                                   help: "Renvoie l'élément à son emplacement d'origine, lu dans le manifeste JSON. Si l'emplacement est devenu indisponible, la restauration est refusée plutôt que d'écrire n'importe où.") {
                            model.restore(record)
                        }
                    }
                }
                Text("Le manifeste JSON écrit à côté de chaque élément conserve son chemin d'origine ; « Restaurer » le remplace sans le réécrire.")
                    .font(.system(size: 10))
                    .foregroundColor(Color.mmTertiaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                StatusLine(text: model.message, busy: model.isBusy)
            }
        }
        .onAppear {
            model.refreshQuarantine()
        }
    }
}

// ============================================================================
//  4. Vérification de signature
// ============================================================================

/// codesign + Gatekeeper sur une application choisie.
struct SecuritySignatureCard: View {
    @ObservedObject private var model = SecurityModel.shared

    var body: some View {
        SectionCard(title: "Vérifier une application",
                    subtitle: "`codesign --verify --verbose` et `spctl --assess --type exec` exécutés sur le bundle choisi.",
                    systemImage: "checkmark.shield.fill",
                    accent: .green,
                    trailing: {
                        ToolButton(title: "Choisir une app…", systemImage: "doc.viewfinder",
                                   color: .green, busy: model.isBusy,
                                   help: "Ouvre le sélecteur du Finder, puis lit la signature du bundle choisi avec `codesign --verify --verbose` et `spctl --assess --type exec`. Rien n'est téléchargé ni envoyé : la vérification se fait sur place.") {
                            model.pickAndAssess()
                        }
                    }) {
            VStack(alignment: .leading, spacing: 8) {
                if let assessment = model.assessment {
                    HStack(spacing: 6) {
                        Text("Rapport de vérification")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color.mmSecondaryLabel)
                        Spacer()
                        CopyButton(text: assessment)
                    }
                    Text(assessment)
                        .font(.system(size: 10, design: .monospaced))
                        .mmTextSelection()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.06)))
                } else {
                    Text("Aucune vérification effectuée dans cette session.")
                        .font(.system(size: 11))
                        .foregroundColor(Color.mmSecondaryLabel)
                }
                HonestyNotes(notes: [
                    "`spctl` reflète la **politique locale** de Gatekeeper : une app refusée peut être légitime (non notarisée) et une app acceptée peut être malveillante si elle a été notarisée avant infection.",
                    "La notarisation en ligne (Apple) n'est pas interrogée : seule la signature présente sur le disque est contrôlée."
                ], color: .blue)
                StatusLine(text: model.message, busy: model.isBusy)
            }
        }
    }
}

// ============================================================================
//  5. Broyeur de fichiers
// ============================================================================

/// File d'attente, passes, broyage et résultat vérifié.
struct SecurityShredderCard: View {
    @ObservedObject private var model = SecurityModel.shared

    var body: some View {
        SectionCard(title: "Broyeur de fichiers",
                    subtitle: "Écrasement multi-passes des octets puis unlink. À réserver aux documents sensibles.",
                    systemImage: "trash.slash.fill",
                    accent: .red) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Passes d'écrasement")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color.mmSecondaryLabel)
                        Stepper(value: $model.passes, in: 1...7) {
                            Text("\(model.passes) × le fichier")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                    }
                    Spacer()
                    ToolButton(title: "Ajouter des fichiers…", systemImage: "plus.square.on.square",
                               color: .blue, busy: false, disabled: model.isBusy,
                               help: "Ouvre le sélecteur du Finder et met le choix dans la file du broyeur. Ajouter à la file n'écrase rien : c'est le bouton « Broyer » qui écrit sur le fichier.") {
                        model.pickForShredder()
                    }
                }

                dropZone

                if !model.shredQueue.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("File d'attente — \(model.shredQueue.count) élément(s) · \(Fmt.size(model.shredQueueBytes))")
                            .font(.system(size: 11, weight: .semibold))
                        ForEach(model.shredQueue, id: \.path) { url in
                            HStack(spacing: 7) {
                                Image(systemName: ("doc.fill").mmSafeSymbol)
                                    .font(.system(size: 10))
                                    .foregroundColor(Color.mmSecondaryLabel)
                                Text(Fmt.prettyPath(url.path))
                                    .font(.system(size: 10, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button {
                                    model.dequeue(url)
                                } label: {
                                    Image(systemName: ("xmark.circle.fill").mmSafeSymbol)
                                        .font(.system(size: 10))
                                        .foregroundColor(Color.mmSecondaryLabel)
                                }
                                .buttonStyle(.plain)
                                .help("Retire ce fichier de la file du broyeur sans rien toucher sur le disque.")
                            }
                        }
                        Button {
                            model.shredAll()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: ("shredder").mmSafeSymbol)
                                Text("Broyer définitivement \(model.shredQueue.count) élément(s)")
                            }
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Theme.gradient(.red))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isBusy)
                        .help("Écrase chaque fichier de la file octet par octet, \(model.passes) passe(s), puis le détache. Irréversible — et sans garantie d'irrécupérabilité sur un SSD chiffré : seul FileVault l'apporte.")
                    }
                }

                if !model.shredResults.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Résultat mesuré")
                            .font(.system(size: 11, weight: .semibold))
                        ForEach(model.shredResults.prefix(12)) { outcome in
                            HStack(spacing: 6) {
                                Image(systemName: (outcome.unlinked && outcome.verified
                                      ? "checkmark.circle.fill" : "xmark.circle.fill").mmSafeSymbol)
                                    .font(.system(size: 10))
                                    .foregroundColor(outcome.unlinked && outcome.verified ? .green : .red)
                                Text(Fmt.prettyPath(outcome.path))
                                    .font(.system(size: 10, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text("\(Fmt.size(outcome.bytesOverwritten)) · \(outcome.passes) passe(s) · "
                                     + (outcome.verified ? "relecture OK" : "relecture échouée"))
                                    .font(.system(size: 9))
                                    .foregroundColor(Color.mmTertiaryLabel)
                            }
                        }
                        if let firstError = model.shredResults.compactMap(\.error).first {
                            Text("Premier échec réel : \(firstError)")
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.08)))
                }

                HonestyNotes(notes: [
                    model.shredderDisclaimer,
                    "`rm -P` (l'écrasement « sécurisé » d'Apple) est également inopérant sur APFS/SSD pour les mêmes raisons — le moteur de l'app le rappelle plutôt que de promettre l'impossible.",
                    "Support de `rm -P` sur cette machine : \(FileShredder.supportsBSDSecureDelete())"
                ])
                StatusLine(text: model.message, busy: model.isBusy)
            }
        }
    }

    /// Zone de glisser-déposer vers la file du broyeur.
    private var dropZone: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: ("arrow.down.doc").mmSafeSymbol)
                    .font(.system(size: 11))
                    .foregroundColor(Color.mmSecondaryLabel)
                Text("Déposez ici les fichiers à broyer")
                    .font(.system(size: 11))
                    .foregroundColor(Color.mmSecondaryLabel)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                .foregroundColor(Color.gray.opacity(0.4))
        )
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            // Le glisser-déposer macOS fournit une archived URL : on la décode
            // pour chaque fournisseur, puis on l'ajoute à la file sur le fil principal.
            for provider in providers {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url = (item as? URL) ?? (item as? NSURL) as URL?
                    if let url = url {
                        DispatchQueue.main.async { model.enqueue([url]) }
                    }
                }
            }
            return !providers.isEmpty
        }
    }
}
