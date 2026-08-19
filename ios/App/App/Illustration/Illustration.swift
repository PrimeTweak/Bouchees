//  Illustration.swift
//
//  Le générateur d'illustrations, porté du JavaScript vers SwiftUI Canvas.
//
//  Le point qui compte : l'illustration est dérivée des ingrédients APRÈS
//  adaptation. Quand le beurre d'arachide devient du beurre de tournesol, la
//  tuile change de couleur. Une image ne peut donc jamais contredire la fiche,
//  ce qui est le défaut fatal d'une photo de stock dans une app d'allergies.
//
//  Contrairement au moteur, ce port ne pose aucun risque de sécurité : un
//  écart entre le dessin JS et le dessin natif est cosmétique.

import SwiftUI

// MARK: - Vocabulaire visuel

enum FormeAliment: String, Sendable {
    case poudre, grain, brin, chunk, rond, arc, goutte, feuille
}

struct VisuelIngredient: Sendable {
    let couleur: Color
    let forme: FormeAliment
    /// 3 = base du plat, 2 = garniture, 1 = touche
    let masse: Int
    /// Clé stable pour dédupliquer et semer l'aléa. Color n'expose pas de
    /// représentation fiable, et hashValue change à chaque lancement.
    let cle: String

    init(_ hex: UInt32, _ forme: FormeAliment, _ masse: Int, _ cle: String = "") {
        self.couleur = Color(red: Double((hex >> 16) & 0xFF) / 255,
                             green: Double((hex >> 8) & 0xFF) / 255,
                             blue: Double(hex & 0xFF) / 255)
        self.forme = forme
        self.masse = masse
        self.cle = cle.isEmpty ? String(format: "%06X-%@", hex, forme.rawValue) : cle
    }
}

enum Palette {

    static func c(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }

    /// Par identifiant d'ingrédient. Tout ce qui manque retombe sur le rôle.
    static let parIngredient: [String: VisuelIngredient] = [
        "farine_ble": .init(0xE6CB93, .poudre, 3),
        "farine_avoine": .init(0xDEC49B, .poudre, 3),
        "farine_riz": .init(0xEDE3CE, .poudre, 3),
        "farine_pois_chiches": .init(0xE0C583, .poudre, 3),
        "melange_sans_gluten": .init(0xE9DCBE, .poudre, 3),
        "chapelure": .init(0xDBB782, .grain, 2),
        "chapelure_sans_gluten": .init(0xE4CDA6, .grain, 2),
        "flocons_avoine": .init(0xD9C49A, .grain, 3),
        "pates_ble": .init(0xE9C97F, .brin, 3),
        "pates_riz": .init(0xEFE2CB, .brin, 3),
        "riz": .init(0xF1EADB, .grain, 3),
        "couscous": .init(0xE6CE9B, .grain, 3),
        "quinoa": .init(0xD8C6A4, .grain, 3),
        "tortillas_ble": .init(0xE7CE9C, .poudre, 3),
        "tortillas_mais": .init(0xEFCF80, .poudre, 3),
        "fecule_mais": .init(0xF2ECDE, .poudre, 1),

        "oeuf": .init(0xF2C64E, .rond, 2),
        "compote_pommes": .init(0xE3CE93, .arc, 2),
        "puree_banane": .init(0xEBD588, .arc, 2),
        "lin_moulu": .init(0x9E7A50, .poudre, 1),
        "graines_chia": .init(0x4C4237, .poudre, 1),
        "aquafaba": .init(0xEDE6D3, .arc, 1),

        "lait_vache": .init(0xF6F1E4, .arc, 2),
        "boisson_soya": .init(0xEFE7D2, .arc, 2),
        "boisson_avoine": .init(0xEDE2CC, .arc, 2),
        "lait_coco": .init(0xF8F5EC, .arc, 2),
        "beurre": .init(0xF0D479, .goutte, 1),
        "margarine_sans_lait": .init(0xF2DA92, .goutte, 1),
        "creme_35": .init(0xF7F2E5, .arc, 2),
        "yogourt_nature": .init(0xF6F2E8, .arc, 2),
        "yogourt_grec": .init(0xF4F0E6, .arc, 2),
        "yogourt_soya": .init(0xEFE8D6, .arc, 2),
        "yogourt_coco": .init(0xF8F5EC, .arc, 2),
        "fromage_cheddar": .init(0xE79B33, .chunk, 2),
        "fromage_mozzarella": .init(0xF4EEDD, .chunk, 2),
        "fromage_parmesan": .init(0xEBD9A8, .poudre, 1),
        "levure_alimentaire": .init(0xE0B84E, .poudre, 1),

        "huile_olive": .init(0xB7A03C, .goutte, 1),
        "huile_canola": .init(0xE2C558, .goutte, 1),
        "puree_avocat": .init(0x7E9B4E, .arc, 2),
        "beurre_arachide": .init(0xBE8347, .goutte, 2),
        "beurre_tournesol": .init(0xA98A55, .goutte, 2),
        "beurre_soya": .init(0xB79A62, .goutte, 2),
        "tahini": .init(0xD3BC86, .goutte, 2),
        "beurre_amande": .init(0xB98D5E, .goutte, 2),
        "noix_grenoble": .init(0x9C7248, .rond, 1),

        "poulet": .init(0xD8A778, .chunk, 3),
        "dinde_hachee": .init(0xC99672, .chunk, 3),
        "poisson_blanc": .init(0xEBDCC6, .chunk, 3),
        "saumon": .init(0xE8926B, .chunk, 3),
        "crevette": .init(0xEE9F80, .chunk, 2),
        "tofu_ferme": .init(0xF1EBDA, .chunk, 3),
        "lentilles": .init(0x9A7A4E, .rond, 3),
        "pois_chiches": .init(0xD8BC7E, .rond, 3),

        "miel": .init(0xE0A32C, .goutte, 1),
        "sirop_erable": .init(0xB5722C, .goutte, 1),
        "sucre": .init(0xF4EFE3, .poudre, 1),
        "dattes": .init(0x7A5136, .rond, 2),

        "banane": .init(0xEDD264, .rond, 2),
        "pomme": .init(0xC5533A, .rond, 2),
        "mangue": .init(0xEFA22F, .rond, 2),
        "bleuets": .init(0x5A5A93, .rond, 1),
        "raisins_secs": .init(0x7B5340, .rond, 1),
        "abricots_seches": .init(0xDE9440, .rond, 1),
        "jus_citron": .init(0xEFDD73, .goutte, 1),

        "patate_douce": .init(0xDE8B41, .chunk, 3),
        "courge_butternut": .init(0xE5A03F, .chunk, 3),
        "carotte": .init(0xDE7F32, .chunk, 2),
        "carotte_crue": .init(0xE88A38, .chunk, 2),
        "concombre": .init(0x8FAE5E, .rond, 2),
        "courgette": .init(0x7C9E4F, .rond, 2),
        "epinards": .init(0x4F7A3E, .feuille, 2),
        "petits_pois": .init(0x6E9B45, .rond, 2),
        "poivron": .init(0xCE4C39, .chunk, 2),
        "brocoli": .init(0x557F42, .feuille, 2),
        "oignon": .init(0xE8DFC9, .arc, 1),
        "ail": .init(0xEFE8D6, .rond, 1),
        "tomates_broyees": .init(0xC24A2E, .arc, 3),

        "moutarde_dijon": .init(0xD8B23F, .goutte, 1),
        "sel": .init(0xF5F2EA, .poudre, 1),
        "cannelle": .init(0x9A6238, .poudre, 1),
        "vanille": .init(0xC4A578, .goutte, 1),
        "basilic": .init(0x4E7B3C, .feuille, 1),
        "gingembre": .init(0xD7B36A, .poudre, 1),
        "sauce_soya": .init(0x4A3226, .arc, 1),
        "sauce_tamari": .init(0x4A3226, .arc, 1),
        "coco_aminos": .init(0x6B4A33, .arc, 1),
        "sauce_poisson": .init(0x8A6437, .goutte, 1),
        "levure_chimique": .init(0xF5F2EA, .poudre, 1),
        "bicarbonate": .init(0xF5F2EA, .poudre, 1),
        "bouillon_sans_sel": .init(0xE4D7B4, .arc, 2),
        "eau": .init(0xEDF1EE, .arc, 1)
    ]

    /// Repli par rôle : aucun ingrédient ne reste sans couleur.
    static let parRole: [String: VisuelIngredient] = [
        "farine": .init(0xE6CB93, .poudre, 3),
        "proteine": .init(0xD8A778, .chunk, 3),
        "legume": .init(0x7C9E4F, .rond, 2),
        "fruit": .init(0xD98A50, .rond, 2),
        "lacte": .init(0xF5F0E3, .arc, 2),
        "liquide": .init(0xEAE3D0, .arc, 2),
        "gras": .init(0xE2C558, .goutte, 1),
        "liant": .init(0xE3CE93, .arc, 1),
        "sucrant": .init(0xC98A34, .goutte, 1),
        "garniture": .init(0x9C7248, .rond, 1),
        "assaisonnement": .init(0xC8B994, .poudre, 1),
        "levant": .init(0xF5F2EA, .poudre, 1)
    ]

    static func visuel(_ id: String, role: String) -> VisuelIngredient {
        parIngredient[id] ?? parRole[role] ?? parRole["assaisonnement"]!
    }

    /// Teintes de fond par catégorie — la nappe sous le bol.
    static func fond(_ categorie: String) -> (Color, Color) {
        switch categorie {
        case "Déjeuner":  return (c(0xF7F1E4), c(0xEFE4CE))
        case "Collation": return (c(0xF8EFF3), c(0xF0E1E9))
        case "Dessert":   return (c(0xF4EFF6), c(0xE8E0EF))
        default:          return (c(0xEDF2EA), c(0xDFEAD9))   // Repas
        }
    }
}

// MARK: - Trigonométrie sans ambiguïté

// CoreGraphics expose cos(CGFloat) et la bibliothèque standard cos(Double).
// Dès qu'on mêle les deux dans une expression CGPoint, le compilateur refuse
// de choisir. Ces enveloppes tranchent : entrée Double, sortie CGFloat.

@inline(__always)
private func cosinus(_ angleRadians: Double) -> CGFloat {
    let v: Double = Foundation.cos(angleRadians)
    return CGFloat(v)
}

@inline(__always)
private func sinus(_ angleRadians: Double) -> CGFloat {
    let v: Double = Foundation.sin(angleRadians)
    return CGFloat(v)
}

/// Degrés vers radians, en Double, pour éviter la même ambiguïté.
@inline(__always)
private func radians(_ degres: Double) -> Double { degres * Double.pi / 180 }

// MARK: - Aléa déterministe

/// Même recette et même profil donnent toujours la même image. Un dessin qui
/// change à chaque défilement donnerait l'impression que l'app improvise.
struct AleaSeme {
    private var etat: UInt32

    init(_ graine: String) {
        var h: UInt32 = 2166136261
        for octet in graine.utf8 {
            h ^= UInt32(octet)
            h = h &* 16777619
        }
        etat = h
    }

    mutating func suivant() -> Double {
        etat = etat &+ 0x6D2B79F5
        var t = etat
        t = (t ^ (t >> 15)) &* (1 | t)
        t = t &+ ((t ^ (t >> 7)) &* (61 | t)) ^ t
        return Double((t ^ (t >> 14)) & 0x7FFFFFFF) / Double(0x7FFFFFFF)
    }

    mutating func entre(_ a: Double, _ b: Double) -> Double { a + (b - a) * suivant() }

    /// Même chose, mais typée CGFloat : le dessin travaille en CGFloat et les
    /// conversions implicites sont exactement ce qui rend les expressions
    /// ambiguës pour le compilateur.
    mutating func entreCG(_ a: Double, _ b: Double) -> CGFloat { CGFloat(entre(a, b)) }
}

// MARK: - La vue

struct PlatVue: View {
    let resultat: RecetteAdaptee
    let categorie: String

    var body: some View {
        Canvas { contexte, taille in
            dessiner(contexte: &contexte, taille: taille)
        }
        .background(degradeFond)
        .accessibilityHidden(true)   // décoratif : le verdict est lu par ailleurs
    }

    private var degradeFond: some View {
        let (a, b) = Palette.fond(categorie)
        return LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Ingrédients visibles = ceux qui restent après adaptation.
    private var elements: [VisuelIngredient] {
        resultat.ingredients
            .filter { $0.statut != .omis && $0.statut != .impossible }
            .map { Palette.visuel($0.vers ?? $0.id, role: $0.role) }
    }

    private var graine: String {
        resultat.id + "|" + resultat.ingredients.map { $0.vers ?? $0.id }.joined(separator: ",")
    }

    private func dessiner(contexte: inout GraphicsContext, taille: CGSize) {
        let tries = elements.sorted { $0.masse > $1.masse }
        guard let base = tries.first else { return }

        var accents: [VisuelIngredient] = []
        var vus = Set<String>()
        for v in tries.dropFirst() {
            if vus.contains(v.cle) || accents.count >= 6 { continue }
            vus.insert(v.cle)
            accents.append(v)
        }

        var alea = AleaSeme(graine)

        // Le bol occupe une proportion fixe, quelle que soit la taille.
        let cote = min(taille.width, taille.height)
        let centre = CGPoint(x: taille.width / 2, y: taille.height / 2)
        let rayonBol = cote * 0.38
        let rayonInterieur = rayonBol * 0.845

        // Miettes sur la nappe : asymétrie volontaire.
        for (i, a) in accents.prefix(3).enumerated() {
            let angle: Double = alea.entre(0, 2 * Double.pi) + Double(i) * 2.1
            let distance = rayonBol * alea.entreCG(1.22, 1.45)
            let p = CGPoint(x: centre.x + cosinus(angle) * distance,
                            y: centre.y + sinus(angle) * distance * 0.78)
            guard p.x > 12, p.x < taille.width - 12, p.y > 12, p.y < taille.height - 12 else { continue }
            var sousContexte = contexte
            sousContexte.opacity = 0.6
            forme(a.forme, dans: &sousContexte, centre: p, taille: cote * 0.028, couleur: a.couleur, alea: &alea)
        }

        // Ombre portée
        contexte.fill(
            Path(ellipseIn: CGRect(x: centre.x - rayonBol * 0.95, y: centre.y + rayonBol * 0.86,
                                   width: rayonBol * 1.9, height: rayonBol * 0.22)),
            with: .color(.black.opacity(0.08)))

        // Le bol
        let bol = Path(ellipseIn: CGRect(x: centre.x - rayonBol, y: centre.y - rayonBol,
                                         width: rayonBol * 2, height: rayonBol * 2))
        contexte.fill(bol, with: .color(Color(red: 0.988, green: 0.984, blue: 0.965)))
        contexte.stroke(bol, with: .color(.black.opacity(0.12)), lineWidth: 1.5)

        let interieur = Path(ellipseIn: CGRect(x: centre.x - rayonInterieur, y: centre.y - rayonInterieur,
                                               width: rayonInterieur * 2, height: rayonInterieur * 2))
        contexte.fill(interieur, with: .color(Color(red: 0.973, green: 0.961, blue: 0.925)))

        // Contenu, découpé au bol
        contexte.drawLayer { couche in
            couche.clip(to: interieur)
            dessinerContenu(&couche, centre: centre, rayon: rayonInterieur,
                            base: base, accents: accents, alea: &alea)
        }

        contexte.stroke(interieur, with: .color(.black.opacity(0.1)), lineWidth: 1)

        // Reflet sur le rebord
        var reflet = Path()
        reflet.addArc(center: centre, radius: rayonBol * 0.92,
                      startAngle: .degrees(198), endAngle: .degrees(248), clockwise: false)
        contexte.stroke(reflet, with: .color(.white.opacity(0.8)),
                        style: StrokeStyle(lineWidth: cote * 0.014, lineCap: .round))
    }

    /// La base se dessine selon sa nature : un potage remplit le bol, un plat
    /// en morceaux se pose en pièces, une pâtisserie fait un dôme.
    private func dessinerContenu(_ contexte: inout GraphicsContext, centre: CGPoint, rayon: CGFloat,
                                 base: VisuelIngredient, accents: [VisuelIngredient],
                                 alea: inout AleaSeme) {
        switch base.forme {
        case .arc:
            contexte.fill(
                Path(ellipseIn: CGRect(x: centre.x - rayon, y: centre.y - rayon,
                                       width: rayon * 2, height: rayon * 2)),
                with: .color(base.couleur))
            var vague = Path()
            vague.move(to: CGPoint(x: centre.x - rayon * 0.62, y: centre.y + rayon * 0.08))
            vague.addQuadCurve(to: CGPoint(x: centre.x, y: centre.y + rayon * 0.08),
                               control: CGPoint(x: centre.x - rayon * 0.31, y: centre.y - rayon * 0.2))
            vague.addQuadCurve(to: CGPoint(x: centre.x + rayon * 0.62, y: centre.y + rayon * 0.08),
                               control: CGPoint(x: centre.x + rayon * 0.31, y: centre.y + rayon * 0.34))
            contexte.stroke(vague, with: .color(.white.opacity(0.3)),
                            style: StrokeStyle(lineWidth: rayon * 0.07, lineCap: .round))

        case .chunk:
            contexte.fill(
                Path(ellipseIn: CGRect(x: centre.x - rayon * 0.95, y: centre.y - rayon * 0.95,
                                       width: rayon * 1.9, height: rayon * 1.9)),
                with: .color(base.couleur.opacity(0.3)))
            for i in 0..<5 {
                let angle: Double = Double(i) * 72 + alea.entre(0, 26)
                let d = rayon * alea.entreCG(0.2, 0.55)
                let p = CGPoint(x: centre.x + cosinus(radians(angle)) * d,
                                y: centre.y + sinus(radians(angle)) * d)
                forme(.chunk, dans: &contexte, centre: p,
                      taille: rayon * alea.entreCG(0.19, 0.27), couleur: base.couleur, alea: &alea)
            }

        default:
            let ombre = blob(centre: CGPoint(x: centre.x, y: centre.y + rayon * 0.12),
                             rayon: rayon * 0.86, alea: &alea)
            contexte.fill(ombre, with: .color(foncer(base.couleur, 0.86)))
            let dome = blob(centre: CGPoint(x: centre.x, y: centre.y + rayon * 0.01),
                            rayon: rayon * 0.87, alea: &alea)
            contexte.fill(dome, with: .color(base.couleur))

            if base.forme == .brin || base.forme == .grain {
                for i in 0..<8 {
                    let angle: Double = Double(i) * 45 + alea.entre(0, 22)
                    let d = rayon * alea.entreCG(0.24, 0.56)
                    let p = CGPoint(x: centre.x + cosinus(radians(angle)) * d,
                                    y: centre.y + sinus(radians(angle)) * d)
                    forme(base.forme, dans: &contexte, centre: p, taille: rayon * 0.15,
                          couleur: foncer(base.couleur, 0.84), alea: &alea)
                }
            }
        }

        // Garnitures, réparties en spirale d'or pour éviter les grappes.
        let n = max(accents.count, 1)
        for (i, a) in accents.enumerated() {
            let repetitions = n <= 2 ? 3 : (n <= 4 ? 2 : 1)
            for j in 0..<repetitions {
                let index = Double(i + j * n)
                let angle: Double = index * 137.508 + decalageStable(a.cle)
                let proportion: Double = 0.17 + 0.55 * (index + 0.55).squareRoot()
                    / Double(n * repetitions).squareRoot()
                let r = rayon * CGFloat(proportion)
                let p = CGPoint(x: centre.x + cosinus(radians(angle)) * r,
                                y: centre.y + sinus(radians(angle)) * r * 0.93)
                forme(a.forme, dans: &contexte, centre: p,
                      taille: rayon * alea.entreCG(0.15, 0.22), couleur: a.couleur, alea: &alea)
            }
        }
    }

    // MARK: - Formes

    private func blob(centre: CGPoint, rayon: CGFloat, alea: inout AleaSeme) -> Path {
        var p = Path()
        let points = 11
        for i in 0..<points {
            let angle: Double = Double(i) / Double(points) * 2 * Double.pi
            let r = rayon * alea.entreCG(0.9, 1.1)
            let point = CGPoint(x: centre.x + cosinus(angle) * r, y: centre.y + sinus(angle) * r * 0.94)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        p.closeSubpath()
        return p
    }

    private func forme(_ forme: FormeAliment, dans contexte: inout GraphicsContext,
                       centre: CGPoint, taille t: CGFloat, couleur: Color, alea: inout AleaSeme) {
        switch forme {
        case .chunk:
            let rect = CGRect(x: centre.x - t, y: centre.y - t * 0.78, width: t * 2, height: t * 1.56)
            var chemin = Path(roundedRect: rect, cornerRadius: t * 0.42)
            chemin = chemin.applying(rotation(alea.entre(-12, 12), autour: centre))
            contexte.fill(chemin, with: .color(couleur))

        case .rond:
            let depart = alea.entre(0, 360)
            for i in 0..<3 {
                let angle: Double = radians(depart + Double(i) * 118)
                let d = t * 0.72
                let c = CGPoint(x: centre.x + cosinus(angle) * d, y: centre.y + sinus(angle) * d * 0.9)
                contexte.fill(
                    Path(ellipseIn: CGRect(x: c.x - t * 0.6, y: c.y - t * 0.6, width: t * 1.2, height: t * 1.2)),
                    with: .color(couleur))
            }

        case .grain:
            let depart = alea.entre(0, 360)
            for i in 0..<5 {
                let angle: Double = radians(depart + Double(i) * 72)
                let c = CGPoint(x: centre.x + cosinus(angle) * t * 0.8, y: centre.y + sinus(angle) * t * 0.7)
                var chemin = Path(ellipseIn: CGRect(x: c.x - t * 0.46, y: c.y - t * 0.26,
                                                    width: t * 0.92, height: t * 0.52))
                chemin = chemin.applying(rotation(Double(i) * 40, autour: c))
                contexte.fill(chemin, with: .color(couleur))
            }

        case .brin:
            for i in 0..<3 {
                let dy = CGFloat(i - 1) * t * 0.62
                var chemin = Path()
                chemin.move(to: CGPoint(x: centre.x - t * 1.5, y: centre.y + dy))
                chemin.addQuadCurve(to: CGPoint(x: centre.x, y: centre.y + dy),
                                    control: CGPoint(x: centre.x - t * 0.75, y: centre.y + dy - t * 0.5))
                chemin.addQuadCurve(to: CGPoint(x: centre.x + t * 1.5, y: centre.y + dy),
                                    control: CGPoint(x: centre.x + t * 0.75, y: centre.y + dy + t * 0.5))
                contexte.stroke(chemin, with: .color(couleur),
                                style: StrokeStyle(lineWidth: t * 0.42, lineCap: .round))
            }

        case .arc:
            var chemin = Path()
            chemin.addArc(center: centre, radius: t * 1.2,
                          startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
            contexte.stroke(chemin, with: .color(couleur),
                            style: StrokeStyle(lineWidth: t * 0.6, lineCap: .round))

        case .goutte:
            var chemin = Path()
            chemin.move(to: CGPoint(x: centre.x, y: centre.y - t))
            chemin.addCurve(to: CGPoint(x: centre.x, y: centre.y + t),
                            control1: CGPoint(x: centre.x + t * 0.85, y: centre.y - t * 0.15),
                            control2: CGPoint(x: centre.x + t * 0.6, y: centre.y + t))
            chemin.addCurve(to: CGPoint(x: centre.x, y: centre.y - t),
                            control1: CGPoint(x: centre.x - t * 0.6, y: centre.y + t),
                            control2: CGPoint(x: centre.x - t * 0.85, y: centre.y - t * 0.15))
            chemin.closeSubpath()
            contexte.fill(chemin, with: .color(couleur))

        case .feuille:
            var chemin = Path()
            chemin.move(to: CGPoint(x: centre.x - t * 1.15, y: centre.y))
            chemin.addQuadCurve(to: CGPoint(x: centre.x + t * 1.15, y: centre.y),
                                control: CGPoint(x: centre.x, y: centre.y - t * 1.1))
            chemin.addQuadCurve(to: CGPoint(x: centre.x - t * 1.15, y: centre.y),
                                control: CGPoint(x: centre.x, y: centre.y + t * 1.1))
            chemin.closeSubpath()
            chemin = chemin.applying(rotation(alea.entre(-40, 20), autour: centre))
            contexte.fill(chemin, with: .color(couleur))

        case .poudre:
            for _ in 0..<7 {
                let p = CGPoint(x: centre.x + t * alea.entreCG(-1.3, 1.3),
                                y: centre.y + t * alea.entreCG(-1.1, 1.1))
                let r = t * alea.entreCG(0.19, 0.29)
                contexte.fill(
                    Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                    with: .color(couleur))
            }
        }
    }

    /// Décalage angulaire dérivé de la clé, identique à chaque lancement.
    private func decalageStable(_ cle: String) -> Double {
        var somme: UInt32 = 0
        for octet in cle.utf8 { somme = (somme &* 31 &+ UInt32(octet)) % 1000 }
        return Double(somme % 60)
    }

    private func rotation(_ degres: Double, autour p: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: p.x, y: p.y)
            .rotated(by: CGFloat(radians(degres)))
            .translatedBy(x: -p.x, y: -p.y)
    }

    private func foncer(_ couleur: Color, _ facteur: Double) -> Color {
        couleur.mix(avec: .black, quantite: 1 - facteur)
    }
}

extension Color {
    /// Mélange simple, sans dépendre d'API récentes.
    func mix(avec autre: Color, quantite: Double) -> Color {
        let q = max(0, min(1, quantite))
        #if canImport(UIKit)
        let a = UIColor(self), b = UIColor(autre)
        var r1: CGFloat = 0, v1: CGFloat = 0, b1: CGFloat = 0, o1: CGFloat = 0
        var r2: CGFloat = 0, v2: CGFloat = 0, b2: CGFloat = 0, o2: CGFloat = 0
        a.getRed(&r1, green: &v1, blue: &b1, alpha: &o1)
        b.getRed(&r2, green: &v2, blue: &b2, alpha: &o2)
        return Color(red: Double(r1 + (r2 - r1) * q),
                     green: Double(v1 + (v2 - v1) * q),
                     blue: Double(b1 + (b2 - b1) * q))
        #else
        return self
        #endif
    }
}
