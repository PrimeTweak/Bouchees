//  Onboarding.swift
//
//  DEMO FIRST, FORM SECOND.
//
//  The old flow asked four times before giving once: a trust screen to read, a
//  name to type, an age to pick, eleven allergens to tap — and only then did a
//  recipe appear. Every one of those steps is a place to close the app, and
//  none of them had yet shown that the thing works.
//
//  The engine adapts a recipe in under a millisecond, offline, with no account.
//  That demonstration was hidden behind a form. Now it IS the first screen: tap
//  an allergen and watch a real recipe rewrite itself.
//
//  The counter is the whole pitch. Two allergens tapped and it still reads 38.
//  A parent expects a shortened list; watching it hold is the moment they
//  believe you.

import SwiftUI

struct OnboardingFlow: View {
    @Environment(AppState.self) private var etat

    @State private var step = 0
    @State private var draft = ChildProfile.defaut
    @State private var name = ""

    var body: some View {
        ZStack {
            Tone.canvas.ignoresSafeArea()

            switch step {
            case 0: LiveDemoStep(draft: $draft, next: { step = 1 })
            case 1: WhoStep(draft: $draft, name: $name, next: { step = 2 })
            default: OfferStep(draft: draft, finish: finish)
            }
        }
        .animation(.smooth(duration: 0.28), value: step)
    }

    private func finish() {
        draft.name = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? String(localized: "My child") : name
        etat.save(draft)
    }
}

// MARK: - Step 1 — the demo

/// A real recipe, on screen, before anything is asked. No account, no name, no
/// typing. The engine is local and instant, so this costs nothing to show — and
/// it is the entire pitch.
private struct LiveDemoStep: View {
    @Environment(AppState.self) private var etat
    @Binding var draft: ChildProfile
    let next: () -> Void

    /// The recipe the demo adapts. Chosen because it carries milk, egg and
    /// wheat, so most taps produce a visible swap.
    private var demoRecipe: Recipe? {
        etat.recipes.first { $0.id == "banana-oat-muffins" } ?? etat.recipes.first
    }

    private var result: AdaptedRecipe? {
        guard let r = demoRecipe else { return nil }
        return etat.adaptPreview(r, for: draft)
    }

    private var tally: AppState.ProfileTally { etat.tally(for: draft) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BoucheesMark(size: 34)
                    .padding(.bottom, 18)

                Text("No account. No network.")
                    .font(Type.label)
                    .foregroundStyle(Tone.brand)
                    .textCase(.uppercase)
                    .kerning(1.4)

                Text("What does your child avoid?")
                    .font(Type.display)
                    .foregroundStyle(Tone.text)
                    .padding(.top, 8)

                Text("Tap one and watch.")
                    .font(Type.secondary)
                    .foregroundStyle(Tone.textSecondary)
                    .padding(.top, 8)

                if let r = demoRecipe, let res = result {
                    DemoCard(recipe: r, result: res)
                        .padding(.top, 20)
                }

                AllergenPad(selected: $draft.allergens, families: etat.knownAllergens)
                    .padding(.top, 16)

                CountLine(tally: tally)
                    .padding(.top, 16)
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.bottom, 120)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button(action: next) {
                    Text("Continue")
                        .font(Type.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: Layout.tapTarget + 6)
                }
                .buttonStyle(PrimaryButton())

                Text("Nothing leaves this device.")
                    .font(Type.caption)
                    .foregroundStyle(Tone.textTertiary)
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.bottom, 12)
            .background(.regularMaterial)
        }
    }
}

/// The card that rewrites itself. The swap carries its reason, because that is
/// what separates this from a search engine.
private struct DemoCard: View {
    let recipe: Recipe
    let result: AdaptedRecipe

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecipeVisual(recipe: recipe, result: result)
                .aspectRatio(2.1, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()

            VStack(alignment: .leading, spacing: 0) {
                Text(recipe.name)
                    .font(Type.title)
                    .foregroundStyle(Tone.text)

                ForEach(result.ingredients.filter { $0.status == .swapped }.prefix(3), id: \.listID) { i in
                    HStack(alignment: .top, spacing: 9) {
                        Text("→")
                            .font(Type.caption.weight(.bold))
                            .foregroundStyle(Tone.swap)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(i.name)
                                .font(Type.caption)
                                .strikethrough()
                                .foregroundStyle(Tone.textTertiary)
                            Text(i.toName ?? "")
                                .font(Type.secondary.weight(.semibold))
                                .foregroundStyle(Tone.text)
                            if let why = i.reason {
                                Text(why)
                                    .font(Type.caption)
                                    .foregroundStyle(Tone.textSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 11)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if result.status == .asIs {
                    HStack(spacing: 7) {
                        VerdictMark(status: .asIs)
                        Text("Nothing to change")
                            .font(Type.caption.weight(.semibold))
                            .foregroundStyle(Tone.yes)
                    }
                    .padding(.top, 11)
                }
            }
            .padding(14)
        }
        .card(24)
        .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
        .animation(.smooth(duration: 0.3), value: result.swapCount)
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
        .animation(.smooth(duration: 0.22), value: selected)
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.removeAll { $0 == id } }
        else { selected.append(id) }
    }
}

/* Its own View rather than a closure with a `let` inside a ViewBuilder. That
 * shape makes the compiler give up on the content and fall back to another
 * ForEach overload, and the error it prints names the Binding it tried, not
 * the line that actually failed. */
private struct AllergenTile: View {
    let allergen: Allergen
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 5) {
                AllergenGlyph(identifier: allergen.id, size: 20)
                Text(allergen.name)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .background {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(isOn ? AnyShapeStyle(Tone.brandGradient)
                               : AnyShapeStyle(Tone.text.opacity(0.05)))
                    .shadow(color: isOn ? Tone.brandDeep.opacity(0.4) : .clear, radius: 11, y: 6)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(isOn ? .white.opacity(0.3) : Tone.hairline, lineWidth: 1)
            }
            .foregroundStyle(isOn ? Color.white : Tone.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// The promise, in one number. It holds while allergens are added, which is the
/// thing a parent does not expect.
private struct CountLine: View {
    let tally: AppState.ProfileTally

    var body: some View {
        HStack(spacing: 13) {
            Text("\(tally.total)")
                .font(Type.figure)
                .foregroundStyle(Tone.yes)
                .contentTransition(.numericText())

            VStack(alignment: .leading, spacing: 2) {
                Text("recipes still work")
                    .font(Type.secondary.weight(.medium))
                    .foregroundStyle(Tone.text)
                Text("\(tally.asIs) with nothing to change")
                    .font(Type.caption)
                    .foregroundStyle(Tone.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .background {
            RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous)
                .fill(LinearGradient(colors: [Tone.yes.opacity(0.14), Tone.yes.opacity(0.05)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous)
                        .strokeBorder(Tone.yes.opacity(0.22), lineWidth: 1)
                }
        }
        .animation(.smooth(duration: 0.3), value: tally.total)
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
                Text("Step 2 of 2")
                    .font(Type.label)
                    .foregroundStyle(Tone.brand)
                    .textCase(.uppercase)
                    .kerning(1.4)

                Text("Who am I cooking for?")
                    .font(Type.display)
                    .foregroundStyle(Tone.text)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text("First name")
                        .font(Type.label)
                        .foregroundStyle(Tone.textTertiary)
                        .textCase(.uppercase)
                        .kerning(1.2)
                    TextField("Livia", text: $name)
                        .font(.system(size: 21, weight: .semibold))
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
                    .font(Type.label)
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
            .padding(.bottom, 140)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 9) {
                Button(action: next) {
                    Text("See the recipes")
                        .font(Type.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: Layout.tapTarget + 6)
                }
                .buttonStyle(PrimaryButton())

                Text("Not medical advice. Swaps come from versioned tables a professional should review.")
                    .font(Type.caption)
                    .foregroundStyle(Tone.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.bottom, 12)
            .background(.regularMaterial)
        }
        .onAppear { focused = true }
    }
}

/* Not Sendable, and not LocalizedStringKey.
 *
 * LocalizedStringKey is not Sendable, so declaring the struct Sendable is a
 * warning today and an error under Swift 6. Storing plain String keys and
 * resolving them at display time is simpler and survives the language mode.
 */
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
                    .font(Type.secondary.weight(.semibold))
                Text(String(localized: stage.detail))
                    .font(Type.caption)
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

// MARK: - Step 3 — the offer

/// The green box is the most important thing on this screen, and it announces
/// what is FREE. Counter-intuitive, and it is what works: showing that safety
/// is not held hostage is what makes the rest credible.
///
/// It is also true in the code — the safety tables go out to everyone, signed
/// in or not.
private struct OfferStep: View {
    @Environment(AppState.self) private var etat
    let draft: ChildProfile
    let finish: () -> Void

    private var tally: AppState.ProfileTally { etat.tally(for: draft) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("For \(draft.firstName)")
                    .font(Type.label)
                    .foregroundStyle(Tone.brand)
                    .textCase(.uppercase)
                    .kerning(1.4)

                Text("\(tally.total) today.\n7 more every week.")
                    .font(Type.display)
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
            .padding(.bottom, 190)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Button(action: finish) {
                    Text("Try 7 days free")
                        .font(Type.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: Layout.tapTarget + 6)
                }
                .buttonStyle(PrimaryButton())

                /* A visible way out RAISES conversion: it removes the sense of
                 * a trap, and it avoids the subscriber who cancels on day 8
                 * feeling tricked. */
                Button(action: finish) {
                    Text("Continue with the free recipes")
                        .font(Type.secondary)
                        .foregroundStyle(Tone.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: Layout.tapTarget)
                }
                .buttonStyle(.plain)

                Text("Then $4.99/month. Cancel any time.")
                    .font(Type.caption)
                    .foregroundStyle(Tone.textTertiary)
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.bottom, 10)
            .background(.regularMaterial)
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
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Tone.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            Text("\(points.last?.value ?? 0) recipes a year from now")
                .font(Type.caption)
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
                    .font(Type.secondary.weight(.semibold))
                    .foregroundStyle(Tone.yes)
            }
            Text("The first recipes, the adaptation engine, and the product scanner. We never sell the answer to \"can my child eat this\".")
                .font(Type.caption)
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
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Tone.brand)
                .frame(width: 19)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Type.secondary.weight(.semibold))
                    .foregroundStyle(Tone.text)
                Text(detail)
                    .font(Type.caption)
                    .foregroundStyle(Tone.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
    }
}
