// Theme.swift Le langage visuel, en un seul endroit.

import SwiftUI

/* Kept as an alias so nothing breaks, but every colour now resolves through
 * Tone — one source, named by role, switching with the appearance. */
enum Tint {
    static let betterave = Tone.brand
    static let pois = Tone.yes
    static let courge = Tone.swap
    static let canneberge = Tone.no
    static let background = Tone.canvas
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

    /// The short form on a card: "As is" and "Adapted" describe what the
    /// engine did; "Ready" and "2 swaps" describe what the parent has to do.
    static func token(_ result: AdaptedRecipe) -> String {
        switch result.status {
        case .asIs: return String(localized: "Ready")
        case .adapted:
            let n = result.swapCount
            let modele = n > 1
                ? String(localized: "%lld swaps")
                : String(localized: "%lld swap")
            return String(format: modele, n)
        case .notAdaptable: return String(localized: "Not this one")
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
                .scaledFont(10, weight: .bold)
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
                .scaledFont(40)
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

// MARK: - Grid adaptative

