# MonitorMyMac — Auteur et métadonnées

## Auteur

**Martial Zinsou** — Développeur et auteur de MonitorMyMac.

- **Dépôt GitHub** : <https://github.com/martialzinsou/MonitorMyMac>
- **Identité de commit** : `martialzinsou`
- **Licence** : MIT — voir le fichier `LICENSE` à la racine du dépôt.
- **Première version** : septembre 2026.

Le contact passe par les [issues du dépôt](https://github.com/martialzinsou/MonitorMyMac/issues) ou les discussions GitHub. Aucune adresse électronique personnelle n'est publiée dans cette documentation.

## Historique des versions

Dates issues de l'historique Git du dépôt.

| Version | Date | Changements principaux |
|---|---|---|
| 1.0 | 2026‑09‑22 | Outil CLI bash + bundle `.app` ; surveillance basique par script shell. |
| 2.0 | 2026‑09‑22 | **Réécriture SwiftUI** : interface, jauges animées, statistiques temps réel, onglets, graphiques d'historique. |
| 2.1 | 2026‑09‑22 → 09‑24 | **Barre de menus** (`NSStatusItem`), **rappels hebdomadaires** (UserNotifications), **sparkline** dans la barre d'état, fenêtre d'aide, documentation et captures. |
| — | 2026‑09‑24 → 09‑25 | Création du wiki, diagrammes UML, galerie de captures, auteur référencé dans les métadonnées. |
| **3.0.0** | 2026‑10‑29 | **Refonte en 8 onglets** et implémentation des quatre familles demandées : Purge (7 familles, doublons SHA‑256, corbeilles multiples), Performance (RAM, démarrage, maintenance, processus), Applications (désinstallation + résidus, mises à jour, extensions), Sécurité (navigation, anti‑malware, intégrité, quarantaine, broyeur). Ajout de Aide illustrée, FAQ (13 questions) et À propos. Nouveau : mode d'auto‑capture `--shots`, `build.sh`, socle `MMUtility` (`Shell`, `Walker`, `PathPolicy`, `DeleteOps`, `Hash`, `Quarantine`), mesures déplacées hors du fil principal. |
| **3.0.0 (refonte UX)** | 2026‑10‑29 | **Navigation revue en quatre espaces** : Purge, Performance, Applications, Sécurité en pastilles ; la surveillance devient un **bandeau ambiant** cliquable qui se déplie en jauges complètes ; Aide, FAQ et À propos réunis dans un **tiroir** ouvert par le « ? ». Une ligne de guidage par espace, et une **info‑bulle sur chaque commande** disant ce qu'elle fait, ce qu'elle ne fait pas et quand elle réclame root. <br>**Cible abaissée à macOS 11.0 (Big Sur)** et **binaire Universel 2** : les deux tranches (`x86_64`, `arm64`) sont compilées avec `-target <arch>-apple-macosx11.0`, assemblées par `lipo`, et contrôlées par `otool` (`minos 11.0` par tranche). Une couche de compatibilité remplace ce que macOS 12+ offrirait : `NSVisualEffectView` au lieu de `Material`, palette `mm*` au lieu de `Color.indigo`/`.teal`/`.cyan`/`.mint`/`.brown`, `mmParseRichText` au lieu de `AttributedString(markdown:)`, `MMSymbol.safe` au lieu de supposer le SF Symbol présent. <br>**Libellés rendus honnêtes** : « Optimisation express » devient « Repérer les fichiers volumineux » (la commande liste, elle ne libère rien) ; « Tout exécuter (sans root) » perd son « sans root » (plusieurs tâches élèvent réellement les privilèges). Le **nettoyage express `⌘⇧N` passe à la corbeille** au lieu de `removeItem`, et son journal distingue le réversible du définitif. Unités et nombres en français (`10,6 Go utilisés sur 16,0 Go`). <br>**Mode sombre vérifié** par `--appearance=dark`, qui force `NSApp.appearance` sans toucher au réglage système : huit captures sombres produites et relues. |

## Ce que la version 3.0 a corrigé de la documentation 2.1

- Les anciennes pages annonçaient des captures « Retina 2880×1800 » alors qu'elles faisaient 1012 × 760 px, et décrivaient un `NSVisualEffectView` en material `.sidebarItem` **qui n'existe pas dans le code** : à l'époque, le seul effet verre réellement présent était `.fill(.ultraThinMaterial)` sur les cartes.
- Depuis la refonte UX, la situation s'est inversée : `NSVisualEffectView` est **bien** présent (c'est `GlassBackground` / `View.mmGlass`, choisi parce que `Material` comme `ShapeStyle` exige macOS 12), et `.ultraThinMaterial` a disparu du code. Toute phrase reprenant l'ancienne formulation est périmée.
- Les cinq PNG « Liquid Glass » du wiki étaient des captures du **bureau entier**, avec des notifications personnelles visibles ; ils sont archivés dans `docs/screenshots/_v2_desktop_backup/` et retirés du wiki.
- Les dates de version étaient écrites « 2025 » alors que l'historique Git est en 2026.
- « Testé sur macOS 13.x et 14.x, Intel et Apple Silicon » : seule la machine de développement (macOS 13.7.8, Intel) a réellement servi aux tests. La refonte n'a pas changé cette limite, elle l'a précisée : la tranche `arm64` est compilée mais **jamais exécutée**, et aucun démarrage n'a eu lieu sous macOS 11.

## Pile technique et outils

- **Langage** : Swift 5.8.1 (toolchain CommandLineTools Apple), SDK macOS 13.3.
- **Cible** : `-target x86_64-apple-macosx11.0` **et** `-target arm64-apple-macosx11.0`, assemblés par `lipo` en un binaire Universel 2 ; `LSMinimumSystemVersion` = 11.0, `minos 11.0` vérifié sur chaque tranche.
- **Frameworks réellement liés** (contrôlés par `otool -L`) : SwiftUI, AppKit, UserNotifications, CryptoKit. Aucun framework tiers, aucun gestionnaire de paquets.
- **Construction** : `swiftc -parse-as-library -O` piloté par `build.sh` — pas d'Xcode complet.
- **Icônes fonctionnelles** : SF Symbols, avec repli à l'exécution — `MMSymbol.safe(_:)` sonde `NSImage(systemSymbolName:)` et remplace un nom absent par un glyphe connu de macOS 11 (`gauge`→`speedometer`, `macbook`→`desktopcomputer`…), parce qu'un nom de symbole est une ressource et que le compilateur ne dit rien. Neuf noms ont été corrigés depuis le premier relevé : les sept consignés dans le journal ([Documentation technique § 6.4](../docs/DOCUMENTATION.md)), `shredder` (le bouton « Broyer ») et la valeur fautive `"shippingbox": "box"` — `box` n'existant pas, le bouton « Quarantaine » retombait sur un rond vide. `resolve(_:)` essaie maintenant le tronc avant le dernier recours, pour qu'une valeur de repli erronée ne puisse plus descendre plus bas que le nom dont elle hérite. Le relevé est reproductible (`tools/list_symbol_names.py` pour la liste, `tools/probe_sf_symbols.swift` pour le test) : 109 noms, 101 présents sur macOS 13.7.
- **Visuels de marque** : `MMBrandIcon` pose les tuiles « Liquid Glass » détourées de deux planches fournies (`assets/`, régénérables par `./build.sh --icons`), et le logo d'en-tête comme le badge d'À propos prennent l'`AppIcon.icns` du bundle — l'image que LaunchServices résout pour ce bundle, donc celle que consultent le Dock, ⌘‑Tab et le Finder. Une tuile manquante fait retomber sur `MSGlassIcon`, la pastille vectorielle ; ce repli a été exécuté sur une copie du bundle privée de ses images. `ImageGen`, un temps prévu pour fabriquer ces visuels, a répondu `HTTP 403` à trois reprises dans cet environnement — le pack existe grâce aux planches fournies, pas grâce à lui.
- **Sources système** : `top`, `vm_stat`, `sysctl`, `df`, `ps`, `launchctl`, `pluginkit`, `systemextensionsctl`, `softwareupdate`, `brew`, `codesign`, `spctl`, `csrutil`, `fdesetup`, `mdutil`, `system_profiler`, `uptime`, `purge`, AppleScript.

## Remerciements

- Développé avec les seuls outils fournis par Apple sur cette machine.
- Les captures d'écran de la documentation sont produites par l'application elle‑même, ce qui garantit qu'elles montrent l'état réel du code.

---
Auteur : **Martial Zinsou**
