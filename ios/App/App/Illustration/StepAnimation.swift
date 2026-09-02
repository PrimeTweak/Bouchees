//  StepAnimation.swift
//  A small animated drawing per cooking verb. Twenty-one definitions as
//  data, one renderer, and a table that maps a step's first verb to one.

import SwiftUI

// MARK: - The verb table

/// Reads data/step-verbs.json: family -> verbs. A step plays the family of
/// the first verb it opens with; a verb in no family plays nothing.
enum StepVerbs {
    private static let table: [String: String] = {
        guard let d = try? Resources.data("step-verbs", "json"),
              let raw = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        var out: [String: String] = [:]
        for (family, verbs) in raw where !family.hasPrefix("_") {
            for v in (verbs as? [String]) ?? [] { out[v.lowercased()] = family }
        }
        return out
    }()

    /// The family of a step, from its first six words: "In a large bowl,
    /// whisk" opens on the bowl.
    static func family(for step: String) -> String? {
        let words = step.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .prefix(6)
        for w in words { if let f = table[String(w)] { return f } }
        return nil
    }
}

// MARK: - The drawing model

/// How a part moves. Every motion loops on its period, in seconds.
enum StepMotion {
    case none
    case swing(center: CGPoint, degrees: Double, period: Double)
    case spin(center: CGPoint, period: Double)
    case shuttle(dx: CGFloat, dy: CGFloat, period: Double)
    case pulse(period: Double)
    case flip(center: CGPoint, height: CGFloat, period: Double)
    case rise(height: CGFloat, period: Double, delay: Double)
    case draw(period: Double)
    case tilt(center: CGPoint, degrees: Double, period: Double)
}

enum StepShape {
    case rect(CGRect, corner: CGFloat)
    case circle(CGPoint, CGFloat)
    case ellipse(CGRect)
    case stroke(Path, width: CGFloat)
    case fill(Path)
}

struct StepPart {
    let shape: StepShape
    let color: Color
    var motion: StepMotion = .none
}

struct StepAnimation {
    let parts: [StepPart]
}

// MARK: - The renderer

/// Draws a StepAnimation in a 64-point box, animated on a timeline. Under
/// Reduce Motion the first frame stands still.
struct StepAnimationView: View {
    let animation: StepAnimation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let s = min(size.width, size.height) / 64
                gc.translateBy(x: (size.width - 64 * s) / 2, y: (size.height - 64 * s) / 2)
                gc.scaleBy(x: s, y: s)
                for part in animation.parts { draw(part, at: t, in: &gc) }
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(_ part: StepPart, at t: Double, in gc: inout GraphicsContext) {
        var g = gc
        var alpha = 1.0
        var drawFraction = 1.0
        switch part.motion {
        case .none: break
        case .swing(let c, let deg, let p):
            let a = Foundation.sin(t / p * 2 * .pi) * deg
            g.translateBy(x: c.x, y: c.y); g.rotate(by: .degrees(a)); g.translateBy(x: -c.x, y: -c.y)
        case .spin(let c, let p):
            let a = (t / p).truncatingRemainder(dividingBy: 1) * 360
            g.translateBy(x: c.x, y: c.y); g.rotate(by: .degrees(a)); g.translateBy(x: -c.x, y: -c.y)
        case .shuttle(let dx, let dy, let p):
            let f = Foundation.sin(t / p * 2 * .pi)
            g.translateBy(x: dx * f, y: dy * f)
        case .pulse(let p):
            alpha = 0.35 + 0.65 * (0.5 + 0.5 * Foundation.sin(t / p * 2 * .pi))
        case .flip(let c, let h, let p):
            let f = (t / p).truncatingRemainder(dividingBy: 1)
            let up = f < 0.2 || f > 0.8 ? 0 : Foundation.sin((f - 0.2) / 0.6 * .pi)
            let a = f < 0.2 || f > 0.8 ? 0 : (f - 0.2) / 0.6 * 360
            g.translateBy(x: c.x, y: c.y - h * up); g.rotate(by: .degrees(a)); g.translateBy(x: -c.x, y: -c.y)
        case .rise(let h, let p, let delay):
            let f = ((t + delay) / p).truncatingRemainder(dividingBy: 1)
            g.translateBy(x: 0, y: -h * f); alpha = 0.9 * (1 - f)
        case .draw(let p):
            drawFraction = (t / p).truncatingRemainder(dividingBy: 1)
        case .tilt(let c, let deg, let p):
            let f = (t / p).truncatingRemainder(dividingBy: 1)
            let a = f < 0.3 ? f / 0.3 : f > 0.7 ? (1 - f) / 0.3 : 1
            g.translateBy(x: c.x, y: c.y); g.rotate(by: .degrees(-deg * a)); g.translateBy(x: -c.x, y: -c.y)
        }
        g.opacity = alpha
        switch part.shape {
        case .rect(let r, let corner):
            g.fill(Path(roundedRect: r, cornerRadius: corner), with: .color(part.color))
        case .circle(let c, let r):
            g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(part.color))
        case .ellipse(let r):
            g.fill(Path(ellipseIn: r), with: .color(part.color))
        case .stroke(let p, let w):
            let path = drawFraction < 1 ? p.trimmedPath(from: 0, to: drawFraction) : p
            g.stroke(path, with: .color(part.color), style: StrokeStyle(lineWidth: w, lineCap: .round))
        case .fill(let p):
            g.fill(p, with: .color(part.color))
        }
    }
}

// MARK: - The bank

/// Twenty-one drawings in a 64 × 64 box, one per family in the verb table.
enum StepBank {
    private static let ink = Tone.text2
    private static let board = Color(red: 0.85, green: 0.79, blue: 0.66)
    private static let pale = Color(red: 0.91, green: 0.85, blue: 0.74)
    private static let brand = Tone.brand
    private static let amber = Tone.swap
    private static let orange = Color(red: 0.91, green: 0.53, blue: 0.17)
    private static let dark = Color(red: 0.16, green: 0.15, blue: 0.13)

    static func animation(for family: String) -> StepAnimation? { all[family] }

    private static func arc(_ points: [(CGFloat, CGFloat)], control: [(CGFloat, CGFloat)] = []) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: CGPoint(x: first.0, y: first.1))
        if control.count == points.count - 1 {
            for (i, pt) in points.dropFirst().enumerated() {
                p.addQuadCurve(to: CGPoint(x: pt.0, y: pt.1), control: CGPoint(x: control[i].0, y: control[i].1))
            }
        } else {
            for pt in points.dropFirst() { p.addLine(to: CGPoint(x: pt.0, y: pt.1)) }
        }
        return p
    }

    private static let all: [String: StepAnimation] = [
        "chop": StepAnimation(parts: [
            StepPart(shape: .rect(CGRect(x: 10, y: 44, width: 44, height: 6), corner: 2), color: board),
            StepPart(shape: .circle(CGPoint(x: 20, y: 41), 3), color: orange),
            StepPart(shape: .circle(CGPoint(x: 28, y: 41), 3), color: orange),
            StepPart(shape: .rect(CGRect(x: 20, y: 30, width: 30, height: 8), corner: 3), color: ink,
                     motion: .swing(center: CGPoint(x: 46, y: 40), degrees: 12, period: 0.5)),
            StepPart(shape: .rect(CGRect(x: 44, y: 26, width: 10, height: 16), corner: 3), color: brand,
                     motion: .swing(center: CGPoint(x: 46, y: 40), degrees: 12, period: 0.5))
        ]),
        "stir": StepAnimation(parts: [
            StepPart(shape: .ellipse(CGRect(x: 10, y: 33, width: 44, height: 18)), color: board),
            StepPart(shape: .ellipse(CGRect(x: 14, y: 34, width: 36, height: 12)), color: pale),
            StepPart(shape: .rect(CGRect(x: 30, y: 18, width: 4, height: 24), corner: 2), color: ink,
                     motion: .spin(center: CGPoint(x: 32, y: 40), period: 1.6)),
            StepPart(shape: .ellipse(CGRect(x: 27, y: 39, width: 10, height: 6)), color: ink,
                     motion: .spin(center: CGPoint(x: 32, y: 40), period: 1.6))
        ]),
        "whisk": StepAnimation(parts: [
            StepPart(shape: .ellipse(CGRect(x: 12, y: 39, width: 40, height: 14)), color: board),
            StepPart(shape: .rect(CGRect(x: 30, y: 10, width: 4, height: 18), corner: 2), color: ink,
                     motion: .swing(center: CGPoint(x: 32, y: 22), degrees: 8, period: 0.45)),
            StepPart(shape: .stroke(arc([(24, 28), (40, 28)], control: [(32, 44)]), width: 2.5), color: ink,
                     motion: .swing(center: CGPoint(x: 32, y: 22), degrees: 8, period: 0.45)),
            StepPart(shape: .stroke(arc([(27, 28), (37, 28)], control: [(32, 42)]), width: 2.5), color: ink,
                     motion: .swing(center: CGPoint(x: 32, y: 22), degrees: 8, period: 0.45))
        ]),
        "pour": StepAnimation(parts: [
            StepPart(shape: .rect(CGRect(x: 26, y: 44, width: 24, height: 10), corner: 3), color: pale),
            StepPart(shape: .rect(CGRect(x: 12, y: 34, width: 20, height: 8), corner: 2), color: ink,
                     motion: .tilt(center: CGPoint(x: 32, y: 40), degrees: 38, period: 2.4)),
            StepPart(shape: .rect(CGRect(x: 31, y: 40, width: 3, height: 10), corner: 1), color: amber,
                     motion: .pulse(period: 2.4))
        ]),
        "bake": StepAnimation(parts: [
            StepPart(shape: .rect(CGRect(x: 10, y: 14, width: 44, height: 38), corner: 5), color: ink),
            StepPart(shape: .rect(CGRect(x: 16, y: 24, width: 32, height: 22), corner: 3), color: dark),
            StepPart(shape: .rect(CGRect(x: 18, y: 26, width: 28, height: 18), corner: 2), color: orange,
                     motion: .pulse(period: 1.8)),
            StepPart(shape: .circle(CGPoint(x: 20, y: 19), 2), color: pale),
            StepPart(shape: .circle(CGPoint(x: 28, y: 19), 2), color: pale)
        ]),
        "blend": StepAnimation(parts: [
            StepPart(shape: .rect(CGRect(x: 20, y: 14, width: 24, height: 30), corner: 4), color: pale),
            StepPart(shape: .rect(CGRect(x: 22, y: 30, width: 20, height: 4), corner: 2), color: ink,
                     motion: .spin(center: CGPoint(x: 32, y: 32), period: 0.7)),
            StepPart(shape: .rect(CGRect(x: 30, y: 22, width: 4, height: 20), corner: 2), color: ink,
                     motion: .spin(center: CGPoint(x: 32, y: 32), period: 0.7)),
            StepPart(shape: .rect(CGRect(x: 18, y: 44, width: 28, height: 8), corner: 3), color: ink)
        ]),
        "grate": StepAnimation(parts: [
            StepPart(shape: .rect(CGRect(x: 24, y: 14, width: 18, height: 38), corner: 4), color: Color(white: 0.55)),
            StepPart(shape: .circle(CGPoint(x: 30, y: 22), 1.5), color: ink),
            StepPart(shape: .circle(CGPoint(x: 36, y: 30), 1.5), color: ink),
            StepPart(shape: .circle(CGPoint(x: 30, y: 38), 1.5), color: ink),
            StepPart(shape: .circle(CGPoint(x: 36, y: 46), 1.5), color: ink),
            StepPart(shape: .circle(CGPoint(x: 18, y: 32), 8), color: orange,
                     motion: .shuttle(dx: 0, dy: 10, period: 0.6))
        ]),
        "peel": StepAnimation(parts: [
            StepPart(shape: .ellipse(CGRect(x: 18, y: 18, width: 28, height: 32)), color: orange),
            StepPart(shape: .stroke(arc([(20, 24), (44, 24), (42, 46)], control: [(32, 12), (50, 36)]), width: 4), color: Tone.canvas,
                     motion: .draw(period: 1.8))
        ]),
        "fold": StepAnimation(parts: [
            StepPart(shape: .ellipse(CGRect(x: 12, y: 39, width: 40, height: 14)), color: board),
            StepPart(shape: .fill(arc([(22, 40), (42, 40)], control: [(32, 28)])), color: pale,
                     motion: .swing(center: CGPoint(x: 32, y: 40), degrees: 25, period: 1.4)),
            StepPart(shape: .rect(CGRect(x: 30, y: 14, width: 4, height: 22), corner: 2), color: ink,
                     motion: .swing(center: CGPoint(x: 32, y: 36), degrees: 25, period: 1.4))
        ]),
        "roll": StepAnimation(parts: [
            StepPart(shape: .rect(CGRect(x: 10, y: 44, width: 44, height: 6), corner: 2), color: board),
            StepPart(shape: .circle(CGPoint(x: 32, y: 34), 10), color: board,
                     motion: .shuttle(dx: 14, dy: 0, period: 2.4)),
            StepPart(shape: .circle(CGPoint(x: 29, y: 31), 2), color: amber,
                     motion: .shuttle(dx: 14, dy: 0, period: 2.4))
        ]),
        "flip": StepAnimation(parts: [
            StepPart(shape: .ellipse(CGRect(x: 10, y: 42, width: 44, height: 12)), color: dark),
            StepPart(shape: .ellipse(CGRect(x: 18, y: 37, width: 28, height: 10)), color: Color(red: 0.91, green: 0.73, blue: 0.42),
                     motion: .flip(center: CGPoint(x: 32, y: 42), height: 22, period: 1.8))
        ]),
        "simmer": StepAnimation(parts: [
            StepPart(shape: .rect(CGRect(x: 16, y: 34, width: 32, height: 18), corner: 4), color: ink),
            StepPart(shape: .stroke(arc([(24, 30), (24, 18)], control: [(28, 24)]), width: 2.5), color: Color(white: 0.65),
                     motion: .rise(height: 14, period: 1.6, delay: 0)),
            StepPart(shape: .stroke(arc([(32, 30), (32, 18)], control: [(36, 24)]), width: 2.5), color: Color(white: 0.65),
                     motion: .rise(height: 14, period: 1.6, delay: 0.5)),
            StepPart(shape: .stroke(arc([(40, 30), (40, 18)], control: [(44, 24)]), width: 2.5), color: Color(white: 0.65),
                     motion: .rise(height: 14, period: 1.6, delay: 1.0))
        ]),
        "rest": StepAnimation(parts: [
            StepPart(shape: .stroke(Path(ellipseIn: CGRect(x: 16, y: 18, width: 32, height: 32)), width: 4), color: Tone.hairline),
            StepPart(shape: .stroke(Path(ellipseIn: CGRect(x: 16, y: 18, width: 32, height: 32)), width: 4), color: Tone.yes,
                     motion: .draw(period: 3)),
            StepPart(shape: .rect(CGRect(x: 30, y: 12, width: 4, height: 6), corner: 1), color: ink)
        ]),
        "pan": StepAnimation(parts: [
            StepPart(shape: .ellipse(CGRect(x: 8, y: 34, width: 40, height: 14)), color: dark),
            StepPart(shape: .rect(CGRect(x: 46, y: 38, width: 12, height: 4), corner: 2), color: ink),
            StepPart(shape: .circle(CGPoint(x: 22, y: 39), 3), color: pale, motion: .shuttle(dx: 0, dy: 2, period: 0.9)),
            StepPart(shape: .circle(CGPoint(x: 32, y: 40), 3), color: pale, motion: .shuttle(dx: 0, dy: 2, period: 0.7)),
            StepPart(shape: .stroke(arc([(28, 30), (28, 20)], control: [(32, 25)]), width: 2), color: Color(white: 0.65),
                     motion: .rise(height: 10, period: 1.4, delay: 0.3))
        ]),
        "serve": StepAnimation(parts: [
            StepPart(shape: .ellipse(CGRect(x: 10, y: 36, width: 44, height: 16)), color: board),
            StepPart(shape: .ellipse(CGRect(x: 16, y: 36, width: 32, height: 10)), color: pale),
            StepPart(shape: .rect(CGRect(x: 40, y: 12, width: 4, height: 26), corner: 2), color: ink,
                     motion: .swing(center: CGPoint(x: 42, y: 38), degrees: 14, period: 1.6)),
            StepPart(shape: .ellipse(CGRect(x: 36, y: 8, width: 12, height: 8)), color: ink,
                     motion: .swing(center: CGPoint(x: 42, y: 38), degrees: 14, period: 1.6))
        ]),
        "store": StepAnimation(parts: [
            StepPart(shape: .rect(CGRect(x: 14, y: 28, width: 36, height: 24), corner: 4), color: pale),
            StepPart(shape: .rect(CGRect(x: 12, y: 22, width: 40, height: 8), corner: 3), color: ink,
                     motion: .shuttle(dx: 0, dy: 3, period: 1.6)),
            StepPart(shape: .circle(CGPoint(x: 26, y: 42), 4), color: amber),
            StepPart(shape: .circle(CGPoint(x: 38, y: 42), 4), color: amber)
        ]),
        "spread": StepAnimation(parts: [
            StepPart(shape: .rect(CGRect(x: 10, y: 40, width: 44, height: 10), corner: 3), color: board),
            StepPart(shape: .rect(CGRect(x: 14, y: 36, width: 36, height: 5), corner: 2), color: amber),
            StepPart(shape: .rect(CGRect(x: 28, y: 14, width: 8, height: 22), corner: 3), color: ink,
                     motion: .shuttle(dx: 14, dy: 0, period: 1.6))
        ]),
        "drain": StepAnimation(parts: [
            StepPart(shape: .ellipse(CGRect(x: 14, y: 22, width: 36, height: 14)), color: Color(white: 0.55)),
            StepPart(shape: .rect(CGRect(x: 30, y: 12, width: 4, height: 12), corner: 2), color: ink),
            StepPart(shape: .circle(CGPoint(x: 24, y: 40), 2), color: amber, motion: .rise(height: -12, period: 1.2, delay: 0)),
            StepPart(shape: .circle(CGPoint(x: 32, y: 40), 2), color: amber, motion: .rise(height: -12, period: 1.2, delay: 0.4)),
            StepPart(shape: .circle(CGPoint(x: 40, y: 40), 2), color: amber, motion: .rise(height: -12, period: 1.2, delay: 0.8))
        ]),
        "mash": StepAnimation(parts: [
            StepPart(shape: .ellipse(CGRect(x: 12, y: 40, width: 40, height: 14)), color: board),
            StepPart(shape: .ellipse(CGRect(x: 18, y: 38, width: 28, height: 10)), color: orange),
            StepPart(shape: .rect(CGRect(x: 30, y: 10, width: 4, height: 24), corner: 2), color: ink,
                     motion: .shuttle(dx: 0, dy: 5, period: 0.7)),
            StepPart(shape: .rect(CGRect(x: 22, y: 32, width: 20, height: 5), corner: 2), color: ink,
                     motion: .shuttle(dx: 0, dy: 5, period: 0.7))
        ]),
        "check": StepAnimation(parts: [
            StepPart(shape: .ellipse(CGRect(x: 14, y: 36, width: 36, height: 14)), color: board),
            StepPart(shape: .rect(CGRect(x: 40, y: 14, width: 4, height: 26), corner: 2), color: ink,
                     motion: .swing(center: CGPoint(x: 42, y: 40), degrees: 18, period: 2)),
            StepPart(shape: .ellipse(CGRect(x: 36, y: 10, width: 12, height: 8)), color: ink,
                     motion: .swing(center: CGPoint(x: 42, y: 40), degrees: 18, period: 2)),
            StepPart(shape: .circle(CGPoint(x: 42, y: 14), 2), color: orange,
                     motion: .swing(center: CGPoint(x: 42, y: 40), degrees: 18, period: 2))
        ]),
        "cover": StepAnimation(parts: [
            StepPart(shape: .rect(CGRect(x: 16, y: 34, width: 32, height: 18), corner: 4), color: ink),
            StepPart(shape: .ellipse(CGRect(x: 14, y: 28, width: 36, height: 10)), color: Color(white: 0.55),
                     motion: .shuttle(dx: 0, dy: -8, period: 2.2)),
            StepPart(shape: .rect(CGRect(x: 30, y: 22, width: 4, height: 6), corner: 1), color: ink,
                     motion: .shuttle(dx: 0, dy: -8, period: 2.2))
        ])
    ]
}

/// The animation for a step, or nothing when its verb is in no family.
struct StepVerbView: View {
    let step: String

    var body: some View {
        if let family = StepVerbs.family(for: step),
           let animation = StepBank.animation(for: family) {
            StepAnimationView(animation: animation)
        }
    }
}
