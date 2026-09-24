# MonitorMyMac — Wiki du projet

## Vue d'ensemble

**MonitorMyMac** est une application **native macOS** élégante et conviviale qui vous permet de **surveiller**, **nettoyer** et **optimiser** votre Mac en un clin d'œil — directement depuis sa **barre de menus**.

- **Version actuelle** : v2.1.0
- **Auteur** : Martial Zinsou
- **Licence** : MIT
- **Technologies** : SwiftUI, Swift, CommandLineTools (pas d'Xcode complet)
- **Compatibilité** : macOS 10.15+, Intel & Apple Silicon (M1/M2/M3)

## Captures d'écran

| # | Capture | Description |
|---|---|---|
| 1 | ![Surveillance](docs/screenshots/01-panel-surveillance.png) | Onglet **Surveillance** : jauges CPU/RAM animées, cartes système, historique temps réel (2 courbes : bleu = CPU, violet = RAM). |
| 2 | ![Nettoyage](docs/screenshots/02-panel-nettoyage.png) | Onglet **Nettoyage** : bouton « Nettoyage intelligent », pastilles de portée (Temp > 60 min, Caches > 2 h, Corbeille), interrupteur rappel hebdomadaire (dimanche 10 h). |
| 3 | ![Optimisation](docs/screenshots/03-panel-optimisation.png) | Onglet **Optimisation** : bouton « Analyse de l'espace », liste des fichiers > 100 Mo dans Téléchargements/Documents/Bureau. |
| 4 | ![Barre de menus](docs/screenshots/04-menu-bar.png) | Icône **barre de menus** : affichage CPU en direct (ex. « 23 % »), menu déroulant avec actions rapides (⌘⇧N Nettoyage, ⌘⇧O Optimisation, Quitter). |
| 5 | ![Aide](docs/screenshots/05-panel-aide.png) | Fenêtre **Aide** illustrée (bouton `?` dans l'en-tête) : descriptions détaillées de chaque fonctionnalité avec symboles SF Symbols. |

> **Astuce** : pour ajouter de nouvelles captures, lancer l'application, accéder à l'écran souhaité, puis utiliser `screencapture -l <ID_FENÊTRE> wiki/screenshots/06-nouvelle.png`.

---

## Diagrammes UML

### 1. Diagramme de classes

```mermaid
classDiagram
    class MonitorMyMacApp {
        +body: some Scene
    }
    class SystemMonitor {
        <<ObservableObject>>
        +cpuUsage: Double
        +memoryUsage: Double
        +diskUsage: Double
        +cpuHistory: [Double]
        +memoryHistory: [Double]
        +remindersEnabled: Bool
        +startLiveUpdates()
        +refreshMetrics()
        +runCleanup()
        +runOptimization()
    }
    class MenuBarDelegate {
        <<NSObject, singleton>>
        -statusItem: NSStatusItem
        +updateQuickStats()
        +applicationDidFinishLaunching()
    }
    class ContentView {
        -selectedTab: Tab
        -showHelp: Bool
    }
    class HelpView {
        +helpSection()
    }
    class GaugeCard
    class DiskCard
    class SystemCard
    class HistoryChartCard
    class HistoryChart
    class SparklinePath { <<Shape>> }
    class CleanupView
    class OptimizationView
    class ActionButton

    MonitorMyMacApp --> AppLifecycleDelegate : adapte
    MonitorMyMacApp --> ContentView : affiche
    ContentView --> SystemMonitor : observe
    ContentView --> GaugeCard : utilise
    ContentView --> DiskCard : utilise
    ContentView --> SystemCard : utilise
    ContentView --> HistoryChartCard : utilise
    ContentView --> CleanupView : onglet
    ContentView --> OptimizationView : onglet
    ContentView --> HelpView : sheet
    HistoryChartCard --> HistoryChart : contient
    HistoryChart --> SparklinePath : dessine
    SystemMonitor --> CPU : interroge
    SystemMonitor --> Memory : interroge
    SystemMonitor --> Disk : interroge
    SystemMonitor --> Device : interroge
    SystemMonitor --> Cleaner : exécute
    SystemMonitor --> Reminder : programme
    SystemMonitor --> MenuBarDelegate : met à jour
```

### 2. Diagramme de séquence — Nettoyage intelligent

```mermaid
sequenceDiagram
    autonumber
    actor U as Utilisateur
    participant V as CleanupView
    participant S as SystemMonitor
    participant C as Cleaner
    participant O as Journal

    U->>V: Clic « Nettoyage intelligent »
    V->>S: runCleanup()
    activate S
    S->>S: isProcessing = true
    S->>C: tempFiles() → /tmp (> 60 min)
    S->>C: userCaches() → ~/Library/Caches (> 2 h)
    S->>C: systemLogs() → /private/var/log (> 24 h)
    S->>C: trash() → ~/.Trash
    C-->>S: nombre d'éléments supprimés
    S->>O: Journal : « ✦ … supprimé(s) »
    S->>S: isProcessing = false, statut mis à jour
    S-->>V: done
    deactivate S
```

### 3. Diagramme d'états — cycle de vie du rafraîchissement

```mermaid
stateDiagram-v2
    [*] --> Démarrage : lancement (ou icône barre de menus)
    Démarrage --> Idle : refreshDeviceInfo() + snapshot
    Idle --> Mesure : Timer (toutes les 2 s)
    Mesure --> Idle : refreshMetrics() / historique mis à jour
    Idle --> Nettoyage : runCleanup()
    Nettoyage --> Idle : Journal alimenté, statut « ✓ »
    Idle --> Optimisation : runOptimization()
    Optimisation --> Idle : gros fichiers listés
    Idle --> [*] : Quitter (menu barre de menus / ⌘Q)
```

### 4. Diagramme de cas d'utilisation

```mermaid
flowchart LR
    U([Utilisateur]) --> S[Surveiller son Mac]
    U --> N[Nettoyer son Mac]
    U --> O[Optimiser l'espace disque]
    U --> R[Activer un rappel hebdomadaire]
    U --> Q[Accéder aux actions depuis la barre de menus]

    S --> S1[Voir CPU / RAM / Disque en temps réel]
    S --> S2[Consulter l'historique 2 min]
    N --> N1[Vider caches et fichiers temporaires]
    N --> N2[Vider la corbeille]
    O --> O1[Lister les fichiers > 100 Mo]
```

---

## Getting Started

### Installation

1. Téléchargez le dossier `MonitorMyMac`.
2. Placez-le dans votre dossier `Applications` (ou n'importe où sur votre disque).
3. Double-cliquez sur `MonitorMyMac.app` pour lancer l'application.

> **Astuce** : Si macOS bloque l'ouverture, faites un clic droit sur l'application puis choisissez **Ouvrir** pour autoriser l'exécution.

### Lancement et utilisation

À l'ouverture, l'application affiche immédiatement l'onglet **Surveillance** : les statistiques de votre Mac se mettent automatiquement à jour **toutes les 2 secondes**.

- Cliquez sur les onglets **Surveillance**, **Nettoyage**, **Optimisation** pour accéder aux fonctionnalités.
- Utilisez le bouton **?** dans l'en-tête pour ouvrir l'aide intégrée.
- L'icône **MonitorMyMac** reste visible dans la barre de menus en haut de l'écran.
- Raccourcis clavier : `⌘⇧N` (Nettoyage rapide), `⌘⇧O` (Optimisation rapide).

### Commandes CLI (optionnelles)

L'application bundle inclus un script bash `monitormymac.sh` utilisable en ligne de commande :

```bash
# Exemple : lancer directement l'onglet Nettoyage
./monitormymac.sh --tab=nettoyage

# Afficher l'aide
./monitormymac.sh --help
```

### Règles de développement

- L'application est construite avec `swiftc` (CommandLineTools Swift 5.8.1), sans Xcode complet.
- Pas d'accessibilité AppleScript (`osascript`) disponible — les captures d'écran se font via le helper `windowid` (CGWindowListCopyWindowInfo) + `screencapture -l <ID>`.
- Les métriques CPU/Mémoire/Disk sont récupérées via `/usr/sbin/system_profiler`, `/bin/df`, et des chemins système internes.
- Le minuteur de rafraîchissement interne est de **2 secondes**.
- Les historiques CPU/RAM conservent **60 points** (soit 2 minutes à 2 s par point). Une extension vers 1800 points (1 h) est prévue dans `metricRecords`.

---

## Auteur

**Martial Zinsou** — Développeur et auteur de MonitorMyMac.

- Repo GitHub : <https://github.com/martialzinsou/MonitorMyMac>
- Ce wiki est généré à partir des fichiers `docs/` et `wiki/` du dépôt.
- Toute modification ou contribution : ouvrir une issue ou forker le dépôt.

---