#!/bin/bash
# ============================================================================
#  MonitorMyMac - Monitoring & Optimization Tool for macOS
#  Version: 1.0.0
#  Description:
#    MonitorMyMac est un outil simple et natif pour macOS permettant de :
#      - Surveiller l'état de son Mac (CPU, mémoire, disque, matériel)
#      - Nettoyer les caches et fichiers temporaires
#      - Optimiser les performances du système
#    Compatible macOS 10.15 et supérieur (Intel & Apple Silicon)
# ============================================================================

set -u

VERSION="1.0.0"
SEPARATOR="========================================="

# ---------------------------------------------------------------------------
# Affichage de l'en-tête du programme
# ---------------------------------------------------------------------------
print_header() {
    echo "$SEPARATOR"
    echo "MonitorMyMac v$VERSION - Monitoring & Optimization"
    echo "$SEPARATOR"
    echo ""
}

# ---------------------------------------------------------------------------
# AESEc: Affiche les informations matérielles du Mac
# Utilise: /usr/sbin/system_profiler
# ---------------------------------------------------------------------------
show_system_info() {
    echo "--- Informations Systeme ---"
    if [ -x "/usr/sbin/system_profiler" ]; then
        /usr/sbin/system_profiler SPHardwareDataType 2>/dev/null | head -20
        echo ""
    else
        echo "[WARN] system_profiler introuvable."
    fi
}

# ---------------------------------------------------------------------------
# Affiche les informations sur le CPU
# Utilise: /usr/sbin/sysctl
# ---------------------------------------------------------------------------
show_cpu_info() {
    echo "--- Informations CPU ---"
    if [ -x "/usr/sbin/sysctl" ]; then
        echo "Processeur: $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
        echo "Cœurs logiques: $(sysctl -n hw.ncpu 2>/dev/null)"
        echo ""
    else
        echo "[WARN] sysctl introuvable."
    fi
}

# ---------------------------------------------------------------------------
# Affiche l'état de la mémoire vive (RAM)
# Utilise: /usr/bin/vm_stat
# ---------------------------------------------------------------------------
show_memory_status() {
    echo "--- Etat Memoire (RAM) ---"
    if [ -x "/usr/bin/vm_stat" ]; then
        /usr/bin/vm_stat 2>/dev/null
        echo ""
    else
        echo "[WARN] vm_stat introuvable."
    fi
}

# ---------------------------------------------------------------------------
# Affiche l'utilisation du disque
# Utilise: /bin/df
# ---------------------------------------------------------------------------
show_disk_usage() {
    echo "--- Utilisation du Disque ---"
    if [ -x "/bin/df" ]; then
        /bin/df -h 2>/dev/null
        echo ""
    else
        echo "[WARN] df introuvable."
    fi
}

# ---------------------------------------------------------------------------
# NETTOYAGE : Caches, fichiers temporaires, logs et corbeille
# ---------------------------------------------------------------------------
cleanup_caches() {
    echo "--- Nettoyage des Caches et Fichiers Temporaires ---"

    # 1. Fichiers temporaires dans /tmp (plus de 60 minutes)
    if [ -d "/tmp" ]; then
        find "/tmp" -maxdepth 1 -type f -mmin +60 -exec rm -f {} \; 2>/dev/null
        echo "[OK] /tmp nettoyé (fichiers de plus de 60 min)"
    fi

    # 2. Caches utilisateur (fichiers .cache et .log de plus de 2h)
    local cache_dir="$HOME/Library/Caches"
    if [ -d "$cache_dir" ]; then
        find "$cache_dir" -type f -name "*.cache" -mmin +120 -exec rm -f {} \; 2>/dev/null
        find "$cache_dir" -type f -name "*.log" -mmin +120 -exec rm -f {} \; 2>/dev/null
        echo "[OK] Caches utilisateur nettoyés (fichiers de plus de 2h)"
    fi

    # 3. Logs système (plus de 24 heures)
    local log_dir="/private/var/log"
    if [ -d "$log_dir" ]; then
        find "$log_dir" -type f -name "*.log" -mmin +1440 -exec rm -f {} \; 2>/dev/null
        echo "[OK] Logs système nettoyés (plus de 24h)"
    fi

    # 4. Corbeille
    rm -rf "$HOME/.Trash/"* 2>/dev/null
    echo "[OK] Corbeille vidée"

    echo ""
}

# ---------------------------------------------------------------------------
# OPTIMISATION : Rapporte les gros fichiers pour libération d'espace
# ---------------------------------------------------------------------------
find_large_files() {
    echo "--- Gros Fichiers (rapport) ---"
    local large_files
    large_files=$(find "$HOME/Downloads" "$HOME/Documents" "$HOME/Desktop" \
                  -type f -size +100M 2>/dev/null | head -10)

    if [ -n "$large_files" ]; then
        echo "Gros fichiers trouvés (>100 Mo) :"
        echo "$large_files"
        echo ""
        echo "Astuce : Supprimez-les manuellement dans le Finder pour libérer de l'espace."
    else
        echo "Aucun gros fichier trouvé dans les emplacements courants."
    fi

    echo ""
}

# ---------------------------------------------------------------------------
# Point d'entrée principal
# ---------------------------------------------------------------------------
main() {
    print_header
    show_system_info
    show_cpu_info
    show_memory_status
    show_disk_usage
    cleanup_caches
    find_large_files

    echo "$SEPARATOR"
    echo "MonitorMyMac v$VERSION - Optimisation terminée"
    echo "$SEPARATOR"
}

main "$@"