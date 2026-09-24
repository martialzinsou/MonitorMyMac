# MonitorMyMac — Features détaillées

## Surveillance en temps réel

- **Jauges annulaires** : CPU, Mémoire, Stockage avec animation fluide.
- **Modèle et cœurs du processeur** : affichage du nom du CPU et nombre de cœurs logiques.
- **Modèle du Mac** : MacBook Pro, Air, iMac, Mac Mini, etc.
- **Version macOS** : ex. « macOS 13.7.8 ».
- **Durée d'activité (uptime)** : temps écoulé depuis le dernier redémarrage.
- **Mémoire totale** :Go physiques installés.
- **Historique temps réel** : deux courbes de tendance sur 2 minutes (CPU en bleu, RAM en violet).

## Nettoyage intelligent

- **Fichiers temporaires** : `/tmp` de plus de 60 minutes sont supprimés.
- **Caches utilisateur** : fichiers `.cache` et `.log` de plus de 2 heures dans `~/Library/Caches`.
- **Logs système** : fichiers de plus de 24 h dans `/private/var/log` (selon les permissions).
- **Corbeille** : vidage de `~/.Trash`.
- **Rappel hebdomadaire** : interrupteur activable → notification chaque dimanche à 10 h. Cliquer sur la notification lance le nettoyage automatiquement.

## Optimisation de l'espace disque

- **Analyse de l'espace** : liste les fichiers de plus de 100 Mo dans les dossiers Téléchargements, Documents et Bureau.
- **Aperçu avant suppression** : les fichiers sont affichés mais **non supprimés automatiquement** — l'utilisateur décide.
- **Taille minimale** : seuil personnalisable (défaut 100 Mo).

## Barre de menus

- **Icône dynamique** : taux CPU affiché en temps réel (ex. « 23 % »), mini-graphique sparkline.
- **Menu déroulant** :
  - MonitorMyMac → rouvre la fenêtre principale
  - Statut → « Prêt », « Nettoyage terminé ✓ », etc.
  - CPU / RAM / Disque → pourcentages en un coup d'œil
  - Nettoyage rapide (`⌘⇧N`) → lance le nettoyage sans ouvrir la fenêtre
  - Optimisation rapide (`⌘⇧O`) → lance l'analyse d'espace
  - Quitter → ferme complètement l'application
- **Raccourcis clavier** : `⌘⇧N`, `⌘⇧O`, `⌘Q`

## Aide intégrée

- Fenêtre ouverte via le bouton **?** dans l'en-tête.
- Contient des descriptions détaillées de chaque fonctionnalité avec symboles SF Symbols.
- Sections : Surveillance, Nettoyage, Optimisation, Barre de menus, Rappels.
- Auteur et copyright en pied de page.

---