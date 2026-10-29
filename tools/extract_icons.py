#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Découpe les deux planches « Liquid Glass » fournies en icônes PNG à fond
transparent, prêtes à être embarquées dans MonitorMyMac.

Pourquoi un script et pas un détourage manuel : les 59 glyphes doivent tous
subir exactement le même traitement, et la planche d'origine est archivée dans
`assets/icon-sheets/` avec son empreinte SHA-256. Régénérer `assets/icons/` ne
demande alors qu'une commande.

Le fond des planches n'est pas transparent mais d'un gris très sombre quasi
uniforme. On récupère donc une matte par cellule :

    alpha = (luminance(pixel) - luminance(fond)) / (p99 - luminance(fond))

puis on « décoince » la couleur du fond (`rgb - fond·(1-α)) / α`), ce qui
rend un verre lumineux se posant aussi bien sur un thème clair que sombre.
Le redimensionnement se fait en couleurs pré-multipliées pour éviter la
frange sombre qu'un Lanczos naïf laisse autour des bords translucides.
"""

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

RACINE = Path(__file__).resolve().parent.parent
PLANCHE1 = RACINE / "assets/icon-sheets/planche-1-24-icones.jpeg"
PLANCHE2 = RACINE / "assets/icon-sheets/planche-2-35-icones.jpeg"
SORTIE = RACINE / "assets/icons"
TUILES = RACINE / "assets/icons/tuiles"

# Grilles régulières, mesurées sur les fichiers (2752 × 1536 px) :
#  - planche 1 : 6 colonnes × 4 lignes, cellule de 458,7 × 384,0 px
#  - planche 2 : 7 colonnes × 5 lignes, cellule de 393,1 × 307,2 px
GRILLE1 = (6, 4)
GRILLE2 = (7, 5)

# Nom de fichier → (planche, ligne, colonne). Les libellés imprimés sous chaque
# glyphe servent de légende humaine ; ici on nomme par usage dans l'app.
PLAN = {
    # — Planche 2 (style le plus régulier) —
    "purge":            (2, 0, 0),   # Purge globale — Balai
    "fichiers-inutiles": (2, 0, 1),  # Fichiers système inutiles
    "gros-fichiers":    (2, 0, 2),   # Gros fichiers
    "doublons":         (2, 0, 3),   # Doublons
    "corbeilles":       (2, 0, 4),   # Vider corbeilles
    "caches":           (2, 0, 5),   # Fichiers caches
    "historiques":      (2, 0, 6),   # Historiques
    "performance":      (2, 1, 0),   # Performances — Fusée
    "ram":              (2, 1, 1),   # Libérer la RAM
    "démarrage":        (2, 1, 2),   # Démarrage
    "scripts":          (2, 1, 3),   # Scripts de maintenance
    "cpu":              (2, 1, 4),   # Contrôle CPU
    "batterie":         (2, 1, 5),   # Gestion batterie
    "processus":        (2, 1, 6),   # Processus
    "applications":     (2, 2, 0),   # Gestion des apps — Engrenage
    "désinstallation":  (2, 2, 1),   # Désinstallation
    "mises-a-jour":     (2, 2, 2),   # Mises à jour
    "extensions":       (2, 2, 3),   # Extensions — Puzzle
    "widgets":          (2, 2, 4),   # Widgets & Plug-ins
    "préférences":      (2, 2, 5),   # Préférences
    "désactivation":    (2, 2, 6),   # Désactivation
    "securite":         (2, 3, 0),   # Sécurité — Cadenas
    "anti-malware":     (2, 3, 1),   # Anti-malware — Bouclier + loupe
    "donnees-web":      (2, 3, 2),   # Données web — Cookie brisé
    "confidentialité":  (2, 3, 3),   # Confidentialité
    "fichiers-sensibles": (2, 3, 4), # Fichiers sensibles
    "mots-de-passe":    (2, 3, 5),   # Mots de passe
    "anti-espion":      (2, 3, 6),   # Anti-espion
    "simplicite-ux":    (2, 4, 0),   # Simplicité UX
    "compatibilité":    (2, 4, 1),   # Compatibilité
    "theme-clair-sombre": (2, 4, 2), # Interface Dark/Light
    "optimiseur":       (2, 4, 3),   # Optimiseur système
    "accessibilité":    (2, 4, 4),   # Accessibilité
    "autorisations":    (2, 4, 5),   # Autorisations
    "moniteur-systeme": (2, 4, 6),   # Moniteur système
    # — Planche 1 (quelques variantes gardées sous la main) —
    "balai":            (1, 0, 0),   # Balai — variante de « purge »
    "memoire-cache":    (1, 0, 5),   # Données numériques
    "jauge":            (1, 1, 4),   # Compteur de vitesse
    "puce-apple":       (1, 3, 4),   # Puce Apple x86
    "traductions":      (1, 0, 1),   # Fichier et Ciseaux
    "mises-a-jour-restes": (1, 2, 2),# Flèches circulaires
}

TAILLE_CIBLE = 256          # 256 px pour une pastille de ~44 pt : large même en @3x
SEUIL_LUM = 60              # en dessous : c'est le fond de la planche
MARGE = 0.05                # respiration autour du glyphe, en fraction


def runs(tab, mini):
    """Intervalles [début, fin) où tab > 0, de longueur au moins `mini`."""
    out, start = [], None
    for i, on in enumerate(tab):
        if on and start is None:
            start = i
        elif not on and start is not None:
            if i - start >= mini:
                out.append((start, i))
            start = None
    if start is not None and len(tab) - start >= mini:
        out.append((start, len(tab)))
    return out


def _signatures(masque):
    """Par ligne : pixels allumés et nombre de traverses continues."""
    lignes = []
    for row in masque:
        v = row.astype(np.int8)
        transitions = int((np.diff(v) == 1).sum()) + (1 if v[0] else 0)
        lignes.append((int(row.sum()), transitions))
    return lignes


def zone_glyphe(cell):
    """Bande de lignes du glyphe, puis emprise horizontale de cette bande.

    Le libellé collé sous l'icône est aussi lumineux qu'elle, et le vide qui
    les sépare tient parfois d'une seule ligne : « une ligne allumée = texte »
    échouait et gardait les mots dans le crop. Ce qui les distingue vraiment,
    c'est la **structure** : une ligne de glyphe est une ou deux traverses
    continues, une ligne de texte en est une dizaine (`runs` mesuré sur les
    deux planches : 1-3 pour le verre, 5-20 pour les lettres). On ne coupe que
    devant trois lignes structurées ainsi d'affilée, pour ne pas tronquer un
    glyphe ponctué d'étincelles.
    """
    masque = cell.max(axis=2) > SEUIL_LUM
    sig = _signatures(masque)
    H = masque.shape[0]
    # Un glyphe dense (le cadran d'une horloge, les traits d'un « RAM ») a lu
    # même plusieurs traverses par ligne : seul le **placement** discerne
    # vraiment l'icône du libellé. En haut de cellule traîne la fin du libellé
    # de la ligne précédente (les planches le laissent déborder), en bas
    # commence le sien. Hors de ces deux zones, on ne déclare rien texte.
    zone_libelle = [i <= 0.15 * H or i >= 0.72 * H for i in range(H)]
    texte = [zone_libelle[i] and tr >= 4 and b > 8 for i, (b, tr) in enumerate(sig)]
    valide = [b > 2 and not t for (b, _), t in zip(sig, texte)]

    bandes = runs(valide, 3)
    # Deux parties d'un même glyphe séparées par quelques lignes à peine
    # lumineuses (le trait fin d'un curseur) ne sont pas deux objets : on les
    # recolle. Mais jamais devant une bande « structurée » comme du texte —
    # sans ce garde-fou, le libellé recollait au glyphe par-dessus la ligne
    # vide qui les sépare, et ressortait dans le PNG.
    def transitions_moyennes(a, b):
        v = [tr for (_, tr), ok in zip(sig[a:b], valide[a:b]) if ok]
        return sum(v) / len(v) if v else 0.0

    mergees = []
    for b in bandes:
        jointure_ok = (mergees
                       and b[0] - mergees[-1][1] <= 14
                       and not any(texte[mergees[-1][1]:b[0]])
                       and transitions_moyennes(*b) < 4.0)
        if jointure_ok:
            mergees[-1] = (mergees[-1][0], b[1])
        else:
            mergees.append(list(b))
    bandes = [tuple(b) for b in mergees if b[1] - b[0] >= 40]
    if not bandes:
        bandes = [b for b in runs([b > 2 for b, _ in sig], 40)]
    if not bandes:
        raise ValueError("aucun glyphe détecté dans cette cellule")
    y0, y1 = max(bandes, key=lambda b: b[1] - b[0])

    # En largeur, plus grande traverse continue (à 6 px de jour près) : un
    # fragment de l'icône voisine reste ainsi hors du cadre au lieu d'élargir
    # l'emprise jusqu'à lui.
    cols = masque[y0:y1].sum(axis=0) > 1
    sautees, start = [], None
    for i, on in enumerate(list(cols) + [False]):
        if on and start is None:
            start = i
        elif not on and start is not None:
            sautees.append((start, i))
            start = None
    fusionnees = []
    for a, b in sautees:
        if fusionnees and a - fusionnees[-1][1] <= 6:
            fusionnees[-1] = (fusionnees[-1][0], b)
        else:
            fusionnees.append((a, b))
    if not fusionnees:
        raise ValueError("bande vide")
    gx0, gx1 = max(fusionnees, key=lambda s: s[1] - s[0])
    return y0, y1, gx0, gx1


def trouves(alpha, seuil=0.35):
    """Pixels sombres **encerclés** par le glyphe : sa silhouette pleine.

    Une matte de luminance ne peut pas distinguer le fond de la planche (gris
    ~23) d'une zone sombre *faisant partie* du dessin — l'écran d'un moniteur,
    l'intérieur d'un cadran. Ces pixels partent à alpha 0 et l'icône ressort
    mitée de trous noirs. On les récupère par remplissage de trous : tout ce
    qu'une inondation partie du bord de la cellule n'atteint pas est clos, donc
    intérieur. Si le contour du glyphe est ouvert, l'inondation entre et rien
    n'est déclaré clos — le mode de défaillance est « aucun changement », pas
    « aplat ».
    """
    vide = alpha < seuil
    front = np.zeros_like(vide)
    front[0, :] = front[-1, :] = front[:, 0] = front[:, -1] = True
    front &= vide
    while front.any():                      # dilatation 4-voisins jusqu'à saturation
        suivant = (np.roll(front, 1, 0) | np.roll(front, -1, 0)
                   | np.roll(front, 1, 1) | np.roll(front, -1, 1))
        suivant &= vide & ~front
        if not suivant.any():
            break
        front |= suivant
    return vide & ~front


def detoure(cell):
    """Fond sombre → alpha, avec couleur décoincée du fond."""
    fond = np.median(cell.reshape(-1, 3), axis=0)
    lum = cell.max(axis=2).astype(np.float64)
    lum_fond = float(fond.max())
    ref = float(np.percentile(lum[lum > SEUIL_LUM], 99)) if (lum > SEUIL_LUM).any() else 255.0
    ref = max(ref, lum_fond + 40.0)
    alpha = np.clip((lum - lum_fond) / (ref - lum_fond), 0.0, 1.0)
    alpha = alpha ** 0.85                      # affermit les bords sans les casser
    alpha[alpha < 0.05] = 0.0                  # tue le bruit JPEG résiduel
    # Le verre est translucide par nature : un filtre médian 3×3 sur la matte
    # efface le grain JPEG sans entamer les contours du glyphe.
    alpha = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8))
                       .filter(ImageFilter.MedianFilter(3))).astype(np.float64) / 255.0

    # Les zones sombres *closes* du dessin redeviennent opaques. La formule de
    # décoinage appliquée à alpha ≈ 0,94 rend presque exactement la couleur
    # d'origine du pixel : l'écran d'un moniteur s'affiche en écran éteint au
    # lieu d'un trou noir, et un cadran garde son fond. Le flou de 0,8 px évite
    # la bordure nette sur le pourtour de la zone récupérée.
    clos = trouves(alpha)
    if clos.any():
        adouc = np.asarray(Image.fromarray((clos * 255).astype(np.uint8))
                           .filter(ImageFilter.GaussianBlur(0.8))
                           .convert("L")).astype(np.float64) / 255.0
        alpha = np.maximum(alpha, adouc * 0.94)

    float_cell = cell.astype(np.float64)
    # Décoincer le fond revient à diviser par alpha ; dans les zones très
    # translucides (le corps d'un nuage de verre), cette division amplifie
    # chaque pixel de bruit en taches multicolores. Plafonner le diviseur à
    # 0.30 laisse ces pixels proches de leur valeur d'origine : l'œil y perd
    # un peu de saturation, il y gagne un verre lisse.
    with np.errstate(divide="ignore", invalid="ignore"):
        couleur = (float_cell - fond[None, None, :] * (1.0 - alpha[..., None])) \
            / np.maximum(alpha[..., None], 0.30)
    couleur = np.clip(couleur, 0.0, 255.0)
    couleur[alpha == 0] = 0.0                  # n'a aucun sens sous alpha nul
    return np.dstack([couleur, alpha * 255.0])


def redimensionne_premultiplie(rgba, taille):
    """Réduit en pré-multipliant : évite la frange sombre sur les bords doux."""
    img = Image.fromarray(rgba.astype(np.uint8))
    a = np.asarray(img)[..., 3:4].astype(np.float64) / 255.0
    rgb = np.asarray(img)[..., :3].astype(np.float64)
    prem = np.dstack([rgb * a, a * 255.0])
    petit = Image.fromarray(np.clip(prem, 0, 255).astype(np.uint8)).resize(
        (taille, taille), Image.LANCZOS)
    out = np.asarray(petit).astype(np.float64)
    na = out[..., 3:4] / 255.0
    with np.errstate(divide="ignore", invalid="ignore"):
        deprem = np.where(na > 0, out[..., :3] / np.maximum(na, 1e-6), 0.0)
    return np.clip(np.dstack([deprem, out[..., 3:4] * 255.0]), 0, 255).astype(np.uint8)


def brut(nom):
    """Cellule native en RGBA détourée, sans redimensionnement.

    Séparé d'`extrais` parce que l'icône d'application a besoin du pixel
    maximum : la planche fait 2 752 × 1 536 px et une cellule de 459 × 384,
    donc le glyphe natif mesure 230-300 px. Partir du PNG 256 déjà réduit
    reviendrait à agrandir un agrandissement.
    """
    planche, ligne, colonne = PLAN[nom]
    path, (cols, rows) = (PLANCHE1, GRILLE1) if planche == 1 else (PLANCHE2, GRILLE2)
    im = Image.open(path).convert("RGB")
    W, H = im.size
    a = np.asarray(im).astype(np.float64)
    x0, y0 = int(round(colonne * W / cols)), int(round(ligne * H / rows))
    x1, y1 = int(round((colonne + 1) * W / cols)), int(round((ligne + 1) * H / rows))
    cell = a[y0:y1, x0:x1]

    gy0, gy1, gx0, gx1 = zone_glyphe(cell)
    h, w = gy1 - gy0, gx1 - gx0
    coté = max(h, w)
    marge = coté * MARGE
    coté = int(round(coté + 2 * marge))
    cy, cx = (gy0 + gy1) / 2.0, (gx0 + gx1) / 2.0
    by0, by1 = int(round(cy - coté / 2)), int(round(cy + coté / 2))
    bx0, bx1 = int(round(cx - coté / 2)), int(round(cx + coté / 2))

    CH, CW = cell.shape[:2]
    # Le carré peut déborder de la cellule des deux côtés à la fois (glyphe
    # collé au bord) : on découpe d'abord dans les coordonnées du carré, puis
    # on reporte dans la cellule. Les deux tranches ont alors toujours la même
    # taille, au lieu de se désajuster d'un pixel et de faire échouer la cellule.
    s0, s1 = max(0, -by0), min(coté, CH - by0)
    t0, t1 = max(0, -bx0), min(coté, CW - bx0)
    bloc = np.zeros((coté, coté, 3))
    bloc[s0:s1, t0:t1] = cell[s0 + by0:s1 + by0, t0 + bx0:t1 + bx0]

    rgba = detoure(bloc)

    # Le carré est centré sur la bande mais plus haut qu'elle dès que le glyphe
    # est large (un ordinateur portable, une main) : ses bords débordent alors
    # sur le libellé du dessous et sur celui de la ligne précédente. On recale
    # l'alpha à l'emprise réelle du glyphe, élargie d'une respiration de 8 px —
    # le halo lumineux reste, les lettres blanches partent.
    respiration = 8
    masque_zone = np.zeros((coté, coté))
    a0, a1 = max(0, gy0 - respiration - by0), min(coté, gy1 + respiration - by0)
    b0, b1 = max(0, gx0 - respiration - bx0), min(coté, gx1 + respiration - bx0)
    masque_zone[a0:a1, b0:b1] = 1.0
    rgba[..., 3] *= masque_zone
    return rgba, coté, (int(w), int(h))


def extrais(nom, journal):
    """Écrit le glyphe 256 px et sa tuile, consigne le relevé dans `journal`."""
    rgba, coté, (w, h) = brut(nom)
    final = redimensionne_premultiplie(rgba, TAILLE_CIBLE)
    out = SORTIE / f"{nom}.png"
    Image.fromarray(final).save(out)
    TUILES.mkdir(parents=True, exist_ok=True)
    Image.fromarray(compose_tuile(rgba, TAILLE_CIBLE)).save(TUILES / f"{nom}.png")
    alpha = final[..., 3] / 255.0
    planche, ligne, colonne = PLAN[nom]
    journal[nom] = {
        "planche": planche, "ligne": ligne, "colonne": colonne,
        "boite_glyphe_px": [w, h], "cote_carre_px": coté,
        "pixels_opaques_pct": round(float((alpha > 0.5).mean()) * 100, 1),
        "pixels_transparents_pct": round(float((alpha == 0).mean()) * 100, 1),
        "couleur_moyenne": [int(v) for v in (final[..., :3] * alpha[..., None]).sum(
            (0, 1)) / max(alpha.sum() * 255, 1)],
    }
    return out


def compose_tuile(rgba, taille, coin=0.235, marge=0.10):
    """Glyphe translucide posé sur sa propre tuile de verre sombre.

    Le verre des planches est éclairé *sur* fond noir : posé tel quel sur une
    carte claire, il y perd ses midtones et devient à peine lisible (vérifié
    sur la grille de contrôle). Une tuile aux angles arrondis, dégradé graphite
    et liseré clair de 1 px rend le glyphe autonome — même rendu, que
    l'interface soit en Clair ou en Sombre. C'est aussi exactement le gabarit
    d'une icône d'application macOS.
    """
    sup = np.linspace(0.0, 1.0, taille, dtype=np.float64)
    xs, ys = np.meshgrid(sup, sup)
    r = coin * taille
    # Rectangle arrondi : distance à la boîte intérieure, façon squircle adouci.
    dx = np.maximum(np.maximum(r - xs * taille, xs * taille - (taille - r)), 0.0)
    dy = np.maximum(np.maximum(r - ys * taille, ys * taille - (taille - r)), 0.0)
    dist = np.hypot(dx, dy)
    interieur = np.clip(r - dist, 0.0, 1.0)

    bas = np.array([23.0, 23.0, 27.0])
    haut = np.array([44.0, 45.0, 53.0])
    tuile = haut[None, None, :] * ys[..., None] + bas[None, None, :] * (1 - ys[..., None])
    # Lévi reflet en biais, comme une vitre posée sur du métal brossé.
    reflet = np.clip(1.0 - np.hypot(xs - 0.28, (ys - 0.18) * 1.7) / 0.62, 0.0, 1.0) ** 2.2
    tuile = tuile + 26.0 * reflet[..., None] * np.array([1.0, 1.02, 1.08])[None, None, :]

    liseré = np.clip(1.0 - np.abs(interieur - 0.5) / 0.5, 0.0, 1.0)
    bord = np.clip((interieur > 0).astype(np.float64) -
                   (np.clip(r - 1.6 - dist, 0.0, 1.0) > 0).astype(np.float64), 0.0, 1.0)
    tuile = tuile + (255.0 - tuile) * 0.30 * bord[..., None]

    # Le glyphe occupe (1 - 2·marge) de la tuile, centré.
    coté = int(round(taille * (1.0 - 2 * marge)))
    depart = (taille - coté) // 2
    glyphe = redimensionne_premultiplie(rgba, coté)
    ga = glyphe[..., 3:4].astype(np.float64) / 255.0
    zone = tuile[depart:depart + coté, depart:depart + coté]
    compose = (glyphe[..., :3].astype(np.float64) * ga + zone * (1 - ga))
    tuile[depart:depart + coté, depart:depart + coté] = compose

    alpha_tuile = interieur[..., None]
    sortie = np.dstack([np.clip(tuile, 0, 255), alpha_tuile * 255.0])
    return np.clip(sortie, 0, 255).astype(np.uint8)


def planche_contact(noms, fond, cible, sortie, sous=""):
    """Grille de contrôle sur fond clair ou sombre : ce que verra l'interface."""
    n = len(noms)
    colonnes = 8
    lignes = -(-n // colonnes)
    cellule = cible + 40
    canevas = Image.new("RGB", (colonnes * cellule, lignes * cellule), fond)
    dossier = (SORTIE / sous) if sous else SORTIE
    for i, nom in enumerate(noms):
        png = np.asarray(Image.open(dossier / f"{nom}.png").convert("RGBA"))
        a = png[..., 3:4].astype(np.float64) / 255.0
        prem = png[..., :3].astype(np.float64) * a
        petit = Image.fromarray(np.clip(np.dstack([prem, a * 255]), 0, 255).astype(np.uint8)).resize((cible, cible), Image.LANCZOS)
        p = np.asarray(petit).astype(np.float64)
        pa = p[..., 3:4] / 255.0
        fond_zone = np.ones((cible, cible, 3)) * np.array(fond, dtype=np.float64)
        compose = p[..., :3] * pa + fond_zone * (1 - pa)
        x = (i % colonnes) * cellule + 20
        y = (i // colonnes) * cellule + 20
        canevas.paste(Image.fromarray(compose.astype(np.uint8)), (x, y))
    canevas.save(sortie)
    return sortie


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--contact", action="store_true",
                    help="écrit aussi deux grilles de contrôle (clair / sombre)")
    args = ap.parse_args()

    SORTIE.mkdir(parents=True, exist_ok=True)
    TUILES.mkdir(parents=True, exist_ok=True)
    journal, erreurs = {}, {}
    for nom in sorted(PLAN):
        try:
            extrais(nom, journal)
        except Exception as exc:                       # une cellule ratée ne doit pas
            erreurs[nom] = f"{type(exc).__name__}: {exc}"   # masquer les 58 autres

    with (SORTIE / "extraction.json").open("w", encoding="utf-8") as fh:
        json.dump({"taille_cible": TAILLE_CIBLE, "icons": journal, "echecs": erreurs},
                  fh, indent=2, ensure_ascii=False, sort_keys=True)

    print(f"extraits : {len(journal)} — échecs : {len(erreurs)}")
    for nom, err in erreurs.items():
        print(f"  ÉCHEC {nom} : {err}")
    opaques = [v["pixels_opaques_pct"] for v in journal.values()]
    if opaques:
        print(f"  couverture opaque moyenne : {sum(opaques)/len(opaques):.1f} % "
              f"(min {min(opaques)}, max {max(opaques)})")

    if args.contact:
        noms = sorted(journal)
        # Les grilles de contrôle vont dans assets/, pas dans un dossier
        # temporaire : c'est la seule façon de juger le pack sans lancer
        # l'application. Elles ne sont pas embarquées dans le bundle — seuls
        # les PNG de docs/screenshots/ le sont.
        clair = planche_contact(noms, (236, 236, 240), 128, SORTIE / "tuiles-contact-clair.png", "tuiles")
        sombre = planche_contact(noms, (28, 28, 30), 128, SORTIE / "tuiles-contact-sombre.png", "tuiles")
        print(f"  contrôles : {clair} · {sombre}")
    return 1 if erreurs else 0


if __name__ == "__main__":
    sys.exit(main())
