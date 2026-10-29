import AppKit

// Sonde de présence des SF Symbols — celle qui produit le relevé cité en
// § 6.4 de docs/DOCUMENTATION.md.
//
// `MMSymbol.safe(_:)` résout les noms à l'exécution dans l'application, mais il
// ne rend compte que des symboles effectivement dessinés avant le relevé. Ce
// programme, lui, est un exécutable AppKit distinct : on lui passe la liste des
// noms du projet et il répond pour chacun, sans aucune logique de repli, si
// `NSImage(systemSymbolName:)` le connaît.
//
// Usage :
//   swiftc -O tools/probe_sf_symbols.swift -o /tmp/probe -framework AppKit
//   python3 tools/list_symbol_names.py > /tmp/symboles
//   /tmp/probe "$(cat /tmp/symboles)" | grep ABSENT
//
// L'argument unique est la liste des noms, un par ligne ; c'est pour ça que le
// fichier est lu via `$(cat …)` et non passé en arguments multiples. La liste
// vient de `tools/list_symbol_names.py` : c'est elle qui définit ce qui est
// « un nom de symbole du projet », et elle le fait avec une règle écrite au
// lieu d'un `grep` global qui collecterait `com.apple` ou `cookies.sqlite`.
// Elle produit 109 noms, dont 101 présents et 8 absents sur macOS 13.7.

for nom in CommandLine.arguments[1].split(separator: "\n").map(String.init) {
    let present = NSImage(systemSymbolName: nom, accessibilityDescription: nil) != nil
    print("\(present ? "présent " : "ABSENT  ") \(nom)")
}
