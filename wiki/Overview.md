# MonitorMyMac — Wiki du projet

## Vue d'ensemble

**MonitorMyMac** est une application **native macOS** de barre de menus qui surveille, nettoie, optimise et sécurise un Mac — sans framework tiers, sans réseau et sans télémétrie.

- **Version actuelle** : v3.0.0
- **Auteur** : Martial Zinsou
- **Licence** : MIT
- **Technologies** : Swift 5.8, SwiftUI + AppKit + UserNotifications, compilé avec `swiftc` (CommandLineTools, pas d'Xcode complet)
- **Cible déclarée** : macOS **11.0 (Big Sur)** et suivants — `LSMinimumSystemVersion` 11.0, empreinte de chargeur `minos 11.0` sur **chacune** des deux tranches, SDK 13.3
- **Architecture** : binaire **Universel 2** (`x86_64` Intel + `arm64` Apple Silicon), assemblé par `lipo`
- **Compatibilité réellement vérifiée** : la tranche `x86_64`, exécutée sur MacBook Pro 11,3 Intel (i7‑4850HQ, 8 cœurs, 16 Go) sous macOS 13.7.8. **Non vérifié** : la tranche `arm64`, compilée par compilation croisée sur cette machine Intel et jamais exécutée ; et aucun démarrage sous macOS 11, 12, 14 ou 15, faute de machine correspondante. La cible 11.0 tient par le compilateur et une couche de compatibilité écrite pour elle, pas par un amorçage sur Big Sur.
- **Surface de code** : 17 fichiers, 11 461 lignes dans `src/`, binaire Universel 2 de 6,51 Mo
- **Identité visuelle** : 41 tuiles « Liquid Glass » détourées de deux planches fournies (`assets/`), et une `AppIcon.icns` en 10 tailles que partagent l'en-tête, le badge d'À propos et la résolution LaunchServices du bundle

## Navigation : quatre espaces, un bandeau, un tiroir

| Niveau | Contenu | Accès |
|---|---|---|
| **Bandeau ambiant** | CPU, RAM, stockage, modèle, système, RAM totale, durée d'activité. Un clic le déplie en page Surveillance complète : anneaux, courbes d'historique sur 2 min, fiche matériel. | toujours visible · `⌘⇧M` |
| **Quatre espaces** | **Purge** · **Performance** · **Applications** · **Sécurité**, en pastilles « verre liquide » (tuiles du pack embarqué, repli vectoriel si la ressource manque) | `⌘⇧1` à `⌘⇧4` |
| **Tiroir de documentation** | **Aide illustrée** (un topic par famille, capture lue depuis le bundle) · **FAQ** (13 questions/réponses sur ce que fait réellement chaque action) · **À propos** (version, auteur, pile technique, raccourcis, limites testées) | bouton « ? » · `⌘⇧H` |

| Destination | Rôle |
|---|---|
| **Purge** | 7 familles de nettoyage : caches, logs/historiques, restes de mise à jour, volumineux et anciens, doublons SHA‑256, corbeilles, traductions `.lproj` (informatif) |
| **Performance** | RAM, éléments de démarrage, scripts de maintenance, processus gourmands |
| **Applications** | Inventaire, désinstallation complète + résidus, mises à jour, extensions |
| **Sécurité** | Données de navigation, anti‑malware local, intégrité système, quarantaine, broyeur |

Huit destinations au total, mais plus huit onglets d'un coup : chacune reste à un
clic, et une ligne de guidage rappelle le geste attendu dans l'espace actif.

## Captures d'écran

Produites par l'application elle‑même (`--shots`), 1320 × 880 px, données réelles.

| # | Capture | Description |
|---|---|---|
| 1 | ![Surveillance](../docs/screenshots/01-surveillance.png) | **Surveillance** : jauges CPU / RAM / stockage, fiche système, historique temps réel. |
| 2 | ![Purge](../docs/screenshots/02-purge.png) | **Purge** : 7 familles balayées, tailles mesurées, sélection par case à cocher, rappel hebdomadaire. |
| 3 | ![Performance](../docs/screenshots/03-performance.png) | **Performance** : RAM, éléments de démarrage, maintenance, processus gourmands. |
| 4 | ![Applications](../docs/screenshots/04-applications.png) | **Applications** : inventaire, désinstallation, mises à jour, extensions. |
| 5 | ![Sécurité](../docs/screenshots/05-securite.png) | **Sécurité** : traces de navigation, anti‑malware, intégrité, broyeur. |
| 6 | ![Aide](../docs/screenshots/06-aide.png) | **Aide** : topics + capture embarquée depuis `Contents/Resources/Screenshots`. |
| 7 | ![FAQ](../docs/screenshots/07-faq.png) | **FAQ** : 13 questions/réponses. |
| 8 | ![À propos](../docs/screenshots/08-apropos.png) | **À propos** : métadonnées, raccourcis, note d'honnêteté. |

Détail et légende complète de chaque image : [Screenshots](Screenshots.md).

---

## Architecture en trois lignes

Une **coquille** (`AppState` + `AppTab` + `ContentView`) choisit la destination — quatre espaces, l'état du bandeau déplié, l'ouverture du tiroir de documentation ; des **modèles observables** singletons (`PurgeModel`, `PerformanceModel`, `AppsModel`, `SecurityModel`, `SystemMonitor`) portent l'état publié ; des **moteurs** sans état (`PurgeEngine`, `MaintenanceScripts`, `AppManagerEngine`, `SecurityEngine`) exécutent le travail sur des files globales ; un **socle** (`MMUtility`) centralise `Shell`, `Walker`, `PathPolicy`, `DeleteOps`, `Hash`, `Quarantine`, `Fmt`.

`PathPolicy` est le point de passage obligé de toute suppression, vérifié deux fois : au scan et à l'exécution.

Les diagrammes détaillés (classes, séquences, états, cas d'utilisation, couches) sont dans [UML-Diagrams](UML-Diagrams.md).

## Ce qui a été réellement mesuré

Valeurs affichées par la **dernière passe de capture** (29 octobre, 23:01 pour le thème clair, 23:03 pour le sombre) sur la machine de développement — ce sont exactement celles des huit PNG publiés ci-dessus. Les mesures instantanées sont données en plage parce qu'elles diffèrent d'une capture à l'autre au sein d'une même passe.

- **Bandeau ambiant** : CPU 57-69 % selon la capture et la charge du moment — 0 % sur la première, prise avant le tout premier relevé (8 cœurs · Intel Core i7-4850HQ @ 2.30GHz), RAM 69 % soit 11,0 Go utilisés sur 16,0 Go (« En attente… » sur cette même première capture), stockage 5 % (21 Go utilisés / 954 Go disponibles), MacBook Pro · macOS 13.7.8 · 16 Go · levé depuis 9:13.
- **Purge** : balayage terminé en 70 s, 7 familles, **12,14 Go signalés**, **35,9 Mo sélectionnés** sur 120 éléments, 0 octet libéré pendant la session ; caches utilisateur 18,4 Mo sur 110 éléments et 14 applications.
- **Performance** : 11,0 Go utilisés sur 16,0 Go · active 4,9 Go, câblée 2,5 Go, compressée 3,6 Go, récupérable 4,9 Go, échange 6,5 Mo ; pression 69 % (normale) ; 20 processus suivis, 23 éléments de démarrage ; en têtes de liste gourmandes, Google Chrome (Aperitif) à 95 % (153,4 Mo de RAM) et MonitorMyMac lui-même à 95 % (264,6 Mo).
- **Applications** : 73 applications, 11,72 Go (iMovie 10.4.2 · 3,26 Go ; Chrome v156.0.8078.74 · 1,53 Go, marqué « en cours » ; GitHub Desktop v3.6.7 · 1,12 Go ; OpenCode v2.2.1 · 776,5 Mo ; Qoder v0.4.11 · 722,9 Mo).
- **Sécurité** : 41 traces, 13,8 Mo sélectionnables ; le groupe Google Chrome (253 Mo : cache 145,9, stockage local 59,6, historique 26,8) est marqué non effaçable parce que le navigateur est ouvert, et la bannière le dit.

> Ces chiffres varient d'une passe à l'autre (mesures vivantes) : les passes précédentes affichaient 51 s puis 68 s de balayage, 19,72 ou 23,9 Go signalés, un Chrome à 252,9 Mo, MonitorMyMac à 178 % CPU. Ce qui ne varie pas, c'est l'origine des nombres — des commandes système réellement exécutées.

### Incident d'unité corrigé pendant la relecture

Une première mouture de la v3.0 affichait la RAM de l'espace Performance en unités **décimales** (`ByteCountFormatter`, style « fichier ») et celle de Surveillance en unités **binaires** : la même machine de 16 Go déclarait « 17,18 Go » dans un espace et « 16,0 Go » dans l'autre. Les deux affichages sont maintenant en binaire, et les libellés en français : `Memory.detail()` rend « 10,6 Go utilisés sur 16,0 Go » (virgule décimale via `frNumber`) et `Disk.detail()` convertit Ti/Gi/Mi/Ki en To/Go/Mo/Ko — voir `src/MonitorMyMacApp.swift`.

## Ce qui n'a pas pu être vérifié

- **Actions destructives sur des données réelles** : les balayages sont réels, mais aucune suppression de masse n'a été exécutée sur le disque de travail, pour ne pas perdre de données. Les chemins de suppression sont donc validés par lecture du code et par la politique `PathPolicy`, pas par une exécution destructrice.
- **Invitations au mot de passe administrateur** : le mécanisme `osascript … with administrator privileges` est en place, mais la saisie réelle du mot de passe n'a pas été effectuée lors des tests automatisés.
- **`softwareupdate --list` sur d'autres versions de macOS** : comportement dépendant de la version testée uniquement.
- **Rendu Retina** : la machine est non Retina, les captures font 1320 × 880 px ; le comportement sur écran Retina n'est pas observé ici.
- **Signature** : ad hoc, sans notarisation — l'ouverture au premier lancement peut exiger une validation manuelle.

---

## Pages du wiki

- [Fonctionnalités détaillées](Features.md)
- [Guide de démarrage](Getting-Started.md)
- [Galerie de captures](Screenshots.md)
- [Diagrammes UML](UML-Diagrams.md)
- [Auteur et versions](Author.md)

Documentation technique longue (modèle de concurrence, tables `PathPolicy`, incidents réels) : [`docs/DOCUMENTATION.md`](../docs/DOCUMENTATION.md) et [`docs/GUIDE.md`](../docs/GUIDE.md).

## Contribution

- Construire avec `./build.sh --typecheck` avant toute compilation complète : typage seul sur les deux architectures (~9 s par passe contre ~80 s par tranche optimisée).
- Viser macOS 11.0 : compiler avec `-target <arch>-apple-macosx11.0`. Une API plus récente devient alors une erreur de compilation, pas une régression silencieuse découverte sur une vieille machine.
- Vérifier un SF Symbol avec `NSImage(systemSymbolName:accessibilityDescription:)` : un nom de symbole est une ressource, pas une API — le compilateur ne dit rien, et plusieurs noms récents rendent silencieusement vide. Utiliser `.mmSafeSymbol`.
- Ne jamais appeler `Process.waitUntilExit()` sur le fil principal : c'est la cause d'un plantage `dispatch_once` réellement observé (voir `docs/DOCUMENTATION.md` §6).
- Toute nouvelle suppression doit passer par `PathPolicy` et `DeleteOps`, avec `FileManager.trashItem` par défaut — y compris dans le nettoyage express.

---
Auteur : **Martial Zinsou** · Repo : <https://github.com/martialzinsou/MonitorMyMac>
