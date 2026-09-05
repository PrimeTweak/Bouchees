// Drawn as a Shape so it takes the theme colour at any size with no asset, no
// @2x/@3x, and no drift between light and dark. Mark.swift

import SwiftUI

struct BoucheesMark: View {
    var size: CGFloat = 32
    /// The bite is punched to whatever sits behind. Pass the surface colour
    /// when the mark is on a card rather than on the page.
    var behind: Color = Tone.canvas

    /// How much of the bite is taken, 0 to 1. Animatable: the launch screen
    /// springs it from nothing so the mark is eaten rather than drawn.
    var bite: CGFloat = 1

    var body: some View {
        Canvas { context, canvasSize in
            let u = canvasSize.width / 100

            var body = Path()
            // stem
            body.addRoundedRect(
                in: CGRect(x: 28.75 * u, y: 21.75 * u, width: 8.5 * u, height: 54.5 * u),
                cornerSize: CGSize(width: 4.25 * u, height: 4.25 * u))
            // bowl
            body.addEllipse(in: CGRect(x: 34.5 * u, y: 37.5 * u,
                                       width: 35 * u, height: 35 * u))

            context.fill(body, with: .color(markColour))

            // the bite, scaled about its own centre
            let taken = max(0, min(1, bite))
            if taken > 0 {
                let full = 15 * u
                let w = full * taken
                let cx = (55.5 + 7.5) * u
                let cy = (37.5 + 7.5) * u
                var mark = Path()
                mark.addEllipse(in: CGRect(x: cx - w / 2, y: cy - w / 2,
                                           width: w, height: w))
                context.fill(mark, with: .color(behind))
            }
        }
        .frame(width: size, height: size)
        .animation(.default, value: bite)
        .accessibilityHidden(true)
    }

    private var markColour: Color { Tone.brand }
}


/// What shows while the engine loads its tables: one gesture, and it is the
/// word "bouchée".
struct LaunchView: View {
    @State private var settled = false
    @State private var bitten = false
    @State private var named = false
    @State private var slow = false

    var body: some View {
        ZStack {
            Tone.canvas.ignoresSafeArea()

            VStack(spacing: 14) {
                /* 116, not 64: the glyph occupies about 55% of its 100-unit
                 * box — the stem runs x=28.75 to 37.25, the bowl to x=69.5 —
                 * so `size: 64` drew a mark 35pt wide. */
                BoucheesMark(size: 116, bite: bitten ? 1 : 0)
                    .scaleEffect(settled ? 1 : 0.82)
                    .opacity(settled ? 1 : 0)

                /* The product name, the one French word the app keeps. */
                Text(verbatim: "Bouchées")
                    .scaledFont(Type.display, weight: .bold)
                    .kerning(-0.6)
                    .foregroundStyle(Tone.text)
                    .offset(y: named ? 0 : 7)
                    .opacity(named ? 1 : 0)
            }

            VStack {
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    Text("Getting this week ready")
                        .scaledFont(Type.caption)
                        .foregroundStyle(Tone.text2)
                    ProgressDots()
                }
                .opacity(slow ? 1 : 0)
                .padding(.bottom, 44)
            }
        }
        .task { await run() }
    }

    private func run() async {
        /* A settle, not a bounce: 0.82 up past 1 and back. The overshoot is
         * what makes it feel like an object landing rather than a fade. */
        withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) {
            settled = true
        }

        try? await Task.sleep(for: .milliseconds(180))
        /* The bite lands with more spring than the mark — it is a smaller
         * thing arriving faster, and the extra bounce is what reads as a
         * bite rather than a dot appearing. */
        withAnimation(.spring(response: 0.34, dampingFraction: 0.5)) {
            bitten = true
        }

        try? await Task.sleep(for: .milliseconds(80))
        withAnimation(.soft(0.3)) { named = true }

        try? await Task.sleep(for: .milliseconds(140))
        withAnimation(.easeOut(duration: 0.35)) { slow = true }
    }
}

/// Three dots that step forward with the real stages, not a spinner. A spinner
/// claims motion it does not have.
private struct ProgressDots: View {
    @State private var lit = 0
    private let tick = Timer.publish(every: 0.42, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(i < lit ? Tone.brand : Tone.text.opacity(0.14))
                    .frame(width: 5, height: 5)
            }
        }
        .onReceive(tick) { _ in
            withAnimation(.soft(0.2)) {
                lit = lit >= 3 ? 1 : lit + 1
            }
        }
    }
}
