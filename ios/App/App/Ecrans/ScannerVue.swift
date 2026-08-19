//  ScannerVue.swift
//
//  Le scanner. Impossible dans un navigateur, et probablement la fonction la
//  plus utile de l'app : vérifier un produit dans l'allée d'épicerie.
//
//  Le verdict vient du MOTEUR, jamais des étiquettes d'allergènes de la base
//  de produits — elles sont indicatives et incomplètes sur bien des articles.
//
//  Données produits : Open Food Facts, sous licence ODbL. Deux conséquences
//  respectées à la lettre : attribution affichée sur chaque fiche, et aucune
//  fusion dans notre catalogue. On consulte, on affiche, on ne conserve rien.

import SwiftUI
import AVFoundation
import UIKit

// MARK: - Capture

@MainActor
final class SessionScanner: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    @Published var code: String?
    @Published var erreur: String?

    let session = AVCaptureSession()
    private var configuree = false
    private var dernierCode: String?

    func demarrer() {
        guard !session.isRunning else { return }
        if !configuree { configurer() }
        guard configuree else { return }
        let s = session
        Task.detached(priority: .userInitiated) { s.startRunning() }
    }

    func arreter() {
        guard session.isRunning else { return }
        let s = session
        Task.detached(priority: .userInitiated) { s.stopRunning() }
    }

    func rearmer() {
        dernierCode = nil
        code = nil
        demarrer()
    }

    private func configurer() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let appareil = AVCaptureDevice.default(for: .video),
              let entree = try? AVCaptureDeviceInput(device: appareil),
              session.canAddInput(entree) else {
            erreur = "La caméra n’est pas disponible sur cet appareil."
            return
        }
        session.addInput(entree)

        let sortie = AVCaptureMetadataOutput()
        guard session.canAddOutput(sortie) else {
            erreur = "La lecture de codes-barres n’a pas pu démarrer."
            return
        }
        session.addOutput(sortie)
        sortie.setMetadataObjectsDelegate(self, queue: .main)
        sortie.metadataObjectTypes = [.ean8, .ean13, .upce, .code128]
        configuree = true
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput,
                                    didOutput objets: [AVMetadataObject],
                                    from connection: AVCaptureConnection) {
        guard let objet = objets.first as? AVMetadataMachineReadableCodeObject,
              let valeur = objet.stringValue else { return }
        Task { @MainActor in
            guard self.dernierCode != valeur else { return }
            self.dernierCode = valeur
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            self.code = valeur
            self.arreter()
        }
    }
}

struct ApercuCamera: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> VueApercu {
        let v = VueApercu()
        v.couche.session = session
        v.couche.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: VueApercu, context: Context) {}

    final class VueApercu: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var couche: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Écran

struct ScannerVue: View {
    @Environment(EtatApp.self) private var etat
    @StateObject private var scanner = SessionScanner()

    @State private var autorisation = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var enCours = false
    @State private var produit: Produit?
    @State private var verdict: VerdictProduit?
    @State private var messageErreur: String?

    var body: some View {
        NavigationStack {
            Group {
                switch autorisation {
                case .authorized: contenu
                case .denied, .restricted: refusee
                default: invitation
                }
            }
            .navigationTitle("Scanner")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onDisappear { scanner.arreter() }
    }

    private var contenu: some View {
        ZStack(alignment: .bottom) {
            ApercuCamera(session: scanner.session)
                .ignoresSafeArea()

            CadreVisee()
                .allowsHitTesting(false)

            if enCours || produit != nil || messageErreur != nil {
                FicheProduit(produit: produit, verdict: verdict,
                             enCours: enCours, erreur: messageErreur) {
                    reinitialiser()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: produit?.code)
        .onAppear { scanner.demarrer() }
        .onChange(of: scanner.code) { _, nouveau in
            guard let code = nouveau else { return }
            Task { await consulter(code) }
        }
    }

    private var invitation: some View {
        EtatVide(symbole: "barcode.viewfinder",
                 titre: "Scanner un produit",
                 message: "Pointez un code-barres : Bouchées lit la liste d’ingrédients et la passe dans le même moteur que vos recettes.",
                 titreAction: "Autoriser la caméra") {
            AVCaptureDevice.requestAccess(for: .video) { accorde in
                Task { @MainActor in
                    autorisation = accorde ? .authorized : .denied
                }
            }
        }
    }

    private var refusee: some View {
        EtatVide(symbole: "camera.fill",
                 titre: "Caméra refusée",
                 message: "Le scanner a besoin de la caméra pour lire les codes-barres. Vous pouvez l’autoriser dans Réglages.",
                 titreAction: "Ouvrir Réglages") {
            if let u = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(u)
            }
        }
    }

    // MARK: - Consultation

    private func consulter(_ code: String) async {
        enCours = true
        produit = nil
        verdict = nil
        messageErreur = nil
        defer { enCours = false }

        do {
            let p = try await etat.consulterProduit(code: code)
            produit = p
            guard let texte = p.ingredientsTexte, !texte.isEmpty else {
                messageErreur = "La base n’a pas la liste d’ingrédients de ce produit. On ne peut pas se prononcer — lisez l’étiquette."
                return
            }
            verdict = try etat.evaluerEtiquette(texte)
        } catch ErreurDepot.reseau(404) {
            messageErreur = "Ce produit n’est pas dans la base ouverte. Lisez l’étiquette — et n’hésitez pas à l’ajouter sur Open Food Facts."
        } catch {
            messageErreur = "Consultation impossible. Vérifiez votre connexion — et dans le doute, lisez l’étiquette."
        }
    }

    private func reinitialiser() {
        produit = nil
        verdict = nil
        messageErreur = nil
        scanner.rearmer()
    }
}

struct CadreVisee: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(.white.opacity(0.9), lineWidth: 3)
            .frame(width: 260, height: 165)
            .shadow(radius: 12)
            .accessibilityHidden(true)
    }
}

struct FicheProduit: View {
    let produit: Produit?
    let verdict: VerdictProduit?
    let enCours: Bool
    let erreur: String?
    let surFermeture: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if enCours {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Lecture de l’étiquette…").font(.subheadline)
                }
            } else if let erreur {
                Label(erreur, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Teinte.courge)
            } else if let produit {
                VStack(alignment: .leading, spacing: 3) {
                    Text(produit.nom ?? "Produit \(produit.code)")
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                    if let m = produit.marque, !m.isEmpty {
                        Text(m).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if let verdict { BandeauVerdictProduit(verdict: verdict) }

                if let attribution = produit.attribution {
                    Text(attribution).font(.caption2).foregroundStyle(.tertiary)
                }
            }

            Button("Scanner un autre produit", action: surFermeture)
                .buttonStyle(.borderedProminent)
                .tint(Teinte.betterave)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(14)
    }
}

struct BandeauVerdictProduit: View {
    let verdict: VerdictProduit

    private var couleur: Color {
        switch verdict.statut {
        case .sur: return Teinte.pois
        case .aEviter: return Teinte.canneberge
        case .incertain: return Teinte.courge
        }
    }

    private var symbole: String {
        switch verdict.statut {
        case .sur: return "checkmark.circle.fill"
        case .aEviter: return "xmark.octagon.fill"
        case .incertain: return "questionmark.circle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: symbole).font(.title3).foregroundStyle(couleur)
                Text(verdict.message).font(.callout.weight(.semibold))
            }

            if !verdict.ingredientsInconnus.isEmpty {
                Text("Non reconnus : \(verdict.ingredientsInconnus.joined(separator: ", ")).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(couleur.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
