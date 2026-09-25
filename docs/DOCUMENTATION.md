# Documentation Technique - MonitorMyMac

Documentation destinée aux développeurs souhaitant comprendre, modifier ou
étendre MonitorMyMac.

> **Auteur : Martial Zinsou**

---

## 1. Architecture

### 1.1 Vue d'ensemble

MonitorMyMac est une application **native macOS** écrite en **Swift + SwiftUI**.
Elle utilise exclusivement les utilitaires et frameworks système Apple
(`Process`, `FileManager`, `sysctl`, `vm_stat`, `df`, `system_profiler`...).
**Aucune dépendance tierce.**

```
┌────────────────────────────────────────────────────────────┐
│  MonitorMyMacApp  (@main, App + @NSApplicationDelegateAdaptor)
│  ├── AppLifecycleDelegate   → pont vers MenuBarDelegate.shared
│  ├── MenuBarDelegate        → NSStatusItem + menu + notifications
│  └── ContentView            (header / tabs / content / log)
│      ├── Surveillance → LazyVGrid de cartes (maison)       │
│      │     ├── GaugeCard   (anneau animé CPU/RAM)          │
│      │     ├── DiskCard    (barre de progression)          │
│      │     ├── SystemCard  (infos statiques)               │
│      │     └── HistoryChartCard (sparklines CPU/RAM)       │
│      ├── Nettoyage   → CleanupView (+ ActionButton)        │
│      └── Optimisation → OptimizationView (+ ActionButton)  │
│                                                              │
│  SystemMonitor (ObservableObject singleton)                 │
│  ├── Timer → refreshMetrics() toutes les 2 s                │
│  ├── cpuHistory/memoryHistory (60 points = 2 min)           │
│  ├── CPU.usage()      → top -l 1 -n 0 -s 0                 │
│  ├── Memory.usage()   → vm_stat + hw.memsize               │
│  ├── Disk.usage()     → df -h /                            │
│  ├── Device.*         → sysctl / system_profiler           │
│  ├── Cleaner.*        → find / rm / FileManager            │
│  └── Reminder.*       → UserNotifications (rappels)        │
└────────────────────────────────────────────────────────────┘
```

### 1.2 Flux d'exécution

1. `@main` démarre l'application ; `ContentView` apparaît.
2. `onAppear` appelle `monitor.startLiveUpdates()`.
3. Un `Timer` rafraîchit CPU / RAM / Disque toutes les 2 secondes.
4. L'utilisateur lance un nettoyage ou une optimisation via les onglets.
5. Les résultats sont ajoutés au **journal** et le statut est mis à jour.

### 1.3 Diagrammes UML

#### 1.3.1 Diagramme de classes

```mermaid
classDiagram
    class MonitorMyMacApp {
        +body: some Scene
    }
    class AppLifecycleDelegate {
        <<NSApplicationDelegate>>
        +applicationDidFinishLaunching()
    }
    class MenuBarDelegate {
        <<NSObject, singleton>>
        -statusItem: NSStatusItem
        +updateQuickStats()
        +applicationDidFinishLaunching()
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
    class CPU {
        <<enum>>
        +usage() Double
    }
    class Memory {
        <<enum>>
        +usage() Double
        +detail() String
    }
    class Disk {
        <<enum>>
        +usage() Double
        +detail() String
    }
    class Device {
        <<enum>>
        +osVersion() String
        +macModel() String
        +cpuModel() String
        +uptime() String
    }
    class Cleaner {
        <<enum>>
        +tempFiles() Int
        +userCaches() Int
        +systemLogs() Int
        +trash() Int
        +largeFiles() [String]
    }
    class Reminder {
        <<enum>>
        +scheduleWeeklyCleanup()
        +cancelWeeklyCleanup()
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
    class SparklinePath {
        <<Shape>>
    }
    class CleanupView
    class OptimizationView
    class ActionButton

    MonitorMyMacApp --> AppLifecycleDelegate : adapte
    MonitorMyMacApp --> MenuBarDelegate : adapte
    AppLifecycleDelegate --> MenuBarDelegate : délègue
    MenuBarDelegate --> SystemMonitor : lit les métriques
    MenuBarDelegate ..> Cleaner : notifications
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

#### 1.3.2 Diagramme de séquence — Nettoyage intelligent

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

#### 1.3.3 Diagramme d'états — cycle de vie du rafraîchissement

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

#### 1.3.4 Diagramme de cas d'utilisation

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

## 2. Code source commenté

Fichier : `src/MonitorMyMacApp.swift`

### 2.1 Structure du fichier

| Élément | Rôle |
|---|---|
| `SystemMonitor` | Service observable **singleton** au cœur de l'interface |
| `MenuBarDelegate` | `NSStatusItem` + menu déroulant + délégué notifications |
| `AppLifecycleDelegate` | Pont entre le cycle de vie SwiftUI et la barre de menus |
| `Metric` | Modèle d'une statistique (ratio 0...1) |
| `CPU` | Calcule le taux CPU à partir de `top` |
| `Memory` | Calcule la RAM utilisée via `vm_stat` |
| `Disk` | Calcule l'espace disque via `df` |
| `Device` | Informations statiques (modèle, macOS, uptime) |
| `Cleaner` | Opérations de nettoyage / optimisation |
| `Reminder` | Rappels hebdomadaires via `UserNotifications` |
| `ContentView` | Interface principale et navigation par onglets |
| `GaugeCard` / `DiskCard` / `SystemCard` | Cartes de surveillance |
| `HistoryChartCard` / `HistoryChart` / `SparklinePath` | Graphiques d'historique |
| `ActionButton` / `CleanupView` / `OptimizationView` | Vues d'action |

### 2.2 Points techniques importants

- **CPU** : `top -l 1 -n 0 -s 0` puis parse de la ligne `CPU usage: … idle`.
  La valeur est bornée entre 0 et 1.
- **Mémoire** : `vm_stat` renvoie les pages libres/inactives ; la mémoire totale
  vient de `hw.memsize` (`ProcessInfo.physicalMemory`).
- **Disque** : `df -h /` ; le taux est extrait de la colonne *Capacity*.
- **Nettoyage** : `find` retourne la liste des fichiers, puis
  `FileManager.removeItem` les supprime individuellement (gère les refus de
  permission avec `try?`).
- **Gestion des erreurs** : toutes les commandes passent par des fonctions
  sécurisées qui renvoient `nil` ou `0` en cas d'échec — l'interface ne plante
  jamais.

---

## 3. Compilation

### 3.1 Depuis la ligne de commande (sans Xcode)

```bash
swiftc -parse-as-library src/MonitorMyMacApp.swift \
  -framework SwiftUI -framework AppKit -framework UserNotifications \
  -o MonitorMyMac.app/Contents/MacOS/MonitorMyMac
```

> L'option `-parse-as-library` est **obligatoire** pour que `@main` fonctionne
> (le fichier contient du code top-level de documentation, pas exécutable).

### 3.2 Signature ad hoc (pour exécution locale)

```bash
codesign --force --deep --sign - MonitorMyMac.app
```

### 3.3 Avec Xcode

Créez un projet *macOS → App* (SwiftUI), remplacez `ContentView.swift` par le
contenu de `MonitorMyMacApp.swift` et définissez le minimum :

- **Deployment Target** : macOS 13.0
- **Bundle Identifier** : `com.monitormymac.app`

---

## 4. Bundle macOS (.app)

### 4.1 Structure

```
MonitorMyMac.app/
└── Contents/
    ├── Info.plist           # Configuration du bundle
    └── MacOS/
        └── MonitorMyMac      # Binaire natif SwiftUI
```

### 4.2 `Info.plist`

| Clé | Valeur |
|---|---|
| `CFBundleExecutable` | `MonitorMyMac` |
| `CFBundleIdentifier` | `com.monitormymac.app` |
| `CFBundleName` | `MonitorMyMac` |
| `CFBundleShortVersionString` / `CFBundleVersion` | `2.0` / `2.0.0` |
| `LSMinimumSystemVersion` | `10.15` |
| `LSApplicationCategoryType` | `public.app-category.utilities` |
| `NSHighResolutionCapable` | `true` |

---

## 5. Étendre MonitorMyMac

### Ajouter une métrique (ex : batterie)

```swift
enum Battery {
    static func level() -> Double {
        // system_profiler SPPowerDataType → "State of Charge"
        ...
    }
}
```

Puis affichez-la dans `monitoringGrid` à l'aide d'une `GaugeCard` :

```swift
GaugeCard(title: "Batterie", subtitle: monitor.modelInfo, icon: "battery.100",
          color: .green, ratio: Battery.level(), footer: "Niveau estimé")
```

### Ajouter une action de nettoyage

```swift
static func oldDownloads() -> Int {
    delete(in: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads").path,
           patterns: ["*"], olderThanMinutes: 43_200) // 30 jours
}
```

Puis intégrez-la dans `SystemMonitor.runCleanup()`.

---

## 6. Tests

### 6.1 Test manuel

```bash
open MonitorMyMac.app
```

Vérifications :
- Les jauges CPU / RAM / Disque bougent pendant l'activité.
- Le bouton « Nettoyage intelligent » remplit le journal.
- Le journal est vidé par « Effacer ».

### 6.2 Outil CLI (bonus)

`src/monitormymac.sh` est un outil en ligne de commande autonome :

```bash
bash -n src/monitormymac.sh      # valide la syntaxe
./src/monitormymac.sh            # exécution directe
```

---

## 7. Captures d'écran

> Toutes les captures d'écran ont été réalisées sur macOS (Retina 2880×1800) avec l'application MonitorMyMac en version **v2.1.0**, fenêtre principale affichée. Les fichiers PNG sont stockés dans `docs/screenshots/` et référencés via des chemins relatifs.

| N° | Capture | Description | Dimensions |
|---|---|---|---|
| 1 | ![Surveillance](screenshots/01-panel-surveillance.png) | Onglet **Surveillance** : jauges CPU/RAM animées, cartes système, historique temps réel (2 courbes : bleu = CPU, violet = RAM). | 1012 × 760 px |
| 2 | ![Nettoyage](screenshots/02-panel-nettoyage.png) | Onglet **Nettoyage** : bouton « Nettoyage intelligent », pastilles de portée (Temp > 60 min, Caches > 2 h, Corbeille), interrupteur rappel hebdomadaire (dimanche 10 h). | 1012 × 760 px |
| 3 | ![Optimisation](screenshots/03-panel-optimisation.png) | Onglet **Optimisation** : bouton « Analyse de l'espace », liste des fichiers > 100 Mo dans Téléchargements/Documents/Bureau. | 1012 × 760 px |
| 4 | ![Barre de menus](screenshots/04-menu-bar.png) | Icône **barre de menus** : affichage CPU en direct (ex. « 23 % »), menu déroulant avec actions rapides (⌘⇧N Nettoyage, ⌘⇧O Optimisation, Quitter). Largeur approximative 520 px (capture de la bande haute de l'écran). | 520 × 56 px |
| 5 | ![Aide](screenshots/05-panel-aide.png) | Fenêtre **Aide** illustrée (bouton `?` dans l'en-tête) : descriptions détaillées de chaque fonctionnalité avec symboles SF Symbols et conseils d'utilisation. | 1012 × 760 px |

### 7.1 Comment ajouter de nouvelles captures d'écran

Si vous souhaitez mettre à jour les captures ou en ajouter de nouvelles :

1. Lancez l'application : `open "MonitorMyMac.app"`
2. Accédez à l'onglet ou à la fenêtre souhaitée (Surveillance / Nettoyage / Optimisation).
3. Cliquez sur **↻** pour rafraîchir les métriques à jour.
4. Capturer : `screencapture -l <ID_FENÊTRE> ~/chemin/vers/fichier.png`
   - Ou via le helper Swift inclus : `swift run windowid` → `screencapture -l <id> docs/screenshots/06-nouvelle.png`
5. Ajoutez la ligne correspondante au tableau ci-dessus en respectant l'ordre numérique.
6. Mettez à jour cette documentation et commitez les modifications.

### 7.2 Taille et format

- Format : **PNG** (perte sans perte, idéal pour les interfaces).
- Redimensionnement recommandé : largeur ≤ 1012 px pour un affichage net sur les Retina 2880×1800 sans dépasser la largeur de la fenêtre principale.
- Les captures 04-menu-bar.png sont des crops (520×56 px) représentant uniquement la bande supérieure de l'écran.

## 9. Design & Interface

### 9.1 Style Visuel : Liquid Glass (Verre Liquide)

MonitorMyMac s'inspire du style **Liquid Glass** (verre liquide), une esthétique moderne qui combine :

- **Transparence légère** : les cartes et jauges utilisent `ultraThinMaterial` avec opacité partielle, laissant deviner le fond tout en maintenant la lisibilité.
- **Effet de flou dynamique** : `NSVisualEffectView` style `.windowContentBackground` qui s'adapte aux modes Clair/Sombre de macOS.
- **Profondeur par couches** : l'en-tête, les cartes d'état et l'historique sont empilés avec des rayons d'ombre (`shadow radius: 6`) pour suggérer une profondeur visuelle.
- **Coin arrondi continu** : `RoundedRectangle(cornerRadius: 18, style: .continuous)` utilisé de manière cohérente sur toutes les cartes.
- **Palette de couleurs** : fond ultra-léger (`Color(white: 1, opacity: 0.02)`) avec des accents en bleu/cyan pour les états actifs et violet pour la mémoire.

#### Effets implémentés dans le code source

| Élément | SwiftUI / AppKit | Description |
|---|---|---|
| Cartes principales | `.ultraThinMaterial` | Transparence dynamique Clair/Sombre |
| Jauges annulaires | `NSVisualEffectView` | Flou dynamique derrière la jauge |
| Fenêtre Aide | `.glass` | Style vitre enrichi de symboles SF |
| Barre de menus | `.sidebarItem` | Intégration native barre de menus macOS |

> **Note** : L'effet "Liquid Glass" est obtenu sans bibliothèque tierce, exclusivement via les API SwiftUI/AppKit native de macOS. L'apparence peut varier selon le thème système (Clair/Sombre) et la version de macOS (10.15+).

### 9.2 Auteur

**Auteur : Martial Zinsou** — Conception visuelle et développement complet de MonitorMyMac. Toutes les décisions d'interface reflètent le style Liquid Glass cherché, alliant esthétique Apple et fonctionnalité pratique.