//  RecipeDetailScreen.swift
//
//  La fiche. Le cœur du product, c'est le journal des ingrédients : ce qu'on
//  change, par quoi, et pourquoi. Un parent qui ne comprend pas un
//  remplacement ne le fera pas.

import SwiftUI

struct RecipeDetailScreen: View {
    let recipe: Recipe
    let result: AdaptedRecipe
    let firstName: String

    @Environment(AppState.self) private var etat

    private var verdict: Verdict { Verdict(result, firstName: firstName) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                RecipeVisual(recipe: recipe, result: result)
                    .aspectRatio(16/10, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 280)
                    .clipped()

                VStack(alignment: .leading, spacing: 14) {
                    title
                    banniereVerdict
                    blocTexture
                    alerts
                    blocIngredients
                    RatingBlock(recipe: recipe)
                    blocPreparation
                    blocProvenance
                    Text(Settings.medicalDisclaimer)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 18)
            }
            .padding(.bottom, 36)
        }
        .background(Tint.background.ignoresSafeArea())
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SaveButton(recipe: recipe)
            }
        }
    }

    // MARK: - Sections

    private var title: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recipe.name)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .lineLimit(3)
            Text(soustitre)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var soustitre: String {
        var bouts = [recipe.subtitle, "\(firstName), \(Format.age(etat.activeProfile.ageMonths))"]
        let noms = etat.allergenNames(etat.activeProfile.allergens)
        if !noms.isEmpty { bouts.append("sans \(Format.liste(noms))") }
        return bouts.joined(separator: " · ")
    }

    private var banniereVerdict: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: verdict.symbol)
                .font(.title3)
                .foregroundStyle(verdict.color)
            VStack(alignment: .leading, spacing: 3) {
                Text(verdict.title).font(.headline)
                Text(verdict.detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(verdict.color.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
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
            Rectangle().frame(width: 4).foregroundStyle(Tint.betterave)
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
                        .foregroundStyle(Tint.betterave)
                        .frame(width: 25, height: 25)
                        .overlay(Circle().strokeBorder(Tint.betterave, lineWidth: 1.5))
                    Text(step).font(.body)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 7)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Étape \(index + 1). \(step)")
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

// MARK: - Ligne d'ingrédient

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
        case .substitue:
            (Text(ingredient.name).strikethrough(true, color: Tint.canneberge).foregroundStyle(.secondary)
             + Text("  →  ").foregroundStyle(Tint.betterave)
             + Text(ingredient.toName ?? "").foregroundStyle(Tint.betterave))
                .font(.subheadline.weight(.semibold))
        case .omis:
            (Text(ingredient.name).strikethrough(true, color: Tint.canneberge).foregroundStyle(.secondary)
             + Text("  →  ").foregroundStyle(Tint.betterave)
             + Text("we leave it out").foregroundStyle(Tint.betterave))
                .font(.subheadline.weight(.semibold))
        case .impossible:
            Text(ingredient.name)
                .strikethrough(true, color: Tint.canneberge)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        case .conserve, .inconnu:
            Text(ingredient.name).font(.subheadline.weight(.semibold))
        }
    }

    private var etiquettes: [(texte: String, color: Color)] {
        var out: [(String, Color)] = []
        if let m = ingredient.reason { out.append((m, Tint.betterave)) }
        if let r = ingredient.ratio,
           ingredient.status == .substitue || ingredient.status == .omis {
            out.append((r, Tint.pois))
        }
        if let p = ingredient.prep { out.append((p, Tint.courge)) }
        if ingredient.status == .impossible {
            out.append(("no safe replacement", Tint.canneberge))
        }
        return out.map { (texte: $0.0, color: $0.1) }
    }

    private var descriptionAccessible: String {
        switch ingredient.status {
        case .substitue:
            return "\(ingredient.name), remplacé par \(ingredient.toName ?? ""). \(ingredient.reason ?? "")"
        case .omis:
            return "\(ingredient.name), retiré. \(ingredient.reason ?? "")"
        case .impossible:
            return "\(ingredient.name), aucun remplacement sûr."
        default:
            return "\(ingredient.name), \(ingredient.displayQuantity). \(ingredient.prep ?? "")"
        }
    }
}

/// Étiquettes qui passent à la ligne, sans dépendre d'une API récente.
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
