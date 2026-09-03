// The heart of the product is the ingredient log: what was change, par quoi,
// et pourquoi. RecipeDetailScreen.swift

import SwiftUI

struct RecipeDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cooking = false
    @State private var showAbout = false
    @State private var openRule: AdaptedIngredient?
    let recipe: Recipe
    let result: AdaptedRecipe
    let firstName: String

    @Environment(AppState.self) private var app

    private var verdict: Verdict { Verdict(result, firstName: firstName) }

    /// The photo runs to the top of the screen and the content scrolls
    /// beneath the floating controls. No opaque navigation bar: a gradient
    /// keeps the status bar legible, which is the platform's own pattern.
    /* As a safeAreaInset on a ScrollView that also carries
     * `.ignoresSafeArea(edges: .top)`, they were drawn in the right place but
     * outside their parent's hit region — so neither back nor favourite */
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
                        /* The child is already named in the verdict pill
                         * below and in the ingredients header — repeating the
                         * whole profile here pushed the line to two rows. */
                        Text(recipe.subtitle)
                            .eyebrow(Tone.heroAccent)
                            .shadow(color: .black.opacity(0.6), radius: 8)

                        Text(recipe.name)
                            .scaledFont(Type.display)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.55), radius: 20)
                            .padding(.top, 8)

                        /* On the pill's own line: the note used to hang from
                         * the bottom of the photo while the pill floats over
                         * the image, so the two could never line up. */
                        /* Bottoms aligned, and the same glass as the verdict
                         * pill rather than a black field: the two read as one
                         * pair. The vertical padding matches VerdictPill's. */
                        HStack(alignment: .bottom) {
                            VerdictPill(result: result, firstName: firstName)
                            Spacer(minLength: 8)
                            if result.status != .asIs, recipe.image != nil {
                                Text("original recipe")
                                    .scaledFont(Type.micro)
                                    .foregroundStyle(Tone.text2)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 9)
                                    .glass(Capsule())
                            }
                        }
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
                    noticeRow
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
        /* The cause was never layout: on iOS 26 a glass container inside the
         * toolbar area intercepts touches, and `hitTest:` on it returns
         * itself, so an overlay drawn there receives nothing. */
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .scaledFont(Type.heading, weight: .semibold)
                        /* Ink, like the bookmark beside it: brand red is for
                         * what the parent acts on, not for going back. */
                        .foregroundStyle(Tone.text)
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
        .sheet(isPresented: $showAbout) { AboutScreen() }
        .sheet(item: $openRule) { item in
            SubstitutionRuleSheet(item: item)
        }
        .navigationDestination(isPresented: $cooking) {
            CookingMode(recipe: recipe, result: result, firstName: firstName)
        }
    }

    /// Glass circles floating over the photo, with content scrolling beneath —
    /// the exact pattern the platform describes for fixed buttons.
    /* One list, already adjusted: the swap is an annotation on the line, not
     * a structure: an amber tag says what it replaces, and the ratio sits
     * underneath when one is needed. */
    private var ingredientList: some View {
        VStack(alignment: .leading, spacing: 0) {
            /* No rules between lines: a full-width divider between two
             * columns is an invoice. */
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: String(localized: "For %@"), firstName))
                    .eyebrow()
                Spacer(minLength: 0)
                Text(String(format: String(localized: "%lld items"),
                            result.ingredients.count))
                    .scaledFont(Type.micro)
                    .foregroundStyle(Tone.text3)
            }
            .padding(.top, 22)
            .padding(.bottom, 4)

            ForEach(result.ingredients) { item in
                IngredientLine(item: item) {
                    if item.status == .swapped { openRule = item }
                }
            }
        }
    }

    /// The only button on this page. Everything else is read; this one moves
    /// you into hands-in-the-batter mode.
    private var startButton: some View {
        Button { cooking = true } label: {
            Text("Start cooking")
                .scaledFont(Type.body, weight: .semibold)
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
        .padding(.top, 40)
        /* Edge to edge, not behind the button: a background wraps the shape
         * it dresses, so this one stopped at the button's margins — and a
         * gradient that stops draws a box. */
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                stops: [.init(color: Tone.canvas.opacity(0), location: 0),
                        .init(color: Tone.canvas.opacity(0.55), location: 0.28),
                        .init(color: Tone.canvas.opacity(0.92), location: 0.55),
                        .init(color: Tone.canvas, location: 0.78)],
                startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var alerts: some View {
        let list = result.nonBlockingAlerts
        if !list.isEmpty {
            VStack(spacing: 8) {
                ForEach(list) { a in
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

    /// The steps, on the page rather than in a card: a white card floating on
    /// cream is a 2019 pattern: the card adds an outline and nothing else, and
    /// it fights the canvas the rest of the screen sits on.
    private var blocPreparation: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Preparation").eyebrow()
                Spacer(minLength: 0)
                Text(String(format: String(localized: "%lld steps"), result.steps.count))
                    .scaledFont(Type.micro)
                    .foregroundStyle(Tone.text3)
            }
            .padding(.top, 26)
            .padding(.bottom, 4)

            ForEach(Array(result.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 13) {
                    Text("\(index + 1)")
                        .scaledFont(Type.title, weight: .bold, design: .default)
                        .kerning(-0.6)
                        .monospacedDigit()
                        .foregroundStyle(Tone.text.opacity(0.14))
                        .frame(width: 26, alignment: .leading)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(step)
                            .scaledFont(Type.secondary)
                            .foregroundStyle(Tone.text)
                            .fixedSize(horizontal: false, vertical: true)

                        /* A duration inside a step becomes a pill. It is the
                         * thing an eye hunts for with hands in the batter. */
                        if let minutes = Self.duree(dans: step) {
                            Label(minutes, systemImage: "timer")
                                .scaledFont(Type.micro, weight: .semibold, design: .monospaced)
                                .foregroundStyle(Tone.swap)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Tone.swap.opacity(0.1), in: Capsule())
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 11)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(index + 1). \(step)")

                if index < result.steps.count - 1 {
                    Divider().overlay(Tone.hairline).padding(.leading, 39)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A duration written in a step, if there is one: reads what the step
    /// already says rather than adding a field to the data: "Bake at 200 °C
    /// for 18 to 20 minutes" already carries it.
    static func duree(dans texte: String) -> String? {
        /* "to" and its French twin (U+00E0): a Quebec recipe writes the range
         * with the French word, and matching only the English half would
         * silently drop the pill on half the corpus. */
        let motif = #"(\d+)(?:\s*(?:to|\u{2013}|-|\u{00e0})\s*(\d+))?\s*(?:min|minute)"#
        guard let r = texte.range(of: motif, options: .regularExpression) else { return nil }
        let raw = String(texte[r])
        let nombres = raw.split(whereSeparator: { !$0.isNumber }).map(String.init)
        guard let premier = nombres.first else { return nil }
        if nombres.count > 1 { return "\(premier)–\(nombres[1]) min" }
        return "\(premier) min"
    }

    /// The notices, as one row rather than eleven lines of grey. A tap opens
    /// About, where the full text lives for both this screen and Family.
    private var noticeRow: some View {
        Button { showAbout = true } label: {
            HStack(spacing: 9) {
                Image(systemName: "info")
                    .scaledFont(Type.label, weight: .bold)
                    .foregroundStyle(Tone.text3)
                    .frame(width: 22, height: 22)
                    .background(Tone.text3.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("Not medical advice")
                        .scaledFont(Type.caption, weight: .medium)
                        .foregroundStyle(Tone.text)
                    Text(recipe.image != nil
                         ? "Photo for illustration · swaps from versioned tables"
                         : "Swaps and age guidance from versioned tables")
                        .scaledFont(Type.micro)
                        .foregroundStyle(Tone.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .scaledFont(Type.micro, weight: .semibold)
                    .foregroundStyle(Tone.text3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tone.text.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Tone.hairline, lineWidth: 0.5)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.top, 18)
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
                Text("Licence: \(p.license)").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tone.text.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Tone.hairline, lineWidth: 1)
            }
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
                /* Text2, not text3: the quantity was set in the palette's
                 * faintest ink, which is meant for counts and captions, not
                 * for a number someone measures with. */
                Text(quantity)
                    .scaledFont(Type.caption, design: .monospaced)
                    .foregroundStyle(Tone.text2)
                    .frame(width: 66, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.toName ?? item.name)
                        .scaledFont(Type.body)
                        .foregroundStyle(swapped ? Tone.swap : Tone.text)
                        .multilineTextAlignment(.leading)
                    if let ratio = item.ratio, swapped {
                        Text(ratio)
                            .scaledFont(Type.label)
                            .foregroundStyle(Tone.text3)
                    }
                    if let prep = item.prep {
                        Text(prep)
                            .scaledFont(Type.label)
                            .foregroundStyle(Tone.swap.opacity(0.85))
                    }
                }

                Spacer(minLength: 6)

                if swapped {
                    Text(String(format: String(localized: "REPLACES %@"),
                                item.name.uppercased()))
                        .scaledFont(Type.micro, weight: .bold, design: .monospaced)
                        .kerning(0.6)
                        .foregroundStyle(Tone.swap)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .overlay {
                            Capsule().strokeBorder(Tone.swap.opacity(0.35), lineWidth: 1)
                        }
                        .padding(.top, 2)

                    /* Say that the row opens: the row has always been a
                     * button, disabled unless the ingredient was swapped, and
                     * nothing on it said so. */
                    Image(systemName: "chevron.right")
                        .scaledFont(Type.micro, weight: .semibold)
                        .foregroundStyle(Tone.swap.opacity(0.6))
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!swapped)
    }

    private var quantity: String {
        let v = item.qty.display
        return v.isEmpty ? item.unit : "\(v) \(item.unit)".trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - The rule behind a swap

/// Tapping a swapped ingredient opens the rule that produced it: every option
/// the table holds, in order, with its ratio and minimum age. This is what a
/// deterministic, versioned engine allows and a generated one cannot fake.
struct SubstitutionRuleSheet: View {
    let item: AdaptedIngredient
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                /* The swap as a swap, not as a sentence with an arrow:
                 * stacked and labelled, it holds at any length and says which
                 * way it goes. */
                Text("Taken out").eyebrow()
                Text(item.name)
                    .scaledFont(Type.heading)
                    .foregroundStyle(Tone.text2)
                    .strikethrough(true, color: Tone.text3)
                    .padding(.top, 3)

                Text("Put in").eyebrow().padding(.top, 13)
                Text(item.toName ?? "")
                    .scaledFont(Type.title, weight: .semibold)
                    .foregroundStyle(Tone.swap)
                    .padding(.top, 3)

                /* The ratio folds under the substitute it belongs to. It had a
                 * titled block and a rule of its own for three characters. */
                if let ratio = item.ratio {
                    Text(ratio)
                        .scaledFont(Type.label, weight: .regular, design: .monospaced)
                        .foregroundStyle(Tone.text2)
                        .padding(.top, 4)
                }

                if let reason = item.reason {
                    rule
                    Text(String(format: String(localized: "Why it is out for %@"),
                                app.activeProfile.name))
                        .eyebrow()
                    Text(reason)
                        .scaledFont(Type.secondary)
                        .foregroundStyle(Tone.text)
                        .padding(.top, 6)
                }

                rule

                /* "Every option in the table" named an internal concept: the
                 * table is ours, not the parent's. */
                Text("All the choices").eyebrow().padding(.bottom, 8)

                ForEach(app.substitutionOptions(for: item.name,
                                                 chosen: item.toName), id: \.name) { opt in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Image(systemName: "checkmark")
                            .scaledFont(Type.micro, weight: .bold)
                            .foregroundStyle(opt.chosen ? Tone.swap : .clear)
                            .frame(width: 12, alignment: .leading)
                        Text(opt.name)
                            .scaledFont(Type.secondary, weight: opt.chosen ? .semibold : .regular)
                            .foregroundStyle(opt.chosen ? Tone.swap : Tone.text)
                        Spacer(minLength: 8)
                        Text(opt.detail)
                            .scaledFont(Type.label)
                            .foregroundStyle(Tone.text2)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, 8)
                    Divider().overlay(Tone.hairline)
                }

                Text("These tables ship with the app and work offline. They are free for everyone, subscribed or not.")
                    .scaledFont(Type.label)
                    .foregroundStyle(Tone.text3)
                    .lineSpacing(2)
                    .padding(.top, 22)
            }
            .padding(.horizontal, Layout.gutter)
            /* Clear of the drag handle. The indicator is drawn OVER the
             * sheet rather than laid out above it, so six points put the
             * first eyebrow underneath it. */
            .padding(.top, 26)
            .padding(.bottom, 40)
        }
        .background(Tone.canvas)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var rule: some View {
        Rectangle().fill(Tone.hairline)
            .frame(height: 1)
            .padding(.vertical, 16)
    }
}
