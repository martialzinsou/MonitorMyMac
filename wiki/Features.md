# MonitorMyMac — Fonctionnalités détaillées (v3.0.0)

L'application est organisée en **quatre espaces de travail** — Purge, Performance, Applications, Sécurité — surmontés d'un **bandeau de surveillance ambiant** et doublés d'un **tiroir de documentation** (Aide illustrée, FAQ, À propos). Huit destinations au total, aucune à plus d'un clic. Tout est natif (SwiftUI + AppKit + UserNotifications), sans framework tiers, sans réseau et sans télémétrie, et rendu sur une seule interface identique de macOS 11 à macOS 15.

Un principe traverse les quatre familles : **mesurer → montrer le chemin et la taille réels → laisser cocher → agir de façon réversible → rendre un compte rendu fidèle** (succès, échecs et refus).

---

## 📊 Surveillance

- **Jauges annulaires** Processeur, Mémoire, Stockage.
- **Processeur** : nom exact et nombre de cœurs (`sysctl machdep.cpu.brand_string`, `hw.logicalcpu`).
- **Mémoire** : totale, active, câblée, compressée, récupérable, échange (`vm_stat`).
- **Stockage** : utilisé / disponible sur `/` (`df -h /`).
- **Système** : modèle (`system_profiler SPHardwareDataType`), version macOS, durée d'activité (`uptime`).
- **Historique temps réel** : deux courbes CPU / RAM sur 60 points, échantillonnage toutes les 2 s.
- Les mesures s'exécutent **hors du fil principal**, avec un verrou `metricsInFlight` / `deviceInFlight` qui empêche deux mesures simultanées ; les valeurs publiées reviennent sur le fil principal.

## 🧹 Purge (nettoyage du stockage)

Sept familles balayées, chacune en carte distincte avec taille et nombre d'éléments mesurés :

1. **Caches utilisateur** — `~/Library/Caches`, fichiers de plus de `cacheAgeDays` (7 j par défaut).
2. **Logs, historiques et diagnostics** — logs utilisateur, rapports d'incident, état des applications (`junkAgeDays`, 7 j).
3. **Restes de mises à jour** — installateurs oubliés et caches de distribution.
4. **Traductions inutilisées (.lproj)** — estimation **théorique** seulement : l'application **refuse** de supprimer un `.lproj`, parce que retirer une langue casse la signature de code et déclenche Gatekeeper. La ligne est informative.
5. **Fichiers volumineux et anciens** — `> largeMinSizeMB` (100 Mo) et `> largeMinAgeDays` (90 j).
6. **Doublons** — regroupement par taille puis empreinte **SHA‑256** (CryptoKit), à partir de `duplicateMinSizeMB` (5 Mo), dans Photos / Musique / Documents ; le gain indiqué est celui de tous les exemplaires sauf le plus ancien.
7. **Corbeilles** — corbeille principale, corbeilles des volumes montés, de Mail et des applications spécifiques.

**Rappel hebdomadaire** : interrupteur → notification chaque dimanche à 10 h ; y cliquer lance le nettoyage express.

## 🚀 Performance

- **Libération de la RAM** : lecture réelle de `vm_stat`, puis `purge` demandé via `osascript … with administrator privileges` (jamais en tâche de fond silencieuse).
- **Éléments de démarrage** : inventaire `launchctl` + `LoginItems`, typés (`LoginItemKind`), avec activation/désactivation et origine.
- **Scripts de maintenance** : vérifier l'indexation Spotlight, réindexer Spotlight, vérifier le volume de démarrage, réparer les autorisations des fichiers système, reconstruire la base Launch Services, purger le cache DNS, exécuter les scripts périodiques, purger les logs système archivés, vider les corbeilles des volumes. Chaque tâche déclare son `AdminRequirement` ; celles qui exigent un mot de passe l'affichent **avant** l'exécution.
- **Processus gourmands** : classement par CPU et par énergie (`top -o power`, `ps -Aceo`), avec `StatLine` et `AppConsumption`.

## ⚙️ Applications

- **Inventaire** : `/Applications` (et dossiers utilisateur), taille réelle du package, version, éditeur, date d'installation.
- **Désinstallation complète** : `AppManagerEngine` + `ResidualScanner` listent les résidus `~/Library` (Caches, Preferences, Application Support, Saved State, Containers, Logs) **avant** toute action ; les paquets protégés par `PathPolicy.packageExtensions` ne sont jamais traversés.
- **Mises à jour centralisées** : `softwareupdate --list` et `brew outdated`, agrégés en `UpdateAudit` / `AvailableUpdate`.
- **Extensions** : `pluginkit` et `systemextensionsctl` pour les plug‑ins, widgets et extensions système (`PluginEntry`, `PluginState`) ; extensions de navigateurs détectées sur disque (`BrowserExtension`).

## 🔒 Sécurité

- **Données de navigation** : par navigateur et par nature — cookies, historique, cache, stockage local, téléchargements temporaires. Safari, Chrome, Edge, Brave, Opera, Firefox. Un navigateur **ouvert** est signalé par une bannière et ses fichiers vivants sont écartés. **Firefox** : `places.sqlite`, signets, mots de passe et trousseaux ne sont **jamais** touchés. L'accès est soumis à TCC (accès complet au disque).
- **Analyse anti‑malware** : sans base de signatures à jour à distance, l'application applique des règles locales — emplacements sensibles (`/Library/LaunchAgents`, `/Library/LaunchDaemons`, `/Library/PreferencePanes`, `/Library/Internet Plug-Ins`, `/Library/StartupItems`, `/Library/Screen Savers`, `/Users/Shared`), lancements cachés (commande pointant vers `/private/var/folders`, `/tmp/`, `/Library/.`), applications non signées ou refusées par `spctl`, extensions système tierces, plug‑ins de navigateurs suspects. Trois niveaux : *signature connue*, *comportement suspect*, *information*.
- **Contrôle d'intégrité** : `codesign --verify`, `spctl --assess`, `csrutil status` (SIP), `fdesetup status` (FileVault), `mdutil -s` (indexation).
- **Quarantaine** : déplacement réversible plutôt que suppression.
- **Broyeur de fichiers** : écrasement (1, 3 ou 7 passes : zéros, aléatoire, zéros) puis troncature et `unlink`. L'application est **honnête sur la limite** : sur APFS/SSD, l'écrasement logique ne garantit pas l'effacement physique, et `rm -P` échoue avec « Operation not permitted » sur les systèmes de fichiers qui ne le garantissent pas. Le broyage protège contre la récupération logicielle courante, pas contre un laboratoire.

## 📖 Aide, FAQ, À propos

- **Aide** : un topic par famille — fonctionnement réel, chemin des données, limites connues — et une **capture d'écran embarquée** lue depuis `Contents/Resources/Screenshots` du bundle.
- **FAQ** : 13 questions/réponses, dont « que supprime vraiment cette option ? », « pourquoi un mot de passe administrateur ? », « pourquoi l'app refuse-t-elle certaines suppressions ? ».
- **À propos** : version, auteur, licence, pile technique, couches d'architecture, table des raccourcis clavier et note d'honnêteté sur ce qui a été testé.

## 🖥 Barre de menus

Icône `NSStatusItem` avec pourcentage CPU et mini‑sparkline ; menu = état, CPU / RAM / Disque, « Nettoyage rapide », « Repérer les fichiers volumineux », et sous‑menu **« Ouvrir une section »** organisé comme la fenêtre : les quatre espaces, le dépliage des jauges, la page Surveillance complète, puis les trois pages de documentation. Chaque entrée porte une info‑bulle.

Les deux actions rapides appellent les mêmes `runCleanup()` et `runOptimization()` que le menu **Actions** de la fenêtre ; elles affichent `⌘N` et `⌘O` dans leur colonne de droite parce qu'un `NSMenuItem` rend toujours son équivalent‑clavier, mais ce menu est celui du `NSStatusItem` et non le menu principal : les raccourcis de la fenêtre restent `⌘⇧N` et `⌘⇧O`.

## ⌨️ Raccourcis clavier

Deux menus de commandes complètent l'interface (les destinations s'atteignent aussi par les pastilles, le bandeau, le tiroir « ? » et le sous‑menu « Ouvrir une section » de la barre de menus) :

| Raccourci | Menu | Action |
|---|---|---|
| `⌘⇧1` | Navigation | Espace Purge |
| `⌘⇧2` | Navigation | Espace Performance |
| `⌘⇧3` | Navigation | Espace Applications |
| `⌘⇧4` | Navigation | Espace Sécurité |
| `⌘⇧M` | Navigation | Déplier / replier les jauges de surveillance |
| `⌘⇧H` | Navigation | Ouvrir / refermer le tiroir Aide · FAQ · À propos |
| `⌘⇧N` | Actions | Nettoyage express (les trois premières collectes vont à la corbeille, la quatrième la vide) |
| `⌘⇧O` | Actions | Repérer les fichiers volumineux (liste seule, rien n'est supprimé) |
| `⌘⇧P` | Actions | Balayer la purge (7 familles) |
| `⌘⇧R` | Actions | Purger la RAM |
| `⌘⇧A` | Actions | Inventorier les applications |
| `⌘⇧X` | Actions | Inventorier les extensions |
| `⌘⇧S` | Actions | Balayer les données de navigation |

Les menus sont scindés en « Actions » et « Navigation » parce que `@ViewBuilder` est limité à 10 enfants — la limite est atteinte, et un onzième enfant se signale par une erreur de typage.

`⌘⇧X` a remplacé `⌘⇧M` pour l'inventaire des extensions : `⌘⇧M` sert désormais au bandeau de surveillance. Les deux menus portent un `keyEquivalent` vide dans la barre d'état, une application-agent n'enregistrant pas de raccourcis globaux ; les raccourcis affichés vivent dans les `CommandMenu` SwiftUI.

## 🛡 Ce que l'application refuse volontairement

`PathPolicy.deniedPrefixes` bloque `/System`, `/usr`, `/bin`, `/sbin`, `/etc`, `/private/etc`, `/private/var/db`, `/private/var/root`, `/Volumes`, `/Library`, `/Applications`, `/opt`, `/private/var/vm`, `/private/var/log`, `/private/tmp` pour toute suppression non demandée. `deniedHomeSubpaths` protège Mail, Keychains, Messages, Calendars, Contacts, MobileSync, Health, HomeKit, l'Address Book et les préférences de connexion. Toute suppression passe par `FileManager.trashItem` (réversible) sauf choix explicite du broyeur.

---
Auteur : **Martial Zinsou**
