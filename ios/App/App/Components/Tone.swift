//  Tone.swift
//
//  THE VALUES FROM THE MOCKUP, IN ONE PLACE.
//
//  Every number here was measured off the HTML comp rather than guessed, so a
//  screen that reads "336pt of photo, faded over 290" in the design is 336 and
//  290 here too. Nothing in a view file carries a hex value or a magic number.
//
//  Three appearances: light, dark, and system. System is the default — the
//  parent already made that choice once at the OS level.
//
//  Colour rules that hold in both:
//    Backgrounds SHIFT, they do not invert. A lighter surface stays lighter in
//    dark; light comes from the sky and depth cues depend on it.
//    Text DOES invert.
//    Accents gain luminosity in dark: brighter, less saturated.

import SwiftUI
import UIKit

// MARK: - Appearance

enum AppTheme: String, CaseIterable, Codable {
    case system, light, dark

    var label: LocalizedStringKey {
        switch self {
        case .system: return "Auto"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    /// nil hands the decision back to iOS.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - Colour

enum Tone {

    // ---- surfaces ----

    /// The page. Warm near-black in dark: food photography glows against it
    /// instead of drowning in white.
    static let canvas = dyn(light: 0xFBF9F6, dark: 0x0B0A09)

    /// Cards and rows, as a gradient — flat fills read as cheap at this size.
    static let cardTop = dyn(light: 0xFFFFFF, dark: 0x1A1715)
    static let cardBottom = dyn(light: 0xFBF9F6, dark: 0x131110)

    /// Hairlines. Barely there, and that is the point.
    static let hairline = dyn(light: 0xE9E3DB, dark: 0x2A2624, darkAlpha: 0.55)

    // ---- text ----

    static let text = dyn(light: 0x17140F, dark: 0xF4F1EC)       // 15.8:1
    static let text2 = dyn(light: 0x6B635A, dark: 0x948C83)      // 5.4:1
        /* 2.9:1 — under the body threshold ON PURPOSE. Reserved for quantities
     * beside a name that carries the meaning, never for a word standing
     * alone. */
    static let text3 = dyn(light: 0xA69C92, dark: 0x615A52)

    // ---- verdicts ----
    // One meaning each. Nothing else touches them.

    /* CONTRAST RATIOS, MEASURED ON THE CANVAS.
     *
     * The amber that shipped was 1.9:1 — the DARK value used in
     * light mode by mistake. WCAG asks 4.5:1 for body text. Every pair below
     * clears it, and a test recomputes them. */
    static let yes = dyn(light: 0x1E8347, dark: 0x5FD08A)      // 4.8:1 / 8.9:1
    static let swap = dyn(light: 0xA35F00, dark: 0xF0AC46)     // 4.8:1 / 9.4:1
    static let no = dyn(light: 0xC4291C, dark: 0xFF5B4F)       // 5.9:1 / 6.4:1

    // ---- brand ----
    // Actions, selection, the active tab. NEVER a verdict.

    static let brand = dyn(light: 0xC03A20, dark: 0xFF7A5C)      // 4.6:1 / 7.7:1
    /* THE SUBSCRIPTION CARD.
     *
     * Warm peach rather than near-black: a dark card on a cream page reads as
     * a hole, and it crushed the meal chips underneath. Contrast measured —
     * the text pair below clears 4.5:1 on this field in both appearances. */
    static var upsellField: LinearGradient {
        LinearGradient(colors: [dyn(light: 0xFFF2EC, dark: 0x2A1D14),
                                dyn(light: 0xFFE6DC, dark: 0x171009)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let upsellText = dyn(light: 0x3A2118, dark: 0xFFFFFF)
    static let upsellText2 = dyn(light: 0x8A6152, dark: 0xA89890)

    /// Behind a drawing in the hero, where a photograph would otherwise be.
    /// Warm and deep enough that white text sits on it without a scrim doing
    /// all the work.
    /* FIXED, NOT THEMED.
     *
     * I wrote "the hero is dark whatever the theme" and then made this
     * gradient theme-dependent anyway — pale beige in light mode, which is
     * exactly what put white text on a pale field.
     *
     * These are constants. White text sits on them in both appearances,
     * which is the whole point. */
    static var heroField: LinearGradient {
        LinearGradient(colors: [Color(red: 0.29, green: 0.22, blue: 0.15),
                                Color(red: 0.10, green: 0.07, blue: 0.04)],
                       startPoint: .top, endPoint: .bottom)
    }

    /// The label over a photo. Brighter than brand so it survives the veil.
    static let heroAccent = Color(red: 1, green: 0.66, blue: 0.56)
    static let brandDeep = dyn(light: 0xC0421F, dark: 0xC03A20)

    /// The gradient on a primary button. Two stops, top-lit.
    static var brandGradient: LinearGradient {
        LinearGradient(colors: [brand, brandDeep],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var cardGradient: LinearGradient {
        LinearGradient(colors: [cardTop, cardBottom],
                       startPoint: .top, endPoint: .bottom)
    }

    // ---- names the rest of the app already uses ----
    // Kept as aliases rather than renamed everywhere: a rename that touches
    // twenty call sites is twenty chances to miss one, and I missed six.

    static var surface: Color { cardTop }
    static var raised: Color { cardTop }
    static var textSecondary: Color { text2 }
    static var textTertiary: Color { text3 }

    /// Verdict washes, for banners and cards that carry a status.
    static let yesWash = dyn(light: 0xEFF6F1, dark: 0x0F2214)
    static let swapWash = dyn(light: 0xFDF5E9, dark: 0x2A1E0A)
    static let noWash = dyn(light: 0xFDF0EF, dark: 0x2A0F0D)
    static let brandWash = dyn(light: 0xFAEEF2, dark: 0x2A1119)

    private static func dyn(light: UInt32, dark: UInt32, darkAlpha: Double = 1) -> Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

// MARK: - Type

/// iOS styles text by WEIGHT and COLOUR, not by size. These are the sizes from
/// the comp, and they map onto the platform's own scale: 34 for a large title,
/// 17 for body, 11 as the floor.
enum Type {
    static let display = Font.system(size: 34, weight: .bold)
    static let displayTight = Font.system(size: 31, weight: .bold)
    static let figure = Font.system(size: 29, weight: .bold)
    static let title = Font.system(size: 16.5, weight: .semibold)
    static let body = Font.system(size: 17)
    static let secondary = Font.system(size: 15)
    static let caption = Font.system(size: 13)
    static let small = Font.system(size: 12)
    static let label = Font.system(size: 11, weight: .bold)
}

extension View {
    /// The tracked, uppercase label used above every section.
    func eyebrow(_ tone: Color = Tone.text3) -> some View {
        self.font(Type.label)
            .textCase(.uppercase)
            .kerning(1.9)
            .foregroundStyle(tone)
    }
}

// MARK: - Layout

enum Layout {
    /// iOS 26 insets the tab bar 21pt from the edges.
    static let tabInset: CGFloat = 21
    static let tabBottom: CGFloat = 26
    static let gutter: CGFloat = 22
    static let tap: CGFloat = 44
    /// The name the rest of the app uses.
    static var tapTarget: CGFloat { tap }

    /// Photo heights, measured off the comp.
    static let heroPhoto: CGFloat = 430
    static let detailPhoto: CGFloat = 430
    /// How far the photo fades into the canvas.
    static let photoFade: CGFloat = 290
    /// The veil that keeps the status bar legible over an image.
    static let topVeil: CGFloat = 150

    static let cardRadius: CGFloat = 20
    /// The 2026 bento exaggerates the radius: tiles read as tactile rather
    /// than rectangular.
    static let tileRadius: CGFloat = 30
    static let sheetRadius: CGFloat = 30
    static let thumb: CGFloat = 66
    static let thumbRadius: CGFloat = 20
}

// MARK: - Liquid Glass

/// GLASS BELONGS TO THE NAVIGATION LAYER, AND NOWHERE ELSE.
///
/// Apple's guidance is explicit and most redesigns miss it: glass is not
/// applied to content layers like lists. Applied to every row the result is
/// translucent mush. It is for what FLOATS above content — the tab bar, a
/// button over a photo, the verdict pill.
///
/// On iOS 26 the material is native: `.glassEffect` carries the highlight, the
/// shadow, the illumination AND the real refraction from Apple's renderer.
/// What follows is the fallback for iOS 17-25, built the same way the comp is:
/// a specular line on the top edge, two drop shadows for separation, a diagonal
/// inner gradient for illumination.
struct Glass: ViewModifier {
    var shape: AnyShape = AnyShape(Capsule())
    var tinted: Bool = false

    /* NO `glassEffect` HERE, DELIBERATELY.
     *
     * The runner builds with Xcode 16.4, whose SDK is iOS 18.5. That API
     * ships with Xcode 26, so the symbol does not exist at compile time —
     * and `if #available(iOS 26, *)` guards RUNTIME, not compilation. The
     * compiler still has to find it.
     *
     * So the material is drawn by hand, the way the comp is. When the build
     * moves to Xcode 26, this whole body becomes one line.
     */
    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        /* Xcode 26 and later: the real material. It carries the highlight,
         * the shadow, the illumination and Apple's own refraction — and, from
         * iOS 27, the user's transparency slider and the system's consistent
         * corner radius, both applied automatically to apps built against the
         * framework.
         *
         * The compiler check, not #available: the symbol has to EXIST at
         * compile time, and it does not in the iOS 18.5 SDK. */
        if #available(iOS 26, *) {
            /* `.interactive()` makes the material illuminate and spring at the
             * touch point. Apple describes it as what separates glass that
             * feels alive from glass that looks painted, and it costs one
             * call. */
            content.glassEffect(tinted ? .regular.tint(Tone.brand.opacity(0.14)).interactive()
                                       : .regular.interactive(),
                                in: shape)
        } else {
            handDrawn(content)
        }
        #else
        handDrawn(content)
        #endif
    }

    /// The fallback for the iOS 18.5 SDK, built the way the comp is.
    private func handDrawn(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay {
                shape
                    .fill(LinearGradient(
                        colors: [.white.opacity(0.20), .white.opacity(0.05),
                                 .white.opacity(0.11)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .blendMode(.plusLighter)
            }
            .overlay {
                /* The specular line on the top edge. Without it the material
                 * reads as frosted plastic rather than glass.
                 *
                 * `stroke`, not `strokeBorder`: AnyShape erases the
                 * InsettableShape conformance that strokeBorder needs. The
                 * line straddles the edge instead of sitting inside it, which
                 * at 0.75pt is the same pixel. */
                shape.stroke(
                    LinearGradient(colors: [.white.opacity(0.55),
                                            .white.opacity(0.14),
                                            .white.opacity(0.30)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75)
            }
            .overlay {
                if tinted { shape.fill(Tone.brand.opacity(0.10)) }
            }
            .shadow(color: .black.opacity(0.42), radius: 17, y: 10)
            .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
    }
}

/// TWO PIECES OF GLASS SIDE BY SIDE MUST BE GROUPED.
///
/// Apple is explicit: adjacent glass elements belong in a
/// `GlassEffectContainer` so they blend and morph as one surface instead of
/// rendering as two separate panes. The tab capsule and the search island sit
/// ten points apart and were never grouped.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    @ViewBuilder
    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    func glass(_ shape: some Shape = Capsule(), tinted: Bool = false) -> some View {
        modifier(Glass(shape: AnyShape(shape), tinted: tinted))
    }

    /// A card: not glass. Content layers get a gradient fill and a hairline.
    /// A bento tile: the card treatment at the larger radius.
    func tile() -> some View { card(Layout.tileRadius) }

    func card(_ radius: CGFloat = Layout.cardRadius) -> some View {
        self
            .background(Tone.cardGradient,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Tone.hairline, lineWidth: 1)
            }
    }
}

// MARK: - Photo treatment

/// The gradient that fades a photo into the canvas, and the veil that keeps the
/// status bar legible over it. Both are in the comp; both have a job.
struct PhotoScrim: View {
    var fade: CGFloat = Layout.photoFade

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.52), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: Layout.topVeil)
                Spacer(minLength: 0)
            }
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LinearGradient(
                    stops: [.init(color: .clear, location: 0),
                            .init(color: Tone.canvas.opacity(0.55), location: 0.42),
                            .init(color: Tone.canvas, location: 0.88)],
                    startPoint: .top, endPoint: .bottom)
                    .frame(height: fade)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Verdict

/// Shape before colour. A filled dot for yes, a ring for a swap — readable for
/// the 8% of men with colour vision deficiency, and in direct sunlight.
struct VerdictMark: View {
    let status: RecipeStatus
    var size: CGFloat = 10

    var body: some View {
        Group {
            switch status {
            case .asIs:
                Circle().fill(Tone.yes)
                    .shadow(color: Tone.yes.opacity(0.7), radius: 7)
            case .adapted:
                Circle().strokeBorder(Tone.swap, lineWidth: size * 0.26)
                    .shadow(color: Tone.swap.opacity(0.45), radius: 6)
            case .notAdaptable:
                Circle().fill(Tone.no)
            case .unknown:
                Circle().strokeBorder(Tone.text3, lineWidth: size * 0.26)
            }
        }
        .frame(width: size, height: size)
    }
}

extension RecipeStatus {
    var tone: Color {
        switch self {
        case .asIs: return Tone.yes
        case .adapted: return Tone.swap
        case .notAdaptable: return Tone.no
        case .unknown: return Tone.text3
        }
    }
}

// MARK: - Buttons

/// The primary action: a two-stop gradient, a specular top edge, and a shadow
/// in the brand's own colour. A flat fill reads as cheap at this size.
struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .fill(Tone.brandGradient)
                    .overlay {
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .strokeBorder(.white.opacity(0.32), lineWidth: 0.75)
                    }
            }
            .shadow(color: Tone.brandDeep.opacity(0.42), radius: 16, y: 10)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.smooth(duration: 0.16), value: configuration.isPressed)
    }
}

// MARK: - Top bar

/// Places a view below the navigation bar and extends the scroll edge effect
/// underneath it.
///
/// `safeAreaBar` is the iOS 26 modifier for this. Below that it falls back to
/// `safeAreaInset`, which reserves the space but does not carry the edge
/// effect — acceptable, because the effect itself is an iOS 26 feature.
struct TopBar<Bar: View>: ViewModifier {
    /* No `@ViewBuilder` on this stored property.
     *
     * The attribute makes the memberwise initialiser take `() -> Bar` rather
     * than `Bar`, so `TopBar(bar: bar())` passed a value where a closure was
     * expected. The extension below already builds the view; this only holds
     * the result. */
    let bar: Bar

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            content.safeAreaBar(edge: .top) { bar }
        } else {
            content.safeAreaInset(edge: .top) { bar }
        }
        #else
        content.safeAreaInset(edge: .top) { bar }
        #endif
    }
}

extension View {
    func topBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        modifier(TopBar(bar: bar()))
    }

    /// The fade that stops content from reading through the tab bar.
    ///
    /// On iOS 26 the scroll edge effect does this on its own; this is the
    /// fallback, and it is harmless where the effect is present.
    func bottomFade() -> some View {
        overlay(alignment: .bottom) {
            LinearGradient(colors: [Tone.canvas.opacity(0), Tone.canvas.opacity(0.92),
                                    Tone.canvas],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 72)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - The soft top bar

/// A top bar that fades out instead of ending on a line.
///
/// A plain background stops at a hard edge, and so does an unmasked
/// `backdrop-filter`: blurring a strip and cutting it produces a SECOND line
/// where the blur ends. Both the tint and the blur have to fall off together,
/// which is what the mask does.
///
/// The hero photo carries the other half — it lightens upward into the canvas
/// over the same distance. Where they overlap there is no edge at all.
struct SoftTopBar<Bar: View>: ViewModifier {
    let bar: Bar
    var height: CGFloat = 112

    /// How much of the extension is drawn, 0 at rest and 1 once scrolled.
    @State private var reveal: CGFloat = 0

    /// The distance over which the extension arrives. A third of a flick:
    /// long enough not to snap, short enough that the first row never meets
    /// the status bar undressed.
    private let travel: CGFloat = 24

    func body(content: Content) -> some View {
        tracked(content).overlay(alignment: .top) {
            ZStack(alignment: .top) {
                /* THE STRIP. Always drawn, in every tab.
                 *
                 * It spans the safe area and stops there, so it covers the
                 * clock, the signal and the battery and reaches no content:
                 * a scroll view starts BELOW the inset, so a title cannot be
                 * under this. That is what lets it stay on over the hero
                 * photo without touching "Shopping" or "Settings".
                 *
                 * The inset is read from the window rather than assumed. A
                 * GeometryReader placed in this overlay reports zero, because
                 * the overlay is already laid out inside the inset. */
                field(height: SafeArea.top, cutoff: 0.62)

                /* THE EXTENSION. Only while content passes under it.
                 *
                 * This is the part that used to wash the titles: it reaches
                 * well past the inset, and at rest there was nothing beneath
                 * it to justify the cost. It now arrives with the scroll. */
                field(height: height, cutoff: 1)
                    .opacity(reveal)

                /* The CONTENT does not ignore the safe area. Applying the
                 * modifier to the ZStack gave it to both, so `padding(.top,
                 * 46)` measured from the physical edge — and a Dynamic Island
                 * occupies 59. The pill ended up underneath it.
                 *
                 * A safe area is the right number on a notch, on an island
                 * and on an iPad; a constant is right on none of them. */
                bar
                    .padding(.top, 4)
            }
        }
    }

    /// One layer of the field. `cutoff` is where the fall-off finishes, as a
    /// fraction of the height — the strip dies early so it clears the title,
    /// the extension runs the full distance.
    private func field(height: CGFloat, cutoff: CGFloat) -> some View {
        LinearGradient(
            stops: [
                .init(color: Tone.canvas.opacity(0.99), location: 0),
                .init(color: Tone.canvas.opacity(0.97), location: 0.30 * cutoff),
                .init(color: Tone.canvas.opacity(0.86), location: 0.52 * cutoff),
                .init(color: Tone.canvas.opacity(0.56), location: 0.70 * cutoff),
                .init(color: Tone.canvas.opacity(0.24), location: 0.85 * cutoff),
                .init(color: Tone.canvas.opacity(0), location: cutoff),
                .init(color: Tone.canvas.opacity(0), location: 1)
            ],
            startPoint: .top, endPoint: .bottom)
            .background(.ultraThinMaterial)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.48 * cutoff),
                        .init(color: .black.opacity(0.6), location: 0.74 * cutoff),
                        .init(color: .clear, location: cutoff),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom)
            }
            .frame(height: height)
            /* The FIELD ignores the safe area — filling to the edge is its
             * whole job. */
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }

    /// Reads the scroll offset where the system offers it.
    ///
    /// `onScrollGeometryChange` is iOS 18 and the deployment target is 17.
    /// Below it the extension is simply always on, which is the behaviour
    /// this modifier had before the split.
    @ViewBuilder
    private func tracked(_ content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                let next = min(max(offset / travel, 0), 1)
                if abs(next - reveal) > 0.01 { reveal = next }
            }
        } else {
            content.onAppear { reveal = 1 }
        }
    }
}

/// The window's top inset.
///
/// 59 on a Dynamic Island, 47 on a notch, 24 on an iPad — a constant is wrong
/// on all three. The fallback is only reached before a window exists.
enum SafeArea {
    static var top: CGFloat {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.isKeyWindow {
                return window.safeAreaInsets.top
            }
        }
        return 47
    }
}

extension View {
    /// Places a bar over a fading field rather than on a hard band.
    func softTopBar<Bar: View>(height: CGFloat = 112,
                               @ViewBuilder _ bar: () -> Bar) -> some View {
        modifier(SoftTopBar(bar: bar(), height: height))
    }

    /// The same field, upside down, behind a pinned footer.
    ///
    /// `.regularMaterial` on a bottom inset ends on a line: the material has
    /// a top edge and the content slides under it and stops there. The
    /// gradient and the blur fall off together instead, so the button sits on
    /// the page rather than on a plate laid over it.
    ///
    /// The negative top padding gives the fall-off room above the footer,
    /// where there is no layout to push.
    func softFooter(reach: CGFloat = 44) -> some View {
        background {
            LinearGradient(
                stops: [
                    .init(color: Tone.canvas.opacity(0), location: 0),
                    .init(color: Tone.canvas.opacity(0.24), location: 0.16),
                    .init(color: Tone.canvas.opacity(0.56), location: 0.31),
                    .init(color: Tone.canvas.opacity(0.86), location: 0.49),
                    .init(color: Tone.canvas.opacity(0.97), location: 0.68),
                    .init(color: Tone.canvas.opacity(0.99), location: 1)
                ],
                startPoint: .top, endPoint: .bottom)
                .background(.ultraThinMaterial)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.6), location: 0.27),
                            .init(color: .black, location: 0.53),
                            .init(color: .black, location: 1)
                        ],
                        startPoint: .top, endPoint: .bottom)
                }
                .padding(.top, -reach)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// Glass, unless something above already supplies it.
    ///
    /// A toolbar item on iOS 26 gets the material from the system. Adding our
    /// own draws a second capsule inside the first — and, worse, a glass
    /// container swallows the first touch, so the control needs two taps.
    @ViewBuilder
    func glassIf(_ on: Bool) -> some View {
        if on { self.glass(Capsule()) } else { self }
    }
}
