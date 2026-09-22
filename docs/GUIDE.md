# Guide Utilisateur - MonitorMyMac

Bienvenue dans **MonitorMyMac**, votre assistant personnel pour surveiller, nettoyer et optimiser votre Mac — simplement et avec une interface élégante.

---

## 1. Premiers pas

### 1.1 Installation

1. Téléchargez le dossier `MonitorMyMac`.
2. Placez-le dans votre dossier `Applications` (ou n'importe où sur votre disque).
3. Double-cliquez sur `MonitorMyMac.app` pour lancer l'application.

> **Astuce** : Si macOS bloque l'ouverture, faites un clic droit sur l'application
> puis choisissez **Ouvrir** pour autoriser l'exécution.

---

## 2. L'interface

L'application s'ouvre sur une fenêtre moderne et minimaliste composée de :

| Zone | Rôle |
|---|---|
| **En-tête** | Logo, titre, indicateur d'activité et bouton d'actualisation |
| **Onglets** | `Surveillance` · `Nettoyage` · `Optimisation` |
| **Cartes** | Jauges animées et statistiques en direct |
| **Historique** | Courbes d'évolution CPU & RAM (2 dernières minutes) |
| **Barre de menus** | Icône macOS + % CPU, menu et actions rapides |
| **Journal** | Suivi de toutes les actions effectuées |
| **Pied de page** | Statut en direct de l'application |

### 2.1 Onglet Surveillance

Les cartes se **mettent à jour automatiquement toutes les 2 secondes** :

- **Processeur** : jauge annulaire du taux d'utilisation, modèle et nombre de cœurs.
- **Mémoire** : jauge annulaire + mémoire utilisée / totale.
- **Stockage** : barre de progression de l'espace disque.
- **Système** : modèle du Mac, version macOS, durée d'activité.
- **Historique temps réel** : deux courbes de tendance (en bleu = CPU, en violet = RAM).

> 💡 Utilisez le bouton **↻** (en haut à droite) pour rafraîchir immédiatement.

### 2.2 Onglet Nettoyage

Cliquez sur **« Nettoyage intelligent »** pour supprimer en toute sécurité :

- les **fichiers temporaires** de `/tmp` (> 60 minutes) ;
- les **caches utilisateur** (`.cache`, `.log` > 2 heures) ;
- les **logs système** (> 24 h, si les permissions le permettent) ;
- la **corbeille**.

💡 Activez le **rappel hebdomadaire** : une notification chaque **dimanche à 10 h**
vous invitera à lancer un nettoyage. Cliquez sur la notification pour l'exécuter
immédiatement.

### 2.3 Onglet Optimisation

Cliquez sur **« Analyse de l'espace »** pour lister les **fichiers volumineux
(> 100 Mo)** présents dans vos dossiers Téléchargements, Documents et Bureau.
Vous pourrez ensuite les supprimer manuellement dans le Finder.

### 2.4 Barre de menus

L'icône **🍎 ▸ 23%** (taux CPU en direct) reste visible en haut de l'écran :

| Élément du menu | Action |
|---|---|
| **Statut** | État courant (« Prêt », « Nettoyage terminé ✓ »…) |
| **CPU / RAM / Disque** | Pourcentages en un coup d'œil |
| **Nettoyage rapide** (`⌘⇧N`) | Lance le nettoyage sans ouvrir la fenêtre |
| **Optimisation rapide** (`⌘⇧O`) | Lance l'analyse d'espace |
| **Quitter** | Ferme complètement l'application |

> L'application reste active dans la barre de menus **même quand on ferme la
> fenêtre**. Utilisez le menu **Quitter** pour l'arrêter totalement.

---

## 3. Lire le journal

Chaque action est consignée dans le panneau **Journal** en bas de la fenêtre :

```
═══════════ NETTOYAGE ═══════════
  ✦ Fichiers temporaires (/tmp) : 12 élément(s) supprimé(s)
  ✦ Caches utilisateur : 34 élément(s) supprimé(s)
```

- **Vider le journal** : cliquez sur *Effacer*.
- **Statut** : le pied de page affiche « Nettoyage terminé ✓ » une fois l'action finie.

---

## 4. Foire aux questions

### Combien de temps dure un nettoyage ?
Quelques secondes seulement.

### Est-ce que MonitorMyMac peut endommager mon Mac ?
**Non.** Il ne supprime que des fichiers temporaires et des caches, comme le
recommande Apple. Il ne touche jamais à vos documents, photos ou applications.

### Les statistiques sont-elles en direct ?
Oui, les cartes CPU, Mémoire et Stockage se rafraîchissent toutes les 2 secondes,
et l'historique affiche leur évolution sur 2 minutes.

### Que se passe-t-il si j'active les rappels ?
macOS demandera l'autorisation d'envoyer des notifications. Ensuite, un rappel
sera programmé chaque **dimanche à 10 h**. Cliquer sur la notification lance le
nettoyage automatiquement.

### Mon Mac s'arrête-t-il quand je ferme la fenêtre ?
Non. L'application reste dans la **barre de menus** pour un accès rapide.
Utilisez *Quitter* dans le menu pour fermer complètement l'application.

### Mes fichiers personnels seront-ils supprimés ?
Non. La corbeille n'est vidée que si elle contient vos propres fichiers, et
aucun répertoire personnel n'est modifié.

### Puis-je utiliser MonitorMyMac avec des droits admin ?
Le nettoyage des logs système (`/private/var/log`) peut nécessiter des droits
élevés. Sur certains systèmes, cliquez sur l'application avec **clic droit →
Ouvrir** une fois pour lui accorder les permissions demandées.

### Est-ce compatible avec Apple Silicon (M1/M2/M3) ?
Oui. L'application est 100 % native et universelle (Intel & Apple Silicon).

---

## 5. Dépannage

| Problème | Solution |
|---|---|
| L'application ne s'ouvre pas | Clic droit → **Ouvrir**, puis confirmer |
| Les jauges restent à 0 % | Relancez l'application (mise à jour automatique) |
| Nettoyage partiel | Exécutez le script CLI en `sudo` (voir doc technique) |

Besoin d'aide ? Consultez la [documentation technique](DOCUMENTATION.md).