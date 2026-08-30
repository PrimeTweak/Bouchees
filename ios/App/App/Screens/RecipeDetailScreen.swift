//  RecipeDetailScreen.swift
//
//  The detail view. The heart of the product is the ingredient log: what was
//  change, par quoi, et pourquoi. Un parent qui ne comprend pas un
//  remplacement ne le fera pas.

import SwiftUI

struct RecipeDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cooking = false
    @State private var openRule: AdaptedIngredient?
    let recipe: Recipe
    let result: AdaptedRecipe
    let firstName: String

    @Environment(AppState.self) private var etat

    private var verdict: Verdict { Verdict(result, firstName: firstName) }

    /// The photo runs to the top of the screen and the content scrolls
    /// beneath the floating controls. No opaque navigation bar: a gradient
    /// keeps the status bar legible, which is the platform's own pattern.
    /* THE BUTTONS LIVE ABOVE THE SCROLL VIEW, NOT INSIDE IT.
     *
     * As a safeAreaInset on a ScrollView that also carries
     * `.ignoresSafeArea(edges: .top)`, they were drawn in the right place but
     * outside their parent's hit region — so neither back nor favourite
     * responded. In a ZStack at screen level they sit above the scrolling
     * content and receive taps normally.
     */
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    /* Dark field under the image, whatever the theme — white
                     * text needs it. See RecipesScreen for the full note. */
                    ZStack {
                        Tone.heroField
                        RecipeVisual(recipe: recipe, result: result,
                                     drawingBackground: false)
                            .frame(height: Layout.detailPhoto)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(height: Layout.detailPhoto)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay { PhotoScrim() }

                    VStack(alignment: .leading, spacing: 0) {
                        /* The recipe only. The child is already named in the
                         * verdict pill below and in the ingredients header —
                         * repeating the whole profile here pushed the line to
                         * two rows and buried the title. */
                        Text(recipe.subtitle)
                            .eyebrow(Tone.heroAccent)
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
                    ingredientList
                    alerts
                    blocPreparation
                    RatingBlock(recipe: recipe)
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
            .padding(.bottom, 16)
        }
        .background(Tone.canvas.ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .top)

        /* As an inset, not an overlay: the content ends above it on its own,
         * and it no longer collides with the tab bar — which is hidden here,
         * as it is in any app once you are inside a detail. */
        .safeAreaInset(edge: .bottom) { startButton }
        .hidesTabBar()
        /* IN THE BAR, NOT OVER IT.
         *
         * Four attempts moved these buttons around the same screen. The cause
         * was never layout: on iOS 26 a glass container inside the toolbar
         * area intercepts touches, and `hitTest:` on it returns itself, so an
         * overlay drawn there receives nothing. Apple has the bug filed
         * (FB18201935) and the reproduction case is this exact shape — an
         * overlay carrying a glassEffect button over a scroll view that
         * ignores the safe area.
         *
         * `.toolbar` puts them INSIDE that container instead of behind it,
         * and iOS 26 gives toolbar items the material automatically, grouped
         * with their neighbours. */
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                }
                .accessibilityLabel("Back")
            }
            ToolbarItem(placement: .topBarTrailing) {
                SaveButton(recipe: recipe)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        /* The system draws its own back button as soon as a screen is pushed.
         * Adding a ToolbarItem beside it gave two — mine and the platform's,
         * side by side. */
        .navigationBarBackButtonHidden(true)
        .sheet(item: $openRule) { item in
            SubstitutionRuleSheet(item: item)
        }
        .navigationDestination(isPresented: $cooking) {
            CookingMode(recipe: recipe, result: result, firstName: firstName)
        }
    }

    /// Glass circles floating over the photo, with content scrolling beneath —
    /// the exact pattern the platform describes for fixed buttons.
    /* ONE LIST, ALREADY ADJUSTED.
     *
     * Not two columns. The parent does not want to see the before — they want
     * the recipe they are going to shop for and cook. The swap is an
     * annotation on the line, not a structure: an amber tag says what it
     * replaces, and the ratio sits underneath when one is needed.
     *
     * Tapping a swapped line opens the rule that produced it. Available, never
     * in the way. */
    private var ingredientList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(format: String(localized: "Ingredients for %@"), firstName))
                .eyebrow()
                .padding(.top, 24)
                .padding(.bottom, 10)

            ForEach(result.ingredients) { item in
                IngredientLine(item: item) {
                    if item.status == .swapped { openRule = item }
                }
                if item.listID != result.ingredients.last?.listID {
                    Divider().overlay(Tone.hairline)
                }
            }
        }
    }

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
        .padding(.top, 14)
        /* Content used to read straight through the button. A fade under it
         * means the list dissolves rather than colliding. */
        .background {
            LinearGradient(colors: [Tone.canvas.opacity(0), Tone.canvas.opacity(0.94),
                                    Tone.canvas],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        }
    }

    /// Glass circles over the photo, content scrolling beneath — the pattern
    /// the platform describes for fixed buttons.
    private var backButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 42, height: 42)
                .glass(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    private var saveButton: some View {
        SaveButton(recipe: recipe)
            .frame(width: 42, height: 42)
            .glass(Circle())
            }

    // MARK: - Sections

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

// MARK: - Ingredient line

/// Quantity, name, and — when it was swapped — an amber tag naming what it
/// replaces, with the ratio underneath. The parent reads their list; the swap
/// information is there if they look for it and invisible if they do not.
struct IngredientLine: View {
    let item: AdaptedIngredient
    var tap: () -> Void = {}

    private var swapped: Bool { item.status == .swapped }

    var body: some View {
        Button(action: tap) {
            HStack(alignment: .top, spacing: 13) {
                Text(quantity)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Tone.text3)
                    .frame(width: 66, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.toName ?? item.name)
                        .font(.system(size: 15.5))
                        .foregroundStyle(swapped ? Tone.swap : Tone.text)
                        .multilineTextAlignment(.leading)
                    if let ratio = item.ratio, swapped {
                        Text(ratio)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Tone.text3)
                    }
                    if let prep = item.prep {
                        Text(prep)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Tone.swap.opacity(0.85))
                    }
                }

                Spacer(minLength: 6)

                if swapped {
                    Text(String(format: String(localized: "REPLACES %@"),
                                item.name.uppercased()))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .kerning(0.6)
                        .foregroundStyle(Tone.swap)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .overlay {
                            Capsule().strokeBorder(Tone.swap.opacity(0.35), lineWidth: 1)
                        }
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!swapped)
    }

    private var quantity: String {
        let v = item.qty.affichage
        return v.isEmpty ? item.unit : "\(v) \(item.unit)".trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - The rule behind a swap

/// Tapping a swapped ingredient opens the rule that produced it: every option
/// the table holds, in order, with its ratio and minimum age. This is what a
/// deterministic, versioned engine allows and a generated one cannot fake.
struct SubstitutionRuleSheet: View {
    let item: AdaptedIngredient
    @Environment(AppState.self) private var etat
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(item.name) → \(item.toName ?? "")")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Tone.text)
                    .padding(.top, 6)

                if let reason = item.reason {
                    field("Why", reason)
                }
                if let ratio = item.ratio {
                    field("Ratio", ratio, mono: true)
                }

                Text("Every option in the table")
                    .eyebrow()
                    .padding(.top, 22)
                    .padding(.bottom, 8)

                ForEach(etat.substitutionOptions(for: item.name), id: \.name) { opt in
                    HStack(alignment: .firstTextBaseline, spacing: 11) {
                        Text(opt.name)
                            .font(.system(size: 13.5))
                            .foregroundStyle(opt.chosen ? Tone.swap : Tone.text2)
                        Spacer(minLength: 8)
                        Text(opt.detail)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Tone.text3)
                    }
                    .padding(.vertical, 8)
                    Divider().overlay(Tone.hairline)
                }

                Text("These tables ship with the app and work offline. They are free for everyone, subscribed or not.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Tone.text3)
                    .lineSpacing(2)
                    .padding(.top, 22)
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.bottom, 40)
        }
        .background(Tone.canvas)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func field(_ key: LocalizedStringKey, _ value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(key).eyebrow()
            Text(value)
                .font(.system(size: 14.5, design: mono ? .monospaced : .default))
                .foregroundStyle(Tone.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 15)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Tone.hairline).frame(height: 1)
        }
    }
}
