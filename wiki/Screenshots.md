# MonitorMyMac — Galerie de captures d'écran

Toutes les captures d'écran présentes dans ce dépôt ont été réalisées sur un **Mac Retina 2880×1800** (configuré en résolution native ou agrandie). Les images sont au format **PNG** et redimensionnées pour un affichage optimal dans la documentation et le wiki.

---

## 01 — Onglet Surveillance

![Surveillance](docs/screenshots/01-panel-surveillance.png)

**Description** : Vue principale de MonitorMyMac. On y trouve :
- Jauges annulaires animées pour le **Processeur** (CPU) et la **Mémoire** (RAM).
- Carte **Stockage** avec barre de progression de l'espace disque utilisé.
- Carte **Système** affichant le modèle du Mac, la version de macOS et la durée d'activité.
- Deux courbes de tendance en bas : **CPU** (en bleu) et **RAM** (en violet), couvrant les 2 dernières minutes (échantillonnage toutes les 2 secondes).

**Dimensions** : 1012 × 760 px (capture d'écran Retina).

---

## 02 — Onglet Nettoyage

![Nettoyage](docs/screenshots/02-panel-nettoyage.png)

**Description** : Onglet de nettoyage intelligente. On y trouve :
- Bouton principal **« Nettoyage intelligent »** qui, au clic, supprime les fichiers temporaires, caches et vidé la corbeille selon les critères d'âge définis.
- Trois pastilles sous le bouton rappelant la portée : `Temp > 60 min` · `Caches > 2 h` · `Corbeille vidée`.
- Interrupteur **« Rappel hebdomadaire de nettoyage »** : lorsqu'il est activé, macOS envoie une notification chaque **dimanche à 10 h** invitant à lancer un nettoyage immédiat.

**Dimensions** : 1012 × 760 px.

---

## 03 — Onglet Optimisation

![Optimisation](docs/screenshots/03-panel-optimisation.png)

**Description** : Onglet d'analyse et d'optimisation de l'espace disque. On y trouve :
- Bouton **« Analyse de l'espace »** qui liste tous les fichiers de plus de **100 Mo** présents dans les dossiers **Téléchargements**, **Documents** et **Bureau**.
- Liste fichiers affichée avec taille et chemin relatif — l'utilisateur peut ensuite les sélectionner et les supprimer manuellement dans le Finder.
- Note importante : l'optimisation **ne supprime rien automatiquement** ; elle ne fait que repérer les gros fichiers.

**Dimensions** : 1012 × 760 px.

---

## 04 — Barre de menus (CPU en direct)

![Barre de menus](docs/screenshots/04-menu-bar.png)

**Description** : Capture de la bande haute de l'écran montrant l'icône **MonitorMyMac** dans la barre de menus supérieure. L'icône affiche le taux CPU actuel (ex. « 23 % ») et un mini-graphique sparkline dynamique. Un clic ouvrira le menu déroulant avec les actions rapides.

**Dimensions** : 520 × 56 px (crop de la partie supérieure de l'écran).

---

## 05 — Fenêtre Aide illustrée

![Aide](docs/screenshots/05-panel-aide.png)

**Description** : Fenêtre ouverte via le bouton **?** situé en haut à droite de l'en-tête de l'application. Elle contient des descriptions détaillées de chaque fonctionnalité de MonitorMyMac, avec :
- Symboles SF integrés (SF Symbols) à côté de chaque section.
- Textes explicatifs sur la surveillance, le nettoyage, l'optimisation, la barre de menus et les rappels.
- Auteur et copyright en pied de page.

**Dimensions** : 1012 × 760 px.

---

## Ajout de nouvelles captures d'écran

Si vous souhaitez contributer de nouvelles captures ou mettre à jour les existantes :

1. Lancez l'application : `open "MonitorMyMac.app"`.
2. Accédez à l'écran ou à la fenêtre souhaitée (onglet, fenêtre d'aide, barre de menus).
3. Cliquez sur **↻** pour rafraîchir les métriques à jour.
4. Détermine l'identifiant de la fenêtre (via l'outil `windowid` inclus ou `ls -l /proc/pid/fd`).
5. Capture d'écran : 
   ```bash
   screencapture -l <ID_FENÊTRE> wiki/screenshots/06-nouvelle.png
   ```
   Ou simplement : `screencapture wiki/screenshots/06-nouvelle.png` (capture de l'écran entier).
6. Redimensionnez si nécessaire (outils : `sips -Z 1012 wiki/screenshots/06-nouvelle.png`).
7. Ajoutez la ligne correspondante au format Markdown dans la section appropriée de ce wiki, en respectant le numéro et le format existants.
8. Commitez vos modifications sur le dépôt.

---
---
Auteur : Martial Zinsou
