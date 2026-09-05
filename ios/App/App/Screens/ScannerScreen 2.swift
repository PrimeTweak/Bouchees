// The verdict comes from the ENGINE, never from the product database's own
// allergen tags — those are indicative and incomplete on many items.
// ScannerScreen.swift

import SwiftUI
import AVFoundation
import UIKit

// MARK: - Capture

@MainActor
final class BarcodeSession: NSObject, ObservableObject,
                            AVCaptureMetadataOutputObjectsDelegate {
    @Published var code: String?
    @Published var error: String?

    let session = AVCaptureSession()
    private var configured = false
    private var lastCode: String?

    func start() {
        guard !session.isRunning else { return }
        if !configured { configure() }
        guard configured else { return }
        let s = session
        Task.detached(priority: .userInitiated) { s.startRunning() }
    }

    func stop() {
        guard session.isRunning else { return }
        let s = session
        Task.detached(priority: .userInitiated) { s.stopRunning() }
    }

    func rearm() {
        lastCode = nil
        code = nil
        start()
    }

    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let camera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            error = String(localized: "The camera is not available on this device.")
            return
        }
        session.addInput(input)

        /* Near focus: a barcode is read at arm's length or closer; with the
         * default range the lens hunts between the jar and the shelf behind
         * it, and a small code on a yogurt cup never gets a sharp frame. */
        if (try? camera.lockForConfiguration()) != nil {
            if camera.isAutoFocusRangeRestrictionSupported {
                camera.autoFocusRangeRestriction = .near
            }
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            camera.unlockForConfiguration()
        }

        let out = AVCaptureMetadataOutput()
        guard session.canAddOutput(out) else {
            error = String(localized: "Barcode reading could not start.")
            return
        }
        session.addOutput(out)
        out.setMetadataObjectsDelegate(self, queue: .main)
                /* Everything a grocery item can carry: iTF-14 is on cartons and
         * multipacks, Data Matrix and QR on newer packaging, Code 39 on some
         * store labels. */
        /* No `.upca`: AVFoundation has no such type. iOS reads a UPC-A as an
         * EAN-13 with a leading zero, which is exactly the form Open Food
         * Facts indexes — so the twelve-digit case is already covered by. */
        /* GS1 DataBar was missing, and it is the code on produce, meat,
         * bakery and coupons — the aisle where a "did not read" complaint
         * most often comes from. iOS reads it since 15.4; the target is 17. */
        out.metadataObjectTypes = [.ean8, .ean13, .upce, .code128,
                                   .code39, .itf14, .dataMatrix, .qr,
                                   .gs1DataBar, .gs1DataBarExpanded, .gs1DataBarLimited]
        configured = true
    }

    /* Which code to trust when a frame holds several: a carton shows its
     * ITF-14 next to the retail EAN-13; a box carries a QR beside its UPC. */
    nonisolated private static let preference: [AVMetadataObject.ObjectType] = [
        .ean13, .upce, .ean8, .gs1DataBar, .gs1DataBarLimited,
        .gs1DataBarExpanded, .itf14, .dataMatrix, .qr, .code128, .code39
    ]

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput,
                                    didOutput objets: [AVMetadataObject],
                                    from connection: AVCaptureConnection) {
        let lisibles = objets.compactMap { $0 as? AVMetadataMachineReadableCodeObject }
        let choisi = lisibles.min { a, b in
            let ia = Self.preference.firstIndex(of: a.type) ?? Int.max
            let ib = Self.preference.firstIndex(of: b.type) ?? Int.max
            return ia < ib
        }
        guard let objet = choisi, let value = objet.stringValue else { return }
        Task { @MainActor in
            guard self.lastCode != value else { return }
            self.lastCode = value
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            self.code = value
            self.stop()
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        /// Not named `layer`: UIView already owns that property, and shadowing
        /// it makes the accessor call itself.
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Screen

struct ScannerScreen: View {
    /// Bound to the tab bar so a refusal can hand the parent back to Cook with
    /// something they CAN make.
    var tab: Binding<Int>? = nil
    @Environment(AppState.self) private var app
    @StateObject private var scanner = BarcodeSession()

    @State private var authorization = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var isWorking = false
    @State private var product: GroceryProduct?
    @State private var verdict: ProductVerdict?
    @State private var messageErreur: String?
    @State private var canContribute = false

    /// The product sheet, when the parent asks for the reasoning.
    @State private var showDetails = false
    /* Once. The one screen where a parent has to know what is NOT checked. */
    @AppStorage("scanner.firstRunSeen") private var firstRunSeen = false

    var body: some View {
        Group {
            switch authorization {
            case .authorized: content
            case .denied, .restricted: denied
            default: prompt
            }
        }
        /* All three states fill the screen: only `content` did — it holds a
         * camera preview, which is greedy by nature. */
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        /* No navigation bar, like Recipes and Shopping: the title said what
         * the tab already says, and the bar pushed the child pill down. */
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear { scanner.stop() }
    }

    /// What the scanner reads, and what it cannot see. Said once, over the
    /// camera, before the first scan: "may contain" is shown, not decided.
    private var firstLaunch: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What the scanner reads")
                .scaledFont(Type.heading, weight: .semibold)
                .foregroundStyle(Tone.text)
            Text(String(format: String(localized: "**The printed ingredient list.** It finds the allergens %@ avoids, under every name they hide behind — casein, whey, albumin."), app.activeProfile.name))
                .scaledFont(Type.secondary)
                .foregroundStyle(Tone.text2)
            Text("**What it cannot see:** cross-contamination. A \"may contain\" line is shown to you, not decided for you. That call is yours.")
                .scaledFont(Type.secondary)
                .foregroundStyle(Tone.text2)
                .padding(.top, 2)
            Button { withAnimation(.soft(0.25)) { firstRunSeen = true } } label: {
                Text("Got it")
                    .scaledFont(Type.body, weight: .semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.tapTarget)
            }
            .buttonStyle(PrimaryButton())
            .padding(.top, 6)
        }
        .padding(16)
        .background(Tone.canvas, in: RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .padding(.horizontal, Layout.gutter)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 24)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var content: some View {
        /* Not a bottom-aligned ZStack: it aligns to its container, not to the
         * safe area, so the verdict sat under the tab bar. */
        ZStack {
            CameraPreview(session: scanner.session)
                .ignoresSafeArea()

            ViewfinderFrame()
                .allowsHitTesting(false)

            if !firstRunSeen { firstLaunch }
        }
        /* The child pill, on the one screen where the wrong child hurts. */
        .softTopBar { ScannerTopBar() }
        .sheet(isPresented: $showDetails) {
            if let p = product, let v = verdict {
                ProductDetailSheet(product: p, verdict: v)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isWorking || product != nil || messageErreur != nil {
                ProductSheet(product: product, verdict: verdict,
                             isWorking: isWorking, error: messageErreur,
                             onDismiss: { reset() },
                             onDetails: { showDetails = true },
                             firstName: app.activeProfile.firstName)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        /* The verdict is a bottom inset: the tab bar cannot sit on its button. */
        .animation(.soft(0.22), value: product?.code)
        .onAppear { scanner.start() }
        .onChange(of: scanner.code) { _, nouveau in
            guard let code = nouveau else { return }
            Task { await lookUp(code) }
        }
    }

    private var prompt: some View {
        EmptyState(symbol: "barcode.viewfinder",
                 title: "Scan a product",
                 /* What it does, and what it does NOT do. A parent asked for
                  * camera access on behalf of their child deserves the second
                  * half before saying yes. */
                 message: "Point at a barcode: Bouchées reads the ingredient list and runs it through the same engine as your recipes. Nothing is recorded or sent.",
                 titreAction: "Allow camera access") {
            AVCaptureDevice.requestAccess(for: .video) { accorde in
                Task { @MainActor in
                    authorization = accorde ? .authorized : .denied
                }
            }
        }
    }

    private var denied: some View {
        EmptyState(symbol: "camera.fill",
                 title: "Camera access denied",
                 message: "The scanner needs the camera to read barcodes. You can allow it in Settings.",
                 titreAction: "Open Settings") {
            if let u = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(u)
            }
        }
    }

    // MARK: - Consultation

    private func lookUp(_ code: String) async {
        isWorking = true
        product = nil
        verdict = nil
        messageErreur = nil
        canContribute = false
        defer { isWorking = false }

        do {
            let p = try await app.lookUpProduct(code: code)
            product = p
            guard let texte = p.ingredientsText, !texte.isEmpty else {
                messageErreur = "The database doesn’t have this product’s ingredient list. We can’t make a call — read the label."
                return
            }
            verdict = try app.evaluateLabel(texte)
        } catch RepositoryError.network(404) {
            /* The cascade tried every form of the code against four
             * databases. If nothing came back the product really is absent —
             * so give the parent the next step rather than a verdict. */
            messageErreur = String(localized:
                "Not in any open database yet. Read the label — and you can add this product so the next parent finds it.")
            canContribute = true
        } catch RepositoryError.network(400) {
            /* The code was read, and there was no product number in it — a
             * QR that points at a website, a serial, a coupon. Not a network
             * problem, and not a missing product. */
            messageErreur = String(localized:
                "That code is not a product barcode. Look for the striped one on the package.")
        } catch RepositoryError.network(503) {
            /* Not the same as 404: the server is out of lookups for this
             * minute, or the database is refusing it. */
            messageErreur = String(localized:
                "The product database is busy. Try again in a moment — and when in doubt, read the label.")
        } catch {
            messageErreur = String(localized:
                "Lookup failed. Check your connection — and when in doubt, read the label.")
        }
    }



    private func reset() {
        product = nil
        verdict = nil
        messageErreur = nil
        canContribute = false
        scanner.rearm()
    }
}

struct ViewfinderFrame: View {
    /// A label needs a taller window than a barcode strip.
    var wide: Bool = false

    /// Four corner brackets rather than a full rectangle. It reads as a target
    /// without boxing in the product, and it survives any camera background.
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width * (wide ? 0.84 : 0.72)
            let h = wide ? w * 1.05 : w / 1.4
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    Corner()
                        .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 34, height: 34)
                        .rotationEffect(.degrees(Double(i) * 90))
                        .offset(x: (i == 0 || i == 3) ? -w/2 + 17 : w/2 - 17,
                                y: (i == 0 || i == 1) ? -h/2 + 17 : h/2 - 17)
                }
            }
            .frame(width: w, height: h)
            .position(x: geo.size.width / 2, y: geo.size.height * 0.38)
        }
    }
}

private struct Corner: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + 10))
        p.addQuadCurve(to: CGPoint(x: r.minX + 10, y: r.minY),
                       control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}

/// Full colour, at arm's length: the rest of the app is calm because fear
/// needs calm — this card is the one exception, and it is the one place glass
/// gives way to solid colour.
struct ProductSheet: View {
    let product: GroceryProduct?
    let verdict: ProductVerdict?
    let isWorking: Bool
    let error: String?
    let onDismiss: () -> Void

    /// Opens the reasoning behind the verdict.
    var onDetails: () -> Void = {}
    var firstName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isWorking {
                HStack(spacing: 11) {
                    ProgressView().tint(.white)
                    Text("Reading the label…")
                        .scaledFont(Type.body, weight: .medium)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error {
                Text(error)
                    .scaledFont(Type.body)
                    .foregroundStyle(.white)
            } else if let v = verdict, let p = product {
                /* VoiceOver reads the verdict first, as one announcement:
                 * the product, the answer, and the child it is for. */
                Text(headline(v))
                    .scaledFont(Type.display, weight: .bold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .accessibilityLabel(Text("\(p.name ?? String(localized: "This product")). \(headline(v)). \(subline(v, p))"))
                    .accessibilityAddTraits(.isHeader)

                Text(subline(v, p))
                    .scaledFont(Type.body)
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.top, 7)

                /* What the verdict is made of, in one line. */
                Text("From the printed ingredient list. Always check the package.")
                    .scaledFont(Type.label)
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.top, 5)

                /* The offending allergen is solid white, the rest translucent.
                 * The culprit is seen before anything is read. */
                let names = Self.splitIngredients(p.ingredientsText)
                if !names.isEmpty {
                    FlowTags(names: Array(names.prefix(9)),
                             highlighted: Set(v.allergensFound))
                        .padding(.top, 15)
                }

                if let attribution = p.attribution {
                    Text(attribution)
                        .scaledFont(Type.micro)
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.top, 12)
                }
            }

            /* Two actions, side by side: in an aisle with a stroller there
             * are exactly two things to do: understand why, or move on. */
            HStack(spacing: 8) {
                if product != nil && verdict != nil {
                    Button { onDetails() } label: {
                        Text("See details")
                            .scaledFont(Type.body, weight: .semibold)
                            .foregroundStyle(background)
                            .frame(maxWidth: .infinity)
                            .frame(height: Layout.tapTarget)
                            .background(.white, in: RoundedRectangle(cornerRadius: 13,
                                                                     style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onDismiss) {
                    Text("Scan another")
                        .scaledFont(Type.body, weight: .medium)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: Layout.tapTarget)
                        .background(Color.white.opacity(0.18),
                                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 15)
            .padding(.top, 9)
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Layout.sheetRadius, style: .continuous)
                .fill(LinearGradient(colors: [background, background.opacity(0.82)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: Layout.sheetRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.28), lineWidth: 0.75)
                }
        }
        .shadow(color: .black.opacity(0.6), radius: 30, y: 14)
        .padding(.horizontal, 14)
        /* A bottom inset, not a fixed offset: the tab bar's height varies. */
        .padding(.bottom, 10)
    }

    /// The label arrives as one string. Split on the usual separators so the
    /// offending ingredient can be highlighted on its own.
    static func splitIngredients(_ text: String?) -> [String] {
        guard let text, !text.isEmpty else { return [] }
        return text
            .components(separatedBy: CharacterSet(charactersIn: ",;()[]"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 1 && $0.count < 30 }
    }

    /// Solid colour, not a tinted banner. The verdict occupies the field of
    /// view and is read without reading.
    private var background: Color {
        switch verdict?.status {
        case .safe: return Tone.yes
        case .avoid: return Tone.no
        /* Caution shares the swap amber with uncertain, and is separated by
         * its words rather than its colour. Both mean "stop and read"; a
         * fourth colour in a viewfinder is a fourth thing to learn. */
        case .uncertain, .caution, .unreadable: return Tone.swap
        case nil: return Tone.brand
        }
    }

    private func headline(_ v: ProductVerdict) -> String {
        let who = firstName.isEmpty ? String(localized: "your child") : firstName
        switch v.status {
        case .safe: return String(format: String(localized: "Good for %@"), who)
        case .avoid: return String(format: String(localized: "Not for %@"), who)
        case .uncertain: return String(localized: "I am not sure")
        case .unreadable: return String(localized: "Nothing to read")
        case .caution: return String(localized: "Made near it")
        }
    }

    private func subline(_ v: ProductVerdict, _ p: GroceryProduct) -> String {
        switch v.status {
        case .safe:
            return p.name ?? String(localized: "This product")
        case .avoid:
            let allergenNames = v.allergensFound.joined(separator: ", ")
            let label = p.name ?? String(localized: "This product")
            return label + " — " + String(format: String(localized: "contains %@"), allergenNames)
        case .uncertain:
            return String(localized: "Something on the label was not recognised. Check the package.")
        case .unreadable:
            return String(localized: "No ingredient list came back for this product. Read the label on the package.")
        case .caution:
            /* The distinction this state exists for: the list is clean, the
             * factory is not. A parent decides this one, not the app. */
            let allergenNames = v.mayContain.joined(separator: ", ")
            let label = p.name ?? String(localized: "This product")
            return label + " — " + String(format: String(localized: "may contain %@"), allergenNames)
        }
    }
}

/// Tags that wrap: the culprit is opaque white; the rest recede.
private struct FlowTags: View {
    let names: [String]
    let highlighted: Set<String>

    var body: some View {
        WrappingRow(spacing: 6, lineSpacing: 6) {
            ForEach(names, id: \.self) { name in
                tag(name)
            }
        }
    }

    private func tag(_ name: String) -> some View {
        let flagged = highlighted.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        return Text(name)
            .scaledFont(Type.label, weight: flagged ? .bold : .regular)
            .foregroundStyle(flagged ? Color.black.opacity(0.82) : Color.white)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(flagged ? AnyShapeStyle(.white)
                                : AnyShapeStyle(Color.white.opacity(0.2)),
                        in: Capsule())
    }
}

/// Lays subviews out left to right, wrapping when the line is full. No
/// GeometryReader, no @State, no round-trip — which is what makes it
/// impossible to loop.
/* The project has its own `enum Layout` holding the spacing constants, and it
 * wins the name lookup — so `: Layout` meant "inherit from the local enum", which
 * gave four cascading errors none of which named the collision. */
struct WrappingRow: SwiftUI.Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: LayoutSubviews,
                      cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth,
                      height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: LayoutSubviews,
                       cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                      proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}



// MARK: - Product details

/// Why the verdict says what it says: a single number folds nutrition,
/// additives and allergens into one value — and for an allergic child only the
/// last one matters.
struct ProductDetailSheet: View {
    let product: GroceryProduct
    let verdict: ProductVerdict
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.navigate) private var navigate

    @State private var showFullList = false

    private var profile: ChildProfile { app.activeProfile }

    /// The allergens that are a problem, and the ones that are not.
    private var bloquants: [String] {
        profile.allergens.filter { a in
            verdict.allergensFound.contains { $0.caseInsensitiveCompare(a) == .orderedSame }
        }
    }
    private var sains: [String] { profile.allergens.filter { !bloquants.contains($0) } }

    /// The measured height of the content, so the sheet stops where it ends.
    @State private var measuredHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            /* 22 between blocks rather than each block carrying its own top
             * padding of 12 to 15. One rhythm instead of six. */
            VStack(alignment: .leading, spacing: 22) {
                head
                reason
                clearLine
                ingredientCard
                alternatives
                attribution
            }
            .padding(.top, 26)
            .padding(.bottom, 30)
            .background {
                GeometryReader { geo in
                    Color.clear.onAppear { measuredHeight = geo.size.height }
                        .onChange(of: geo.size.height) { _, h in measuredHeight = h }
                }
            }
        }
        .background(Tone.canvas.ignoresSafeArea())
        /* No detent was declared at all, so iOS opened it full height: a
         * short ingredient list sat in the top third of the screen with two
         * thirds of empty canvas under it. */
        .presentationDetents(measuredHeight > 0
            ? [.height(min(max(measuredHeight, 260), UIScreen.main.bounds.height * 0.75)), .large]
            /* Before the first measurement: medium, which is close to what a
             * typical product needs, instead of a 260pt stub that visibly
             * grows on the next frame. */
            : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var head: some View {
        HStack(alignment: .top, spacing: 13) {
            PackageThumb()
            VStack(alignment: .leading, spacing: 3) {
                Text(product.name ?? String(localized: "Unnamed product"))
                    .scaledFont(Type.heading, weight: .bold)
                    .kerning(-0.35)
                    .foregroundStyle(Tone.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let brand = product.marque {
                    Text(brand)
                        .scaledFont(Type.label)
                        .foregroundStyle(Tone.text2)
                }
                Text(product.code)
                    .scaledFont(Type.micro, design: .monospaced)
                    .foregroundStyle(Tone.text3)

                VerdictBadge(status: verdict.status, firstName: profile.firstName)
                    .padding(.top, 8)
                Text("From the printed ingredient list. Always check the package.")
                    .scaledFont(Type.micro)
                    .foregroundStyle(Tone.text3)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, Layout.gutter)
    /* The stack spaces the blocks now; a top padding here would add to it. */
    }

    /// One card for the reason: proportion carries the verdict now: what
    /// blocks takes space, what is fine takes a line.
    @ViewBuilder
    private var reason: some View {
        if !bloquants.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("The reason")
                    .scaledFont(Type.micro, weight: .bold, design: .monospaced)
                    .kerning(1.6)
                    .foregroundStyle(Tone.no)

                Text(String(format: String(localized: "Contains %@"),
                            app.allergenNames(bloquants).joined(separator: ", ")))
                    .scaledFont(Type.body, weight: .bold)
                    .kerning(-0.3)
                    .foregroundStyle(Tone.text)

                Text("Read from the ingredient list, not from a database tag.")
                    .scaledFont(Type.label)
                    .foregroundStyle(Tone.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(
                LinearGradient(colors: [Tone.no.opacity(0.09), Tone.no.opacity(0.04)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(Tone.no.opacity(0.18), lineWidth: 1)
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.top, 16)
        }
    }

    /// Everything that is fine, on one line.
    @ViewBuilder
    private var clearLine: some View {
        if !sains.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .scaledFont(Type.micro, weight: .bold)
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Tone.yes, in: Circle())

                Text(String(format: String(localized: "%@ — none present, no trace warning."),
                            app.allergenNames(sains).joined(separator: ", ")))
                    .scaledFont(Type.label)
                    .foregroundStyle(Tone.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Tone.yes.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Tone.yes.opacity(0.14), lineWidth: 1)
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.top, 11)
        }
    }

    /// The full list, with the offending word marked: tHE EXPANSION PUSHES.
    private var ingredientCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.soft(0.22)) { showFullList.toggle() }
            } label: {
                HStack(spacing: 11) {
                    Text("Full ingredient list")
                        .scaledFont(Type.label, weight: .semibold)
                        .foregroundStyle(Tone.text)
                    Spacer(minLength: 0)
                    Text(String(format: String(localized: "%lld read · %lld recognised"),
                                readCount, max(0, readCount - verdict.unknownIngredients.count)))
                        .scaledFont(Type.micro)
                        .foregroundStyle(Tone.text3)
                    Image(systemName: showFullList ? "chevron.up" : "chevron.down")
                        .scaledFont(Type.micro, weight: .semibold)
                        .foregroundStyle(Tone.text3)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .background(Tone.text.opacity(0.025))

            if showFullList, let texte = product.ingredientsText {
                marked(texte)
                    .scaledFont(Type.micro)
                    .foregroundStyle(Tone.text2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Tone.hairline, lineWidth: 1)
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 11)
    }

    /// The word that produced the verdict, highlighted in the list.
    ///
    /// A parent should be able to check the app rather than take its word.
    private func marked(_ texte: String) -> Text {
        let cibles = app.allergenNames(bloquants).map { $0.lowercased() }
        var out = Text("")
        var rest = Substring(texte)

        while let plage = rest.range(of: cibles.first(where: {
            rest.lowercased().contains($0)
        }) ?? "\u{0}", options: .caseInsensitive) {
            out = out + Text(rest[..<plage.lowerBound])
            out = out + Text(rest[plage])
                .foregroundColor(Tone.no)
                .fontWeight(.semibold)
            rest = rest[plage.upperBound...]
        }
        return out + Text(rest)
    }

    private var readCount: Int {
        (product.ingredientsText ?? "")
            .split(whereSeparator: { ",;()".contains($0) })
            .filter { $0.trimmingCharacters(in: .whitespaces).count > 1 }
            .count
    }

    /// A recipe, not another product.
    @ViewBuilder
    private var alternatives: some View {
        if verdict.status == .avoid {
            let pool = app.weekRecipes.prefix(2).compactMap { r in
                app.resultFor(r).map { (recipe: r, result: $0) }
            }
            if !pool.isEmpty {
                Text(String(format: String(localized: "%@ can have these tonight"),
                            profile.firstName))
                    .eyebrow()
                    .padding(.horizontal, Layout.gutter)
                    .padding(.top, 4)
                ForEach(pool, id: \.recipe.id) { pair in
                    Button {
                        dismiss()
                        navigate(.recipe(pair.recipe.id))
                    } label: {
                        RecipeRow(recipe: pair.recipe, result: pair.result)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var attribution: some View {
        VStack(alignment: .leading, spacing: 8) {
            /* The disclaimer where the risk is: a parent reading a green
             * verdict in an aisle never sees Settings. */
            Text(Settings.medicalDisclaimer)
                .scaledFont(Type.micro)
                .foregroundStyle(Tone.text3)
                .fixedSize(horizontal: false, vertical: true)
            Text("From Open Food Facts, ODbL. Bouchées re-derives every allergen from the ingredient list rather than trusting the database tags.")
                .scaledFont(Type.micro)
                .foregroundStyle(Tone.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 4)
    }
}


/// A package, drawn: `GroceryProduct` carries a code, a name, a brand and the
/// ingredient text — no image.
private struct PackageThumb: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(LinearGradient(colors: [Tone.cardTop, Tone.cardBottom],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))

            VStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Tone.text.opacity(0.1))
                    .frame(height: 20)

                /* Bars, not an icon. It is what the camera just read. */
                HStack(spacing: 1.5) {
                    ForEach(0..<11, id: \.self) { i in
                        Rectangle()
                            .fill(Tone.text.opacity(i % 3 == 0 ? 0.4 : 0.24))
                            .frame(width: i % 4 == 0 ? 2 : 1.2)
                    }
                }
                .frame(height: 13)
            }
            .padding(.horizontal, 9)
        }
        .frame(width: 58, height: 72)
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Tone.hairline, lineWidth: 1)
        }
    }
}

/// The child pill and, with two profiles, the one-tap "Everyone" beside it.
private struct ScannerTopBar: View {
    @Environment(AppState.self) private var app

    /// The child pill and, with two profiles, the one-tap "Everyone" beside it —
    /// in the pill's own glass, at the pill's own height.
    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            if app.profiles.count > 1 {
                Button {
                    withAnimation(.soft(0.22)) { app.familyMode.toggle() }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: app.familyMode ? "person.fill" : "person.2.fill")
                            .scaledFont(Type.caption, weight: .semibold)
                        Text(app.familyMode ? "One child" : "Everyone")
                            .scaledFont(Type.secondary, weight: .semibold)
                            .lineLimit(1)
                    }
                    .foregroundStyle(app.familyMode ? Tone.brand : Tone.text)
                    .frame(height: 30)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .contentShape(Capsule())
                }
                .glass(Capsule(), tinted: app.familyMode)
                .buttonStyle(.plain)
                .accessibilityLabel(app.familyMode
                    ? Text("Checking for everyone. Tap to check for one child.")
                    : Text("Checking for one child. Tap to check for everyone."))
            }
            CookingContextHeader(compact: true)
        }
        .padding(.horizontal, Layout.gutter)
    }
}

/// The verdict, in one line, with the child's name in it.
private struct VerdictBadge: View {
    let status: ProductVerdict.Statut
    let firstName: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .scaledFont(Type.micro, weight: .bold)
            Text(phrase)
                .scaledFont(Type.label, weight: .bold)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(tint.opacity(0.1), in: Capsule())
    }

    private var symbol: String {
        switch status {
        case .safe: return "checkmark"
        case .avoid: return "exclamationmark.triangle.fill"
        case .uncertain: return "questionmark"
        case .unreadable: return "text.viewfinder"
        case .caution: return "exclamationmark.triangle"
        }
    }

    private var tint: Color {
        switch status {
        case .safe: return Tone.yes
        case .avoid: return Tone.no
        case .uncertain, .caution, .unreadable: return Tone.swap
        }
    }

    private var phrase: String {
        switch status {
        case .safe: return String(format: String(localized: "Good for %@"), firstName)
        case .avoid: return String(format: String(localized: "Not for %@"), firstName)
        case .uncertain: return String(localized: "I am not sure")
        case .unreadable: return String(localized: "Nothing to read")
        case .caution: return String(localized: "Made near it")
        }
    }
}
