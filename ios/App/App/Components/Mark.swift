//  Mark.swift
//
//  The Bouchées mark, drawn rather than shipped as an image.
//
//  A lowercase b whose bowl has a bite taken out of it. "Bouchée" means a
//  mouthful — the name carries its own shape, which is why this beats the
//  spoon-and-checkmark I proposed first: that one was clever, this one is
//  simply true.
//
//  Drawn as a Shape so it takes the theme colour at any size with no asset,
//  no @2x/@3x, and no drift between light and dark.
//
//  Geometry matches ios/icon-source exactly, in a 100x100 space:
//      stem   (33,26) to (33,72), 8.5 wide, round caps
//      bowl   centre (52,55), radius 17.5
//      bite   centre (63,45), radius 7.5, punched out

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

/// Mark plus name. Used on the launch screen and at the top of onboarding —
/// and nowhere else. An app does not need to remind someone of its name
/// straight after they opened it.
struct BoucheesLockup: View {
    var size: CGFloat = 34

    var body: some View {
        HStack(spacing: size * 0.35) {
            BoucheesMark(size: size)
            Text("Bouchées")
                .font(.system(size: size * 0.74, weight: .bold))
                .foregroundStyle(Tone.text)
                .kerning(-size * 0.02)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Bouchées")
    }
}

/// What shows while the engine loads its tables. It replaces a white flash
/// with the app's own colour, and it follows the theme.
/// THE LAUNCH SCREEN.
///
/// It follows the system's own launch image, which now carries the SAME
/// colour — before, the system painted one cream and the app repainted
/// another at the next frame, which read as a flicker.
///
/// The animation says the name: the mark settles, then the bite lands. One
/// gesture, and it is the word "bouchée".
///
/// Nothing appears before 400 ms. On a warm launch the app is already ready,
/// and a status line that flashes makes the start feel slower than it is.
struct LaunchView: View {
    @State private var settled = false
    @State private var bitten = false
    @State private var named = false
    @State private var slow = false

    var body: some View {
        ZStack {
            Tone.canvas.ignoresSafeArea()

            VStack(spacing: 14) {
                BoucheesMark(size: 64, bite: bitten ? 1 : 0)
                    .scaleEffect(settled ? 1 : 0.82)
                    .opacity(settled ? 1 : 0)

                /* The product name, the one French word the app keeps. */
                Text(verbatim: "Bouchées")
                    .font(.system(size: 21, weight: .bold))
                    .kerning(-0.6)
                    .foregroundStyle(Tone.text)
                    .offset(y: named ? 0 : 7)
                    .opacity(named ? 1 : 0)
            }

            VStack {
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    Text("Getting this week ready")
                        .font(.system(size: 12))
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
        withAnimation(.smooth(duration: 0.3)) { named = true }

        try? await Task.sleep(for: .milliseconds(140))
        withAnimation(.easeOut(duration: 0.35)) { slow = true }
    }
}

/// Three dots that step forward with the real stages, not a spinner.
///
/// A spinner claims motion it does not have. These advance when something
/// actually finished: tables decoded, engine ready, recipes in.
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
            withAnimation(.smooth(duration: 0.2)) {
                lit = lit >= 3 ? 1 : lit + 1
            }
        }
    }
}
