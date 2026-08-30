//  RecipeDetailScreen.swift
//
//  The detail view. The heart of the product is the ingredient log: what was
//  change, par quoi, et pourquoi. Un parent qui ne comprend pas un
//  remplacement ne le fera pas.

import SwiftUI

struct RecipeDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cooking = false
    let recipe: Recipe
    let result: AdaptedRecipe
    let firstName: String

    @Environment(AppState.self) private var etat

    private var verdict: Verdict { Verdict(result, firstName: firstName) }

    /// The photo runs to the top of the screen and the content scrolls
    /// beneath the floating controls. No opaque navigation bar: a gradient
    /// keeps the status bar legible, which is the platform's own pattern.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    RecipeVisual(recipe: recipe, result: result)
                        .frame(height: Layout.detailPhoto)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .overlay { PhotoScrim() }

                    VStack(alignment: .leading, spacing: 0) {
                        Text(soustitre)
                            .eyebrow(Tone.brand)
                            .shadow(color: .black.opacity(0.6), radius: 8)

                        Text(recipe.name)
                            .font(Type.displayTight)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.55), radius: 20)
                            .padding(.top, 8)

                        VerdictPill(result: result, firstName: firstName)
                            .padding(.top, 14)
                    }
                    .padding(.horizontal, Layout.gutter)
                    .padding(.bottom, 22)
                }

                VStack(alignment: .leading, spacing: 0) {
                    blocTexture
                    alerts
                    blocIngredients
                    RatingBlock(recipe: recipe)
                    blocPreparation
                    blocProvenance
                    Text(Settings.medicalDisclaimer)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Tone.text3)
                        .lineSpacing(2)
                        .padding(.top, 28)
                }
                .padding(.horizontal, Layout.gutter)
                .padding(.top, 4)
            }
            .padding(.bottom, 130)
        }
        .background(Tone.canvas.ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topLeading) { backButton }
        .overlay(alignment: .topTrailing) { saveButton }
        .overlay(alignment: .bottom) { startButton }
        .navigationDestination(isPresented: $cooking) {
            CookingMode(recipe: recipe, result: result, firstName: firstName)
        }
    }

    /// Glass circles floating over the photo, with content scrolling beneath —
    /// the exact pattern the platform describes for fixed buttons.
    /// The only button on this page. Everything else is read; this one moves
    /// you into hands-in-the-batter mode.
    private var startButton: some View {
        Button { cooking = true } label: {
            Text("Start cooking")
                .font(.system(size: 16.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Tone.brandGradient)
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(.white.opacity(0.3), lineWidth: 0.75)
                        }
                }
                .shadow(color: Tone.brandDeep.opacity(0.46), radius: 18, y: 10)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 26)
    }

    /// Glass circles over the photo, content scrolling beneath — the pattern
    /// the platform describes for fixed buttons.
    private var backButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .glass(Circle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 18)
        .padding(.top, 58)
        .accessibilityLabel("Back")
    }

    private var saveButton: some View {
        SaveButton(recipe: recipe)
            .frame(width: 42, height: 42)
            .glass(Circle())
            .padding(.trailing, 18)
            .padding(.top, 58)
    }

    // MARK: - Sections

    private var soustitre: String {
        var bouts = [recipe.subtitle, "\(firstName), \(Format.age(etat.activeProfile.ageMonths))"]
        let noms = etat.allergenNames(etat.activeProfile.allergens)
        if !noms.isEmpty { bouts.append("no \(Format.liste(noms))") }
        return bouts.joined(separator: " · ")
    }

    private var blocTexture: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Texture — \(result.texture.name)").font(.headline)
            Text(result.texture.texture).font(.subheadline)
            if let note = result.texture.note, !note.isEmpty {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle().frame(width: 4).foregroundStyle(Tone.brand)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }

    @ViewBuilder
    private var alerts: some View {
        let liste = result.nonBlockingAlerts
        if !liste.isEmpty {
            VStack(spacing: 8) {
                ForEach(liste) { a in
                    HStack(alignment: .top, spacing: 11) {
                        Text(a.level.label)
                            .font(.caption2.weight(.bold))
                            .kerning(0.5)
                            .padding(.top, 2)
                        Text(a.message).font(.subheadline)
                    }
                    .foregroundStyle(a.level.color)
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(a.level.color.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var blocIngredients: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(result.hasChanges ? "Ingredients — what we change, and why" : "Ingredients")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .kerning(1.2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 12)

            ForEach(Array(result.ingredients.enumerated()), id: \.offset) { index, ing in
                IngredientRow(ingredient: ing)
                if index < result.ingredients.count - 1 {
                    Divider().padding(.vertical, 2)
                }
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var blocPreparation: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Preparation")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .kerning(1.2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 12)

            ForEach(Array(result.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 13) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Tone.brand)
                        .frame(width: 25, height: 25)
                        .overlay(Circle().strokeBorder(Tone.brand, lineWidth: 1.5))
                    Text(step).font(.body)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 7)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(index + 1). \(step)")
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var blocProvenance: some View {
        if let p = recipe.source {
            VStack(alignment: .leading, spacing: 5) {
                Text("Source")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(1.2)
                    .foregroundStyle(.tertiary)
                Text(p.source).font(.caption.monospaced())
                if let url = p.url, !url.isEmpty {
                    Text(url).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                }
                Text("Licence : \(p.license)").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

// MARK: - Ingredient row

struct IngredientRow: View {
    let ingredient: AdaptedIngredient

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                name
                Spacer(minLength: 8)
                Text(ingredient.displayQuantity)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: true, vertical: false)
            }

            if !etiquettes.isEmpty {
                TagFlow(etiquettes: etiquettes)
            }

            if let note = ingredient.note {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(descriptionAccessible)
    }

    @ViewBuilder
    private var name: some View {
        switch ingredient.status {
        case .swapped:
            (Text(ingredient.name).strikethrough(true, color: Tone.no).foregroundStyle(.secondary)
             + Text("  →  ").foregroundStyle(Tone.brand)
             + Text(ingredient.toName ?? "").foregroundStyle(Tone.brand))
                .font(.subheadline.weight(.semibold))
        case .omitted:
            (Text(ingredient.name).strikethrough(true, color: Tone.no).foregroundStyle(.secondary)
             + Text("  →  ").foregroundStyle(Tone.brand)
             + Text("we leave it out").foregroundStyle(Tone.brand))
                .font(.subheadline.weight(.semibold))
        case .blocked:
            Text(ingredient.name)
                .strikethrough(true, color: Tone.no)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        case .kept, .unknown:
            Text(ingredient.name).font(.subheadline.weight(.semibold))
        }
    }

    private var etiquettes: [(texte: String, color: Color)] {
        var out: [(String, Color)] = []
        if let m = ingredient.reason { out.append((m, Tone.brand)) }
        if let r = ingredient.ratio,
           ingredient.status == .swapped || ingredient.status == .omitted {
            out.append((r, Tone.yes))
        }
        if let p = ingredient.prep { out.append((p, Tone.swap)) }
        if ingredient.status == .blocked {
            out.append(("no safe replacement", Tone.no))
        }
        return out.map { (texte: $0.0, color: $0.1) }
    }

    private var descriptionAccessible: String {
        switch ingredient.status {
        case .swapped:
            return "\(ingredient.name), replaced by \(ingredient.toName ?? ""). \(ingredient.reason ?? "")"
        case .omitted:
            return "\(ingredient.name), removed. \(ingredient.reason ?? "")"
        case .blocked:
            return "\(ingredient.name), no safe replacement."
        default:
            return "\(ingredient.name), \(ingredient.displayQuantity). \(ingredient.prep ?? "")"
        }
    }
}

/// Wrapping labels, without depending on recent API.
struct TagFlow: View {
    let etiquettes: [(texte: String, color: Color)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(etiquettes.enumerated()), id: \.offset) { _, e in
                Text(e.texte)
                    .font(.caption2)
                    .foregroundStyle(e.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(e.color.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
