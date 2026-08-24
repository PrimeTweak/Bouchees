//  DishArtwork.swift
//
//  The dish illustration, drawn with SwiftUI Canvas.
//
//  What matters here: the drawing is derived from the ingredients AFTER
//  adaptation. When peanut butter becomes sunflower seed butter, the tile
//  changes colour. An image can therefore never contradict the recipe card,
//  which is the fatal flaw of a stock photo in an allergy app.
//
//  Unlike the engine, this port carries no safety risk: a difference between
//  the JS drawing and the native one is cosmetic.

import SwiftUI

// MARK: - Vocabulaire visuel

enum FoodShape: String, Sendable {
    case poudre, grain, brin, chunk, rond, arc, goutte, feuille
}

struct IngredientVisual: Sendable {
    let color: Color
    let shape: FoodShape
    /// 3 = base du plat, 2 = garniture, 1 = touche
    let weight: Int
    /// Stable key for deduplication and for seeding the randomness. Color has
    /// no reliable representation, and hashValue changes on every launch.
    let key: String

    init(_ hex: UInt32, _ shape: FoodShape, _ weight: Int, _ key: String = "") {
        self.color = Color(red: Double((hex >> 16) & 0xFF) / 255,
                             green: Double((hex >> 8) & 0xFF) / 255,
                             blue: Double(hex & 0xFF) / 255)
        self.shape = shape
        self.weight = weight
        self.key = key.isEmpty ? String(format: "%06X-%@", hex, shape.rawValue) : key
    }
}

enum Palette {

    static func c(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }

    /// Keyed by ingredient identifier. Anything missing falls back to the role.
    static let parIngredient: [String: IngredientVisual] = [
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

    /// Fallback by role: no ingredient is ever left without a colour.
    static let parRole: [String: IngredientVisual] = [
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

    static func visuel(_ id: String, role: String) -> IngredientVisual {
        parIngredient[id] ?? parRole[role] ?? parRole["assaisonnement"]!
    }

    /// Background tints per category — the cloth under the bowl.
    static func background(_ category: String) -> (Color, Color) {
        switch category {
        case "Breakfast":  return (c(0xF7F1E4), c(0xEFE4CE))
        case "Snack": return (c(0xF8EFF3), c(0xF0E1E9))
        case "Dessert":   return (c(0xF4EFF6), c(0xE8E0EF))
        default:          return (c(0xEDF2EA), c(0xDFEAD9))   // Repas
        }
    }
}

// MARK: - Unambiguous trigonometry

// CoreGraphics exposes cos(CGFloat) and the standard library cos(Double). Mix
// the two in a CGPoint expression and the compiler refuses to choose. These
// wrappers settle it: Double in, CGFloat out.

@inline(__always)
private func cosine(_ angleRadians: Double) -> CGFloat {
    let v: Double = Foundation.cos(angleRadians)
    return CGFloat(v)
}

@inline(__always)
private func sine(_ angleRadians: Double) -> CGFloat {
    let v: Double = Foundation.sin(angleRadians)
    return CGFloat(v)
}

/// Degrees to radians, in Double, to avoid the same ambiguity.
@inline(__always)
private func radians(_ degres: Double) -> Double { degres * Double.pi / 180 }

// MARK: - Deterministic randomness

/// The same recipe and the same profile always give the same image. A drawing
/// that changed on every scroll would make the app look like it improvises.
struct SeededRandom {
    private var etat: UInt32

    init(_ seed: String) {
        var h: UInt32 = 2166136261
        for octet in seed.utf8 {
            h ^= UInt32(octet)
            h = h &* 16777619
        }
        etat = h
    }

    mutating func next() -> Double {
        etat = etat &+ 0x6D2B79F5
        var t = etat
        t = (t ^ (t >> 15)) &* (1 | t)
        t = t &+ ((t ^ (t >> 7)) &* (61 | t)) ^ t
        return Double((t ^ (t >> 14)) & 0x7FFFFFFF) / Double(0x7FFFFFFF)
    }

    mutating func between(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }

    /// Same thing, typed CGFloat: the drawing works in CGFloat and mixed
    /// conversions implicites sont exactement ce qui rend les expressions
    /// expressions are ambiguous to the compiler.
    mutating func betweenCG(_ a: Double, _ b: Double) -> CGFloat { CGFloat(between(a, b)) }
}

// MARK: - La vue

struct DishArtwork: View {
    let result: AdaptedRecipe
    let category: String

    var body: some View {
        Canvas { context, size in
            draw(context: &context, size: size)
        }
        .background(backgroundGradient)
        .accessibilityHidden(true)   // decorative: the verdict is read elsewhere
    }

    private var backgroundGradient: some View {
        let (a, b) = Palette.background(category)
        return LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Visible ingredients = those left after adaptation.
    private var items: [IngredientVisual] {
        result.ingredients
            .filter { $0.status != .omis && $0.status != .impossible }
            .map { Palette.visuel($0.to ?? $0.id, role: $0.role) }
    }

    private var seed: String {
        result.id + "|" + result.ingredients.map { $0.to ?? $0.id }.joined(separator: ",")
    }

    private func draw(context: inout GraphicsContext, size: CGSize) {
        let sorted = items.sorted { $0.weight > $1.weight }
        guard let base = sorted.first else { return }

        var accents: [IngredientVisual] = []
        var seen = Set<String>()
        for v in sorted.dropFirst() {
            if seen.contains(v.key) || accents.count >= 6 { continue }
            seen.insert(v.key)
            accents.append(v)
        }

        var rng = SeededRandom(seed)

        // Le bowl occupe une proportion fixe, quelle que soit la size.
        let side = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let rayonBol = side * 0.38
        let rayonInterieur = rayonBol * 0.845

        // Crumbs on the cloth: deliberate asymmetry.
        for (i, a) in accents.prefix(3).enumerated() {
            let angle: Double = rng.between(0, 2 * Double.pi) + Double(i) * 2.1
            let distance = rayonBol * rng.betweenCG(1.22, 1.45)
            let p = CGPoint(x: center.x + cosine(angle) * distance,
                            y: center.y + sine(angle) * distance * 0.78)
            guard p.x > 12, p.x < size.width - 12, p.y > 12, p.y < size.height - 12 else { continue }
            var sousContexte = context
            sousContexte.opacity = 0.6
            shape(a.shape, dans: &sousContexte, center: p, size: side * 0.028, color: a.color, rng: &rng)
        }

        // Drop shadow
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - rayonBol * 0.95, y: center.y + rayonBol * 0.86,
                                   width: rayonBol * 1.9, height: rayonBol * 0.22)),
            with: .color(.black.opacity(0.08)))

        // Le bowl
        let bowl = Path(ellipseIn: CGRect(x: center.x - rayonBol, y: center.y - rayonBol,
                                         width: rayonBol * 2, height: rayonBol * 2))
        context.fill(bowl, with: .color(Color(red: 0.988, green: 0.984, blue: 0.965)))
        context.stroke(bowl, with: .color(.black.opacity(0.12)), lineWidth: 1.5)

        let inner = Path(ellipseIn: CGRect(x: center.x - rayonInterieur, y: center.y - rayonInterieur,
                                               width: rayonInterieur * 2, height: rayonInterieur * 2))
        context.fill(inner, with: .color(Color(red: 0.973, green: 0.961, blue: 0.925)))

        // Contents, clipped to the bowl
        context.drawLayer { layer in
            layer.clip(to: inner)
            dessinerContenu(&layer, center: center, radius: rayonInterieur,
                            base: base, accents: accents, rng: &rng)
        }

        context.stroke(inner, with: .color(.black.opacity(0.1)), lineWidth: 1)

        // Reflet sur le rebord
        var highlight = Path()
        highlight.addArc(center: center, radius: rayonBol * 0.92,
                      startAngle: .degrees(198), endAngle: .degrees(248), clockwise: false)
        context.stroke(highlight, with: .color(.white.opacity(0.8)),
                        style: StrokeStyle(lineWidth: side * 0.014, lineCap: .round))
    }

    /// La base se dessine selon sa nature : un potage remplit le bowl, un plat
    /// something in pieces sits as pieces, a bake forms a dome.
    private func dessinerContenu(_ context: inout GraphicsContext, center: CGPoint, radius: CGFloat,
                                 base: IngredientVisual, accents: [IngredientVisual],
                                 rng: inout SeededRandom) {
        switch base.shape {
        case .arc:
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                       width: radius * 2, height: radius * 2)),
                with: .color(base.color))
            var vague = Path()
            vague.move(to: CGPoint(x: center.x - radius * 0.62, y: center.y + radius * 0.08))
            vague.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius * 0.08),
                               control: CGPoint(x: center.x - radius * 0.31, y: center.y - radius * 0.2))
            vague.addQuadCurve(to: CGPoint(x: center.x + radius * 0.62, y: center.y + radius * 0.08),
                               control: CGPoint(x: center.x + radius * 0.31, y: center.y + radius * 0.34))
            context.stroke(vague, with: .color(.white.opacity(0.3)),
                            style: StrokeStyle(lineWidth: radius * 0.07, lineCap: .round))

        case .chunk:
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - radius * 0.95, y: center.y - radius * 0.95,
                                       width: radius * 1.9, height: radius * 1.9)),
                with: .color(base.color.opacity(0.3)))
            for i in 0..<5 {
                let angle: Double = Double(i) * 72 + rng.between(0, 26)
                let d = radius * rng.betweenCG(0.2, 0.55)
                let p = CGPoint(x: center.x + cosine(radians(angle)) * d,
                                y: center.y + sine(radians(angle)) * d)
                shape(.chunk, dans: &context, center: p,
                      size: radius * rng.betweenCG(0.19, 0.27), color: base.color, rng: &rng)
            }

        default:
            let ombre = blob(center: CGPoint(x: center.x, y: center.y + radius * 0.12),
                             radius: radius * 0.86, rng: &rng)
            context.fill(ombre, with: .color(darken(base.color, 0.86)))
            let dome = blob(center: CGPoint(x: center.x, y: center.y + radius * 0.01),
                            radius: radius * 0.87, rng: &rng)
            context.fill(dome, with: .color(base.color))

            if base.shape == .brin || base.shape == .grain {
                for i in 0..<8 {
                    let angle: Double = Double(i) * 45 + rng.between(0, 22)
                    let d = radius * rng.betweenCG(0.24, 0.56)
                    let p = CGPoint(x: center.x + cosine(radians(angle)) * d,
                                    y: center.y + sine(radians(angle)) * d)
                    shape(base.shape, dans: &context, center: p, size: radius * 0.15,
                          color: darken(base.color, 0.84), rng: &rng)
                }
            }
        }

        // Toppings, laid out on a golden spiral to avoid clumping.
        let n = max(accents.count, 1)
        for (i, a) in accents.enumerated() {
            let repetitions = n <= 2 ? 3 : (n <= 4 ? 2 : 1)
            for j in 0..<repetitions {
                let index = Double(i + j * n)
                let angle: Double = index * 137.508 + stableOffset(a.key)
                let proportion: Double = 0.17 + 0.55 * (index + 0.55).squareRoot()
                    / Double(n * repetitions).squareRoot()
                let r = radius * CGFloat(proportion)
                let p = CGPoint(x: center.x + cosine(radians(angle)) * r,
                                y: center.y + sine(radians(angle)) * r * 0.93)
                shape(a.shape, dans: &context, center: p,
                      size: radius * rng.betweenCG(0.15, 0.22), color: a.color, rng: &rng)
            }
        }
    }

    // MARK: - Formes

    private func blob(center: CGPoint, radius: CGFloat, rng: inout SeededRandom) -> Path {
        var p = Path()
        let points = 11
        for i in 0..<points {
            let angle: Double = Double(i) / Double(points) * 2 * Double.pi
            let r = radius * rng.betweenCG(0.9, 1.1)
            let point = CGPoint(x: center.x + cosine(angle) * r, y: center.y + sine(angle) * r * 0.94)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        p.closeSubpath()
        return p
    }

    private func shape(_ shape: FoodShape, dans context: inout GraphicsContext,
                       center: CGPoint, size t: CGFloat, color: Color, rng: inout SeededRandom) {
        switch shape {
        case .chunk:
            let rect = CGRect(x: center.x - t, y: center.y - t * 0.78, width: t * 2, height: t * 1.56)
            var path = Path(roundedRect: rect, cornerRadius: t * 0.42)
            path = path.applying(rotation(rng.between(-12, 12), autour: center))
            context.fill(path, with: .color(color))

        case .rond:
            let depart = rng.between(0, 360)
            for i in 0..<3 {
                let angle: Double = radians(depart + Double(i) * 118)
                let d = t * 0.72
                let c = CGPoint(x: center.x + cosine(angle) * d, y: center.y + sine(angle) * d * 0.9)
                context.fill(
                    Path(ellipseIn: CGRect(x: c.x - t * 0.6, y: c.y - t * 0.6, width: t * 1.2, height: t * 1.2)),
                    with: .color(color))
            }

        case .grain:
            let depart = rng.between(0, 360)
            for i in 0..<5 {
                let angle: Double = radians(depart + Double(i) * 72)
                let c = CGPoint(x: center.x + cosine(angle) * t * 0.8, y: center.y + sine(angle) * t * 0.7)
                var path = Path(ellipseIn: CGRect(x: c.x - t * 0.46, y: c.y - t * 0.26,
                                                    width: t * 0.92, height: t * 0.52))
                path = path.applying(rotation(Double(i) * 40, autour: c))
                context.fill(path, with: .color(color))
            }

        case .brin:
            for i in 0..<3 {
                let dy = CGFloat(i - 1) * t * 0.62
                var path = Path()
                path.move(to: CGPoint(x: center.x - t * 1.5, y: center.y + dy))
                path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + dy),
                                    control: CGPoint(x: center.x - t * 0.75, y: center.y + dy - t * 0.5))
                path.addQuadCurve(to: CGPoint(x: center.x + t * 1.5, y: center.y + dy),
                                    control: CGPoint(x: center.x + t * 0.75, y: center.y + dy + t * 0.5))
                context.stroke(path, with: .color(color),
                                style: StrokeStyle(lineWidth: t * 0.42, lineCap: .round))
            }

        case .arc:
            var path = Path()
            path.addArc(center: center, radius: t * 1.2,
                          startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
            context.stroke(path, with: .color(color),
                            style: StrokeStyle(lineWidth: t * 0.6, lineCap: .round))

        case .goutte:
            var path = Path()
            path.move(to: CGPoint(x: center.x, y: center.y - t))
            path.addCurve(to: CGPoint(x: center.x, y: center.y + t),
                            control1: CGPoint(x: center.x + t * 0.85, y: center.y - t * 0.15),
                            control2: CGPoint(x: center.x + t * 0.6, y: center.y + t))
            path.addCurve(to: CGPoint(x: center.x, y: center.y - t),
                            control1: CGPoint(x: center.x - t * 0.6, y: center.y + t),
                            control2: CGPoint(x: center.x - t * 0.85, y: center.y - t * 0.15))
            path.closeSubpath()
            context.fill(path, with: .color(color))

        case .feuille:
            var path = Path()
            path.move(to: CGPoint(x: center.x - t * 1.15, y: center.y))
            path.addQuadCurve(to: CGPoint(x: center.x + t * 1.15, y: center.y),
                                control: CGPoint(x: center.x, y: center.y - t * 1.1))
            path.addQuadCurve(to: CGPoint(x: center.x - t * 1.15, y: center.y),
                                control: CGPoint(x: center.x, y: center.y + t * 1.1))
            path.closeSubpath()
            path = path.applying(rotation(rng.between(-40, 20), autour: center))
            context.fill(path, with: .color(color))

        case .poudre:
            for _ in 0..<7 {
                let p = CGPoint(x: center.x + t * rng.betweenCG(-1.3, 1.3),
                                y: center.y + t * rng.betweenCG(-1.1, 1.1))
                let r = t * rng.betweenCG(0.19, 0.29)
                context.fill(
                    Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                    with: .color(color))
            }
        }
    }

    /// Angular offset derived from the key, identical on every launch.
    private func stableOffset(_ key: String) -> Double {
        var somme: UInt32 = 0
        for octet in key.utf8 { somme = (somme &* 31 &+ UInt32(octet)) % 1000 }
        return Double(somme % 60)
    }

    private func rotation(_ degres: Double, autour p: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: p.x, y: p.y)
            .rotated(by: CGFloat(radians(degres)))
            .translatedBy(x: -p.x, y: -p.y)
    }

    private func darken(_ color: Color, _ facteur: Double) -> Color {
        color.mix(avec: .black, quantite: 1 - facteur)
    }
}

extension Color {
    /// Simple shuffle, without depending on recent API.
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
