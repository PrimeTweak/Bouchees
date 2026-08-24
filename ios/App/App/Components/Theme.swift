//  Theme.swift
//
//  Le langage visuel, en un seul endroit. Les couleurs viennent des assets
//  (light and dark), no values hard-coded in the views.

import SwiftUI

enum Tint {
    static let betterave = Color("Betterave")
    static let pois = Color("Pois")
    static let courge = Color("Courge")
    static let courgePale = Color("CourgePale")
    static let canneberge = Color("Canneberge")
    static let background = Color("Fond")
}

extension RecipeStatus {
    var color: Color {
        switch self {
        case .asIs: return Tint.pois
        case .adapted: return Tint.betterave
        case .notAdaptable: return Tint.canneberge
        case .unknown: return .secondary
        }
    }

    var symbol: String {
        switch self {
        case .asIs: return "checkmark.circle.fill"
        case .adapted: return "arrow.triangle.swap"
        case .notAdaptable: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

extension AlertLevel {
    var color: Color {
        switch self {
        case .blocking: return Tint.canneberge
        case .safety, .caution: return Tint.courge
        case .info: return Tint.betterave
        }
    }
}

// MARK: - Verdict

/// The verdict, phrased the way a parent would ask it: can they eat this?
struct Verdict {
    let title: String
    let detail: String
    let color: Color
    let symbol: String

    init(_ result: AdaptedRecipe, firstName: String) {
        color = result.status.color
        symbol = result.status.symbol
        switch result.status {
        case .asIs:
            title = String(localized: "Yes, as is")
            detail = String(format: String(localized: "No ingredient to change for %@."), firstName)
        case .adapted:
            let n = result.swapCount
            let modele = n > 1
                ? String(localized: "Yes — with %lld swaps")
                : String(localized: "Yes — with %lld swap")
            title = String(format: modele, n)
            detail = String(localized: "What we replace, with what, and why — it’s all detailed below.")
        case .notAdaptable:
            title = String(format: String(localized: "Not this time for %@"), firstName)
            detail = result.blockingAlert?.message
                ?? String(localized: "One ingredient has no safe replacement.")
        case .unknown:
            title = String(localized: "We can’t say")
            detail = String(localized: "This recipe couldn’t be analysed. Don’t serve it without checking yourself.")
        }
    }

    /// Version courte pour une carte.
    static func token(_ result: AdaptedRecipe) -> String {
        switch result.status {
        case .asIs: return String(localized: "As is")
        case .adapted:
            let n = result.swapCount
            let modele = n > 1
                ? String(localized: "Yes — with %lld swaps")
                : String(localized: "Yes — with %lld swap")
            return String(format: modele, n)
        case .notAdaptable: return String(localized: "Not this time")
        case .unknown: return String(localized: "Needs checking")
        }
    }
}

// MARK: - Composants

struct VerdictChip: View {
    let result: AdaptedRecipe

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: result.status.symbol)
                .font(.system(size: 10, weight: .bold))
            Text(Verdict.token(result))
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(result.status.color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
    }
}

struct GuidanceChip: View {
    let count: Int

    var body: some View {
        Text("\(count) age-related safety note\(count > 1 ? "s" : "")")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Tint.courge)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
            .accessibilityLabel("\(count) age-related safety note\(count > 1 ? "s" : "")")
    }
}

struct RecipeCard: View {
    let recipe: Recipe
    let result: AdaptedRecipe

    private var estBloquee: Bool { result.status == .notAdaptable }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecipeVisual(recipe: recipe, result: result)
                .aspectRatio(4/3, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()
                .saturation(estBloquee ? 0.35 : 1)
                .opacity(estBloquee ? 0.75 : 1)
                .overlay(alignment: .topLeading) {
                    VerdictChip(result: result).padding(9)
                }
                .overlay(alignment: .topTrailing) {
                    if !estBloquee && result.ageGuidanceCount > 0 {
                        GuidanceChip(count: result.ageGuidanceCount).padding(9)
                    }
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(recipe.name)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)

                HStack(spacing: 7) {
                    Text(recipe.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let v = recipe.votes, v > 0 {
                        RatingBadge(votes: v, average: recipe.average, compact: true)
                    }
                }

                if let bloquante = result.blockingAlert {
                    Text(bloquante.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .padding(.top, 4)
                } else if let e = result.firstSwap {
                    SwapLine(de: e.de, to: e.to, autres: result.swapCount - 1)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(estBloquee ? Tint.canneberge.opacity(0.25) : Color.primary.opacity(0.07),
                              style: StrokeStyle(lineWidth: 1, dash: estBloquee ? [4, 3] : []))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(recipe.name). \(Verdict.token(result)).")
    }
}

/// The swap preview: original struck through, arrow, replacement.
struct SwapLine: View {
    let de: String
    let to: String
    var autres: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().padding(.bottom, 7)
            (Text(de).strikethrough(true, color: Tint.canneberge).foregroundStyle(.secondary)
             + Text("  →  ").foregroundStyle(Tint.betterave)
             + Text(to).foregroundStyle(Tint.betterave).fontWeight(.semibold)
             + Text(autres > 0 ? "  +\(autres)" : "").foregroundStyle(.tertiary))
                .font(.caption)
                .lineLimit(2)
        }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var titreAction: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundStyle(Tint.betterave.opacity(0.7))
            Text(title).font(.title3.weight(.bold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if let action, let titreAction {
                Button(titreAction, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Tint.betterave)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

struct MessageBanner: View {
    let texte: String
    var color: Color = Tint.courge

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "wifi.slash").font(.caption)
            Text(texte).font(.footnote)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: String
    let compte: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(title).font(.title3.weight(.bold))
            Text("\(compte)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            Rectangle().frame(height: 1).foregroundStyle(.quaternary)
        }
    }
}

// MARK: - Grid adaptative

enum Grid {
    static let colonnes = [GridItem(.adaptive(minimum: 158), spacing: 14)]
}
