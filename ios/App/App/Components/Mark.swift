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

            // the bite
            var bite = Path()
            bite.addEllipse(in: CGRect(x: 55.5 * u, y: 37.5 * u,
                                       width: 15 * u, height: 15 * u))
            context.fill(bite, with: .color(behind))
        }
        .frame(width: size, height: size)
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
struct LaunchView: View {
    var body: some View {
        ZStack {
            Tone.canvas.ignoresSafeArea()
            BoucheesMark(size: 68)
        }
    }
}
