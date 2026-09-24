# MonitorMyMac — Guide de démarrage

## Prérequis

- macOS 10.15 ou version ultérieure.
- CommandLineTools Swift (installable via `xcode-select --install`).
- 150 Mo d'espace disque libres minimum.

## Installation pas à pas

### Méthode graphique (recommandée)

1. Ouvrez votre navigateur et accédez à la page de release ou de téléchargement du projet.
2. Téléchargez l'archive `MonitorMyMac.zip` (ou le dossier `.app` directement).
3. Décompressez l'archive si nécessaire.
4. Faites glisser `MonitorMyMac.app` dans le dossier `Applications`.
5. Ouvrez le dossier Applications et double-cliquez sur l'icône `MonitorMyMac`.

### Depuis la ligne de commande (advanced)

```bash
# 1. Cloner le dépôt
git clone https://github.com/martialzinsou/MonitorMyMac.git

# 2. Accéder au dossier
cd MonitorMyMac

# 3. Compiler (nécessite Swift 5.8.1+)
swiftc -parse-as-library src/MonitorMyMacApp.swift \
  -framework SwiftUI -framework AppKit -framework UserNotifications \
  -o "MonitorMyMac.app/Contents/MacOS/MonitorMyMac"

# 4. Signer (nécessaire pour lancer depuis Finder sans avertissement de développeur non identifié)
codesign --force --deep --sign - "MonitorMyMac.app"

# 5. Lancer
open "MonitorMyMac.app"
```

### Contourner l'avertage "développeur non identifié"

- Clic droit → **Ouvrir** → **Ouvrir** pour la première fois.
- Ou dans Système Préférences → Confidentialité et sécurité → quand MonitorMyMac apparaît, cliquez sur **Tout de même**.

## Première utilisation

1. Au lancement, la fenêtre **Surveillance** s'affiche immédiatement.
2. Les jauges commencent à se remplir toutes les 2 secondes.
3. Cliquez sur l'onglet **Nettoyage** pour voir les options de nettoyage.
4. Cliquez sur **Optimisation** pour analyser l'espace disque.
5. Cliquez sur le bouton **?** en haut à droite pour lire l'aide intégrée.
6. Regardez la barre de menus en haut de votre écran — l'icône MonitorMyMac y reste visible.

## Mise à jour

- Redéployez simplement la nouvelle version en remplacement de l'ancienne.
- Les préférences (rappels hebdomadaires, historique) sont stockées dans `UserDefaults` et conservées automatiquement.

## Dépannage

| Problème | Solution |
|---|---|
| L'application ne s'ouvre pas | Clic droit → **Ouvrir**, puis confirmer |
| Les jauges restent à 0 % | Relancez l'application (mise à jour automatique) |
| La fenêtre ne réapparaît pas | Clic sur **MonitorMyMac** dans la barre de menus |
| Nettoyage partiel | Exécutez le script CLI en `sudo` (voir doc technique) |
| L'icône de barre de menus n'apparaît pas | Vérifiez que l'application n'est pas arrêtée dans Activity Monitor |

---