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

// MARK: - Capture

@MainActor
final class BarcodeSession: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
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
        out.metadataObjectTypes = [.ean8, .ean13, .upce, .code128]
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

// MARK: - Écran

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

    var body: some View {
        NavigationStack {
            Group {
                switch authorization {
                case .authorized: content
                case .denied, .restricted: denied
                default: prompt
                }
            }
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onDisappear { scanner.stop() }
    }

    private var content: some View {
        ZStack(alignment: .bottom) {
            CameraPreview(session: scanner.session)
                .ignoresSafeArea()

            ViewfinderFrame()
                .allowsHitTesting(false)

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
            messageErreur = "This product isn’t in the open database. Read the label — and feel free to add it to Open Food Facts."
        } catch {
            messageErreur = "Lookup failed. Check your connection — and when in doubt, read the label."
        }
    }

    private func reset() {
        product = nil
        verdict = nil
        messageErreur = nil
        scanner.rearm()
    }
}

struct ViewfinderFrame: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(.white.opacity(0.9), lineWidth: 3)
            .frame(width: 260, height: 165)
            .shadow(radius: 12)
            .accessibilityHidden(true)
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
                    .font(.system(size: 30, weight: .bold))
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
        .padding(21)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: Layout.sheetRadius, style: .continuous))
        .shadow(color: .black.opacity(0.34), radius: 22, y: 8)
        .padding(14)
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
private struct FlowTags: View {
    let names: [String]
    let highlighted: Set<String>

    private let columns = [GridItem(.adaptive(minimum: 60), spacing: 6, alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(names, id: \.self) { n in
                Text(n)
                    .font(.system(size: 11, weight: isHit(n) ? .bold : .regular))
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(isHit(n) ? Color.white : Color.white.opacity(0.18),
                                in: Capsule())
                    .foregroundStyle(isHit(n) ? Tone.no : Color.white)
            }
        }
    }

    private func isHit(_ n: String) -> Bool {
        highlighted.contains { n.localizedCaseInsensitiveContains($0) }
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
