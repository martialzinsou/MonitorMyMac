# MonitorMyMac

[![macOS](https://img.shields.io/badge/macOS-10.15%2B-blue)](https://www.apple.com/macos/)
[![Version](https://img.shields.io/badge/version-1.0.0-green)]()
[![License](https://img.shields.io/badge/license-MIT-yellow)]()

**MonitorMyMac** est une application native macOS qui permet de **surveiller** et **optimiser** son Mac de manière simple et rapide.

---

## Fonctionnalités

| Catégorie | Fonction | Description |
|---|---|---|
| 📊 **Monitoring** | Informations système | Modèle, processeur, mémoire, UUID, SMC |
| 📊 **Monitoring** | CPU | Marque, modèle et nombre de cœurs |
| 📊 **Monitoring** | Mémoire (RAM) | Pages libres, actives, compressées |
| 📊 **Monitoring** | Disque | Utilisation et espace disponible par volume |
| 🧹 **Nettoyage** | Caches | Suppression des caches utilisateur (.cache / .log) |
| 🧹 **Nettoyage** | Fichiers temporaires | Nettoyage de `/tmp` (> 60 min) |
| 🧹 **Nettoyage** | Logs système | Suppression des logs de plus de 24h |
| 🧹 **Nettoyage** | Corbeille | Vider la corbeille automatiquement |
| ⚡ **Optimisation** | Gros fichiers | Détection des fichiers > 100 Mo pour libérer de l'espace |

---

## Démarrage rapide

### Option 1 : Exécuter directement la source (recommandé pour les développeurs)

```bash
chmod +x src/monitormymac.sh
./src/monitormymac.sh
```

### Option 2 : Lancer l'application macOS

```bash
open MonitorMyMac.app
```

### Option 3 : Depuis le Finder

Double-cliquez sur `MonitorMyMac.app`.

---

## Structure du projet

```
MonitorMyMac/
├── MonitorMyMac.app/           # Application macOS (bundle)
│   └── Contents/
│       ├── Info.plist          # Fichier de configuration du bundle
│       └── MacOS/
│           └── MonitorMyMac    # Script exécutable principal
├── src/
│   └── monitormymac.sh         # Code source principal
├── docs/
│   ├── GUIDE.md                # Guide utilisateur
│   └── DOCUMENTATION.md        # Documentation technique
└── README.md                   # Ce fichier
```

---

## Prérequis

- macOS **10.15 (Catalina)** ou supérieur
- Processeur **Intel** ou **Apple Silicon**
- Aucune installation de dépendance nécessaire (100 % natif)

---

## Exemple de sortie

```
=========================================
MonitorMyMac v1.0.0 - Monitoring & Optimization
=========================================

--- Informations Systeme ---
    Model Name: MacBook Pro
    Processor Name: Quad-Core Intel Core i7
    Memory: 16 GB
    ...

--- Utilisation du Disque ---
Filesystem     Size  Used  Avail Capacity
/dev/disk1s4s1 954Gi 21Gi  640Gi    4%

--- Nettoyage des Caches et Fichiers Temporaires ---
[OK] /tmp nettoyé (fichiers de plus de 60 min)
[OK] Caches utilisateur nettoyés (fichiers de plus de 2h)
[OK] Logs système nettoyés (plus de 24h)
[OK] Corbeille vidée
```

---

## Documentation

- [Guide utilisateur](docs/GUIDE.md) - Comment utiliser MonitorMyMac au quotidien
- [Documentation technique](docs/DOCUMENTATION.md) - Architecture et code source

---

## Licence

Distribué sous licence MIT. Voir le fichier `LICENSE` pour plus d'informations.