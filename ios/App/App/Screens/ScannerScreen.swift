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
                             isWorking: isWorking, error: messageErreur) {
                    reset()
                }
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

struct ProductSheet: View {
    let product: GroceryProduct?
    let verdict: ProductVerdict?
    let isWorking: Bool
    let error: String?
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if isWorking {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading the label…").font(.subheadline)
                }
            } else if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Tint.courge)
            } else if let product {
                VStack(alignment: .leading, spacing: 3) {
                    Text(product.name ?? "GroceryProduct \(product.code)")
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                    if let m = product.marque, !m.isEmpty {
                        Text(m).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if let verdict { ProductVerdictBanner(verdict: verdict) }

                if let attribution = product.attribution {
                    Text(attribution).font(.caption2).foregroundStyle(.tertiary)
                }
            }

            Button("Scan another product", action: onDismiss)
                .buttonStyle(.borderedProminent)
                .tint(Tint.betterave)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(14)
    }
}

struct ProductVerdictBanner: View {
    let verdict: ProductVerdict

    private var color: Color {
        switch verdict.status {
        case .sur: return Tint.pois
        case .aEviter: return Tint.canneberge
        case .incertain: return Tint.courge
        }
    }

    private var symbol: String {
        switch verdict.status {
        case .sur: return "checkmark.circle.fill"
        case .aEviter: return "xmark.octagon.fill"
        case .incertain: return "questionmark.circle.fill"
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
