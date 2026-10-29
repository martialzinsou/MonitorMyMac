# MonitorMyMac — Guide de démarrage

## Prérequis

- **macOS 11.0 (Big Sur) ou suivant** — `LSMinimumSystemVersion` = 11.0, et les deux tranches sont compilées avec `-target <arch>-apple-macosx11.0` (SDK 13.3). Le binaire livré est **Universel 2** : `x86_64` pour Intel, `arm64` pour Apple Silicon.
- **CommandLineTools Apple** avec Swift 5.8+ : `xcode-select --install`. Xcode complet n'est **pas** nécessaire — tout passe par `swiftc`.
- Environ 150 Mo d'espace disque pour le bundle et les captures embarquées.

> Ce que la cible 11.0 veut dire, précisément : le compilateur **refuse** toute API
> plus récente que macOS 11, et `--typecheck` rejoue cette contrainte sur les deux
> architectures. En revanche, le projet n'a jamais démarré sur une machine sous
> macOS 11, et la tranche `arm64` n'a jamais été exécutée (machine Intel). La
> compatibilité est établie par la compilation, pas par l'observation.

## Construire l'application

Le dépôt est livré avec `build.sh`, qui compile, assemble le `.app`, génère l'`Info.plist`, embarque les captures et signe.

```bash
git clone https://github.com/martialzinsou/MonitorMyMac.git
cd MonitorMyMac

./build.sh --typecheck   # typage complet : SDK par défaut + cible 11.0 sur x86_64 et arm64
./build.sh               # deux tranches -O assemblées par lipo (~190 s), binaire Universel 2 6,51 Mo
./build.sh --run         # construit puis ouvre l'application
./build.sh --icons       # régénère le pack d'icônes et AppIcon.icns depuis assets/icon-sheets/
./build.sh --shots       # construit, lance l'app et régénère les 8 captures
./build.sh --zip         # emballe MonitorMyMac.app.zip (7,51 Mo) + contrôle aller-retour
./build.sh --clean       # supprime les artefacts
```

Ce que fait `build.sh` :

1. Pour chaque architecture de `ARCHS=(x86_64 arm64)` : `swiftc -parse-as-library -O
   -target <arch>-apple-macosx11.0` sur les 16 fichiers de `src/Core/*.swift` et
   `src/UI/*.swift` plus `src/MonitorMyMacApp.swift` (17 unités de compilation), avec
   `-framework SwiftUI -framework AppKit -framework UserNotifications`.
2. `lipo -create` des deux tranches, puis contrôles : `lipo -info`, `file`,
   `otool -l` (le `minos 11.0` est vérifié **par tranche**) et `codesign --verify`.
3. Écriture de l'`Info.plist` — la version est lue depuis `static let version` de `src/UI/DocsViews.swift`, donc un seul endroit à modifier. `LSMinimumSystemVersion` = 11.0, `CFBundleIconFile` = `AppIcon`.
4. Copie de `docs/screenshots/*.png` vers `Contents/Resources/Screenshots` (lues par la page Aide illustrée), de `assets/appicon/AppIcon.icns` vers `Contents/Resources/` et des 41 tuiles de `assets/icons/tuiles/` vers `Contents/Resources/Icons/`.
5. Nettoyage des `xattr` et des `.DS_Store` **puis** `codesign --force --sign -`. Cet ordre est obligatoire : sans lui, la signature échoue avec « resource fork, Finder information, or similar detritus not allowed ».

Les images de marque sont des artefacts **livrés dans le dépôt** : rien n'est
téléchargé ni régénéré pendant un `./build.sh` normal, et `python3` + Pillow ne
sont nécessaires que si l'on relance `--icons`. Sans `AppIcon.icns` ni tuiles,
l'application se construit, se lance et rend ses pastilles en vecteur — le build
avertit, il ne échoue pas.

## Installation

```bash
cp -R MonitorMyMac.app /Applications/
open /Applications/MonitorMyMac.app
```

La signature est **ad hoc**, sans identifiant Apple et sans notarisation. Au premier lancement depuis le Finder, macOS peut donc bloquer l'ouverture : clic droit sur l'application → **Ouvrir** → **Ouvrir**, ou Réglages Système → Confidentialité et sécurité → **Ouvrir quand même**. Ce n'est pas un défaut de compilation, c'est l'absence de certificat développeur.

## Première utilisation

L'application est une **application de barre de menus** : une icône avec le pourcentage CPU s'installe en haut à droite, et la fenêtre SwiftUI s'ouvre sur l'espace **Purge**, avec un bandeau de surveillance ambiante en tête qui se rafraîchit toutes les 2 secondes.

1. **Bandeau ambiant** — CPU, RAM, stockage, modèle, système, RAM totale et durée d'activité, visible depuis n'importe quel espace. Un clic dessus le déplie en page Surveillance complète : anneaux, courbes d'historique sur 2 minutes et fiche matériel.
2. **Purge** — lancer « Balayer » ; les 7 familles apparaissent avec leurs tailles mesurées ; cocher ce qui doit l'être ; vérifier le volume sélectionné dans le pied de carte avant d'agir.
3. **Performance** — RAM, éléments de démarrage, scripts de maintenance, processus gourmands.
4. **Applications** — inventaire, désinstallation complète, mises à jour, extensions.
5. **Sécurité** — données de navigation, analyse anti‑malware, intégrité système, broyeur.
6. **Aide illustrée / FAQ / À propos** — réunis dans le tiroir ouvert par le « ? » de l'en-tête (ou `⌘⇧H`) : explications, réponses et limites connues.

Les actions destructives sont **toujours** précédées d'une sélection explicite par case à cocher, et passent par la corbeille (`FileManager.trashItem`) sauf utilisation volontaire du broyeur.

## Autorisations demandées

| Demande | Quand | Pourquoi |
|---|---|---|
| Mot de passe administrateur | `purge`, réparation des permissions, réindexation Spotlight, purge des logs système | Ces commandes exigent la racine ; elles ne sont jamais lancées en tâche de fond. |
| Accès complet au disque | Données de navigation de Chrome / Edge / Brave / Opera | Les profils sont protégés par TCC ; sans cette autorisation, le scan renvoie vide — et l'app le dit au lieu d'inventer des chiffres. |
| Notifications | Rappel hebdomadaire | Uniquement si l'interrupteur est activé. |

Aucune connexion réseau n'est ouverte : le binaire n'utilise ni `URLSession` ni socket.

## Mise à jour

Remplacer l'ancien bundle par le nouveau. Les réglages (rappel hebdomadaire, seuils de purge) vivent dans `UserDefaults` sous `purgeSettings.v1` et sont conservés.

## Dépannage

| Problème | Cause et solution |
|---|---|
| L'application ne s'ouvre pas | Signature ad hoc : clic droit → **Ouvrir** une première fois. |
| `codesign` : « similar detritus not allowed » | `.DS_Store` ou `xattr` présents dans le bundle — relancer `./build.sh` qui nettoie avant de signer. |
| Icônes absentes dans une destination | Le SF Symbol choisi n'existe pas sur le macOS qui vous sert. `MMSymbol.safe(_:)` devrait y remédier : il sonde `NSImage(systemSymbolName:)` à l'exécution et replie sur un glyphe connu de macOS 11. Si un trou subsiste, le nom n'est pas dans sa table de repli — l'y ajouter plutôt que changer d'icône. |
| Scans qui reviennent vides | Autorisation manquante (accès complet au disque) : Réglages Système → Confidentialité et sécurité → Accès complet au disque. |
| La fenêtre ne réapparaît pas | Clic sur l'icône de la barre de menus → **Ouvrir une section**. |
| L'application se ferme d'un coup au démarrage d'une destination | Chercher un `Process.waitUntilExit()` appelé sur le fil principal pendant l'initialisation d'un `static let` : c'est la classe de plantage `dispatch_once` documentée dans `docs/DOCUMENTATION.md`. |

## Structure du dépôt

```
build.sh                 construction, signature, icônes, captures
src/MonitorMyMacApp.swift  app, barre de menus, Surveillance, moniteur
src/Core/                  MMUtility, Purge, Performance, Apps, Security (moteurs + modèles)
src/UI/                    MMTheme (verre, palette, icônes), 4 espaces, DocsViews, ShotCapture
assets/                  planches fournies, 41 tuiles, AppIcon.icns — régénérable par --icons
tools/                   extract_icons.py, make_app_icon.py et les sondes (icônes, SF Symbols)
docs/                    GUIDE.md, DOCUMENTATION.md, screenshots/
wiki/                    ce wiki
```

---
Auteur : **Martial Zinsou**
