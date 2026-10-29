// ============================================================================
//  MonitorMyMac — onglet Performance (optimisation des performances)
//  Auteur : Martial Zinsou
//  ============================================================================
//
//  Couvre les quatre points demandés :
//    • libération de la mémoire RAM (`purge`, avec mesure du gain réel) ;
//    • gestion des éléments de démarrage (LaunchAgents/Daemons, `launchctl`) ;
//    • scripts de maintenance (permissions, Spotlight, DNS, périodiques…) ;
//    • contrôle des applications gourmandes (CPU, RAM, énergie `top -o power`).
//
//  Chaque chiffre affiché provient d'une commande réellement exécutée ; les
//  commandes qui exigent root passent par l'invite d'authentification macOS.
// ============================================================================

import SwiftUI

/// Onglet « Performance ».
struct PerformanceView: View {
    @ObservedObject private var model = PerformanceModel.shared

    var body: some View {
        VStack(spacing: 16) {
            memoryCard
            greedyCard
            startupCard
            maintenanceCard
        }
        .onAppear {
            if model.processes.isEmpty { model.refreshAll() }
        }
    }

    // -------------------------------------------------------------------------
    //  1. Mémoire vive
    // -------------------------------------------------------------------------

    private var memoryCard: some View {
        SectionCard(title: "Mémoire vive",
                    subtitle: model.memoryCardDetail,
                    systemImage: "memorychip",
                    accent: .purple,
                    trailing: {
                        ToolButton(title: "Actualiser", systemImage: "arrow.clockwise", color: .gray,
                                   busy: model.isBusy,
                                   help: "Relit `vm_stat`, `sysctl` et `top` : pression mémoire réelle, pages câblées, compressées et swap mesuré. Aucune écriture, aucun nettoyage.") {
                            model.refreshAll()
                        }
                    }) {
            VStack(alignment: .leading, spacing: 12) {
                PressureBar(ratio: model.memoryPressureRatio,
                            stateLabel: model.snapshot.stateLabel,
                            stateColor: Theme.memoryState(model.snapshot.stateLabel))
                    .help("Pression mémoire = (active + câblée + compressée) / total, mesuré sur `vm_stat`.")

                HStack(spacing: 14) {
                    StatChip(value: Fmt.shortSize(model.snapshot.active), label: "active", color: .blue)
                    StatChip(value: Fmt.shortSize(model.snapshot.wired), label: "câblée", color: .purple)
                    StatChip(value: Fmt.shortSize(model.snapshot.compressed), label: "compressée", color: .orange)
                    StatChip(value: Fmt.shortSize(model.snapshot.purgeable), label: "récupérable", color: .green)
                    StatChip(value: Fmt.shortSize(model.snapshot.swapUsed), label: "échange utilisée", color: .red)
                }

                HStack(spacing: 10) {
                    Button {
                        model.purgeMemory()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: ("arrow.down.circle").mmSafeSymbol)
                            Text("Purger la RAM")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.gradient(.purple))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isBusy)
                    .help("`/usr/sbin/purge` : exige une authentification administrateur (la commande est réservée à root).")

                    VStack(alignment: .leading, spacing: 1) {
                        if let gain = model.lastPurgeGain, let date = model.lastPurgeDate {
                            Text("Dernier gain mesuré : \(Fmt.size(gain))")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.green)
                            Text(Fmt.date(date))
                                .font(.system(size: 10))
                                .foregroundColor(Color.mmTertiaryLabel)
                        } else {
                            Text("Aucune purge effectuée dans cette session.")
                                .font(.system(size: 10))
                                .foregroundColor(Color.mmSecondaryLabel)
                        }
                    }
                    Spacer()
                }

                HonestyNotes(notes: [
                    "`purge` libère les pages inactives et le cache disque : le gain mesuré est souvent modeste et macOS récupère ces pages tout seul quand un en a besoin. Fermer des applications reste plus efficace.",
                    "Environnement estimé jusqu'à \(model.purgeableEstimate) sans droits administrateur (pages inactives + libres)."
                ], color: .blue)
                StatusLine(text: model.message, busy: model.isBusy)
            }
        }
    }

    // -------------------------------------------------------------------------
    //  2. Applications gourmandes
    // -------------------------------------------------------------------------

    private var greedyCard: some View {
        SectionCard(title: "Applications gourmandes",
                    subtitle: model.energyAvailable
                        ? "Top des processus par CPU (`ps`), avec l'estimation d'énergie de `top -o power`."
                        : "Top des processus par CPU (`ps`). L'estimation d'énergie n'a pas pu être lue sur cette machine.",
                    systemImage: "flame.fill",
                    accent: .orange,
                    trailing: {
                        ToolButton(title: "Actualiser", systemImage: "arrow.clockwise", color: .gray,
                                   help: "Relit `top -o power` et `ps -Aceo …` : la liste des applications par consommation réelle, regroupées par binaire. Lecture seule.") {
                            model.refreshAll()
                        }
                    }) {
            VStack(alignment: .leading, spacing: 10) {
                if model.appConsumers.isEmpty {
                    Text("Aucun processus relevé — lancez « Actualiser ».")
                        .font(.system(size: 11))
                        .foregroundColor(Color.mmSecondaryLabel)
                } else {
                    Text("Par application (helpers regroupés)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.mmSecondaryLabel)
                    ForEach(model.appConsumers) { group in
                        HStack(spacing: 9) {
                            Image(systemName: (group.gui ? "app.fill" : "cpu").mmSafeSymbol)
                                .font(.system(size: 11))
                                .foregroundColor(group.cpu > 60 ? .red : (group.cpu > 25 ? .orange : .secondary))
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(group.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                Text("\(group.pids.count) processus · \(Fmt.size(group.bytes)) en RAM")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color.mmTertiaryLabel)
                            }
                            Spacer()
                            Text(String(format: "%.0f %%", group.cpu))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(group.cpu > 60 ? .red : .primary)
                            if group.gui {
                                ToolButton(title: "Quitter", systemImage: "power", color: .orange,
                                           help: "Demande de fermeture propre (`NSRunningApplication.terminate`) à toutes les instances du binaire, puis `forceTerminate` si l'application ne répond pas. Une fenêtre ouverte perd ce qui n'est pas enregistré : enregistrez d'abord.") {
                                    model.quit(group)
                                }
                            }
                        }
                        .padding(.vertical, 3)
                    }

                    Divider()

                    Text("Processus individuels (10 premiers)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.mmSecondaryLabel)
                    ForEach(model.processes.prefix(10)) { entry in
                        HStack(spacing: 9) {
                            Text("\(entry.pid)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(Color.mmTertiaryLabel)
                                .frame(width: 38, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Text(entry.detail)
                                    .font(.system(size: 10))
                                    .foregroundColor(Color.mmTertiaryLabel)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if entry.killable {
                                ToolButton(title: "Arrêter", systemImage: "stop.circle", color: .red,
                                           help: "`kill` SIGTERM, puis SIGKILL si le processus tient. Réservé aux processus de votre utilisateur : un processus appartenant à root ou à un autre compte est affiché sans bouton, l'application n'escalade pas par elle-même.") {
                                    model.terminate(entry)
                                }
                            } else {
                                Pill(text: "appartient à \(entry.user)", systemImage: "lock.fill", color: .gray)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                HonestyNotes(notes: [
                    "Un processus d'un autre utilisateur (root, _windowserver…) ne peut pas être arrêté depuis votre session : le bouton est remplacé par un cadenas.",
                    "Arrêter un processus non graphique peut déstabiliser une application en cours. Préférez « Quitter » sur les applications."
                ])
                if !model.consoleOutput.isEmpty && model.message.contains("arrêt") {
                    Text(model.consoleOutput)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color.mmSecondaryLabel)
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    //  3. Éléments de démarrage
    // -------------------------------------------------------------------------

    private var startupCard: some View {
        SectionCard(title: "Éléments de démarrage",
                    subtitle: "\(model.loginItems.count) LaunchAgents et LaunchDaemons relevés · \(model.disabledStartupCount) désactivé(s) par MonitorMyMac",
                    systemImage: "powerplug.fill",
                    accent: .mmTeal,
                    trailing: {
                        ToolButton(title: "Actualiser", systemImage: "arrow.clockwise", color: .gray,
                                   help: "Fusionne `launchctl list` et la lecture des plist de ~/Library/LaunchAgents, /Library/LaunchAgents et /Library/LaunchDaemons. Les éléments système ne sont que listés : l'app n'y touche pas.") {
                            model.refreshAll()
                        }
                    }) {
            VStack(alignment: .leading, spacing: 8) {
                if model.loginItems.isEmpty {
                    Text("Aucun élément trouvé — lancez « Actualiser ».")
                        .font(.system(size: 11))
                        .foregroundColor(Color.mmSecondaryLabel)
                }
                ForEach(model.loginItems) { item in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: (item.disabledByApp
                              ? "pause.circle"
                              : (item.loaded ? "play.circle" : "circle.dashed")).mmSafeSymbol)
                            .font(.system(size: 13))
                            .foregroundColor(item.disabledByApp ? .orange : (item.loaded ? .green : .secondary))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            Text(item.detail)
                                .font(.system(size: 10))
                                .foregroundColor(Color.mmTertiaryLabel)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if item.manageable {
                            ToolButton(title: item.disabledByApp ? "Réactiver" : "Désactiver",
                                       systemImage: item.disabledByApp ? "arrow.uturn.backward" : "slash.circle",
                                       color: item.disabledByApp ? .green : .orange,
                                       busy: false, disabled: model.isBusy,
                                       help: "Renomme le plist de l'agent en `.plist.disabled` (et `launchctl bootout`/`bootstrap` pour la session courante). Le fichier reste sur le disque, l'extension prouve le geste : « Réactiver » rend le nom d'origine.") {
                                model.toggle(item)
                            }
                        } else {
                            Pill(text: "lecture seule", systemImage: "lock.fill", color: .gray)
                        }
                    }
                    .padding(.vertical, 3)
                }
                HonestyNotes(notes: [
                    "Désactiver renomme le plist en suffixant « .mmm-off » et décharge l'élément de launchd : l'opération est réversible par le bouton « Réactiver », ou en renommant le fichier.",
                    "Les éléments de /Library/LaunchDaemons et ceux d'un autre utilisateur exigent des droits administrateur : ils restent en lecture seule.",
                    "Depuis macOS 13 Ventura, les « Login Items » déclarés par une application (ouverture à la session) ne sont pas lisibles par une app tierce : seules les listes LaunchAgents/LaunchDaemons sont vues ici."
                ], color: .blue)
            }
        }
    }

    // -------------------------------------------------------------------------
    //  4. Scripts de maintenance
    // -------------------------------------------------------------------------

    private var maintenanceCard: some View {
        SectionCard(title: "Scripts de maintenance",
                    subtitle: "Commandes système réelles, exécutées une par une avec leur sortie complète.",
                    systemImage: "wrench.and.screwdriver.fill",
                    accent: .mmIndigo,
                    trailing: {
                        ToolButton(title: "Tout exécuter", systemImage: "play.circle",
                                   color: .mmIndigo, busy: model.isBusy,
                                   help: "Enchaîne les scripts de la suite, dans l'ordre d'affichage. Ceux qui touchent le système (`mdutil -E`, `dscacheutil`, les corbeilles de volumes) passent par `osascript … with administrator privileges` : c'est macOS qui demande le mot de passe, à chaque tâche concernée, et l'annulation est reportée telle quelle. « Vérifier le volume » se lance sans droits particuliers.") {
                            model.runAll()
                        }
                    }) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.tasks) { task in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 9) {
                            Image(systemName: (task.systemImage).mmSafeSymbol)
                                .font(.system(size: 13))
                                .foregroundColor(statusColor(task))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(task.title)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(task.command)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(Color.mmTertiaryLabel)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Pill(text: task.needsAdmin.rawValue,
                                 systemImage: task.needsAdmin == .no ? "checkmark.circle" : "lock.shield",
                                 color: task.needsAdmin == .yes ? .red : (task.needsAdmin == .maybe ? .orange : .green))
                            ToolButton(title: task.ran ? "Relancer" : "Exécuter",
                                       systemImage: "play.fill", color: .mmIndigo,
                                       busy: false, disabled: model.isBusy,
                                       help: "Lance la commande telle qu'elle est écrite sur la carte : \(task.command.prefix(120))") {
                                model.run(task: task)
                            }
                        }
                        Text(task.explanation)
                            .font(.system(size: 10))
                            .foregroundColor(Color.mmSecondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 27)
                    }
                    .padding(.vertical, 3)
                }

                if !model.consoleOutput.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Sortie réelle de la dernière commande")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color.mmSecondaryLabel)
                            Spacer()
                            CopyButton(text: model.consoleOutput, color: Color.mmSecondaryLabel)
                        }
                        ScrollView {
                            Text(model.consoleOutput)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Color.mmLabel)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .mmTextSelection()
                                .padding(10)
                        }
                        .frame(maxHeight: 180)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.black.opacity(0.06))
                        )
                    }
                }
                StatusLine(text: model.message, busy: model.isBusy)
            }
        }
    }

    /// Couleur de l'icône d'une tâche selon son état réel.
    private func statusColor(_ task: MaintenanceTask) -> Color {
        if !task.ran { return .secondary }
        return task.succeeded ? .green : .red
    }
}
