// The engine now rewrites the steps, and this screen is where that fix pays
// off — because here the step is the only thing on the screen.
// CookingMode.swift

import SwiftUI

struct CookingMode: View {
    let recipe: Recipe
    let result: AdaptedRecipe
    let firstName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @State private var step = 0
    @State private var secondsLeft: Int?
    @State private var running = false
    @State private var askingForRating = false
    @State private var showIngredients = false

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var steps: [String] { result.steps.isEmpty ? recipe.steps : result.steps }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            progress
            stepLabel
            stepText
            stepPhoto
            swapReminder
            Spacer(minLength: 16)
            timerCard
            ingredientsButton
                .frame(maxWidth: .infinity)
            controls
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .background(Tone.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        /* Tasty does this and it is one line: the screen must not dim while
         * someone is following a step with their hands full. Scoped to this
         * screen only — an app that never sleeps drains a battery. */
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onReceive(tick) { _ in advanceTimer() }
        .sheet(isPresented: $showIngredients) {
            IngredientsSheet(ingredients: result.ingredients)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $askingForRating, onDismiss: { dismiss() }) {
            HowWasIt(recipe: recipe, firstName: app.activeProfile.firstName)
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Pieces

    private var progress: some View {
        HStack(spacing: 5) {
            ForEach(0..<steps.count, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Tone.brand : Tone.text.opacity(0.13))
                    .frame(height: 4)
            }
        }
        .animation(.soft(0.25), value: step)
    }

    private var stepLabel: some View {
        Text(String(format: String(localized: "Step %lld of %lld · for %@"),
                    step + 1, steps.count, firstName))
            .eyebrow(Tone.brand)
            .padding(.top, 24)
    }

    private var stepText: some View {
        Text(steps.indices.contains(step) ? steps[step] : "")
            .scaledFont(Type.display, weight: .semibold)
            .lineSpacing(5)
            .foregroundStyle(Tone.text)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 15)
            .contentTransition(.opacity)
            .id(step)
    }

    /// The verb's drawing, in place of the photo that repeated on every
    /// step. A step whose verb is in no family shows the photo instead.
    @ViewBuilder
    private var stepPhoto: some View {
        if StepVerbs.family(for: steps[step]) != nil {
            StepVerbView(step: steps[step])
                .frame(width: 220, height: 220)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
                .id(step)
                .transition(.opacity)
        } else {
            RecipeVisual(recipe: recipe, result: result)
                .frame(height: 130)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.top, 24)
        }
    }

    /// The swaps that matter for THIS step, with their ratios. Without the
    /// ratio the swap is not executable: "flax instead of egg" is useless
    /// without "15 ml plus 45 ml of water".
    @ViewBuilder
    private var swapReminder: some View {
        let relevant = swapsForCurrentStep
        if !relevant.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Text("→")
                    .scaledFont(Type.body, weight: .bold)
                    .foregroundStyle(Tone.swap)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(relevant, id: \.listID) { i in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: String(localized: "%@ replaces %@."),
                                        i.toName ?? "", i.name))
                                .scaledFont(Type.secondary, weight: .semibold)
                                .foregroundStyle(Tone.swap)
                            if let ratio = i.ratio {
                                Text(ratio)
                                    .scaledFont(Type.secondary)
                                    .foregroundStyle(Tone.text2)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(17)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [Tone.swap.opacity(0.13), Tone.swap.opacity(0.045)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Tone.swap.opacity(0.24), lineWidth: 1)
                    }
            }
            .padding(.top, 24)
        }
    }

    @ViewBuilder
    private var timerCard: some View {
        if let minutes = minutesInStep(step) {
            HStack(spacing: 15) {
                Text(clock)
                    .scaledFont(Type.display, weight: .bold, design: .monospaced)
                    .foregroundStyle(Tone.text)
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Timer")
                        .scaledFont(Type.secondary, weight: .semibold)
                        .foregroundStyle(Tone.text)
                    Text(running ? "Running" : String(format: String(localized: "%lld minutes"), minutes))
                        .scaledFont(Type.caption)
                        .foregroundStyle(Tone.text2)
                }
                Spacer(minLength: 8)
                Button {
                    if running { running = false }
                    else { secondsLeft = secondsLeft ?? minutes * 60; running = true }
                } label: {
                    Image(systemName: running ? "pause.fill" : "play.fill")
                        .scaledFont(Type.body, weight: .bold)
                        .foregroundStyle(Tone.canvas)
                        .frame(width: 42, height: 42)
                        .background(Tone.text, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .card(24)
        }
    }

    private var controls: some View {
        HStack(spacing: 11) {
            Button {
                withAnimation(.soft(0.25)) { back() }
            } label: {
                Image(systemName: step == 0 ? "xmark" : "chevron.left")
                    .scaledFont(Type.heading, weight: .semibold)
                    .foregroundStyle(Tone.text2)
                    .frame(width: 74, height: 58)
                    .background(Tone.text.opacity(0.055),
                                in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Back"))

            Button {
                withAnimation(.soft(0.25)) { forward() }
            } label: {
                Text(step == steps.count - 1 ? "Done" : "Next step")
                    .scaledFont(Type.body, weight: .semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Tone.brandGradient)
                            .overlay {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .strokeBorder(.white.opacity(0.3), lineWidth: 0.75)
                            }
                    }
                    .shadow(color: Tone.brandDeep.opacity(0.44), radius: 16, y: 10)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 15)
        .padding(.bottom, 30)
    }

    /// The list, in a sheet, without leaving the step: "how much milk was
    /// that" is asked with both hands busy.
    private var ingredientsButton: some View {
        Button { showIngredients = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "list.bullet")
                Text("Ingredients")
            }
            .scaledFont(Type.caption, weight: .semibold)
            .foregroundStyle(Tone.text2)
            .frame(height: Layout.tapTarget)
            .padding(.horizontal, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Logic

    /// Only the swaps whose replacement is actually named in this step. A list
    /// of every swap on every screen is noise; the one on screen is not.
    private var swapsForCurrentStep: [AdaptedIngredient] {
        guard steps.indices.contains(step) else { return [] }
        let t = steps[step].lowercased()
        return result.ingredients.filter { i in
            i.status == .swapped && (i.toName.map { t.contains($0.lowercased()) } ?? false)
        }
    }

    /// A duration written into the step, so the timer offers what the recipe
    /// actually asks for rather than a guess.
    private func minutesInStep(_ i: Int) -> Int? {
        guard steps.indices.contains(i) else { return nil }
        let t = steps[i]
        guard let m = t.range(of: #"(\d+)\s*(?:to\s*\d+\s*)?min"#,
                              options: .regularExpression) else { return nil }
        let digits = t[m].prefix { $0.isNumber }
        return Int(digits)
    }

    private var clock: String {
        let s = secondsLeft ?? (minutesInStep(step).map { $0 * 60 } ?? 0)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func advanceTimer() {
        guard running, let s = secondsLeft, s > 0 else { return }
        secondsLeft = s - 1
        if secondsLeft == 0 { running = false }
    }

    private func forward() {
        if step < steps.count - 1 {
            step += 1
            secondsLeft = nil
            running = false
        } else {
            /* The moment to ask: the "cooked" mark is set here whatever they
             * answer, so the week keeps a trace without asking for one. */
            app.markCooked(recipe.id)
            askingForRating = true
        }
    }

    private func back() {
        if step > 0 {
            step -= 1
            secondsLeft = nil
            running = false
        } else {
            dismiss()
        }
    }
}

/// One second, three stars, a skip: nothing else: the parent has just finished
/// cooking and is about to eat.
private struct HowWasIt: View {
    let recipe: Recipe
    let firstName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("How was it?")
                .scaledFont(Type.title, weight: .bold)
                .foregroundStyle(Tone.text)
                .padding(.top, 30)
            Text(firstName.isEmpty ? recipe.name
                 : String(format: String(localized: "%@, for %@"), recipe.name, firstName))
                .scaledFont(Type.caption)
                .foregroundStyle(Tone.text2)
                .padding(.top, 5)

            RatingBlock(recipe: recipe)
                .padding(.top, 22)
                .padding(.horizontal, Layout.gutter)

            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .scaledFont(Type.micro, weight: .bold)
                Text("Cooked")
                    .scaledFont(Type.label, weight: .semibold)
            }
            .foregroundStyle(Tone.yes)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Tone.yes.opacity(0.08), in: Capsule())
            .padding(.top, 20)

            Button { dismiss() } label: {
                Text("Skip")
                    .scaledFont(Type.secondary)
                    .foregroundStyle(Tone.text3)
                    .frame(height: Layout.tapTarget)
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(Tone.canvas.ignoresSafeArea())
    }
}

/// The adapted ingredients, read-only, for a glance mid-step.
private struct IngredientsSheet: View {
    let ingredients: [AdaptedIngredient]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Ingredients").eyebrow().padding(.bottom, 10)
                ForEach(ingredients.filter { $0.status != .omitted }) { i in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(i.qty.display + (i.unit.isEmpty ? "" : " " + i.unit))
                            .scaledFont(Type.caption, weight: .regular, design: .monospaced)
                            .foregroundStyle(Tone.text2)
                            .frame(width: 66, alignment: .leading)
                        Text(i.status == .swapped ? (i.toName ?? i.name) : i.name)
                            .scaledFont(Type.body)
                            .foregroundStyle(Tone.text)
                        if i.status == .swapped {
                            Text(String(format: String(localized: "replaces %@"), i.name))
                                .scaledFont(Type.micro, weight: .semibold)
                                .foregroundStyle(Tone.swap)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)
                    Divider().overlay(Tone.hairline)
                }
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.top, 26)
            .padding(.bottom, 30)
        }
        .background(Tone.canvas.ignoresSafeArea())
    }
}
