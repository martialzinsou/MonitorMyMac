// ============================================================================
//  MonitorMyMac — onglets Aide, FAQ et À propos
//  Auteur : Martial Zinsou
//  ============================================================================
//
//  L'Aide explique le **fonctionnement réel** de chaque onglet : les commandes
//  système appelées, les seuils, ce qui est réversible et ce qui ne l'est pas.
//  Les captures d'écran proviennent de l'application elle-même (mode
//  `--shots`) ; si elles manquent, le composant le dit au lieu d'inventer.
// ============================================================================

import SwiftUI

// ============================================================================
//  MARK: - Aide illustrée
// ============================================================================

/// Sujet d'aide : une famille de fonctionnalités.
struct HelpTopic: Identifiable {
    var id: String { title }
    let title: String
    let icon: String
    let accent: Color
    let screenshot: String
    let caption: String
    let how: [String]
    let commands: [String]
    let limits: [String]
}

/// Onglet « Aide » : guide illustré de toutes les fonctions.
struct HelpTabView: View {
    var body: some View {
        VStack(spacing: 16) {
            introduction
            ForEach(HelpTabView.topics) { topic in
                HelpTopicCard(topic: topic)
            }
            shortcutsCard
            availabilityCard
        }
    }

    // -------------------------------------------------------------------------
    //  Contenu
    // -------------------------------------------------------------------------

    static let topics: [HelpTopic] = [
        HelpTopic(
            title: "Surveillance en temps réel",
            icon: "gauge.medium",
            accent: .blue,
            screenshot: "01-surveillance",
            caption: "Tableau de bord : jauge CPU, jauge RAM, stockage, système et courbes d'historique sur 2 minutes.",
            how: [
                "Le rafraîchissement automatique intervient toutes les 2 secondes (minuteur principal) et l'icône de la barre de menus affiche le pourcentage CPU en direct.",
                "Les courbes du bas conservent les 60 derniers relevés CPU et RAM ; elles permettent de voir une pointe plutôt qu'une moyenne."
            ],
            commands: [
                "`top -l 1 -n 0 -s 0` pour le CPU (100 % − idle)",
                "`vm_stat` + `sysctl hw.memsize` pour la RAM",
                "`df -h /` pour le stockage",
                "`sysctl machdep.cpu.brand_string`, `hw.ncpu`, `hw.model` pour le matériel"
            ],
            limits: [
                "Ces chiffres sont ceux de la commande au moment de la lecture : `top` moyenne sur un instant, un pic très court peut donc ne pas apparaître."
            ]
        ),
        HelpTopic(
            title: "Purge : nettoyage du stockage",
            icon: "bubbles.and.sparkles.fill",
            accent: .pink,
            screenshot: "02-purge",
            caption: "Les sept familles analysées, avec leur taille réelle, leurs avertissements et la sélection avant action.",
            how: [
                "Cycle imposé : balayer, examiner, cocher, agir. Aucun fichier n'est supprimé sans case cochée, et le mode par défaut est la corbeille (réversible).",
                "Caches : seuls les fichiers plus anciens que le seuil (7 jours par défaut) sont proposés, pour ne pas casser un cache « chaud ».",
                "Gros fichiers : taille et ancienneté sont toutes deux filtrées (100 Mo et 90 jours par défaut), sur vos dossiers personnels et ceux que vous ajoutez.",
                "Doublons : regroupement par taille, puis empreinte SHA-256 partielle (premier et dernier Mio), puis empreinte complète. Un groupe ne propose que les copies à supprimer, jamais l'original le plus ancien.",
                "Corbeilles : corbeille de l'utilisateur, corbeilles de volumes, corbeilles applicatives et données Mail téléchargées sont listées séparément."
            ],
            commands: [
                "`du`/taille allouée par `URLResourceValues.totalFileAllocatedSize`",
                "CryptoKit `SHA256` pour l'empreinte des doublons",
                "`osascript` pour le vidage du courrier indésirable de Mail",
                "`osascript … with administrator privileges` pour les corbeilles de volumes"
            ],
            limits: [
                "Les fichiers de traduction (.lproj) sont repérés et chiffrés, mais leur suppression est refusée : enlever un .lproj casse la signature du code et Gatekeeper bloque ensuite l'application.",
                "Les corbeilles de volumes externes appartiennent à root : le vidage passe obligatoirement par l'authentification macOS.",
                "En mode corbeille, l'espace n'est rendu qu'après vidage de la corbeille — le rapport le rappelle."
            ]
        ),
        HelpTopic(
            title: "Performance : RAM, démarrage, maintenance, gourmands",
            icon: "bolt.fill",
            accent: .orange,
            screenshot: "03-performance",
            caption: "Jauge de pression mémoire, applications gourmandes regroupées, LaunchAgents/Daemons et scripts de maintenance avec leur sortie réelle.",
            how: [
                "La pression mémoire est calculée comme macOS : (active + câblée + compressée) / total, mesurée sur `vm_stat`.",
                "« Purger la RAM » exécute `/usr/sbin/purge` (root) et mesure le gain réel en comparant les pages inactive+libre avant et après.",
                "Les éléments de démarrage listent `~/Library/LaunchAgents`, `/Library/LaunchAgents` et `/Library/LaunchDaemons`, avec leur état launchd.",
                "La désactivation renomme le plist en « .mmm-off » et décharge l'élément de launchd ; « Réactiver » fait l'inverse.",
                "Les scripts de maintenance (Spotlight, permissions, cache DNS, scripts périodiques, logs système, corbeilles de volumes) affichent la sortie brute de la commande."
            ],
            commands: [
                "`ps -Aceo pid=,user=,pcpu=,pmem=,rss=,comm= -r` et `top -o power`",
                "`launchctl list` / `bootout` / `bootstrap`",
                "`mdutil -s -a`, `mdutil -E /`, `diskutil verifyVolume /`, `diskutil repairPermissions /`",
                "`lsregister -R`, `dscacheutil -flushcache`, `periodic daily|weekly|monthly`"
            ],
            limits: [
                "`purge` rend souvent peu de mémoire : macOS récupère les pages inactives seul quand un besoin apparaît. Fermer des applications reste plus efficace.",
                "`diskutil repairPermissions` est dépréciée depuis APFS (macOS répare les droits tout seul) : la sortie réelle est montrée, sans enjoliver.",
                "Depuis macOS 13 Ventura, les « Login Items » déclarés par une application ne sont pas lisibles par une app tierce : seules les listes LaunchAgents/LaunchDaemons sont visibles."
            ]
        ),
        HelpTopic(
            title: "Applications : désinstallation, mises à jour, extensions",
            icon: "square.grid.3x2.fill",
            accent: .mmIndigo,
            screenshot: "04-applications",
            caption: "Inventaire trié par taille, résidus d'une application, contrôle des canaux de mise à jour, greffons/widgets et extensions de navigateurs.",
            how: [
                "L'inventaire lit les bundles (`Info.plist`) de /Applications, /Applications/Utilities, ~/Applications, ~/Downloads et /System/Applications, avec taille réelle et receipt App Store.",
                "« Résidus » cherche les emplacements standards de ~/Library au nom exact de l'identifiant de bundle, puis, avec plus de prudence, au nom de l'éditeur.",
                "La désinstallation ferme l'application, autorise temporairement le bundle (`PathPolicy.approveUninstall`), supprime le bundle et les résidus cochés, puis retire l'autorisation.",
                "« Quarantaine » déplace le bundle dans le dossier de l'app avec manifeste d'origine : réversible sans suppression.",
                "Extensions : `pluginkit -m -A -v` pour les greffons et widgets, lecture des manifestes réels des profils de navigateurs."
            ],
            commands: [
                "`pluginkit -m -A -v`, `pluginkit -e use|ignore|invalidate`",
                "`systemextensionsctl list`",
                "`softwareupdate --list` (sortie brute conservée), `brew outdated` si Homebrew est présent",
                "manifestes `extensions.json` (Firefox) et dossiers d'extensions Chrome/Edge/Brave/Arc/Opera/Vivaldi"
            ],
            limits: [
                "Aucune mise à jour n'est téléchargée ni installée : `softwareupdate --install` exige root et l'App Store impose son flux authentifié.",
                "Les applications d'/System/Applications sont en lecture seule (protection SSV/SIP).",
                "Les extensions de Safari ne sont pas énumérables par une app tierce (TCC).",
                "Une extension de navigateur ne peut être retirée que navigateur fermé."
            ]
        ),
        HelpTopic(
            title: "Sécurité : navigation, malwares, broyeur",
            icon: "lock.shield.fill",
            accent: .mmCyan,
            screenshot: "05-securite",
            caption: "Traces mesurées par navigateur, constats d'analyse par signatures, dossier de quarantaine et file du broyeur.",
            how: [
                "Les traces (cookies, historique, cache, stockage local) sont mesurées sur les profils réels, groupées par navigateur, et sélectionnables une par une.",
                "Signets, mots de passe, cartes de paiement et trousseau ne sont jamais touchés ; `places.sqlite` de Firefox non plus, car l'historique y est mélangé aux signets.",
                "L'analyse de sécurité compare à des signatures connues (malwares/adwares macOS documentés), cherche des exécutables planqués dans des caches, des extensions système non Apple et lit la posture (SIP, Gatekeeper, FileVault).",
                "Le mouvement par défaut est la quarantaine réversible ; la suppression directe reste un clic explicite.",
                "Le broyeur écrase le fichier sur place (zéros puis motifs aléatoires) autant de passes que demandé, relit un échantillon pour confirmer, puis détache le fichier (`unlink`)."
            ],
            commands: [
                "`codesign --verify --verbose`, `spctl --assess --type exec`",
                "`csrutil status`, `sysadminctl -sdot status`, `fdesetup status`",
                "`systemextensionsctl list` et `pluginkit` pour l'inventaire des extensions",
                "écriture directe par `FileHandle` + `unlink` pour le broyage"
            ],
            limits: [
                "Ce n'est pas un antivirus certifié : détection par signatures locales et heuristiques, sans audit de laboratoire. Un échantillon inconnu peut passer.",
                "Sur APFS/SSD, le copy-on-write, le TRIM et les instantanés Local Time Machine peuvent faire survivre d'anciens blocs à l'écrasement : pour des données truly sensibles, la garantie réelle reste FileVault.",
                "Sans « Accès complet au disque », les zones protégées (Safari, Cookies, Mail, /private/var/log) sont annoncées illisibles — jamais comptées à tort."
            ]
        )
    ]

    // -------------------------------------------------------------------------
    //  Cartes d'introduction, raccourcis et disponibilité des captures
    // -------------------------------------------------------------------------

    private var introduction: some View {
        SectionCard(title: "Comment travaille MonitorMyMac",
                    subtitle: "Le même contrat partout : mesurer, proposer, laisser l'utilisateur choisir, agir de façon réversible et rendre compte honnêtement.",
                    systemImage: "questionmark.circle.fill",
                    accent: .blue) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach([
                    "1. Balayage : l'app lit le système avec des commandes officielles et des API Foundation ; elle ne devine jamais une taille.",
                    "2. Examen : chaque résultat affiche son chemin, sa taille réelle, son risque et l'avertissement qui l'accompagne.",
                    "3. Choix : rien n'est coché par défaut si le risque est « à vérifier » ; la sélection est explicite, élément par élément.",
                    "4. Action : corbeille par défaut, politique de sécurité appliquée au moment de l'acte, et rapport final listant succès, échecs et refus."
                ], id: \.self) { step in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: ("circlebadge.fill").mmSafeSymbol)
                            .font(.system(size: 7))
                            .foregroundColor(.blue)
                        Text(step)
                            .font(.system(size: 11))
                            .foregroundColor(Color.mmSecondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var shortcutsCard: some View {
        SectionCard(title: "Raccourcis et barre de menus",
                    subtitle: "Tout est accessible sans ouvrir l'espace correspondant.",
                    systemImage: "command", accent: .purple) {
            // Deux blocs distincts : un `@ViewBuilder` SwiftUI n'accepte que dix
            // enfants, et la liste complète des raccourcis en dépasse largement le compte.
            VStack(alignment: .leading, spacing: 6) {
                Text("Les quatre espaces")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color.mmTertiaryLabel)
                shortcutRow("⌘⇧1", "Espace Purge")
                shortcutRow("⌘⇧2", "Espace Performance")
                shortcutRow("⌘⇧3", "Espace Applications")
                shortcutRow("⌘⇧4", "Espace Sécurité")
                shortcutRow("⌘⇧M", "Déplier ou replier les jauges de surveillance")
                shortcutRow("⌘⇧H", "Ouvrir ou refermer le tiroir Aide / FAQ / À propos")
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Les actions")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color.mmTertiaryLabel)
                shortcutRow("⌘⇧N", "Nettoyage express (temp, caches, logs, corbeille)")
                shortcutRow("⌘⇧O", "Repérer les fichiers volumineux (liste seule, rien n'est supprimé)")
                shortcutRow("⌘⇧P", "Balayage complet de la Purge")
                shortcutRow("⌘⇧R", "Purger la RAM (authentification administrateur)")
                shortcutRow("⌘⇧A", "Inventaire des applications")
                shortcutRow("⌘⇧X", "Inventaire des extensions")
                shortcutRow("⌘⇧S", "Balayage des données de navigation")
            }
            Divider()
            Text("L'icône de la barre de menus garde le pourcentage CPU visible en permanence et propose les mêmes actions, fenêtre fermée. Le rappel hebdomadaire (dimanche 10 h) s'active depuis l'espace Purge, sous la carte d'action.")
                .font(.system(size: 10))
                .foregroundColor(Color.mmSecondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func shortcutRow(_ keys: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text(keys)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.gray.opacity(0.15)))
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(Color.mmSecondaryLabel)
            Spacer()
        }
    }

    private var availabilityCard: some View {
        let names = AppScreenshot.availableNames()
        return SectionCard(title: "Captures d'écran de cette aide",
                           subtitle: names.isEmpty
                               ? "Aucune capture n'est embarquée dans le bundle : les images sont remplacées par une notice, jamais par une illustration inventée."
                               : "\(names.count) capture(s) réelle(s) sur 8 disponibles : \(names.joined(separator: ", ")).",
                           systemImage: "camera.fill", accent: .gray) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pour (re)produire les captures depuis l'application réelle :")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.mmSecondaryLabel)
                HStack(spacing: 6) {
                    Text("./build.sh --shots")
                        .font(.system(size: 11, design: .monospaced))
                        .mmTextSelection()
                    Spacer()
                    CopyButton(text: "./build.sh --shots", title: "Copier la commande")
                }
                Text("Chaque espace est ouvert, ses balayages sont lancés, puis la fenêtre est photographiée par AppKit (`cacheDisplay`) et écrite dans docs/screenshots/.")
                    .font(.system(size: 10))
                    .foregroundColor(Color.mmSecondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Carte d'un sujet d'aide : capture + fonctionnement + commandes + limites.
struct HelpTopicCard: View {
    let topic: HelpTopic

    var body: some View {
        SectionCard(title: topic.title,
                    subtitle: topic.caption,
                    systemImage: topic.icon,
                    accent: topic.accent) {
            VStack(alignment: .leading, spacing: 10) {
                AppScreenshot(name: topic.screenshot, caption: topic.caption)
                bulletBlock("Comment ça marche", items: topic.how, icon: "chevron.right.circle", color: topic.accent)
                bulletBlock("Commandes réellement appelées", items: topic.commands, icon: "terminal", color: .secondary)
                HonestyNotes(notes: topic.limits)
            }
        }
    }

    private func bulletBlock(_ title: String, items: [String], icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.mmSecondaryLabel)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: (icon).mmSafeSymbol)
                        .font(.system(size: 9))
                        .foregroundColor(color)
                    Text(item)
                        .font(.system(size: 10))
                        .foregroundColor(Color.mmSecondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// ============================================================================
//  MARK: - FAQ
// ============================================================================

/// Question/réponse de la FAQ.
struct FAQEntry: Identifiable {
    var id: String { question }
    let question: String
    let answer: String
    let section: String
}

/// Onglet « FAQ » : réponses courtes aux questions réellement posées.
struct FAQTabView: View {
    @State private var filter = ""

    var body: some View {
        VStack(spacing: 16) {
            SectionCard(title: "Questions fréquentes",
                        subtitle: "\(FAQTabView.questions.count) réponses, chacune issue du comportement réel du code et des commandes système.",
                        systemImage: "questionmark.bubble.fill",
                        accent: .mmTeal,
                        trailing: {
                            Pill(text: "\(visible.count) affichée(s)", color: .mmTeal)
                        }) {
                HStack(spacing: 8) {
                    Image(systemName: ("magnifyingglass").mmSafeSymbol)
                        .font(.system(size: 11))
                        .foregroundColor(Color.mmTertiaryLabel)
                    TextField("Rechercher (« corbeille », « FileVault », « Mail »…)", text: $filter)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)))
            }

            ForEach(visible) { entry in
                FAQRow(entry: entry)
            }
            if visible.isEmpty {
                Card {
                    Text("Aucune réponse ne contient « \(filter) ».")
                        .font(.system(size: 11))
                        .foregroundColor(Color.mmSecondaryLabel)
                }
            }
        }
    }

    private var visible: [FAQEntry] {
        guard !filter.isEmpty else { return FAQTabView.questions }
        let needle = filter.lowercased()
        return FAQTabView.questions.filter {
            $0.question.lowercased().contains(needle) || $0.answer.lowercased().contains(needle)
        }
    }

    static let questions: [FAQEntry] = [
        FAQEntry(question: "La purge de la RAM ne rend presque rien : est-ce un bug ?",
                 answer: "Non. `purge` ne peut libérer que les pages inactive et le cache disque ; les pages câblées (noyau) et compressées restent utilisées. macOS rend de toute façon les pages inactives dès qu'une application en a besoin. La valeur affichée est la mesure avant/après réelle, pas une estimation.",
                 section: "Performance"),
        FAQEntry(question: "Pourquoi les corbeilles des volumes externes refusent-elles le vidage ?",
                 answer: "Parce que /Volumes/<disque>/.Trashes appartient à root (mode d-wx--x--t) : votre utilisateur ne peut ni la lister ni y écrire. L'app le detecte, affiche l'erreur réelle et propose le bouton « Corbeilles des volumes (admin) », qui passe par l'invite d'authentification macOS.",
                 section: "Purge"),
        FAQEntry(question: "Les fichiers de traduction inutiles sont listés mais non supprimables, pourquoi ?",
                 answer: "Retirer un .lproj d'un bundle casse sa signature de code : Gatekeeper refusera ensuite de lancer l'application, parfois de façon définitive sans reconstruction. La section reste donc en « rapport seul », avec la taille économisable, pour que vous décidez vous-même avec les outils de l'éditeur.",
                 section: "Purge"),
        FAQEntry(question: "MonitorMyMac peut-il vider l'historique de Firefox ?",
                 answer: "Pas l'historique seul. Dans Firefox, l'historique vit dans `places.sqlite` en même temps que vos signets : une suppression du fichier effacerait aussi les signets. L'app épargne donc ce fichier et propose la page officielle de purge du navigateur. Les caches, cookies et stockage local, eux, sont bien supprimables.",
                 section: "Sécurité"),
        FAQEntry(question: "Certaines zones sont annoncées « illisibles » : est-ce un manque de l'app ?",
                 answer: "C'est macOS qui protège ces répertoires (TCC). Accordez l'Accès complet au disque dans Réglages ▸ Confidentialité et sécurité ▸ Accès complet au disque, puis relancez le balayage. Sans cette autorisation, l'affiche un chiffre réel de 0 et la mention « protégé » : elle ne devine jamais une taille.",
                 section: "Sécurité"),
        FAQEntry(question: "Le broyeur garantit-il que personne ne récupérera le fichier ?",
                 answer: "Sur un disque dur mécanique chiffré ou non, l'écrasement multi-passes fonctionne. Sur APFS/SSD, le copy-on-write écrit les nouvelles données dans d'autres blocs, le TRIM et les instantanés Local Time Machine peuvent conserver l'ancien contenu. La seule garantie robuste pour des données sensibles reste le chiffrement du volume (FileVault) : le fichier devient alors illisible une fois son bloc supprimé.",
                 section: "Sécurité"),
        FAQEntry(question: "Où va un fichier « supprimé » par MonitorMyMac ?",
                 answer: "En mode par défaut, à la corbeille de l'utilisateur (via l'API officielle `FileManager.trashItem`) : vous pouvez la restaurer. En mode « Effacement direct », il est supprimé sans passer par la corbeille. La quarantaine, elle, déplace l'élément dans ~/Library/Application Support/MonitorMyMac/Quarantine avec un manifeste JSON indiquant le chemin d'origine, pour restauration.",
                 section: "Général"),
        FAQEntry(question: "Comment remettre un élément de démarrage que j'ai désactivé ?",
                 answer: "Bouton « Réactiver » dans l'espace Performance : le plist .mmm-off est renommé, puis `launchctl bootstrap` le recharge. Vous pouvez aussi renommer le fichier vous-même dans le Finder. Rien n'est supprimé pendant cette opération.",
                 section: "Performance"),
        FAQEntry(question: "Pourquoi une désinstallation laisse-t-elle des fichiers derrière elle ?",
                 answer: "L'espace Applications liste les résidus trouvés au nom exact de l'identifiant de bundle. Les fichiers écrits dans un dossier partagé par l'éditeur (par exemple ~/Library/Application Support/Google) ne sont jamais supprimés avec une seule application : ce serait destructeur pour les autres produits du même éditeur. Ils restent visibles pour un contrôle manuel.",
                 section: "Applications"),
        FAQEntry(question: "MonitorMyMac installe-t-il des mises à jour à ma place ?",
                 answer: "Non, volontairement. `softwareupdate --install` exige des droits administrateur et peut redémarrer la machine ; l'App Store impose une session authentifiée. L'app liste ce qui est disponible (sortie brute de `softwareupdate --list` conservée), et les canaux invérifiables hors application (Electron, utilitaires tiers) sont explicitement marqués « à contrôler vous-même ».",
                 section: "Applications"),
        FAQEntry(question: "Mon antivirus préféré trouverait-il ce que MonitorMyMac signale ?",
                 answer: "Pas nécessairement. Le moteur local utilise des signatures documentées et des heuristiques (exécutable planqué dans un cache, extension système non Apple, item de démarrage orphelin). Il donne des indices, pas un verdict certifié, et aucun laboratoire n'a audité cette détection. Pour une contamination avérée, faites appel à un outil de sécurité professionnel.",
                 section: "Sécurité"),
        FAQEntry(question: "Les notifications de rappel ne s'affichent pas ?",
                 answer: "Elles dépendent des autorisations de notification accordées à l'application (Réglages ▸ Notifications) et du fait que le rappel doit être activé dans l'espace Purge, sous la carte d'action. Si macOS refuse l'autorisation, aucune notification n'est programmée : l'interrupteur reste sans effet.",
                 section: "Général"),
        FAQEntry(question: "L'application envoie-t-elle des données quelque part ?",
                 answer: "Aucune. MonitorMyMac est un binaire natif SwiftUI sans dépendance réseau : tout est lu et traité localement, avec les outils déjà présents sur macOS. Le code source est court, lisible et compilable sans Xcode.",
                 section: "Général")
    ]
}

/// Une réponse dépliable de la FAQ.
struct FAQRow: View {
    let entry: FAQEntry
    @State private var open = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { open.toggle() }
                } label: {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: (open ? "chevron.down.circle.fill" : "chevron.right.circle.fill").mmSafeSymbol)
                            .font(.system(size: 12))
                            .foregroundColor(Color.mmSecondaryLabel)
                        Text(entry.question)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Pill(text: entry.section, color: .mmTeal)
                    }
                }
                .buttonStyle(.plain)
                .help(open ? "Replier la réponse." : "Déplier la réponse.")
                if open {
                    Text(entry.answer)
                        .font(.system(size: 11))
                        .foregroundColor(Color.mmSecondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 21)
                        .mmTextSelection()
                }
            }
        }
    }
}

// ============================================================================
//  MARK: - À propos
// ============================================================================

/// Onglet « À propos » : identité, architecture, sources réelles et limites.
struct AboutTabView: View {
    var body: some View {
        VStack(spacing: 16) {
            identityCard
            architectureCard
            sourcesCard
            limitsCard
            buildCard
        }
    }

    private var identityCard: some View {
        SectionCard(title: "MonitorMyMac \(AppInfo.version)",
                    subtitle: AppInfo.tagline,
                    systemImage: "macbook.and.iphone", accent: .blue) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    AppScreenshot(name: "08-apropos", caption: "Capture de la fenêtre À propos.", maxHeight: 180)
                    // Marque de fabrique : l'icône réelle de l'application, la
                    // même que dans le Dock. Les icônes fonctionnelles restent
                    // des SF Symbols ; seuls les visuels de marque portent ce
                    // rendu « verre liquide » issu des planches fournies.
                    VStack(spacing: 6) {
                        MMBrandIcon(tile: "AppIcon", accent: .purple, size: 56,
                                    fallbackSymbol: "macbook.and.iphone")
                        Text("Universel 2")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color.mmTertiaryLabel)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        aboutRow("Auteur", AppInfo.author)
                        aboutRow("Version", AppInfo.version)
                        aboutRow("Licence", AppInfo.licence)
                        aboutRow("Système", AppInfo.supports)
                        aboutRow("Architecture", AppInfo.architecture)
                        aboutRow("Langage", AppInfo.language)
                    }
                }
                Text(AppInfo.description)
                    .font(.system(size: 11))
                    .foregroundColor(Color.mmSecondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func aboutRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(key)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.mmSecondaryLabel)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.system(size: 10))
                .mmTextSelection()
        }
    }

    private var architectureCard: some View {
        SectionCard(title: "Architecture du projet",
                    subtitle: "Couches séparées : des moteurs qui parlent au système, des modèles qui orchestrent, des vues qui n'affichent que ce qu'elles ont reçu.",
                    systemImage: "square.3.layers.3d.down.right", accent: .purple) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(AppInfo.layers, id: \.self) { layer in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: ("square.fill").mmSafeSymbol)
                            .font(.system(size: 6))
                            .foregroundColor(.purple)
                        Text(layer)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color.mmSecondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var sourcesCard: some View {
        SectionCard(title: "Sources de données réelles",
                    subtitle: "Chaque chiffre affiché vient de l'une de ces lectures ; aucune valeur n'est simulée.",
                    systemImage: "point.3.connected.trianglepath.dotted", accent: .green) {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(AppInfo.sources, id: \.self) { source in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: ("checkmark.seal.fill").mmSafeSymbol)
                            .font(.system(size: 9))
                            .foregroundColor(.green)
                        Text(source)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color.mmSecondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var limitsCard: some View {
        SectionCard(title: "Ce que cette application ne fait pas",
                    subtitle: "Liste assumée : préférer une porte fermée à une promesse fausse.",
                    systemImage: "hand.raised.fill", accent: .red) {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(AppInfo.refusals, id: \.self) { item in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: ("xmark.octagon.fill").mmSafeSymbol)
                            .font(.system(size: 9))
                            .foregroundColor(.red)
                        Text(item)
                            .font(.system(size: 10))
                            .foregroundColor(Color.mmSecondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var buildCard: some View {
        SectionCard(title: "Compiler et tester",
                    subtitle: "Commandes exactes, sans Xcode.",
                    systemImage: "hammer.fill", accent: .gray) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(AppInfo.commands, id: \.self) { command in
                    HStack(spacing: 8) {
                        Text(command)
                            .font(.system(size: 10, design: .monospaced))
                            .mmTextSelection()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        CopyButton(text: command)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.06)))
                }
                Text("Merci d'avoir lu jusqu'ici. MonitorMyMac est un projet personnel : chaque module a été écrit, compilé et exécuté sur la machine de son auteur.")
                    .font(.system(size: 10))
                    .foregroundColor(Color.mmSecondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Métadonnées affichées dans l'onglet À propos.
enum AppInfo {
    static let version = "3.0.0"
    static let tagline = "Surveillance, purge, performance, applications et sécurité — 100 % natif, aucune donnée envoyée."
    static let author = "Martial Zinsou"
    static let licence = "MIT (voir LICENSE)"
    static let supports = "macOS 11.0 (Big Sur) et suivants — binaire Universel 2 (Intel x86_64 + Apple Silicon arm64). Tranche Intel exécutée et mesurée ; tranche arm64 compilée sur cette machine Intel, donc non exécutée ici."
    static let architecture = "Application de barre de menus + fenêtre SwiftUI ; deux tranches compilées puis assemblées par `lipo`, sans framework tiers"
    static let language = "Swift 5.8, SwiftUI + AppKit + UserNotifications"
    static let description = """
    MonitorMyMac applique un contrat simple : mesurer avec les commandes officielles de macOS, montrer le chemin et la taille réels, \
    laisser l'utilisateur cocher, puis agir de façon réversible par défaut et rendre un compte rendu fidèle — succès, échecs et refus compris. \
    Les quatre familles demandées (stockage, performances, applications, sécurité) sont implémentées, avec les fenêtres Aide, FAQ et À propos.
    """

    static let layers = [
        "src/Core/MMUtility.swift — Shell, Fmt, PathPolicy, Walker, DeleteOps, Hash, Quarantine, PrivacyAccess",
        "src/Core/PurgeEngine.swift + PurgeModel.swift — sept balayages et l'orchestration « balayer → cocher → agir »",
        "src/Core/PerformanceEngine.swift + PerformanceModel.swift — mémoire, processus, démarrage, scripts",
        "src/Core/AppManagerEngine.swift + AppsModel.swift — bundles, résidus, mises à jour, extensions",
        "src/Core/SecurityEngine.swift + SecurityModel.swift — traces, signatures, posture, broyeur",
        "src/UI/*.swift — thème, quatre espaces + page Surveillance, Aide/FAQ/À propos et mode capture",
        "src/MonitorMyMacApp.swift — SystemMonitor, barre de menus, raccourcis clavier, point d'entrée"
    ]

    static let sources = [
        "top · vm_stat · sysctl (hw.memsize, hw.pagesize, vm.swapusage) · df -h",
        "ps -Aceo pid,user,pcpu,pmem,rss,comm -r · top -o power · NSRunningApplication",
        "launchctl list/bootout/bootstrap · plist LaunchAgents & LaunchDaemons",
        "pluginkit -m -A -v · systemextensionsctl list · manifestes de navigateurs",
        "softwareupdate --list · brew outdated (si Homebrew présent)",
        "codesign --verify · spctl --assess · csrutil status · fdesetup status",
        "mdutil -s/-E · diskutil verifyVolume/repairPermissions · lsregister · dscacheutil · periodic",
        "FileManager (taille allouée réelle) · CryptoKit SHA-256 · FileHandle pour l'écrasement"
    ]

    static let refusals = [
        "Ne supprime jamais un composant de /System, /usr, /bin, /sbin ou /private/var/db.",
        "Ne supprime pas les traductions .lproj (casse la signature du code).",
        "Ne touche pas aux signets, mots de passe, trousseau ni au places.sqlite de Firefox.",
        "N'installe aucune mise à jour et ne télécharge rien depuis Internet.",
        "N'est pas un antivirus certifié et n'a été audité par aucun laboratoire.",
        "Ne promet pas l'irrécupérabilité sur APFS/SSD : FileVault reste la seule vraie garantie.",
        "N'enverra jamais de télémétrie : aucune classe réseau n'est liée au binaire."
    ]

    static let commands = [
        "./build.sh                       # deux tranches (-target …-macosx11.0), lipo, signature, contrôles",
        "./build.sh --typecheck           # typage SDK par défaut + cible macOS 11.0 sur x86_64 et arm64",
        "./build.sh --shots               # lance l'app et génère docs/screenshots/*.png",
        "./build.sh --zip                 # MonitorMyMac.app.zip + contrôle aller-retour de la signature",
        "lipo -info MonitorMyMac.app/Contents/MacOS/MonitorMyMac   # doit annoncer « x86_64 arm64 »",
        "./MonitorMyMac --tab=purge --help  # ouverture directe d'une destination (surveillance, purge,"
            + " performance, applications, securite, aide, faq, apropos)"
    ]
}
