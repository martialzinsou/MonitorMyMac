# Documentation Technique - MonitorMyMac

Documentation destinée aux développeurs souhaitant comprendre, modifier ou
étendre MonitorMyMac.

---

## 1. Architecture

### 1.1 Vue d'ensemble

MonitorMyMac est une application native macOS conçue en **Bash** et utilisant
uniquement les **utilitaires système Apple** disponibles sur toutes les
installations de macOS. Aucune dépendance externe n'est requise.

```
┌─────────────────────────────────────────────────┐
│            MonitorMyMac (Bash)                  │
├─────────────────────────────────────────────────┤
│  print_header()        → En-tête de sortie      │
│  show_system_info()    → system_profiler        │
│  show_cpu_info()       → sysctl                 │
│  show_memory_status()  → vm_stat                │
│  show_disk_usage()     → df                     │
│  cleanup_caches()      → find + rm              │
│  find_large_files()    → find                   │
│  main()                → Point d'entrée         │
└─────────────────────────────────────────────────┘
```

### 1.2 Processus d'exécution

1. `main()` est appelé avec tous les arguments du script.
2. Les fonctions de **monitoring** collectent et affichent les données système.
3. Les fonctions de **nettoyage** suppriment les fichiers obsolètes.
4. La fonction d'**optimisation** génère un rapport des gros fichiers.

---

## 2. Code source commenté

### 2.1 Gestion des erreurs

- `set -u` : le script s'arrête silencieusement en cas de variable non définie.
- Les utilitaires sont vérifiés avec `[ -x "path" ]` avant exécution.
- Les commandes `find` / `rm` utilisent `-exec ... \; 2>/dev/null` pour ne pas
  bloquer en cas de fichiers protégés.

### 2.2 Sécurité

- Le script ne supprime **que** les fichiers dans des répertoires bien définis :
  `/tmp`, `~/Library/Caches`, `/private/var/log`, `~/.Trash`.
- Aucune commande en `suid` n'est exécutée.
- Les noms de chemins sont toujours entre guillemets doubles pour éviter les
  problèmes avec les espaces.

---

## 3. Utilitaires système utilisés

| Outil | Chemin | Rôle |
|---|---|---|
| `system_profiler` | `/usr/sbin/system_profiler` | Infos matérielles détaillées |
| `sysctl` | `/usr/sbin/sysctl` | Paramètres et stats du noyau |
| `vm_stat` | `/usr/bin/vm_stat` | Statistiques mémoire virtuelle |
| `df` | `/bin/df` | Utilisation des systèmes de fichiers |
| `find` | `/usr/bin/find` | Recherche et suppression de fichiers |

---

## 4. Bundle macOS (.app)

### 4.1 Structure

```
MonitorMyMac.app/
└── Contents/
    ├── Info.plist      # Configuration du bundle
    └── MacOS/
        └── MonitorMyMac  # Script bash exécutable
```

### 4.2 `Info.plist`

| Clé | Valeur | Description |
|---|---|---|
| `CFBundleExecutable` | `MonitorMyMac` | Nom de l'exécutable |
| `CFBundleIdentifier` | `com.monitormymac.monitormymac` | Identifiant unique |
| `CFBundleName` | `MonitorMyMac` | Nom affiché |
| `CFBundleVersion` | `1.0` | Version du bundle |
| `LSMinimumSystemVersion` | `10.15` | Version minimale macOS |
| `CFBundlePackageType` | `APPL` | Type : application |

### 4.3 Régénérer l'exécutable

Après modification du script source, copiez-le dans le bundle :

```bash
cp src/monitormymac.sh "MonitorMyMac.app/Contents/MacOS/MonitorMyMac"
chmod +x "MonitorMyMac.app/Contents/MacOS/MonitorMyMac"
```

---

## 5. Étendre MonitorMyMac

### Ajouter une nouvelle fonction de monitoring

Créez une fonction et appelez-la dans `main()` :

```bash
show_battery_info() {
    echo "--- Batterie ---"
    system_profiler SPPowerDataType 2>/dev/null | head -15
}
```

### Ajouter une nouvelle fonction de nettoyage

```bash
cleanup_downloads() {
    echo "--- Nettoyage des Téléchargements ---"
    find "$HOME/Downloads" -type f -mtime +30 -exec rm -f {} \; 2>/dev/null
    echo "[OK] Téléchargements de plus de 30 jours supprimés"
}
```

---

## 6. Tests

### Test manuel

```bash
./src/monitormymac.sh
```

### Validation de la syntaxe

```bash
bash -n src/monitormymac.sh   # Aucune sortie = syntaxe valide
shellcheck src/monitormymac.sh  # Linter (si installé)
```

### Vérification du bundle

```bash
open MonitorMyMac.app
```

---

## 7. Historique des versions

| Version | Date | Changements |
|---|---|---|
| 1.0.0 | 2025 | Version initiale : monitoring, nettoyage, optimisation |