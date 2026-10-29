# MonitorMyMac — Diagrammes UML (v3.0.0)

Diagrammes rédigés en **syntaxe Mermaid**, lisibles directement sur GitHub. Ils décrivent le code réellement présent dans `src/` ; chaque nom de classe, de structure ou de méthode correspond à une déclaration existante.

---

## 1. Diagramme de classes — coquille applicative

```mermaid
classDiagram
    class MonitorMyMacApp {
        <<App>>
        +body: some Scene
    }
    class AppLifecycleDelegate {
        <<NSObject, NSApplicationDelegate>>
        +applicationDidFinishLaunching()
    }
    class MenuBarDelegate {
        <<NSObject, singleton>>
        -statusItem: NSStatusItem
        +updateQuickStats()
        +buildMenu()
        -openSection(_:)
        +openMainWindow()
    }
    class AppState {
        <<ObservableObject, singleton>>
        +tab: AppTab
        +hostWindow: NSWindow?
        +go()
        +showMainWindow()
    }
    class AppTab {
        <<enumeration>>
        surveillance
        purge
        performance
        applications
        security
        help
        faq
        about
        +title: String
        +icon: String
        +accent: Color
        +shotName: String
        +fromSlug()  AppTab?
        +fromCommandLine() AppTab?
    }
    class WindowResolver {
        <<NSViewRepresentable>>
        +makeNSView()
    }
    class ContentView {
        +body: some View
        -tabSelector: some View
        -content: some View
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
        +refreshDeviceInfo()
        +runCleanup()
        +runOptimization()
    }

    MonitorMyMacApp --> AppLifecycleDelegate : adapte
    MonitorMyMacApp --> ContentView : affiche
    AppLifecycleDelegate --> MenuBarDelegate : installe
    AppLifecycleDelegate --> ShotCapture : déclenche si --shots
    ContentView --> AppState : observe
    ContentView --> SystemMonitor : observe
    ContentView --> WindowResolver : fond
    ContentView --> AppTab : sélecteur d'espaces + tiroir
    ContentView --> SpacePill : pastilles des quatre espaces
    ContentView --> StripMetric : bandeau ambiant
    WindowResolver --> AppState : publie hostWindow
    AppState --> AppTab : valeur courante
    AppState --> monitorExpanded : bandeau déplié ou replié
    AppState --> docsOpen : tiroir de documentation
    MenuBarDelegate --> AppState : « Ouvrir une section »
    SystemMonitor --> MenuBarDelegate : updateQuickStats()
```

## 2. Diagramme de classes — destinations et modèles

```mermaid
classDiagram
    class PurgeView
    class PerformanceView
    class AppsView
    class SecurityView
    class HelpTabView
    class FAQTabView
    class AboutTabView

    class PurgeModel {
        <<ObservableObject, singleton>>
        +sections: [PurgeSection]
        +settings: PurgeSettings
        +scan()
        +emptyVolumeTrashesWithAdmin()
        +emptyMailJunk()
    }
    class PerformanceModel {
        <<ObservableObject, singleton>>
        +snapshot: MemorySnapshot
        +loginItems: [LoginItem]
        +processes: [ProcessEntry]
        +refreshAll()
        +purgeMemory()
    }
    class AppsModel {
        <<ObservableObject, singleton>>
        +apps: [ManagedApp]
        +plugins: [PluginEntry]
        +updates: UpdateAudit
        +scanApps()
        +scanExtensions()
        +auditUpdates()
    }
    class SecurityModel {
        <<ObservableObject, singleton>>
        +groups: [BrowserTraceGroup]
        +findings: [ThreatFinding]
        +scanTraces()
        +scanThreats()
    }

    PurgeView --> PurgeModel
    PerformanceView --> PerformanceModel
    AppsView --> AppsModel
    SecurityView --> SecurityModel
    HelpTabView --> AppInfo
    FAQTabView --> AppInfo
    AboutTabView --> AppInfo
    AppsView --> SecurityModel : scanThreats(apps:plugins:)
```

Les huit destinations sont sélectionnées par le même `switch` de `ContentView.spaceContent` (avec `EmptyView()` pour `.surveillance`, dont le contenu est servi par `monitoringGrid`). Quatre d'entre elles — Purge, Performance, Applications, Sécurité — sont des espaces choisis par les pastilles ; trois — Aide, FAQ, À propos — sont des pages de documentation atteintes par le tiroir, qui règle `AppState.docsOpen` en plus de `AppState.tab`. La page Surveillance complète remplace l'espace quand `AppState.monitorExpanded` l'exige.

## 3. Diagramme de classes — moteurs et utilitaires

```mermaid
classDiagram
    class Shell {
        <<enumeration>>
        +run()  ShellOutcome
        +runWithAdmin()  ShellOutcome
        +appleScript()  ShellOutcome
        +isAvailable()  Bool
    }
    class Walker {
        <<enumeration>>
        +load()  FileRecord?
        +records()  [FileRecord]
        +size()  Int64
        +mountedVolumeURLs() [URL]
    }
    class PathPolicy {
        <<enumeration>>
        +deniedPrefixes: [String]
        +deniedHomeSubpaths: [String]
        +packageExtensions: Set~String~
        +allowsDeletion()  Bool
        +reason()  String?
        +approveUninstall()
        +isTCCProtected()  Bool
        +canRead()  Bool
    }
    class DeleteOps {
        <<enumeration>>
        +apply()  DeletionReport
        +applyToContents()  DeletionReport
        +emptyTrashDirectory()  DeletionReport
        +waitUntilGone()  Bool
    }
    class DeletionMode {
        <<enumeration>>
        trash
        permanent
        shred
    }
    class Hash {
        <<enumeration>>
        +partial()  String?
        +full()  String?
    }
    class Quarantine {
        <<enumeration>>
        +isolate()  URL?
        +items() [FileRecord]
        +restore()  Bool
    }
    class PrivacyAccess {
        <<enumeration>>
        +hasFullDiskAccess() Bool
        +openFullDiskAccessSettings()
        +openAutomationSettings()
    }
    class Fmt {
        <<enumeration>>
        +size()  String
        +date()  String
        +age()  String
        +percent()  String
        +prettyPath()  String
    }

    Shell --> ShellOutcome
    Walker --> FileRecord
    Walker --> PathPolicy
    DeleteOps --> PathPolicy
    DeleteOps --> DeletionMode
    DeleteOps --> FileRecord
    Quarantine --> FileRecord
```

`PathPolicy` est le **garde‑fou unique** : tout ce qui est supprimé y passe, et un chemin non autorisé produit un refus tracé dans le compte rendu, jamais un silence.

## 4. Diagramme de classes — moteurs métier

```mermaid
classDiagram
    class PurgeEngine {
        <<enumeration>>
        +scan()  [PurgeSection]
    }
    class PurgeSection {
        <<struct>>
        +title: String
        +subtitle: String
        +records: [FileRecord]
        +totalBytes: Int64
        +count: Int
    }
    class PurgeSettings {
        <<struct>>
        +cacheAgeDays: Int
        +junkAgeDays: Int
        +largeMinSizeMB: Int
        +largeMinAgeDays: Int
        +duplicateMinSizeMB: Int
    }

    class MaintenanceScripts {
        <<enumeration>>
        +tasks() [MaintenanceTask]
    }
    class MaintenanceTask {
        <<struct>>
        +title: String
        +requirement: AdminRequirement
    }
    class StartupManager {
        <<enumeration>>
    }
    class ProcessProbe {
        <<enumeration>>
    }
    class MemorySnapshot {
        <<struct>>
        +total: Int64
        +active: Int64
        +wired: Int64
        +compressed: Int64
        +recoverable: Int64
        +swapUsed: Int64
        +empty: MemorySnapshot
    }

    class AppsScanner {
        <<enumeration>>
    }
    class ResidualScanner {
        <<enumeration>>
    }
    class UpdateProber {
        <<enumeration>>
    }
    class ExtensionManager {
        <<enumeration>>
    }

    class SecurityScanner {
        <<enumeration>>
    }
    class BrowserData {
        <<enumeration>>
    }
    class FileShredder {
        <<enumeration>>
        +passPresets: presets
        +shred()  ShredOutcome
        +supportsBSDSecureDelete() String
    }
    class ThreatFinding {
        <<struct>>
        +path: String
        +title: String
        +severity: ThreatSeverity
    }

    PurgeEngine --> PurgeSection : produit
    PurgeSection --> PurgeSettings : réglé par
    PurgeEngine --> Walker
    PurgeEngine --> Hash : doublons SHA-256
    MaintenanceScripts --> MaintenanceTask
    MaintenanceTask --> AdminRequirement
    StartupManager --> LoginItem
    ProcessProbe --> ProcessEntry
    AppsScanner --> ManagedApp
    ResidualScanner --> ManagedApp
    UpdateProber --> AvailableUpdate
    UpdateProber --> UpdateAudit
    ExtensionManager --> PluginEntry
    ExtensionManager --> BrowserExtension
    SecurityScanner --> ThreatFinding
    SecurityScanner --> Quarantine
    BrowserData --> BrowserTraceGroup
    BrowserTraceGroup --> BrowserTrace
    ThreatFinding --> ThreatSeverity
```

## 5. Diagramme de séquence — balayage puis suppression (Purge)

```mermaid
sequenceDiagram
    autonumber
    actor U as Utilisateur
    participant V as PurgeView
    participant M as PurgeModel
    participant E as PurgeEngine
    participant W as Walker
    participant P as PathPolicy
    participant D as DeleteOps

    U->>V: Clic « Balayer »
    V->>M: scan()
    M->>M: isScanning = true (fil principal)
    M->>E: scan(settings:) [global qos userInitiated]
    E->>W: records(in:) sur chaque racine
    W->>P: filtre deniedPrefixes / packageExtensions
    P-->>W: autorisé ou refus motivé
    W-->>E: [FileRecord] (taille, date, empreinte)
    E-->>M: [PurgeSection] (7 familles)
    M-->>V: sections publiées, sélection par défaut
    U->>V: coche des lignes, vérifie le volume sélectionné
    V->>D: apply(urls, mode: .trash)
    D->>P: allowsDeletion(of:) — encore, à l'exécution
    D->>D: FileManager.trashItem(url:)
    D-->>V: DeletionReport (succès, échecs, refus)
    V->>V: ReportCard : compte rendu fidèle
```

La double vérification par `PathPolicy` (au scan **et** à l'exécution) est volontaire : une liste construite à l'avance ne doit jamais pouvoir convaincre l'app de supprimer un chemin protégé.

## 6. Diagramme de séquence — action privilégiée

```mermaid
sequenceDiagram
    autonumber
    actor U as Utilisateur
    participant V as PerformanceView
    participant M as PerformanceModel
    participant S as Shell
    participant OS as osascript

    U->>V: Clic « Purger la RAM »
    V->>M: purgeMemory()
    M->>M: requirement == .admin → l'afficher avant
    M->>S: runWithAdmin("purge")
    S->>OS: with administrator privileges
    OS->>U: mot de passe (seule la racine l'obtient)
    alt autorisation accordée
        OS-->>S: sortie + code retour
        S-->>M: ShellOutcome(succeeded: true)
    else refus ou annulation
        OS-->>S: code non nul
        S-->>M: ShellOutcome(succeeded: false, stderr)
        M->>V: message d'échec explicite, rien d'inventé
    end
```

## 7. Diagramme d'états — cycle de vie d'une destination

```mermaid
stateDiagram-v2
    [*] --> Lancement : applicationDidFinishLaunching
    Lancement --> BarreDeMenus : NSStatusItem + menu
    Lancement --> Idle : fenêtre sur AppState.tab (Purge par défaut)
    Lancement --> ModeCapture : si --shots présent
    ModeCapture --> [*] : NSApp.terminate après 8 captures

    Idle --> EspaceDeplie : clic sur le bandeau / ⌘⇧M
    EspaceDeplie --> Idle : jauges repliées, l'espace est conservé
    Idle --> TiroirOuvert : bouton ? / ⌘⇧H
    TiroirOuvert --> Idle : « Fermer » ramène l'espace précédent

    Idle --> Balayage : clic « Balayer » / raccourci
    Balayage --> MesureEnCours : scan sur file globale
    MesureEnCours --> Resultats : sections / listes publiées
    Resultats --> Selection : cases cochées
    Selection --> Application : DeleteOps.apply(mode:)
    Application --> CompteRendu : DeletionReport
    CompteRendu --> Idle : statut et journal mis à jour

    Idle --> Surveillance : Timer 2 s
    Surveillance --> Idle : métriques hors fil principal, publication sur le fil principal
```

## 8. Diagramme d'états — machine de capture `--shots`

```mermaid
stateDiagram-v2
    [*] --> Dimensionnee : fenêtre réglée sur 1320 × 880
    Dimensionnee --> DestinationSuivante : file AppTab.allCases
    DestinationSuivante --> Amorcage : prime(tab) lance le scan réel
    Amorcage --> Attente : isBusy(tab) ?
    Attente --> Attente : sonde 0,5 s, budget 20 à 170 s
    Attente --> Photographie : modèle inactif
    Photographie --> DestinationSuivante : PNG écrit (cacheDisplay)
    Photographie --> Erreur : aucun NSWindow / écriture impossible
    Erreur --> DestinationSuivante : journalise et poursuit
    DestinationSuivante --> [*] : pile vide → NSApp.terminate
```

Aucune attente bloquante : `DispatchQueue.main.asyncAfter` enchaîne les états, sinon le `NSRunLoop` se bloque et la capture échoue.

## 9. Diagramme de cas d'utilisation

```mermaid
flowchart LR
    U([Utilisateur]) --> SV[Surveiller]
    U --> PU[Purger le stockage]
    U --> PE[Optimiser les performances]
    U --> AP[Gérer applications et extensions]
    U --> SE[Sécuriser et privatiser]
    U --> DO[Comprendre Aide / FAQ / À propos]
    U --> MB[Barre de menus]

    SV --> SV1[Jauges CPU / RAM / disque]
    SV --> SV2[Historique 2 minutes]
    SV --> SV3[Fiche système et uptime]

    PU --> PU1[Caches, logs, restes de mise à jour]
    PU --> PU2[Volumineux et anciens]
    PU --> PU3[Doublons SHA-256]
    PU --> PU4[Corbeilles Finder / volumes / Mail]
    PU --> PU5[Rappel hebdomadaire]

    PE --> PE1[Libérer la RAM]
    PE --> PE2[Éléments de démarrage]
    PE --> PE3[Scripts de maintenance]
    PE --> PE4[Processus gourmands CPU / énergie]

    AP --> AP1[Désinstallation complète + résidus]
    AP --> AP2[Mises à jour centralisées]
    AP --> AP3[Extensions, widgets, navigateurs]

    SE --> SE1[Données de navigation par navigateur]
    SE --> SE2[Analyse anti-malware locale]
    SE --> SE3[Intégrité : SIP, Gatekeeper, FileVault]
    SE --> SE4[Quarantaine réversible]
    SE --> SE5[Broyeur multi-passes]

    DO --> DO1[Aide illustrée depuis le bundle]
    DO --> DO2[13 questions de FAQ]
    DO --> DO3[À propos et limites testées]

    MB --> MB1[Ouvrir une section]
    MB --> MB2[Actions rapides ⌘…]
```

## 10. Schéma d'architecture en couches

```mermaid
graph TD
    subgraph Presentation["Présentation — src/UI + ContentView"]
        CV[ContentView : bandeau + 4 espaces + tiroir]
        PV[PurgeView]
        PEF[PerformanceView]
        AV[AppsView]
        SV[SecurityView]
        DV[Help / FAQ / About]
        SP[SpacePill + StripMetric + MMBrandIcon]
        TH[MMTheme : SectionCard, Pill, HonestyNotes, AppScreenshot, mmGlass, MMBrandIcon]
        SC[ShotCapture + WindowResolver]
    end

    subgraph Modeles["Modèles observables (singletons)"]
        PM[PurgeModel]
        PFM[PerformanceModel]
        AM[AppsModel]
        SM[SecurityModel]
        SYS[SystemMonitor]
        ST[AppState]
    end

    subgraph Moteurs["Moteurs métier — src/Core"]
        PE[PurgeEngine]
        MS[MaintenanceScripts / StartupManager / ProcessProbe]
        AMG[AppsScanner / ResidualScanner / UpdateProber / ExtensionManager]
        SEC[SecurityScanner / BrowserData / FileShredder]
    end

    subgraph Socle["Socle technique — MMUtility"]
        SH[Shell]
        WK[Walker]
        PP[PathPolicy]
        DO[DeleteOps]
        HS[Hash]
        QR[Quarantine]
        PA[PrivacyAccess]
        FT[Fmt]
    end

    subgraph Systeme["macOS"]
        CMD[top, vm_stat, sysctl, df, ps, launchctl, pluginkit, systemextensionsctl, softwareupdate, brew, codesign, spctl, csrutil, fdesetup, mdutil, system_profiler, uptime, purge]
        FS[Fichier : ~/Library, /Applications, corbeilles]
        OS[osascript avec privileges administrator]
        UN[UserNotifications]
    end

    CV --> PV & PEF & AV & SV & DV
    CV --> ST
    PV --> PM
    PEF --> PFM
    AV --> AM
    SV --> SM
    DV --> TH
    SC --> ST
    PM --> PE
    PFM --> MS
    AM --> AMG
    SM --> SEC
    PE --> WK & HS
    MS --> SH
    AMG --> WK & SH
    SEC --> WK & SH & QR
    WK --> PP & FT
    DO --> PP
    PE --> DO
    SEC --> DO
    AMG --> DO
    SH --> CMD
    SH --> OS
    WK --> FS
    DO --> FS
    SYS --> CMD
    SYS --> UN
    ST --> MB[MenuBarDelegate : NSStatusItem]
```

---

## 11. Chaîne des icônes — des planches au Dock

Rien de ce graphe n'est exécuté par l'application : la colonne de gauche est un
pipeline hors-ligne (Python + `iconutil`), celle de droite ce que le bundle
contient et ce que SwiftUI en fait.

```mermaid
flowchart LR
    subgraph Sources["Fournis (jamais lus à l'exécution)"]
        P1[planche-1-24-icones.jpeg<br/>2 752 × 1 536, 6 × 4]
        P2[planche-2-35-icones.jpeg<br/>2 752 × 1 536, 7 × 5]
    end

    subgraph Outillage["tools/ — ./build.sh --icons"]
        E[extract_icons.py<br/>grille → zone_glyphe → matte de luminance<br/>→ trouves → detoure → compose_tuile]
        M[make_app_icon.py<br/>gabarit Apple 81 % / rendu 2× / iconutil]
    end

    subgraph Artefacts["assets/ — régénérables"]
        G[41 glyphes 256 px<br/>+ extraction.json]
        T[41 tuiles 256 px<br/>assets/icons/tuiles/]
        I[AppIcon.iconset 10 tailles<br/>AppIcon.icns master 1 024 px]
    end

    subgraph Bundle["MonitorMyMac.app/Contents — posés par build.sh : install_icons"]
        RI[Resources/Icons/*.png]
        RA[Resources/AppIcon.icns]
        PL[Info.plist<br/>CFBundleIconFile = AppIcon]
    end

    subgraph Runtime["Exécution — Swift"]
        ART[MMBrandArt<br/>cache verrouillé · 3 candidats<br/>relevé des absences]
        BICON[MMBrandIcon]
        VEC[MSGlassIcon<br/>repli vectoriel]
        UI[Sélecteur d'espaces ·<br/>en-tête · badge À propos ·<br/>Dock / ⌘-Tab / Finder]
        LOG[Journal de lancement<br/>nomme chaque ressource absente]
    end

    P1 & P2 --> E
    E --> G & T
    E --> M
    M --> I
    T --> RI
    I --> RA
    B[build.sh — write_info_plist] --> PL
    RI & RA --> ART
    ART -->|image trouvée| BICON
    ART -->|image absente| VEC
    ART --> LOG
    BICON & VEC --> UI
    RA -->|LaunchServices| UI
```

Deux arêtes méritent le commentaire. `MMBrandArt → MSGlassIcon` est le chemin de
défaillance : il a été exercé pour de vrai sur une copie du bundle privée de
`Icons/` et d'`AppIcon.icns`, et c'est lui qui rend le pack non obligatoire à la
compilation. `AppIcon.icns → LaunchServices → Dock` est le seul chemin par
lequel l'icône du Dock a été contrôlée ici — le Dock de la machine de
développement est masqué, et `NSWorkspace.icon(forFile:)` consulte exactement la
même résolution.

---
Auteur : **Martial Zinsou**
