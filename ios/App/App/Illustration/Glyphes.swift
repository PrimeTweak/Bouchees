//  Glyphes.swift
//
//  Les onze familles d'allergènes, dessinées en Path natif. Un glyphe se
//  reconnaît d'un coup d'œil dans une grille; un mot demande d'être lu.

import SwiftUI

struct GlypheAllergene: View {
    let identifiant: String
    var taille: CGFloat = 20

    var body: some View {
        Canvas { contexte, _ in
            let chemin = Self.chemin(identifiant, dans: CGSize(width: taille, height: taille))
            contexte.stroke(chemin, with: .color(.primary),
                            style: StrokeStyle(lineWidth: taille * 0.075,
                                               lineCap: .round, lineJoin: .round))
        }
        .frame(width: taille, height: taille)
        .accessibilityHidden(true)
    }

    /// Chemins dessinés dans un carré de 20×20, puis mis à l'échelle.
    static func chemin(_ id: String, dans taille: CGSize) -> Path {
        var p = Path()
        let e = min(taille.width, taille.height) / 20

        func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * e, y: y * e) }

        switch id {
        case "lait":
            // Berlingot
            p.move(to: point(7, 3)); p.addLine(to: point(13, 3))
            p.addLine(to: point(13, 6)); p.addLine(to: point(15, 9))
            p.addLine(to: point(15, 17)); p.addLine(to: point(5, 17))
            p.addLine(to: point(5, 9)); p.addLine(to: point(7, 6))
            p.closeSubpath()
            p.move(to: point(7, 6)); p.addLine(to: point(13, 6))

        case "oeuf":
            p.move(to: point(10, 3))
            p.addCurve(to: point(15, 11), control1: point(13, 3), control2: point(15, 7.5))
            p.addCurve(to: point(10, 17), control1: point(15, 14.5), control2: point(12.8, 17))
            p.addCurve(to: point(5, 11), control1: point(7.2, 17), control2: point(5, 14.5))
            p.addCurve(to: point(10, 3), control1: point(5, 7.5), control2: point(7, 3))

        case "arachide":
            // Gousse en huit
            p.move(to: point(10, 3))
            p.addCurve(to: point(10, 10), control1: point(14.5, 3.5), control2: point(14, 8))
            p.addCurve(to: point(10, 17), control1: point(14.5, 12), control2: point(14, 17))
            p.addCurve(to: point(10, 10), control1: point(6, 17), control2: point(5.5, 12))
            p.addCurve(to: point(10, 3), control1: point(6, 8), control2: point(5.5, 3.5))
            p.move(to: point(7.5, 6.5)); p.addLine(to: point(12.5, 6.5))
            p.move(to: point(7.5, 13.5)); p.addLine(to: point(12.5, 13.5))

        case "noix":
            p.addEllipse(in: CGRect(x: 3.5 * e, y: 3.5 * e, width: 13 * e, height: 13 * e))
            p.move(to: point(10, 3.5)); p.addLine(to: point(10, 16.5))
            p.move(to: point(7, 5.2))
            p.addCurve(to: point(7, 14.8), control1: point(8.6, 8), control2: point(8.6, 12))
            p.move(to: point(13, 5.2))
            p.addCurve(to: point(13, 14.8), control1: point(11.4, 8), control2: point(11.4, 12))

        case "ble":
            // Épi
            p.move(to: point(10, 17.5)); p.addLine(to: point(10, 6))
            for niveau in [6.0, 10.0, 13.5] {
                p.move(to: point(10, niveau))
                p.addCurve(to: point(13, niveau - 3.8),
                           control1: point(10, niveau - 2), control2: point(11.2, niveau - 3.3))
                p.addCurve(to: point(10, niveau),
                           control1: point(13.3, niveau - 1.7), control2: point(12.2, niveau - 0.3))
                p.move(to: point(10, niveau))
                p.addCurve(to: point(7, niveau - 3.8),
                           control1: point(10, niveau - 2), control2: point(8.8, niveau - 3.3))
                p.addCurve(to: point(10, niveau),
                           control1: point(6.7, niveau - 1.7), control2: point(7.8, niveau - 0.3))
            }

        case "soya":
            // Gousse avec fèves
            p.move(to: point(4.5, 12.5))
            p.addCurve(to: point(12, 5), control1: point(4.5, 8.5), control2: point(8, 5))
            p.addCurve(to: point(15.5, 8.5), control1: point(14, 5), control2: point(15.5, 6.5))
            p.addCurve(to: point(8, 16), control1: point(15.5, 12.5), control2: point(12, 16))
            p.addCurve(to: point(4.5, 12.5), control1: point(6, 16), control2: point(4.5, 14.5))
            p.addEllipse(in: CGRect(x: 6.6 * e, y: 11.1 * e, width: 2.8 * e, height: 2.8 * e))
            p.addEllipse(in: CGRect(x: 10.4 * e, y: 7.6 * e, width: 2.8 * e, height: 2.8 * e))

        case "sesame":
            for (cx, cy) in [(7.0, 8.0), (12.5, 7.0), (10.0, 13.0)] {
                p.addEllipse(in: CGRect(x: (cx - 1.8) * e, y: (cy - 2.8) * e,
                                        width: 3.6 * e, height: 5.6 * e))
            }

        case "poisson":
            p.move(to: point(3.5, 10))
            p.addCurve(to: point(16, 10), control1: point(6.5, 4.5), control2: point(13, 4.5))
            p.addCurve(to: point(3.5, 10), control1: point(13, 15.5), control2: point(6.5, 15.5))
            p.move(to: point(3.5, 10)); p.addLine(to: point(1.5, 7))
            p.addLine(to: point(1.5, 13)); p.addLine(to: point(3.5, 10))
            p.addEllipse(in: CGRect(x: 12.1 * e, y: 8.3 * e, width: 1.6 * e, height: 1.6 * e))

        case "crustaces_mollusques":
            // Crevette recourbée
            p.move(to: point(15, 5.5))
            p.addCurve(to: point(7.5, 11), control1: point(11, 5.5), control2: point(7.5, 8))
            p.addCurve(to: point(11.5, 14.8), control1: point(7.5, 13.2), control2: point(9.3, 14.8))
            p.addCurve(to: point(15, 11.8), control1: point(13.5, 14.8), control2: point(15, 13.5))
            p.move(to: point(7.5, 11))
            p.addCurve(to: point(3.9, 8.7), control1: point(5.9, 11), control2: point(4.5, 10.1))
            p.move(to: point(15, 5.5)); p.addLine(to: point(17.3, 3))
            p.addEllipse(in: CGRect(x: 13.6 * e, y: 6.8 * e, width: 1.6 * e, height: 1.6 * e))

        case "moutarde":
            // Pot
            p.move(to: point(8, 3)); p.addLine(to: point(12, 3))
            p.addLine(to: point(12, 5.2)); p.addLine(to: point(13.6, 7.5))
            p.addLine(to: point(13.6, 17)); p.addLine(to: point(6.4, 17))
            p.addLine(to: point(6.4, 7.5)); p.addLine(to: point(8, 5.2))
            p.closeSubpath()
            p.move(to: point(6.4, 10)); p.addLine(to: point(13.6, 10))

        case "sulfites":
            // Fiole
            p.move(to: point(8, 3)); p.addLine(to: point(12, 3))
            p.addLine(to: point(12, 7.4)); p.addLine(to: point(15.3, 14.5))
            p.addCurve(to: point(13.8, 17), control1: point(15.8, 15.6), control2: point(15.1, 17))
            p.addLine(to: point(6.2, 17))
            p.addCurve(to: point(4.7, 14.5), control1: point(4.9, 17), control2: point(4.2, 15.6))
            p.closeSubpath()
            p.addEllipse(in: CGRect(x: 8 * e, y: 12.4 * e, width: 2 * e, height: 2 * e))
            p.addEllipse(in: CGRect(x: 11 * e, y: 14.2 * e, width: 1.6 * e, height: 1.6 * e))

        default:
            p.addEllipse(in: CGRect(x: 4 * e, y: 4 * e, width: 12 * e, height: 12 * e))
        }
        return p
    }
}

/// Le bouton d'allergène : glyphe + nom, état pressé bien visible.
struct BoutonAllergene: View {
    let allergene: Allergene
    let actif: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                GlypheAllergene(identifiant: allergene.id, taille: 20)
                    .foregroundStyle(actif ? Color.white : Color.primary)
                Text(allergene.nom)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(actif ? Color.white : Color.secondary)
            .background(actif ? Color.primary : Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(actif ? Color.clear : Color.primary.opacity(0.1), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(actif ? [.isSelected] : [])
        .accessibilityLabel("\(allergene.nom)\(actif ? ", évité" : "")")
    }
}
