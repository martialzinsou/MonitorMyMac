#!/usr/bin/env python3
"""Liste reproductible des noms de SF Symbols à sonder.

Le relevé cité au § 6.4 de `docs/DOCUMENTATION.md` doit pouvoir être rejoué
sans dépendre de la mémoire de celui qui l'a écrit. Ce script produit
exactement la liste soumise à `NSImage(systemSymbolName:)`, et il le fait avec
une règle assumée plutôt qu'avec un `grep` global :

    1. les littéraux `"…"` des lignes de `src/` où la chaîne est manifestement
       un nom de symbole (`systemName:`, `symbol`, `icon`, `tile:`,
       `mmSafeSymbol`, `fallback`) ;
    2. les 50 clés de la table `MMSymbol.fallbacks` ;
    3. les 46 valeurs de cette même table.

Un `grep -rhoE '"[a-z0-9]+(\\.[a-z0-9]+)+"' src/` serait plus simple et faux :
il collecte aussi `com.apple`, `cookies.sqlite`, `extensions.json`,
`hw.pagesize`, `3.0.0` — 122 chaînes dont une vingtaine n'ont jamais été des
noms d'icône. Ici la règle est nommée, donc contrôlable.

Usage :
    python3 tools/list_symbol_names.py > /tmp/noms.txt
    swiftc -O tools/probe_sf_symbols.swift -o /tmp/probe -framework AppKit
    /tmp/probe "$(cat /tmp/noms.txt)" | grep ABSENT
"""

import os
import re
import sys

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
THEME = os.path.join(RACINE, "src", "UI", "MMTheme.swift")

# Une chaîne est prise pour nom de symbole si le mot-clé de sa ligne en fait
# un emplacement d'icône.
CONTEXTE = re.compile(
    r"systemName|symbolName|\bsymbol\b|\bicon|iconName|glassIcon|\btile:|mmSafeSymbol|fallback"
)
LITTERAL = re.compile(r'"([a-z0-9]+(?:\.[a-z0-9]+)*)"')
PAIRE = re.compile(r'"([a-z0-9.]+)"\s*:\s*"([a-z0-9.]+)"')


def litteraux_depuis_les_emplacements_icones() -> set:
    noms = set()
    for dossier, _, fichiers in os.walk(os.path.join(RACINE, "src")):
        for f in fichiers:
            if not f.endswith(".swift"):
                continue
            chemin = os.path.join(dossier, f)
            with open(chemin, encoding="utf-8") as source:
                for ligne in source:
                    if CONTEXTE.search(ligne):
                        noms.update(LITTERAL.findall(ligne))
    return noms


def table_de_repli():
    """Renvoie (clés, valeurs) de `MMSymbol.fallbacks`.

    Le bloc est délimité par le déclarateur et le premier `]` en colonne 4 :
    la table est le seul dictionnaire de ce nom, et ses valeurs peuvent être
    suivies de commentaires multi-lignes qu'il ne faut pas hacher.
    """
    with open(THEME, encoding="utf-8") as source:
        texte = source.read()
    marker = "static let fallbacks: [String: String] = ["
    depart = texte.index(marker) + len(marker)
    fin = texte.index("\n    ]", depart)
    bloc = texte[depart:fin]
    paires = PAIRE.findall(bloc)
    return {k for k, _ in paires}, {v for _, v in paires}, len(paires)


def main() -> int:
    sites = litteraux_depuis_les_emplacements_icones()
    cles, valeurs, entrees = table_de_repli()
    univers = sorted(sites | cles | valeurs)
    print(
        f"# sources : {len(sites)} littéraux d'emplacement + "
        f"{len(cles)} clés + {len(valeurs)} valeurs "
        f"({entrees} entrées de table) → {len(univers)} noms distincts",
        file=sys.stderr,
    )
    for nom in univers:
        print(nom)
    return 0


if __name__ == "__main__":
    sys.exit(main())
