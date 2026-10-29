import AppKit

// Sonde le bundle MonitorMyMac.app exactement comme le fait `MMBrandArt.charger`
// dans l'application : mêmes types de ressource, même ordre de candidats.
// `Bundle(path:)` tient lieu de `Bundle.main`, ce qui permet de vérifier un
// bundle sans le lancer — et donc de contrôler les six visuels attendus, y
// compris ceux qu'aucune vue ne demande au moment du relevé au lancement.
//
// Usage : swift tools/probe_brand_icons.swift MonitorMyMac.app
// Sortie : une ligne par ressource, code 1 si l'une manque.

let arguments = CommandLine.arguments
guard arguments.count > 1, let bundle = Bundle(path: arguments[1]) else {
    print("usage : probe_brand_icons.swift <bundle.app>")
    exit(2)
}

let attendues = ["AppIcon", "moniteur-systeme", "purge", "performance",
                 "applications", "securite"]
var absentes: [String] = []

for nom in attendues {
    let candidats = [
        bundle.url(forResource: nom, withExtension: "png", subdirectory: "Icons"),
        bundle.url(forResource: nom, withExtension: "png"),
        bundle.url(forResource: nom, withExtension: "icns"),
    ]
    var detail = "aucun candidat résolu"
    var trouve = false
    for cas in candidats {
        guard let url = cas, let image = NSImage(contentsOf: url),
              image.size.width > 0 else { continue }
        detail = "\(Int(image.size.width))×\(Int(image.size.height)), "
            + "\(image.representations.count) taille(s), via \(url.path.replacingOccurrences(of: bundle.bundlePath + "/", with: ""))"
        trouve = true
        break
    }
    print("\(trouve ? "OK    " : "MANQUE") \(nom) — \(detail)")
    if !trouve { absentes.append(nom) }
}

// L'Info.plist doit annoncer le fichier d'icône : sans cette clé,
// LaunchServices cherche un Assets.car que ce bundle n'a pas et le Dock
// affiche l'icône générique même si AppIcon.icns est en place.
let plist = bundle.infoDictionary ?? [:]
print("CFBundleIconFile : \(plist["CFBundleIconFile"] ?? "absent")")

// Deuxième niveau de contrôle : ce que **LaunchServices** résout comme icône
// pour ce chemin. C'est exactement l'image que le Dock, ⌘-Tab et le Finder
// iraient chercher — et le Dock est masqué sur cette machine, donc le
// vérifier à l'écran demanderait de modifier un réglage de l'utilisateur.
// L'icône résolue est écrite dans /tmp pour être regardée.
let icone = NSWorkspace.shared.icon(forFile: bundle.bundlePath)
icone.size = NSSize(width: 128, height: 128)
if let tiff = icone.tiffRepresentation,
   let copie = NSBitmapImageRep(data: tiff),
   let png = copie.representation(using: .png, properties: [:]) {
    let chemin = URL(fileURLWithPath: "/tmp/icone-ls.png")
    try? png.write(to: chemin)
    print("icône LaunchServices : \(Int(icone.size.width))×\(Int(icone.size.height)), "
        + "\(icone.representations.count) taille(s), écrite dans \(chemin.path)")
} else {
    print("icône LaunchServices : illisible")
}

print(absentes.isEmpty
      ? "verdict : pack de marque complet"
      : "verdict : \(absentes.joined(separator: ", ")) absente(s)")
exit(absentes.isEmpty ? 0 : 1)
