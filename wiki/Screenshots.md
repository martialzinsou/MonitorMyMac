# MonitorMyMac — Galerie de captures d'écran

Toutes les captures d'écran présentes dans ce dépôt ont été réalisées sur un **Mac Retina 2880×1800** (configuré en résolution native ou agrandie). Les images sont au format **PNG** et redimensionnées pour un affichage optimal dans la documentation et le wiki. L'application utilise un style **Liquid Glass** (verre liquide) avec transparence légère (`ultraThinMaterial`) et flou dynamique selon le thème Clair/Sombre de macOS.

---

## 01 — Onglet Surveillance (style Liquid Glass)

![Surveillance](wiki/screenshots/01-panel-surveillance-liquid.png)

**Description** : Vue principale de MonitorMyMac en style **Liquid Glass**. On y trouve :
- Jauges annulaires animées avec effet de transparence légère et flou dynamique pour le **Processeur** (CPU) et la **Mémoire** (RAM).
- Carte **Stockage** avec barre de progression de l'espace disque utilisé, fond verre léger.
- Carte **Système** affichant le modèle du Mac, la version de macOS et la durée d'activité, avec fond diffus.
- Deux courbes de tendance en bas : **CPU** (en bleu) et **RAM** (en violet), couvrant les 2 dernières minutes (échantillonnage toutes les 2 secondes), dessinées sur un chemin glassmorphism.

**Dimensions** : 1012 × 760 px (capture d'écran Retina). L'effet de transparence permet de deviner légèrement l'arrière-plan du bureau tout en maintenant une lecture claire des informations.

---

## 02 — Onglet Nettoyage (style Liquid Glass)

![Nettoyage](wiki/screenshots/02-panel-nettoyage-liquid.png)

**Description** : Onglet de nettoyage intelligente en style **Liquid Glass**. On y trouve :
- Bouton principal **« Nettoyage intelligent »** avec pastille verre transparente, au clic supprime les fichiers temporaires, caches et vidé la corbeille selon les critères d'âge définis.
- Trois pastilles sous le bouton rappelant la portée : `Temp > 60 min` · `Caches > 2 h` · `Corbeille vidée`, avec fond translucide.
- Interrupteur **« Rappel hebdomadaire de nettoyage »** : lorsqu'il est activé, macOS envoie une notification chaque **dimanche à 10 h** invitant à lancer un nettoyage immédiat. L'interrupteur bénéficie lui aussi de l'effet verre liquide.

**Dimensions** : 1012 × 760 px. L'ensemble des éléments interactifs profite de l'effet `ultraThinMaterial` pour une cohérence visuelle.

---

## 03 — Onglet Optimisation (style Liquid Glass)

![Optimisation](wiki/screenshots/03-panel-optimisation-liquid.png)

**Description** : Onglet d'analyse et d'optimisation de l'espace disque en style **Liquid Glass**. On y trouve :
- Bouton **« Analyse de l'espace »** avec fond verre liquide, qui liste tous les fichiers de plus de **100 Mo** présents dans les dossiers **Téléchargements**, **Documents** et **Bureau**.
- Liste fichiers affichée avec taille et chemin relatif — l'utilisateur peut ensuite les sélectionner et les supprimer manuellement dans le Finder. Chaque ligne du liste bénéficie d'un fond légèrement transparent.
- Note importante : l'optimisation **ne supprime rien automatiquement** ; elle ne fait que repérer les gros fichiers. Les entrées du tableau ont un fond verre léger avec ombre portée.

**Dimensions** : 1012 × 760 px. L'effet de transparence permet de distinguer subtilement la structure du tableau.

---

## 04 — Barre de menus (CPU en direct, style Liquid Glass)

![Barre de menus](wiki/screenshots/04-menu-bar-liquid.png)

**Description** : Capture de la bande haute de l'écran montrant l'icône **MonitorMyMac** dans la barre de menus supérieure en style **Liquid Glass**. L'icône affiche le taux CPU actuel (ex. « 23 % ») et un mini-graphique sparkline dynamique dans un icône au style verre arrondi. Un clic ouvrira le menu déroulant avec les actions rapides (⌘⇧N Nettoyage, ⌘⇧O Optimisation, Quitter). L'icône de la barre de menus utilise un `NSVisualEffectView` avec material `.sidebarItem` pour s'intégrer harmonieusement au thème système.

**Dimensions** : 520 × 56 px (crop de la partie supérieure de l'écran). L'effet de flou dynamique s'adapte au mode Clair ou Sombre de macOS.

---

## 05 — Fenêtre Aide illustrée (style Liquid Glass)

![Aide](wiki/screenshots/05-panel-aide-liquid.png)

**Description** : Fenêtre ouverte via le bouton **?** situé en haut à droite de l'en-tête de l'application en style **Liquid Glass**. Elle contient des descriptions détaillées de chaque fonctionnalité de MonitorMyMac, avec :
- Symboles SF intégrés (SF Symbols) à côté de chaque section, sur fond verre translucide.
- Textes explicatifs sur la surveillance, le nettoyage, l'optimisation, la barre de menus et les rappels, avec une lisibilité optimisée grâce au fond verre.
- Auteur et copyright en pied de page, avec style verre léger.
- L'ensemble de la fenêtre bénéficie d'un effet de flou dynamique derrière les éléments de contenu.

**Dimensions** : 1012 × 760 px. L'effet de profondeur est créé par l'ombre discrète (`shadow radius: 6`) et le fond `ultraThinMaterial`.

---

## Anciennes captures (référence originale)

Ces captures montrent l'interface avant l'implementation complète du style Liquid Glass. Elles restent utiles comme référence historique.

| # | Capture | Description |
|---|---|---|
| 1 | ![Surveillance](docs/screenshots/01-panel-surveillance.png) | Onglet Surveillance original |
| 2 | ![Nettoyage](docs/screenshots/02-panel-nettoyage.png) | Onglet Nettoyage original |
| 3 | ![Optimisation](docs/screenshots/03-panel-optimisation.png) | Onglet Optimisation original |
| 4 | ![Barre de menus](docs/screenshots/04-menu-bar.png) | Barre de menus originale |
| 5 | ![Aide](docs/screenshots/05-panel-aide.png) | Fenêtre Aide originale |

---

## Ajout de nouvelles captures d'écran

Si vous souhaitez contributer de nouvelles captures ou mettre à jour les existantes :

1. Lancez l'application : `open "MonitorMyMac.app"`.
2. Accédez à l'écran ou à la fenêtre souhaitée (onglet, fenêtre d'aide, barre de menus).
3. Cliquez sur **↻** pour rafraîchir les métriques à jour.
4. Pour capturer avec l'effet Liquid Glass assuré : l'application applique automatiquement le style verre translucide via `ultraThinMaterial` et `NSVisualEffectView`.
5. Détermine l'identifiant de la fenêtre (via l'outil `windowid` inclus ou inspection système).
6. Capture d'écran : 
   ```bash
   screencapture -l <ID_FENÊTRE> wiki/screenshots/06-nouvelle.png
   ```
   Ou simplement : `screencapture wiki/screenshots/06-nouvelle.png` (capture de l'écran entier).
7. Redimensionnez si nécessaire (outils : `sips -Z 1012 wiki/screenshots/06-nouvelle.png`).
8. Ajoutez la ligne correspondante au format Markdown dans la section appropriée de ce wiki, en respectant le numéro et le format existants.
9. Commitez vos modifications sur le dépôt.

---
---
Auteur : **Martial Zinsou**