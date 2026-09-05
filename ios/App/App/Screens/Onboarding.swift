// Every one of those steps is a place to close the app, and none of them had
// yet shown that the thing works. The counter is the whole pitch.

import SwiftUI
/* UIImpactFeedbackGenerator. */
import UIKit

struct OnboardingFlow: View {
    @Environment(AppState.self) private var app

    @State private var step = 0
    @State private var draft = ChildProfile.defaut
    @State private var name = ""

    var body: some View {
        ZStack {
            Tone.canvas.ignoresSafeArea()

            switch step {
            case 0: LiveDemoStep(draft: $draft, next: { step = 1 })
            case 1: WhoStep(draft: $draft, name: $name, next: { step = 2 })
            case 2: WeekStep(draft: draft, name: name, next: { step = 3 })
            default: OfferStep(draft: draft, finish: finish)
            }
        }
        .animation(.soft(0.28), value: step)
    }

    private func finish() {
        draft.name = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? String(localized: "My child") : name
        app.save(draft)
    }
}

/// The demo and the week again, for the child already saved: shown to a
/// partner, or revisited after being skipped. No name asked, no offer.
struct ReplayDemo: View {
    @Environment(AppState.self) private var app
    let done: () -> Void
    @State private var step = 0
    @State private var draft = ChildProfile.defaut

    var body: some View {
        ZStack {
            Tone.canvas.ignoresSafeArea()
            switch step {
            case 0: LiveDemoStep(draft: $draft, next: { step = 1 })
            default: WeekStep(draft: draft, name: draft.firstName, next: done)
            }
        }
        .animation(.soft(0.28), value: step)
        .onAppear { draft = app.activeProfile }
        .overlay(alignment: .topTrailing) {
            Button(action: done) {
                Image(systemName: "xmark")
                    .scaledFont(Type.secondary, weight: .semibold)
                    .foregroundStyle(Tone.text)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .glass(Circle())
            .padding(.trailing, Layout.gutter)
            .padding(.top, 12)
            .accessibilityLabel(Text("Close"))
        }
    }
}

// MARK: - Step 1 — the demo

/// A real recipe, on screen, before anything is asked. No account, no name, no
/// typing. The engine is local and instant, so this costs nothing to show — and
/// it is the entire pitch.
private struct LiveDemoStep: View {
    @Environment(AppState.self) private var app
    @Binding var draft: ChildProfile
    let next: () -> Void

    /// The recipe the demo adapts. Chosen because it carries milk, egg and
    /// wheat, so most taps produce a visible swap.
    private var demoRecipe: Recipe? {
        /* Only a recipe WITH a body can be adapted. The old fallback took the
         * first card alphabetically, which after a sync is a card without one
         * — and the demo went blank. */
        let withBody = app.recipes.filter(\.hasBody)
        return withBody.first { $0.id == "banana-oat-muffins" }
            ?? withBody.first { r in
                let ids = Set(r.ingredients.map(\.id))
                return ids.contains("cow_milk") || ids.contains("egg") || ids.contains("wheat_flour")
            }
            ?? withBody.first
    }

    private var result: AdaptedRecipe? {
        guard let r = demoRecipe else { return nil }
        return app.adaptPreview(r, for: draft)
    }


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BoucheesMark(size: 34)
                    .padding(.bottom, 18)

                Text("Nothing to sign up for. Works without a signal.")
                    .scaledFont(Type.label)
                    .foregroundStyle(Tone.brand)
                    .textCase(.uppercase)
                    .kerning(1.4)

                Text("What does your child avoid?")
                    .scaledFont(Type.display)
                    .foregroundStyle(Tone.text)
                    .padding(.top, 8)

                Text("Tap one and watch.")
                    .scaledFont(Type.body)
                    .foregroundStyle(Tone.textSecondary)
                    .padding(.top, 8)

                if let r = demoRecipe, let res = result {
                    DemoCard(recipe: r, result: res)
                        .padding(.top, 20)
                } else {
                    /* Never nothing: the engine is still loading, or no body
                     * is here yet. Say so instead of leaving a hole. */
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading a recipe to adapt…")
                            .scaledFont(Type.secondary)
                            .foregroundStyle(Tone.text3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Tone.text.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous))
                    .padding(.top, 20)
                }

                AllergenPad(selected: $draft.allergens, families: app.knownAllergens)
                    .padding(.top, 16)
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.bottom, 16)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button(action: next) {
                    Text("Continue")
                        .scaledFont(Type.heading, weight: .semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: Layout.tapTarget + 6)
                }
                .buttonStyle(PrimaryButton())

                Text("Nothing leaves this device.")
                    .scaledFont(Type.secondary)
                    .foregroundStyle(Tone.textTertiary)
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.bottom, 12)
            .softFooter()
        }
    }
}

/// The card that rewrites itself. The swap carries its reason, because that is
/// what separates this from a search engine.
private struct DemoCard: View {
    let recipe: Recipe
    let result: AdaptedRecipe

    /* One body holding the photo, the title, three swap rows and a verdict
     * defeats the type checker — the error it gives, "unable to type-check in
     * reasonable time", names the body and not the part that is heavy. */
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecipeVisual(recipe: recipe, result: result)
                .aspectRatio(2.1, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()

            VStack(alignment: .leading, spacing: 0) {
                Text(recipe.name)
                    .scaledFont(Type.heading, weight: .semibold)
                    .foregroundStyle(Tone.text)
                swaps
                readyMark
            }
            .padding(16)
        }
        .card(24)
        .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
        .animation(.soft(0.3), value: result.swapCount)
    }

    private var swaps: some View {
        ForEach(swapped.prefix(3), id: \.listID) { i in
            SwapRow(from: i.name, to: i.toName ?? "", why: i.reason)
        }
    }

    @ViewBuilder
    private var readyMark: some View {
        if result.status == .asIs {
            HStack(spacing: 8) {
                VerdictMark(status: .asIs)
                Text("Nothing to change")
                    .scaledFont(Type.secondary, weight: .semibold)
                    .foregroundStyle(Tone.yes)
            }
            .padding(.top, 13)
        }
    }

    private var swapped: [AdaptedIngredient] {
        result.ingredients.filter { $0.status == .swapped }
    }
}

/// One swap, with its reason attached. The reason is what separates this from
/// a search engine, so it never leaves the row it explains.
private struct SwapRow: View {
    let from: String
    let to: String
    let why: String?

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Text("→")
                .scaledFont(Type.secondary, weight: .bold)
                .foregroundStyle(Tone.swap)
            VStack(alignment: .leading, spacing: 2) {
                Text(from)
                    .scaledFont(Type.secondary)
                    .strikethrough()
                    .foregroundStyle(Tone.text3)
                Text(to)
                    .scaledFont(Type.body, weight: .semibold)
                    .foregroundStyle(Tone.text)
                if let why {
                    Text(why)
                        .scaledFont(Type.caption)
                        .foregroundStyle(Tone.text2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 13)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// All eleven families visible at once, no dropdown. The glyphs are the ones
/// already drawn for the app.
private struct AllergenPad: View {
    @Binding var selected: [String]
    let families: [Allergen]

    private let columns = [GridItem(.adaptive(minimum: 74), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(families) { a in
                AllergenTile(allergen: a,
                             isOn: selected.contains(a.id),
                             toggle: { toggle(a.id) })
            }
        }
        /* A settle, not a fade: this grid is the demonstration: tick milk and
         * the card above changes, the counts diverge, the recipe is re-
         * adapted in front of you. */
        .animation(.spring(response: 0.34, dampingFraction: 0.66), value: selected)
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.removeAll { $0 == id } }
        else { selected.append(id) }
        /* The tick is a decision about a child's food. It deserves the same
         * feedback as a switch, not silence. */
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

/* Its own View rather than a closure with a `let` inside a ViewBuilder. */
private struct AllergenTile: View {
    let allergen: Allergen
    let isOn: Bool
    let toggle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The press, the settle, and nothing in between: the overshoot reads as a
    /// consequence, which is what this screen exists to show: tick milk and
    /// the recipe above rewrites itself.
    private var settle: Animation {
        reduceMotion ? .easeInOut(duration: 0.15)
                     : .spring(response: 0.3, dampingFraction: 0.58)
    }

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 5) {
                AllergenGlyph(identifier: allergen.id, size: 23)
                    .foregroundStyle(isOn ? Color.white : Tone.text2)
                    /* The glyph leads by 40ms. It is what the eye is on, so it
                     * has to move before the rectangle behind it. */
                    .scaleEffect(isOn ? 1.1 : 1)
                    .animation(reduceMotion ? .easeInOut(duration: 0.15)
                                            : .spring(response: 0.26,
                                                      dampingFraction: 0.5),
                               value: isOn)

                Text(allergen.name)
                    .scaledFont(Type.micro, weight: .semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(isOn ? Color.white : Tone.text2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isOn ? AnyShapeStyle(Tone.brandGradient)
                               : AnyShapeStyle(Tone.text.opacity(0.045)))
                    .shadow(color: isOn ? Tone.brandDeep.opacity(0.32) : .clear,
                            radius: 10, y: 5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isOn ? .clear : Tone.hairline, lineWidth: 1)
            }
            /* A tick, not just a colour: eleven tiles is too many to scan by
             * colour alone, and it is the only cue for a parent who cannot
             * separate the two. */
            .overlay(alignment: .topTrailing) {
                if isOn {
                    Image(systemName: "checkmark")
                        .scaledFont(Type.micro, weight: .bold)
                        .foregroundStyle(.white)
                        .frame(width: 14, height: 14)
                        .background(Color.white.opacity(0.26), in: Circle())
                        .padding(5)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .scaleEffect(isOn ? 1.04 : 1)
            .animation(settle, value: isOn)
        }
        .buttonStyle(PressedTile())
        .accessibilityLabel(Text(allergen.name))
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }
}

/// The press itself: down to 0.94, then the settle takes over.
private struct PressedTile: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7),
                       value: configuration.isPressed)
    }
}

// MARK: - Step 2 — who

/// Name and age on one screen. They are two taps, not two decisions; splitting
/// them added a step and bought nothing.
private struct WhoStep: View {
    @Binding var draft: ChildProfile
    @Binding var name: String
    let next: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Step 2 of 4")
                    .scaledFont(Type.label)
                    .foregroundStyle(Tone.brand)
                    .textCase(.uppercase)
                    .kerning(1.4)

                Text("Who am I cooking for?")
                    .scaledFont(Type.display)
                    .foregroundStyle(Tone.text)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text("First name")
                        .scaledFont(Type.label)
                        .foregroundStyle(Tone.textTertiary)
                        .textCase(.uppercase)
                        .kerning(1.2)
                    TextField("First name", text: $name)
                        .scaledFont(Type.secondary)
                        .foregroundStyle(Tone.text)
                        .focused($focused)
                        .submitLabel(.next)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Tone.surface, in: RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous)
                    .strokeBorder(Tone.hairline, lineWidth: 1))
                .padding(.top, 22)

                Text("Age")
                    .scaledFont(Type.label)
                    .foregroundStyle(Tone.textTertiary)
                    .textCase(.uppercase)
                    .kerning(1.2)
                    .padding(.top, 22)
                    .padding(.bottom, 9)

                /* By stage, and each stage says what it changes. "Still quarter
                 * the grapes" is the reason a parent cares about age at all. */
                VStack(spacing: 7) {
                    ForEach(AgeStage.all, id: \.months) { st in
                        StageRow(stage: st, selected: draft.ageMonths == st.months) {
                            draft.ageMonths = st.months
                        }
                    }
                }
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.bottom, 16)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 9) {
                Button(action: next) {
                    Text(name.trimmingCharacters(in: .whitespaces).isEmpty
                         ? String(localized: "Plan the week")
                         : String(format: String(localized: "Plan %@'s week"), name.trimmingCharacters(in: .whitespaces)))
                        .scaledFont(Type.heading, weight: .semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: Layout.tapTarget + 6)
                }
                .buttonStyle(PrimaryButton())

                Text("Not medical advice. Swaps come from versioned tables a professional should review.")
                    .scaledFont(Type.secondary)
                    .foregroundStyle(Tone.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.bottom, 12)
            .softFooter()
        }
        .onAppear { focused = true }
    }
}

/* Not Sendable, and not LocalizedStringKey: localizedStringKey is not
 * Sendable, so declaring the struct Sendable is a warning today and an error
 * under Swift 6. */
struct AgeStage {
    let months: Int
    let title: String.LocalizationValue
    let detail: String.LocalizationValue

    static let all: [AgeStage] = [
        .init(months: 7, title: "6–8 months", detail: "Smooth purées, soft sticks they can hold"),
        .init(months: 10, title: "9–11 months", detail: "Coarsely mashed, small soft pieces"),
        .init(months: 18, title: "1–2 years", detail: "Most textures — still quarter the grapes"),
        .init(months: 36, title: "3 years", detail: "Nearly everything, cut small"),
        .init(months: 60, title: "4 years and up", detail: "Any texture")
    ]
}

private struct StageRow: View {
    let stage: AgeStage
    let selected: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: stage.title))
                    .scaledFont(Type.body, weight: .semibold)
                Text(String(localized: stage.detail))
                    .scaledFont(Type.secondary)
                    .opacity(selected ? 0.85 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .background(selected ? Tone.brand : Tone.surface,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Color.clear : Tone.hairline, lineWidth: 1))
            .foregroundStyle(selected ? Color.white : Tone.text)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: - Step 3 — the week

/// The thing the subscription actually sells, shown before the price: this
/// child's real week, from the real sequence, with the name just typed. Then
/// four tiles, three words each, for the four features the demo never showed.
private struct WeekStep: View {
    @Environment(AppState.self) private var app
    let draft: ChildProfile
    let name: String
    let next: () -> Void

    private var prenom: String {
        let t = name.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? String(localized: "Your child") : t
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Step 3 of 4")
                    .scaledFont(Type.label)
                    .foregroundStyle(Tone.brand)
                    .textCase(.uppercase)
                    .kerning(1.4)

                Text(String(format: String(localized: "%@'s week is ready."), prenom))
                    .scaledFont(Type.display)
                    .foregroundStyle(Tone.text)
                    .padding(.top, 8)

                Text(String(format: String(localized: "Fourteen recipes, one meal and one snack a day — every one of them safe for %@, already adapted."), prenom))
                    .scaledFont(Type.body)
                    .foregroundStyle(Tone.textSecondary)
                    .padding(.top, 8)

                apercu
                    .padding(.top, 18)

                tuiles
                    .padding(.top, 18)
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.bottom, 16)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button(action: next) {
                    Text("Continue")
                        .scaledFont(Type.heading, weight: .semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: Layout.tapTarget + 6)
                }
                .buttonStyle(PrimaryButton())

                Text("Nothing leaves this device.")
                    .scaledFont(Type.secondary)
                    .foregroundStyle(Tone.text3)
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .background(Tone.canvas)
        }
    }

    /// The first three days, fading out: there is more below the fold.
    private var apercu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(app.weekPreview(for: draft), id: \.day) { jour in
                Text(WeekDay.full[jour.day])
                    .eyebrow()
                    .padding(.top, jour.day == 0 ? 0 : 12)
                    .padding(.bottom, 4)
                ForEach(jour.recipes, id: \.id) { r in
                    HStack(spacing: 12) {
                        if let res = app.adaptPreview(r, for: draft) ?? app.liteResult(for: r, profile: draft) {
                            RecipeVisual(recipe: r, result: res)
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(Tone.text.opacity(0.06))
                                .frame(width: 52, height: 52)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name).scaledFont(Type.body, weight: .semibold).foregroundStyle(Tone.text).lineLimit(1)
                            Text(r.isMeal ? String(localized: "Meal") : String(localized: "Snack"))
                                .scaledFont(Type.caption).foregroundStyle(Tone.text2)
                        }
                    }
                    .padding(.vertical, 7)
                }
            }
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0.72), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
    }

    private var tuiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            tuile("calendar", String(localized: "Your week"), String(localized: "Planned for you. Swap any two dishes."))
            tuile("barcode.viewfinder", String(localized: "The scanner"), String(localized: "A barcode at the store: yes or no, no signal needed."))
            tuile("cart", String(localized: "The list"), String(localized: "Groceries build themselves from the week."))
            tuile("play.fill", String(localized: "Cooking mode"), String(localized: "One step at a time, one hand free."))
        }
    }

    private func tuile(_ symbole: String, _ titre: String, _ texte: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbole)
                .scaledFont(Type.caption, weight: .semibold)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Tone.brand, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(titre).scaledFont(Type.secondary, weight: .semibold).foregroundStyle(Tone.text)
            Text(texte).scaledFont(Type.label, weight: .regular).foregroundStyle(Tone.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Tone.text.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Step 4 — the offer

/// The green box is the most important thing on this screen, and it announces
/// what is FREE. Counter-intuitive, and it is what works: showing that safety
/// is not held hostage is what makes the rest credible.
private struct OfferStep: View {
    @Environment(AppState.self) private var app
    let draft: ChildProfile
    let finish: () -> Void

    /// The App Store's own price, in the user's currency. Falls back to the
    /// trial wording alone when StoreKit has not answered — never to a
    /// number we invented.
    private var priceLine: String {
        guard let price = app.subscription.displayPrice else {
            return String(localized: "7 days free")
        }
        let period = app.subscription.displayPeriod ?? String(localized: "month")
        return String(format: String(localized: "7 days free, then %@/%@"), price, period)
    }

    private var tally: AppState.ProfileTally { app.tally(for: draft) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("For \(draft.firstName)")
                    .scaledFont(Type.label)
                    .foregroundStyle(Tone.brand)
                    .textCase(.uppercase)
                    .kerning(1.4)

                Text("\(tally.total) today.\n7 more every week.")
                    .scaledFont(Type.display)
                    .foregroundStyle(Tone.text)
                    .padding(.top, 8)

                GrowthBars(today: tally.total)
                    .padding(.top, 22)

                FreeForever()
                    .padding(.top, 20)

                VStack(spacing: 0) {
                    Perk(title: "7 new recipes every week",
                         detail: "Written for the profiles with the fewest options")
                    Divider().overlay(Tone.hairline)
                    Perk(title: "Every past week, kept",
                         detail: "Nothing disappears once it is unlocked")
                }
                .padding(.top, 18)
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.bottom, 16)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Button(action: finish) {
                    Text("Try 7 days free")
                        .scaledFont(Type.heading, weight: .semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: Layout.tapTarget + 6)
                }
                .buttonStyle(PrimaryButton())

                /* A visible way out RAISES conversion: it removes the sense of
                 * a trap, and it avoids the subscriber who cancels on day 8
                 * feeling tricked. */
                Button(action: finish) {
                    Text("Continue with the free recipes")
                        .scaledFont(Type.body)
                        .foregroundStyle(Tone.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: Layout.tapTarget)
                }
                .buttonStyle(.plain)

                Text(priceLine)
                    .scaledFont(Type.secondary)
                    .foregroundStyle(Tone.textTertiary)
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.bottom, 10)
            .softFooter()
        }
    }
}

/// Honest arithmetic: today, and the same corpus a year out at seven a week.
private struct GrowthBars: View {
    let today: Int

    private var points: [(label: LocalizedStringKey, value: Int)] {
        [("Now", today), ("1 mo", today + 28), ("3 mo", today + 84),
         ("6 mo", today + 182), ("1 yr", today + 364)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 7) {
                ForEach(Array(points.enumerated()), id: \.offset) { i, p in
                    let peak = points.last?.value ?? 1
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(i == 0 ? Tone.yes : Tone.brand.opacity(0.35 + 0.14 * Double(i)))
                        .frame(height: max(18, 96 * CGFloat(p.value) / CGFloat(peak)))
                }
            }
            HStack(spacing: 7) {
                ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                    Text(p.label)
                        .scaledFont(Type.micro, weight: .medium)
                        .foregroundStyle(Tone.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            Text("\(points.last?.value ?? 0) recipes a year from now")
                .scaledFont(Type.secondary)
                .foregroundStyle(Tone.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private struct FreeForever: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Tone.yes)
                Text("Free, forever")
                    .scaledFont(Type.body, weight: .semibold)
                    .foregroundStyle(Tone.yes)
            }
            Text("The first recipes, the adaptation engine, and the product scanner. We never sell the answer to \"can my child eat this\".")
                .scaledFont(Type.secondary)
                .foregroundStyle(Tone.textSecondary)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tone.yesWash, in: RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous)
            .strokeBorder(Tone.yes.opacity(0.3), lineWidth: 1))
    }
}

private struct Perk: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "plus")
                .scaledFont(Type.secondary, weight: .bold)
                .foregroundStyle(Tone.brand)
                .frame(width: 19)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .scaledFont(Type.body, weight: .semibold)
                    .foregroundStyle(Tone.text)
                Text(detail)
                    .scaledFont(Type.secondary)
                    .foregroundStyle(Tone.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
    }
}
