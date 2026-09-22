# MonitorMyMac

[![macOS](https://img.shields.io/badge/macOS-10.15%2B-blue)](https://www.apple.com/macos/)
[![Version](https://img.shields.io/badge/version-2.0.0-green)]()
[![Language](https://img.shields.io/badge/language-SwiftUI-orange)]()
[![License](https://img.shields.io/badge/license-MIT-yellow)]()

**MonitorMyMac** est une application **native macOS** élégante et conviviale qui vous permet de **surveiller**, **nettoyer** et **optimiser** votre Mac en un clin d'œil.

> ✨ Interface moderne : cartes vitrées, jauges animées, statistiques en temps réel
> et mode sombre/clair automatique — le tout en **SwiftUI** 100 % natif.

---

## Fonctionnalités

### 📊 Surveillance en temps réel
| Fonction | Description |
|---|---|
| **Processeur** | Jauge annulaire de l'utilisation CPU + modèle & nombre de cœurs |
| **Mémoire (RAM)** | Jauge annulaire + Go utilisés / Go disponibles |
| **Stockage** | Barre de progression + espace utilisé / disponible |
| **Système** | Modèle, version macOS, mémoire totale, durée d'activité |
| **Rafraîchissement** | Mises à jour automatiques toutes les 2 secondes + bouton d'actualisation |

### 🧹 Nettoyage intelligent
| Fonction | Description |
|---|---|
| **Fichiers temporaires** | Nettoyage de `/tmp` (plus de 60 min) |
| **Caches utilisateur** | Suppression des caches `.cache` / `.log` (plus de 2 h) |
| **Logs système** | Logs de plus de 24 h (selon les permissions) |
| **Corbeille** | Vidage automatique de la corbeille |

### ⚡ Optimisation
| Fonction | Description |
|---|---|
| **Analyse de l'espace** | Détection des fichiers volumineux (> 100 Mo) dans Downloads, Documents et Bureau |

---

## Démarrage rapide

### Option 1 : Lancer l'application macOS (recommandé)

```bash
open MonitorMyMac.app
```

Ou double-cliquez simplement sur `MonitorMyMac.app` dans le Finder.

### Option 2 : Compiler depuis la source (développeurs)

```bash
swiftc -parse-as-library src/MonitorMyMacApp.swift -framework SwiftUI \
  -o MonitorMyMac.app/Contents/MacOS/MonitorMyMac
```

---

## Structure du projet

```
MonitorMyMac/
├── MonitorMyMac.app/           # Application macOS (bundle)
│   └── Contents/
│       ├── Info.plist          # Fichier de configuration du bundle
│       └── MacOS/
│           └── MonitorMyMac    # Binaire natif SwiftUI compilé
├── src/
│   ├── MonitorMyMacApp.swift   # Code source principal (SwiftUI)
│   └── monitormymac.sh         # Ancien outil CLI (bonus)
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

## Aperçu de l'interface

- **En-tête** : logo dégradé, titre, bouton de rafraîchissement
- **Onglets** : `Surveillance` · `Nettoyage` · `Optimisation`
- **Grille de cartes** : jauges animées et informations système
- **Journal** : liste des actions effectuées
- **Pied de page** : statut en direct de l'application

---

## Documentation

- [Guide utilisateur](docs/GUIDE.md) - Comment utiliser MonitorMyMac au quotidien
- [Documentation technique](docs/DOCUMENTATION.md) - Architecture et code source

---

## Licence

Distribué sous licence MIT. Voir le fichier `LICENSE` pour plus d'informations.