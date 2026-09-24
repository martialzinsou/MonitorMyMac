# MonitorMyMac — Diagrammes UML

Cette section présente l'ensemble des diagrammes UML (Modélisation Unifiée du Langage) utilisés pour décrire l'architecture, le flux d'exécution et les cas d'utilisation de MonitorMyMac. Tous les diagrammes sont rédigés en **syntaxe Mermaid** et peuvent être visualisés directement sur GitHub (pages wiki ou fichiers `.md` du dépôt).

---

## 1. Diagramme de classes

Représente les principales classes et structures du projet, leurs responsabilités et leurs relations d'association, d'héritage et de dépendance.

```mermaid
classDiagram
    class MonitorMyMacApp {
        +body: some Scene
    }
    class SystemMonitor {
        <<ObservableObject, singleton>>
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
        -refreshTimer: Timer
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

---

## 2. Diagramme de séquence — Flux de nettoyage intelligent

Montre l'interaction pas à pas entre l'utilisateur, la vue de nettoyage, le moniteur système et le nettoyeur lorsqu'un nettoyage est déclenché.

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

---

## 3. Diagramme d'états — Cycle de vie du rafraîchissement

Montre les différents états que traverse l'application, depuis le lancement jusqu'à la sortie, en passant par le rafraîchissement périodique et les actions utilisateur.

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

---

## 4. Diagramme de cas d'utilisation

Montre les actions principales que l'utilisateur peut effectuer dans l'application, depuis l'interface utilisateur jusqu'aux fonctionnalités sous-jacentes.

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

## 5. Schéma d'architecture globale (vue d'ensemble)

```mermaid
graph TD
    subgraph "Interface Utilisateur"
        C[ContentView] -->|écoute| S[SystemMonitor]
        C -->|utilise| GC[GaugeCard]
        C -->|utilise| DC[DiskCard]
        C -->|utilise| SC[SystemCard]
        C -->|utilise| HCC[HistoryChartCard]
        C -->|onglet| CV[CleanupView]
        C -->|onglet| OV[OptimizationView]
        C -->|sheet| HV[HelpView]
    end

    subgraph "Services & Logique"
        SM[SystemMonitor] -->|interroge| CPU[CPU]
        SM -->|interroge| MEM[Memory]
        SM -->|interroge| DISK[Disk]
        SM -->|interroge| DEV[Device]
        SM -->|exécute| CLN[Cleaner]
        SM -->|programme| RM[Reminder]
        SM -->|met à jour| MBD[MenuBarDelegate]
    end

    subgraph "Barre de menus"
        MBD -->|icône+sparkline| NB[NSStatusItem]
        MBD -->|menu| MM[NSMenu]
    end

    style MonitorMyMacApp fill:#f9f9f9,stroke:#333,stroke-width:2px