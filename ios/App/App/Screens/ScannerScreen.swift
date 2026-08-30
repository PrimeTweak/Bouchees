//  ScannerScreen.swift
//
//  Le scanner. Impossible dans un navigateur, et probablement la fonction la
//  most useful thing the app does: check a product in the grocery aisle.
//
//  The verdict comes from the ENGINE, never from the product database's own
//  allergen tags — those are indicative and incomplete on many items.
//
//  Product data: Open Food Facts, under the ODbL. Two consequences honoured to
//  the letter: attribution shown on every sheet, and no
//  fusion dans notre catalogue. On consulte, on affiche, on ne conserve rien.

import SwiftUI
import AVFoundation
import UIKit
/* On-device text recognition. The reason it is here: for Canada, Open Food
 * Facts has 124,088 products and complete ingredients for 21,918 of them.
 * The ingredient list is printed on the package, in front of the camera,
 * and it is the source that legally governs. */
import Vision

// MARK: - Capture

@MainActor
final class BarcodeSession: NSObject, ObservableObject,
                            AVCaptureMetadataOutputObjectsDelegate,
                            AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var code: String?
    @Published var error: String?

    let session = AVCaptureSession()
    private var configured = false
    private let fileVideo = DispatchQueue(label: "ca.bouchees.frames", qos: .userInitiated)

    /// Set while the label mode is active. Off, frames are ignored entirely
    /// so the camera costs nothing extra when scanning barcodes.
    var readingLabel = false
    let reader = LabelReader()
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

        guard let appareil = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: appareil),
              session.canAddInput(input) else {
            error = String(localized: "The camera is not available on this device.")
            return
        }
        session.addInput(input)

        let out = AVCaptureMetadataOutput()
        guard session.canAddOutput(out) else {
            error = String(localized: "Barcode reading could not start.")
            return
        }
        session.addOutput(out)
        out.setMetadataObjectsDelegate(self, queue: .main)

        /* A second output, for reading the label. Frames are dropped while a
         * recognition is in flight — Vision on `.accurate` takes longer than
         * a frame interval, and queueing them would grow without bound. */
        let video = AVCaptureVideoDataOutput()
        video.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(video) {
            session.addOutput(video)
            video.setSampleBufferDelegate(self, queue: fileVideo)
        }
        /* Everything a grocery item can carry.
         *
         * ITF-14 is on cartons and multipacks, Data Matrix and QR on newer
         * packaging, Code 39 on some store labels. The server normalises
         * whichever form comes back, so accepting more here costs nothing. */
        /* No `.upca`: AVFoundation has no such type. iOS reads a UPC-A as an
         * EAN-13 with a leading zero, which is exactly the form Open Food
         * Facts indexes — so the twelve-digit case is already covered by
         * .ean13, and the server normalises the rest. */
        out.metadataObjectTypes = [.ean8, .ean13, .upce, .code128,
                                   .code39, .itf14, .dataMatrix, .qr]
        configured = true
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput,
                                    didOutput objets: [AVMetadataObject],
                                    from connection: AVCaptureConnection) {
        guard let objet = objets.first as? AVMetadataMachineReadableCodeObject,
              let value = objet.stringValue else { return }
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
    @Environment(AppState.self) private var etat
    @StateObject private var scanner = BarcodeSession()

    @State private var authorization = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var isWorking = false
    @State private var product: GroceryProduct?
    @State private var verdict: ProductVerdict?
    @State private var messageErreur: String?
    @State private var canContribute = false

    /// Barcode, or read the label directly.
    ///
    /// Two modes because the databases cover one product in six here. The
    /// second is not a fallback bolted on — it is the mode that works in a
    /// grocery basement with no signal, on a product nobody catalogued.
    @State private var mode: ScanMode = .barcode
    /// Where a verdict came from. A parent deciding for their child has to
    /// know whether a database said it or the package did.
    @State private var source: VerdictSource = .database

    var body: some View {
        Group {
            switch authorization {
            case .authorized: content
            case .denied, .restricted: denied
            default: prompt
            }
        }
        .navigationTitle("Scan")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { scanner.stop() }
    }

    private var content: some View {
        /* NOT a bottom-aligned ZStack.
         *
         * A ZStack aligns to the bottom of its CONTAINER, not to the safe
         * area, so the verdict sat under the tab bar however much padding it
         * carried. The camera fills the frame; the verdict is a safeAreaInset
         * like every other bar in this app, and the tab bar reserves its own
         * space below it. */
        ZStack {
            CameraPreview(session: scanner.session)
                .ignoresSafeArea()

            ViewfinderFrame(wide: mode == .label)
                .allowsHitTesting(false)

            VStack {
                modePicker
                    .padding(.top, 48)
                Spacer(minLength: 0)
            }

        }
        .onChange(of: scanner.reader.text) { _, texte in
            guard let t = texte, mode == .label else { return }
            evaluerEtiquette(t)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isWorking || product != nil || messageErreur != nil {
                ProductSheet(product: product, verdict: verdict,
                             isWorking: isWorking, error: messageErreur,
                             onDismiss: { reset() },
                             onFindAlternatives: {
                                 /* Back to Cook, filtered to what is ready as
                                  * is. The parent asked a question and gets an
                                  * answer, not a refusal. */
                                 reset()
                                 tab?.wrappedValue = 0
                             },
                             firstName: etat.activeProfile.firstName)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        /* The verdict is an inset, not a floating card. It was anchored a
         * fixed distance from the bottom and the tab bar sat on top of its
         * button; reserving the space is what stops that for good. */
        .animation(.easeInOut(duration: 0.22), value: product?.code)
        .onAppear { scanner.start() }
        .onChange(of: scanner.code) { _, nouveau in
            guard let code = nouveau else { return }
            Task { await lookUp(code) }
        }
    }

    private var prompt: some View {
        EmptyState(symbol: "barcode.viewfinder",
                 title: "Scan a product",
                 message: "Point at a barcode: Bouchées reads the ingredient list and runs it through the same engine as your recipes.",
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
            let p = try await etat.lookUpProduct(code: code)
            product = p
            guard let texte = p.ingredientsText, !texte.isEmpty else {
                messageErreur = "The database doesn’t have this product’s ingredient list. We can’t make a call — read the label."
                return
            }
            verdict = try etat.evaluateLabel(texte)
        } catch RepositoryError.network(404) {
            /* The cascade tried every form of the code against four
             * databases. If nothing came back the product really is absent —
             * so give the parent the next step rather than a verdict. */
            messageErreur = String(localized:
                "Not in any open database yet. Read the label — and you can add this product so the next parent finds it.")
            canContribute = true
        } catch {
            messageErreur = "Lookup failed. Check your connection — and when in doubt, read the label."
        }
    }

    /// Barcode or label, one tap.
    private var modePicker: some View {
        HStack(spacing: 3) {
            ForEach([ScanMode.barcode, .label], id: \.self) { m in
                Button {
                    withAnimation(.smooth(duration: 0.22)) {
                        mode = m
                        scanner.readingLabel = (m == .label)
                        reset()
                    }
                } label: {
                    Text(m == .barcode ? "Barcode" : "Ingredients")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(mode == m ? Color.black : Color.white.opacity(0.66))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .background(mode == m ? AnyShapeStyle(Color.white)
                                              : AnyShapeStyle(Color.clear),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(.white.opacity(0.24), lineWidth: 0.5) }
    }

    /// Runs the label text through the same engine a database result goes
    /// through. Same 603 terms, same rules, same refusal to guess.
    private func evaluerEtiquette(_ texte: String) {
        source = .label
        product = nil
        messageErreur = nil
        do {
            verdict = try etat.evaluateLabel(texte)
            UINotificationFeedbackGenerator().notificationOccurred(
                verdict?.status == .avoid ? .warning : .success)
        } catch {
            messageErreur = String(localized:
                "I could not read enough of the label. Try holding it flatter, in better light.")
        }
    }

    private func reset() {
        product = nil
        verdict = nil
        messageErreur = nil
        canContribute = false
        scanner.reader.reset()
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

/// FULL COLOUR, AT ARM'S LENGTH.
///
/// One hand on the stroller, one on the phone, grocery lighting. The rest of
/// the app is calm because fear needs calm — this card is the one exception,
/// and it is the one place glass gives way to solid colour.
///
/// The child's first name is in the verdict. "Not for Livia", not "Contains
/// milk": the app does the translation, not the parent.
struct ProductSheet: View {
    let product: GroceryProduct?
    let verdict: ProductVerdict?
    let isWorking: Bool
    let error: String?
    let onDismiss: () -> Void
    var onFindAlternatives: () -> Void = {}
    var firstName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isWorking {
                HStack(spacing: 11) {
                    ProgressView().tint(.white)
                    Text("Reading the label…")
                        .font(Type.secondary.weight(.medium))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error {
                Text(error)
                    .font(Type.secondary)
                    .foregroundStyle(.white)
            } else if let v = verdict, let p = product {
                Text(headline(v))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                Text(subline(v, p))
                    .font(Type.secondary)
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.top, 7)

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
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.top, 12)
                }
            }

            /* A refusal always opens a door. A parent in an aisle told "no" has
             * learned something useful and been left with nothing to do. */
            if verdict?.status == .avoid {
                Button(action: onFindAlternatives) {
                    Text("See recipes that replace this")
                        .font(Type.secondary.weight(.semibold))
                        .foregroundStyle(background)
                        .frame(maxWidth: .infinity)
                        .frame(height: Layout.tapTarget + 2)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 17)
            }

            Button(action: onDismiss) {
                Text("Scan another product")
                    .font(Type.secondary.weight(verdict?.status == .avoid ? .medium : .semibold))
                    .foregroundStyle(verdict?.status == .avoid ? Color.white : background)
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.tapTarget + 2)
                    .background(
                        verdict?.status == .avoid
                            ? AnyShapeStyle(Color.white.opacity(0.18))
                            : AnyShapeStyle(Color.white),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
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
        /* It was anchored 100pt from the bottom while the bar occupies 86 —
         * so the tab labels bled through the action. An inset reserves its
         * own strip, like everything else on this screen. */
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
        case .uncertain: return Tone.swap
        case nil: return Tone.brand
        }
    }

    private func headline(_ v: ProductVerdict) -> String {
        let who = firstName.isEmpty ? String(localized: "your child") : firstName
        switch v.status {
        case .safe: return String(format: String(localized: "Good for %@"), who)
        case .avoid: return String(format: String(localized: "Not for %@"), who)
        case .uncertain: return String(localized: "I am not sure")
        }
    }

    private func subline(_ v: ProductVerdict, _ p: GroceryProduct) -> String {
        switch v.status {
        case .safe:
            return p.name ?? String(localized: "This product")
        case .avoid:
            let noms = v.allergensFound.joined(separator: ", ")
            let label = p.name ?? String(localized: "This product")
            return label + " — " + String(format: String(localized: "contains %@"), noms)
        case .uncertain:
            return String(localized: "Something on the label was not recognised. Check the package.")
        }
    }
}

/// Tags that wrap. The culprit is opaque white; the rest recede.
/// A wrapping row of ingredient names.
///
/// A LazyVGrid with fixed columns truncated every name to the width of the
/// narrowest cell — "Carbonate…", "Arôme…" — which is useless when the point
/// is to read what is in the product. This measures each tag and wraps.
///
/// The names come off the product label, so French entries on a Quebec
/// product are correct and stay as they are.
/// A wrapping row of ingredient names.
///
/// MEASURES NOTHING.
///
/// The version this replaces was a feedback loop: an outer GeometryReader
/// whose `.frame(height:)` was fed by an inner GeometryReader measuring its
/// own content, plus `alignmentGuide` closures mutating captured variables.
/// SwiftUI calls those closures an unpredictable number of times, in an
/// unpredictable order, so the layout never converged — the main thread spun
/// and the whole screen stopped responding. From the outside that looked like
/// "the scanner no longer reads barcodes".
///
/// `Layout` does the same job natively since iOS 16, in one pass, with no
/// state and no measurement round-trip.
///
/// The names come off the product label, so French entries on a Quebec
/// product are correct and stay as they are.
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
            .font(.system(size: 11.5, weight: flagged ? .bold : .regular))
            .foregroundStyle(flagged ? Color.black.opacity(0.82) : Color.white)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(flagged ? AnyShapeStyle(.white)
                                : AnyShapeStyle(Color.white.opacity(0.2)),
                        in: Capsule())
    }
}

/// Lays subviews out left to right, wrapping when the line is full.
///
/// A `Layout` computes size and positions in ONE pass from sizes it asks for
/// directly. No GeometryReader, no @State, no round-trip — which is what makes
/// it impossible to loop.
/* `SwiftUI.Layout`, qualified.
 *
 * The project has its own `enum Layout` holding the spacing constants, and it
 * wins the name lookup — so `: Layout` meant "inherit from my enum", which
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

struct ProductVerdictBanner: View {
    let verdict: ProductVerdict

    private var color: Color {
        switch verdict.status {
        case .safe: return Tone.yes
        case .avoid: return Tone.no
        case .uncertain: return Tone.swap
        }
    }

    private var symbol: String {
        switch verdict.status {
        case .safe: return "checkmark.circle.fill"
        case .avoid: return "xmark.octagon.fill"
        case .uncertain: return "questionmark.circle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: symbol).font(.title3).foregroundStyle(color)
                Text(verdict.message).font(.callout.weight(.semibold))
            }

            if !verdict.unknownIngredients.isEmpty {
                Text("Non reconnus : \(verdict.unknownIngredients.joined(separator: ", ")).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// What the camera is looking for.
enum ScanMode: Hashable {
    case barcode
    case label
}

/// Where a verdict came from.
enum VerdictSource: Hashable {
    case database
    case label
}

// MARK: - Reading the label

/// Reads an ingredient list off the package with on-device text recognition.
///
/// WHY THIS EXISTS. A coverage study of April 2026 measured Open Food Facts at
/// 124,088 Canadian products with complete ingredients for 21,918 — roughly
/// one in six. USDA holds 2,319 Canadian barcodes out of two million. Stacking
/// more databases does not fix a product that was never entered, and small
/// Quebec producers rarely are.
///
/// The list is printed on the package. Vision reads it on the device: offline,
/// free, private, and it works on a product nobody has ever catalogued.
@MainActor
@Observable
final class LabelReader {

    private(set) var text: String?
    private(set) var reading = false

    /// Everything Vision saw, so the parent can check what was read rather
    /// than trust it. OCR misreads, and a misread on an allergen matters.
    private(set) var lines: [String] = []

    func reset() {
        text = nil
        lines = []
        reading = false
    }

    /// Recognises text in one frame.
    ///
    /// `.accurate` rather than `.fast`: a curved bottle in grocery lighting is
    /// exactly where the fast path drops words, and a dropped word on an
    /// ingredient list is the failure this app exists to prevent.
    func read(_ buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        guard !reading else { return }
        reading = true

        let requete = VNRecognizeTextRequest { [weak self] requete, _ in
            guard let obs = requete.results as? [VNRecognizedTextObservation] else { return }
            /* Several candidates, not one. Vision returns them ordered by
             * confidence, and asking for more than one measurably improves
             * reading order on multi-line labels. */
            let lues = obs.compactMap { $0.topCandidates(3).first?.string }
            Task { @MainActor [weak self] in
                self?.finish(lues)
            }
        }
        requete.recognitionLevel = .accurate
        requete.usesLanguageCorrection = true
        /* A Quebec package is bilingual, and the French half is often the
         * fuller one. */
        requete.recognitionLanguages = ["fr-CA", "fr-FR", "en-CA", "en-US"]

        let handler = VNImageRequestHandler(cvPixelBuffer: buffer,
                                            orientation: orientation, options: [:])
        Task.detached(priority: .userInitiated) {
            try? handler.perform([requete])
        }
    }

    private func finish(_ lues: [String]) {
        reading = false
        guard !lues.isEmpty else { return }

        lines = lues
        /* Keep only what follows an "ingredients" heading when there is one.
         * A nutrition table above it would otherwise be read as ingredients,
         * and "sodium 5 mg" is not an ingredient. */
        let joint = lues.joined(separator: " ")
        text = Self.ingredientSection(in: joint) ?? joint
    }

    /// The ingredient list within everything the camera saw.
    ///
    /// Both languages, because a Canadian package prints both and either may
    /// be the one in focus.
    static func ingredientSection(in texte: String) -> String? {
        let bas = texte.lowercased()
        let entetes = ["ingredients:", "ingredients :", "ingredients",
                       "ingr\u00e9dients:", "ingr\u00e9dients :", "ingr\u00e9dients"] // label text
        for e in entetes {
            guard let r = bas.range(of: e) else { continue }
            var suite = String(texte[r.upperBound...])
            /* Stop at whatever follows the list on a package. */
            for fin in ["nutrition facts", "contains:", "may contain", "produced in",
                        "keep refrigerated", "best before",
                        "valeur nutritive", "contient:", "peut contenir",
                        "produit en", "garder au froid", "meilleur avant"] { // label text
                if let f = suite.lowercased().range(of: fin) {
                    suite = String(suite[..<f.lowerBound])
                }
            }
            let propre = suite.trimmingCharacters(in: .whitespacesAndNewlines)
            if propre.count > 8 { return propre }
        }
        return nil
    }
}

// MARK: - Frames

extension BarcodeSession {
    /// Hands one frame to the reader, and only when the label mode is on.
    ///
    /// Nonisolated because AVFoundation calls this on its own queue; the hop
    /// to the main actor happens once, with the pixel buffer, rather than for
    /// every frame.
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        Task { @MainActor [weak self] in
            guard let self, self.readingLabel else { return }
            self.reader.read(pixels, orientation: .right)
        }
    }
}
