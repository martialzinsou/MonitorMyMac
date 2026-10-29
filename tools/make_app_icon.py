#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Fabrique l'icône d'application MonitorMyMac (.icns) à partir des planches
« Liquid Glass » fournies, détourées par `extract_icons.py`.

Pourquoi partir d'un glyphe extrait plutôt que d'un dessin vectorisé : la
demande est une icône qui parle le même langage visuel que les pastilles de
l'interface. Le gabarit, lui, est calculé (aucun pixel importé) : squircle en
superelliptique adouci, dégradé graphite, reflet spéculaire en biais, liseré
de verre de 1,6 px — ce que fait `compose_tuile`, aux proportions macOS près.

Le gabarit est vectoriel, le glyphe est raster. C'est la limite réelle du
résultat et elle est mesurée ici : la cellule native d'une planche de
2 752 × 1 536 px donne un carré de ~250-320 px de glyphe. Pour un master
1 024 px, le glyphe est donc agrandi d'un facteur ~3 ; les rendus 512 et 1024
sont en augmentation, pas en réduction. Le script l'affiche au lieu de le
cacher, et le journal JSON le consigne.

Gabarit Apple (grille « icon ») : le coin arrondi occupe ~81 % du canevas à
partir de 64 px, et presque tout le canevas en dessous de 32 px — sans ce
rattrapage, un 16 px devient illisible dans le Dock.

Usage :
    python3 tools/make_app_icon.py                     # moniteur-systeme
    python3 tools/make_app_icon.py --glyphe jauge
    python3 tools/make_app_icon.py --apercu             # planche de contrôle
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import extract_icons as ei                                 # noqa: E402

RACINE = ei.RACINE
SORTIE = RACINE / "assets/appicon"
ICONSET = SORTIE / "AppIcon.iconset"
ICNS = SORTIE / "AppIcon.icns"

# Taille du canevas → (fraction occupée par le squircle, arrondi relatif,
# marge laissée autour du glyphe dans le squircle).
ECHELLES = [
    (16,   1.00, 0.26, 0.16),
    (32,   0.94, 0.255, 0.145),
    (64,   0.88, 0.25, 0.13),
    (128,  0.85, 0.235, 0.115),
    (256,  0.82, 0.235, 0.105),
    (512,  0.81, 0.235, 0.10),
    (1024, 0.81, 0.235, 0.10),
]

NOMS_ICONS = {
    16: "icon_16x16.png",          32: "icon_16x16@2x.png",
    64: "icon_32x32@2x.png",      128: "icon_128x128.png",
    256: "icon_128x128@2x.png",   512: "icon_256x256@2x.png",
    1024: "icon_512x512@2x.png",
}
# Les deux tailles manquantes (32×32 natif, 256×256 natif, 512×512 natif) sont
# des réductions exactes des masters : iconutil les exige sous des noms précis.
MANQUANTS = {
    32:  (64,  "icon_32x32.png"),
    256: (512, "icon_256x256.png"),
    512: (1024, "icon_512x512.png"),
}


def rendu(taille, ratio, coin, marge, rgba, sursampling=2):
    """Un rendu `taille` × `taille`, calculé à `taille × sursampling` puis réduit.

    Le sursampling est là pour l'arrondi : à 16 px, un bord dessiné à 16 px
    dente visiblement, alors qu'un bord dessiné à 32 px et réduit en
    pré-multiplié reste lisse.
    """
    grand = taille * sursampling
    forme = int(round(grand * ratio))
    tuile = ei.compose_tuile(rgba, forme, coin=coin, marge=marge)
    canevas = np.zeros((grand, grand, 4), dtype=np.uint8)
    depart = (grand - forme) // 2
    a = tuile[..., 3:4].astype(np.float64) / 255.0
    zone = canevas[depart:depart + forme, depart:depart + forme, :3].astype(np.float64)
    mix = tuile[..., :3].astype(np.float64) * a + zone * (1 - a)
    canevas[depart:depart + forme, depart:depart + forme] = np.clip(
        np.dstack([mix, tuile[..., 3]]), 0, 255).astype(np.uint8)
    petit = ei.redimensionne_premultiplie(canevas.astype(np.float64), taille)
    return petit


def compose_fond(petits, fond, taille):
    """Pose une icône sur un fond : ce que verront le Dock et le Finder."""
    toiles = Image.new("RGB", (taille, taille), fond)
    img = Image.fromarray(petits)
    a = np.asarray(img)[..., 3:4].astype(np.float64) / 255.0
    rgb = np.asarray(img)[..., :3].astype(np.float64)
    zone = np.asarray(toiles).astype(np.float64)
    zone[:] = rgb * a + zone * (1 - a)
    return Image.fromarray(zone.astype(np.uint8))


def apercu(masters, nom, chemin):
    """Bande de contrôle : chaque taille, à sa taille réelle, sur fond clair
    puis sombre — le test du Dock, sans ouvrir le Dock."""
    ordre = [16, 32, 64, 128, 256, 512]
    vus = [min(o, 256) for o in ordre]
    hauteur = 256 + 60
    largeur = sum(v + 24 for v in vus) + 40
    plan = Image.new("RGB", (largeur, hauteur * 2), (255, 255, 255))
    px = np.asarray(plan).astype(np.float64)
    px[hauteur:, :] = 24.0
    plan = Image.fromarray(px.astype(np.uint8))
    x = 20
    for taille, pose_taille in zip(ordre, vus):
        for saut, fond in ((0, (236, 236, 240)), (hauteur, (24, 24, 26))):
            img = compose_fond(masters[taille], fond, taille)
            if pose_taille != taille:
                img = img.resize((pose_taille, pose_taille), Image.LANCZOS)
            plan.paste(img, (x + (256 - pose_taille) // 2,
                             saut + 30 + (256 - pose_taille) // 2))
        x += pose_taille + 24
    plan.save(chemin)
    return chemin


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--glyphe", default="moniteur-systeme",
                    help="nom d'un glyphe extrait (voir assets/icons/)")
    ap.add_argument("--apercu", action="store_true",
                    help="écrit une bande de contrôle des tailles")
    args = ap.parse_args()

    if args.glyphe not in ei.PLAN:
        print(f"Glyphe inconnu : {args.glyphe}. Choix : "
              f"{', '.join(sorted(ei.PLAN))}")
        return 2

    rgba, coté, (w, h) = ei.brut(args.glyphe)
    facteur = 1024 * 0.81 * (1 - 2 * 0.10) / max(w, h)
    print(f"glyphe : {args.glyphe} — natif {w}×{h} px dans un carré de {coté} px")
    print(f"agrandissement vers le master 1024 : ×{facteur:.2f} "
          f"(au-delà de ×1, ce n'est plus de l'information native)")

    ICONSET.mkdir(parents=True, exist_ok=True)
    masters, journal = {}, {}
    for taille, ratio, coin, marge in ECHELLES:
        img = rendu(taille, ratio, coin, marge, rgba)
        masters[taille] = img
        Image.fromarray(img).save(ICONSET / NOMS_ICONS[taille])
        journal[str(taille)] = {"ratio_gabarit": ratio, "marge_glyphe": marge,
                                "coefficient_agrandissement": round(facteur, 2)}
    for taille, (source, nom) in MANQUANTS.items():
        Image.fromarray(masters[source]).resize((taille, taille), Image.LANCZOS) \
            .save(ICONSET / nom)

    if ICNS.exists():
        ICNS.unlink()
    subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(ICNS)],
                   check=True)
    Image.fromarray(masters[1024]).save(SORTIE / "AppIcon-1024.png")
    with (SORTIE / "appicon.json").open("w", encoding="utf-8") as fh:
        json.dump({"glyphe": args.glyphe, "natif_px": [w, h],
                   "cote_carre_px": coté, "tailles": journal},
                  fh, indent=2, ensure_ascii=False, sort_keys=True)

    tailles = sorted(p.name for p in ICONSET.glob("*.png"))
    print(f"iconset : {len(tailles)} PNG — {', '.join(tailles)}")
    print(f"icns    : {ICNS} ({ICNS.stat().st_size:,} o)")

    if args.apercu:
        chemin = apercu(masters, args.glyphe, Path("/tmp/appicon-tailles.png"))
        print(f"aperçu  : {chemin}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
