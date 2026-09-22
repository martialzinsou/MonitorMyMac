# Guide Utilisateur - MonitorMyMac

Bienvenue dans **MonitorMyMac**, votre assistant personnel pour surveiller et optimiser votre Mac.

---

## 1. Premiers pas

### 1.1 Installation

1. Téléchargez le dossier `MonitorMyMac`.
2. Placez-le dans votre dossier `Applications` ou n'importe où sur votre disque.
3. Double-cliquez sur `MonitorMyMac.app` pour lancer l'application.

> **Astuce** : Si macOS bloque l'ouverture, faites un clic droit sur l'application puis
> choisissez **Ouvrir** pour autoriser l'exécution.

### 1.2 Lancement depuis le terminal (alternative)

```bash
cd /chemin/vers/MonitorMyMac
chmod +x src/monitormymac.sh
./src/monitormymac.sh
```

---

## 2. Utilisation

À chaque lancement, MonitorMyMac effectue automatiquement les étapes suivantes :

### Étape 1 : Surveillance

- **Informations système** : modèle du Mac, processeur, mémoire, identifiants.
- **État du CPU** : modèle et nombre de cœurs.
- **Mémoire (RAM)** : dans quelle mesure votre RAM est utilisée.
- **Disque** : espace restant sur chaque volume.

### Étape 2 : Nettoyage

MonitorMyMac supprime automatiquement :

- Les **fichiers temporaires** dans `/tmp` ayant plus de 60 minutes.
- Les **caches utilisateur** (`*.cache`, `*.log`) plus anciens que 2 heures.
- Les **logs système** de plus de 24 heures.
- La **corbeille** (uniquement vos fichiers, jamais ceux des autres utilisateurs).

### Étape 3 : Optimisation

- MonitorMyMac **liste les gros fichiers** (> 100 Mo) dans Downloads, Documents et
  Bureau afin que vous puissiez les supprimer manuellement si vous le souhaitez.

---

## 3. Lire les résultats

Chaque section est précédée d'un titre clair (`--- Informations Systeme ---`,
`--- Nettoyage des Caches ---`, etc.).

- `[OK]` : l'action a été effectuée avec succès.
- `[WARN]` : un outil système n'était pas disponible (peu fréquent).

---

## 4. Foire aux questions (FAQ)

### Combien de temps dure une analyse ?
Moins de 30 secondes en général.

### Est-ce que MonitorMyMac peut endommager mon Mac ?
Non. Il ne supprime que des fichiers temporaires et des caches, similaires à ce
que les outils système d'Apple recommandent de nettoyer régulièrement.

### Mes fichiers personnels seront-ils supprimés ?
Non. MonitorMyMac ne touche **jamais** à vos documents, photos ou applications.
La corbeille n'est vidée que si elle contient vos propres fichiers.

### Puis-je utiliser MonitorMyMac avec des droits admin ?
Le nettoyage des logs système peut nécessiter des droits élevés sur certains
systèmes. Lancez le script avec `sudo` si nécessaire :

```bash
sudo src/monitormymac.sh
```

### Est-ce compatible avec Apple Silicon (M1/M2/M3) ?
Oui. Le script utilise uniquement des outils natifs disponibles sur macOS.

---

## 5. Dépannage

| Problème | Solution |
|---|---|
| L'application ne s'ouvre pas | Faites un clic droit → **Ouvrir** |
| Aucune information affichée | Vérifiez que `/usr/sbin/system_profiler` existe |
| Nettoyage partiel | Relancez le script avec `sudo` |

Pour plus d'aide, reportez-vous à la [documentation technique](DOCUMENTATION.md)
ou ouvrez un ticket sur le dépôt GitHub.