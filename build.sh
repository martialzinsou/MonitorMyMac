#!/bin/bash
# ============================================================================
#  MonitorMyMac — script de construction (sans Xcode)
#  Auteur : Martial Zinsou
#
#  Usage :
#    ./build.sh                     compile, assemble et signe MonitorMyMac.app
#    ./build.sh --typecheck         typage complet : SDK par défaut + cible 11.0
#                                   sur les deux architectures
#    ./build.sh --icons             régénère assets/icons (tuiles) et
#                                   assets/appicon/AppIcon.icns depuis les
#                                   planches JPEG de assets/icon-sheets/
#    ./build.sh --run               construit puis ouvre l'application
#    ./build.sh --shots             construit, lance l'app et génère les captures
#    ./build.sh --zip               construit puis emballe MonitorMyMac.app.zip
#    ./build.sh --clean             supprime les artefacts de build
#
#  Produit : un binaire Universel 2 (x86_64 + arm64) dont la version plancher
#  est macOS 11.0, contrôlé à chaque build par lipo, otool et codesign.
#
#  Ce script n'installe rien et ne télécharge rien : il utilise uniquement le
#  compilateur Swift présent sur la machine (toolchain Xcode CLT).
# ============================================================================

set -euo pipefail

cd "$(dirname "$0")"

APP="MonitorMyMac.app"
BINARY="$APP/Contents/MacOS/MonitorMyMac"
RESOURCES="$APP/Contents/Resources"
SHOTS_SRC="docs/screenshots"
BUILD_DIR="build"

# Cible de déploiement et architectures.
#
# 11.0 est la version minimale annoncée : le code n'utilise plus aucune API
# macOS 12+ sans garde d'exécution (voir MMTheme.swift, section compatibilité).
# Le SDK installé sur la machine reste le SDK 13 ; c'est `-target` qui fixe la
# version plancher et qui fait refuser au compilateur les API trop récentes.
DEPLOY_MIN="11.0"
ARCHS=(x86_64 arm64)

# Sources : la coque, les moteurs (Core) et les vues (UI).
SOURCES=(src/MonitorMyMacApp.swift)
while IFS= read -r file; do SOURCES+=("$file"); done < <(ls src/Core/*.swift src/UI/*.swift 2>/dev/null)

FRAMEWORKS=(-framework SwiftUI -framework AppKit -framework UserNotifications)

notice() { printf '\033[1m▸ %s\033[0m\n' "$1"; }

# ---------------------------------------------------------------------------
#  1. Vérification de la toolchain
# ---------------------------------------------------------------------------
require_swift() {
    if ! command -v swiftc >/dev/null 2>&1; then
        echo "Erreur : swiftc introuvable. Installez les outils de ligne de commande :" >&2
        echo "    xcode-select --install" >&2
        exit 1
    fi
    notice "swiftc : $(swiftc -version 2>&1 | head -2 | tr '\n' ' ')"
}

# ---------------------------------------------------------------------------
#  2. Typage seul (beaucoup plus rapide qu'une liaison complète)
# ---------------------------------------------------------------------------
#   Le typage est fait sous la cible 11.0, pas sous la version du SDK : c'est
#   la seule façon de faire refuser au compilateur les API macOS 12+ appelées
#   sans garde. Un typage « par défaut » ne détecterait rien.
typecheck() {
    require_swift
    notice "Vérification de typage de ${#SOURCES[@]} fichiers sources…"
    swiftc -typecheck -parse-as-library "${SOURCES[@]}" "${FRAMEWORKS[@]}"
    notice "Typage OK (SDK par défaut)."

    for arch in "${ARCHS[@]}"; do
        notice "Typage cible macOS ${DEPLOY_MIN} — ${arch}…"
        swiftc -typecheck -parse-as-library -target "${arch}-apple-macosx${DEPLOY_MIN}" \
            "${SOURCES[@]}" "${FRAMEWORKS[@]}"
        notice "Typage OK pour ${arch} sous macOS ${DEPLOY_MIN}."
    done
}

# ---------------------------------------------------------------------------
#  3. Compilation + assemblage du bundle
# ---------------------------------------------------------------------------
#   Un binaire par architecture, puis assemblage Universel 2 avec lipo.
#   Le cross-assemblage arm64 depuis un Mac Intel fonctionne : le compilateur
#   produit la tranche, mais seule une machine Apple Silicon peut l'exécuter.
compile_slice() {
    local arch="$1" out="$BUILD_DIR/MonitorMyMac-${arch}"
    mkdir -p "$BUILD_DIR"
    # Le message de progression part sur stderr : la sortie standard ne doit
    # porter que le chemin, sinon `$(compile_slice …)` mélange les deux.
    printf '\033[1m  · %s → macOS %s…\033[0m\n' "$arch" "$DEPLOY_MIN" >&2
    if ! swiftc -parse-as-library -O -target "${arch}-apple-macosx${DEPLOY_MIN}" \
        "${SOURCES[@]}" "${FRAMEWORKS[@]}" -o "$out" 2>"$BUILD_DIR/${arch}.log"; then
        echo "    ! tranche ${arch} en échec — voir $BUILD_DIR/${arch}.log" >&2
        sed 's/^/      /' "$BUILD_DIR/${arch}.log" >&2
        return 1
    fi
    printf '%s\n' "$out"
}

build() {
    require_swift
    mkdir -p "$APP/Contents/MacOS" "$RESOURCES" "$BUILD_DIR"

    notice "Compilation Universel 2 (cible macOS ${DEPLOY_MIN}) de ${#SOURCES[@]} fichiers sources…"
    local start=$SECONDS slices=() arch out
    for arch in "${ARCHS[@]}"; do
        if out=$(compile_slice "$arch"); then
            slices+=("$out")
        fi
    done
    if [ ${#slices[@]} -eq 0 ]; then
        echo "Erreur : aucune tranche compilée." >&2
        exit 1
    fi
    lipo -create "${slices[@]}" -o "$BINARY"
    notice "Binaire : $(du -h "$BINARY" | cut -f1) en $((SECONDS - start)) s — $(lipo -archs "$BINARY")"
    if [ ${#slices[@]} -lt ${#ARCHS[@]} ]; then
        echo "  ! attention : ${#slices[@]} tranche(s) sur ${#ARCHS[@]} — binaire non Universel 2." >&2
    fi

    write_info_plist
    install_screenshots
    install_icons
    sign_bundle
    verify_bundle

    notice "Bundle prêt : $APP"
}

# Contrôles de ce qui sort du build : architectures, version plancher du
# chargement, signature. Sans ces lignes, on ne peut pas affirmer que
# l'application s'ouvre sur Big Sur.
verify_bundle() {
    notice "Contrôles du bundle…"
    printf '  lipo : %s\n' "$(lipo -info "$BINARY" | sed 's/.*: //')"
    printf '  file : %s\n' "$(file -b "$BINARY")"
    # `LC_BUILD_VERSION` (ou son ancêtre LC_VERSION_MIN_MACOSX) porte le champ
    # `minos` : c'est la version que le chargeur refuse en dessous, indépendamment
    # d'Info.plist.
    local minos
    minos=$(otool -l "$BINARY" 2>/dev/null \
        | awk '/LC_BUILD_VERSION|LC_VERSION_MIN_MACOSX/{f=1} f && /minos/{print $2; exit}')
    printf '  minos (chargeur) : %s\n' "${minos:-inconnu}"
    local cs
    if cs=$(codesign --verify --deep --strict --verbose=1 "$APP" 2>&1); then
        printf '  codesign : %s\n' "$(printf '%s' "$cs" | tail -1)"
    else
        printf '  codesign : ÉCHEC\n%s\n' "$(printf '%s\n' "$cs" | sed 's/^/    /')" >&2
    fi
}

# Signature ad hoc, isolée pour pouvoir être relancée après une modification
# des ressources (les captures embarquées sont couvertes par la signature).
sign_bundle() {
    notice "Signature ad hoc…"
    # macOS refuse de signer un bundle portant des attributs étendus (Finder info,
    # .DS_Store) : on les retire d'abord, sinon codesign échoue sur « detritus ».
    find "$APP" -name '.DS_Store' -delete 2>/dev/null || true
    xattr -cr "$APP" 2>/dev/null || true
    if codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1; then
        notice "Bundle signé (ad hoc)."
    else
        echo "  ! codesign a échoué : l'app reste exécutable en local, mais pas redistribuable." >&2
    fi
}

# ---------------------------------------------------------------------------
#  4. Info.plist (version alignée sur AppInfo.version du code)
# ---------------------------------------------------------------------------
write_info_plist() {
    local version
    version=$(grep -m1 'static let version' src/UI/DocsViews.swift | sed -e 's/.*= "//' -e 's/".*//' || true)
    [ -z "${version:-}" ] && version="3.0.0"
    notice "Info.plist — version $version"
    cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>fr</string>
    <key>CFBundleExecutable</key>
    <string>MonitorMyMac</string>
    <key>CFBundleIdentifier</key>
    <string>com.monitormymac.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MonitorMyMac</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025-2026 Martial Zinsou. Licence MIT.</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${version}</string>
    <key>CFBundleVersion</key>
    <string>${version}</string>
    <key>CSResourcesFileMapped</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>${DEPLOY_MIN}</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>MonitorMyMac utilise AppleScript pour vider la corbeille de Mail et demander les opérations nécessitant un administrateur.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>MonitorMyMac liste les corbeilles des volumes montés afin de vous en donner la taille réelle.</string>
</dict>
</plist>
PLIST
}

# ---------------------------------------------------------------------------
#  5. Captures embarquées (l'onglet Aide les affiche)
# ---------------------------------------------------------------------------
install_screenshots() {
    if [ -d "$SHOTS_SRC" ] && ls "$SHOTS_SRC"/*.png >/dev/null 2>&1; then
        mkdir -p "$RESOURCES/Screenshots"
        rm -f "$RESOURCES/Screenshots"/*.png
        cp "$SHOTS_SRC"/*.png "$RESOURCES/Screenshots/"
        notice "Captures embarquées : $(ls "$RESOURCES/Screenshots" | wc -l | tr -d ' ') PNG"
    else
        notice "Aucune capture dans $SHOTS_SRC — relancez ./build.sh --shots."
    fi
}

# ---------------------------------------------------------------------------
#  6. Icônes « Liquid Glass » embarquées
# ---------------------------------------------------------------------------
#  Deux choses partent dans le bundle :
#   - AppIcon.icns   : l'icône de l'application (Dock, ⌘-Tab, Finder) ;
#   - Resources/Icons: les tuiles PNG des quatre espaces et de l'en-tête.
#  Les deux sont des artefacts régénérables (`./build.sh --icons`) et non des
#  sources : sans eux, l'interface retombe sur les pastilles vectorielles, elle
#  ne casse pas. D'où l'avertissement plutôt que l'erreur.
install_icons() {
    local icns="assets/appicon/AppIcon.icns"
    if [ -f "$icns" ]; then
        cp "$icns" "$RESOURCES/AppIcon.icns"
        # `sips` lit le .icns et répond bien le nombre d'images embarquées ;
        # c'est la seule façon de vérifier que la plus grande tranche existe,
        # sans quoi le Dock rendrait un 32 px flou en pleine taille.
        local dims
        dims=$(sips -g pixelWidth -g pixelHeight "$RESOURCES/AppIcon.icns" 2>/dev/null \
            | awk '/pixelWidth/{w=$2} END{print w}')
        notice "Icône d'application : $(du -h "$RESOURCES/AppIcon.icns" | cut -f1), master ${dims:-?} px"
    else
        echo "  ! $icns absente : relancez ./build.sh --icons (l'app garde son icône générique)." >&2
    fi

    if [ -d assets/icons/tuiles ] && ls assets/icons/tuiles/*.png >/dev/null 2>&1; then
        mkdir -p "$RESOURCES/Icons"
        rm -f "$RESOURCES/Icons"/*.png
        cp assets/icons/tuiles/*.png "$RESOURCES/Icons/"
        notice "Tuiles embarquées : $(ls "$RESOURCES/Icons" | wc -l | tr -d ' ') PNG"
    else
        echo "  ! assets/icons/tuiles vide : relancez ./build.sh --icons." >&2
    fi
}

# Régénération du pack complet à partir des planches JPEG. Dépend de Python 3
# + Pillow + numpy : c'est l'étape la plus lente et la seule qui touche aux
# images, elle reste donc hors du build courant.
make_icons() {
    if ! command -v python3 >/dev/null 2>&1; then
        echo "Erreur : python3 introuvable ; le pack d'icônes ne peut pas être régénéré." >&2
        exit 1
    fi
    notice "Découpage des planches (assets/icon-sheets → assets/icons)…"
    python3 tools/extract_icons.py --contact
    notice "Fabrication de l'icône d'application (assets/appicon)…"
    python3 tools/make_app_icon.py --apercu
}

# ---------------------------------------------------------------------------
#  7. Lancement / auto-capture
# ---------------------------------------------------------------------------
run_app() {
    build
    notice "Ouverture de $APP…"
    open "$APP"
}

shots() {
    build
    mkdir -p "$SHOTS_SRC"
    notice "Auto-capture des huit onglets (balayages réels, 3 à 6 minutes)…"
    # L'application se photographie elle-même via AppKit, puis se quitte.
    "$BINARY" --shots="$PWD/$SHOTS_SRC" 2>&1 | sed 's/^/  /'
    # Sans cette étape, le bundle embarquerait les captures précédentes :
    # build() tourne avant la capture, pas après. La signature est relancée
    # parce que les ressources font partie du sceau.
    install_screenshots
    sign_bundle
    notice "Fichiers produits :"
    ls -la "$SHOTS_SRC" | sed 's/^/  /'
}

# Emplacement de MonitorMyMac.app.zip. `--keepParent` est indispensable :
# sans lui, ditto archive le contenu de Contents/ à la racine du zip, et
# l'archive décompressée n'est plus un bundle lançable.
dist_zip() {
    build
    local archive="MonitorMyMac.app.zip"
    rm -f "$archive"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$archive"
    notice "Archive : $archive ($(du -h "$archive" | cut -f1))"

    # Contrôle aller-retour : on extrait dans un dossier temporaire, puis on
    # vérifie la signature du bundle reconstitué avant de le déclarer publiable.
    local probe
    probe=$(mktemp -d)
    if ditto -x -k "$archive" "$probe" >/dev/null 2>&1 \
        && codesign --verify "$probe/$APP" >/dev/null 2>&1; then
        notice "Contrôle aller-retour : extrait et signature valide."
    else
        echo "  ! l'archive extraite ne passe pas codesign — ne pas publier." >&2
    fi
    rm -rf "$probe"
}

clean() {
    rm -rf "$BUILD_DIR" "$BINARY"
    notice "Artefacts supprimés (les sources et $APP restent en place)."
}

# ---------------------------------------------------------------------------
#  Aiguillage
# ---------------------------------------------------------------------------
case "${1:-}" in
    --typecheck) typecheck ;;
    --icons)     make_icons ;;
    --run)       run_app ;;
    --shots)     shots ;;
    --zip)       dist_zip ;;
    --clean)     clean ;;
    --help|-h)   sed -n '2,20p' "$0" ;;
    "")          build ;;
    *)           echo "Option inconnue : $1 (voir ./build.sh --help)" >&2; exit 2 ;;
esac
