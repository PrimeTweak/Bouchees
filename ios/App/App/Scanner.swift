//  Scanner.swift — lecteur de code-barres (bloc H)
//
//  La fonction la plus utile de l'app, et impossible dans Safari : on scanne
//  un produit à l'épicerie, on lit sa liste d'ingrédients, et c'est LE MOTEUR
//  qui rend le verdict — le même moteur déterministe que pour les recettes,
//  avec le même catalogue.
//
//  Données produits : Open Food Facts, sous licence ODbL. Deux conséquences
//  qu'on respecte à la lettre :
//    1. Attribution visible à l'écran du résultat.
//    2. Aucune fusion dans notre base. On consulte, on affiche, on jette.
//       L'ODbL imposerait de publier toute base dérivée en données ouvertes.

import SwiftUI
import AVFoundation

// MARK: - Capture

final class SessionScanner: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    @Published var code: String?
    @Published var erreur: String?
    let session = AVCaptureSession()
    private var dejaVu = Set<String>()

    func demarrer() {
        guard session.inputs.isEmpty else {
            if !session.isRunning { Task.detached { self.session.startRunning() } }
            return
        }
        guard let appareil = AVCaptureDevice.default(for: .video),
              let entree = try? AVCaptureDeviceInput(device: appareil),
              session.canAddInput(entree) else {
            erreur = "Caméra indisponible."
            return
        }
        session.addInput(entree)
        let sortie = AVCaptureMetadataOutput()
        guard session.canAddOutput(sortie) else { erreur = "Lecture impossible."; return }
        session.addOutput(sortie)
        sortie.setMetadataObjectsDelegate(self, queue: .main)
        sortie.metadataObjectTypes = [.ean8, .ean13, .upce, .code128]
        Task.detached { self.session.startRunning() }
    }

    func arreter() {
        if session.isRunning { Task.detached { self.session.stopRunning() } }
    }

    func metadataOutput(_ o: AVCaptureMetadataOutput,
                        didOutput objets: [AVMetadataObject],
                        from c: AVCaptureConnection) {
        guard let m = objets.first as? AVMetadataMachineReadableCodeObject,
              let valeur = m.stringValue, !dejaVu.contains(valeur) else { return }
        dejaVu.insert(valeur)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        code = valeur
        arreter()
    }

    func rearmer() {
        dejaVu.removeAll()
        code = nil
        demarrer()
    }
}

struct AperçuCamera: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        let couche = AVCaptureVideoPreviewLayer(session: session)
        couche.videoGravity = .resizeAspectFill
        couche.frame = UIScreen.main.bounds
        v.layer.addSublayer(couche)
        return v
    }
    func updateUIView(_ v: UIView, context: Context) {
        (v.layer.sublayers?.first as? AVCaptureVideoPreviewLayer)?.frame = v.bounds
    }
}

// MARK: - Produit consulté

struct Produit: Codable {
    let code: String
    let nom: String?
    let marque: String?
    let ingredientsTexte: String?
    let etiquettesAllergenes: [String]
    let attribution: String
}

@MainActor
final class ServiceProduit: ObservableObject {
    @Published var enCours = false
    @Published var produit: Produit?
    @Published var verdict: VerdictProduit?
    @Published var erreur: String?

    /// Consultation à la demande. Rien n'est écrit sur l'appareil : ni cache
    /// disque, ni base locale. Contrainte ODbL respectée, et vie privée en
    /// prime — on ne construit pas l'historique d'épicerie de personne.
    func consulter(code: String, base: URL, pont: Pont?,
                   evites: [String], ageMois: Int) async {
        enCours = true; erreur = nil; produit = nil; verdict = nil
        defer { enCours = false }
        do {
            var req = URLRequest(url: base.appendingPathComponent("api/produit")
                .appending(queryItems: [URLQueryItem(name: "code", value: code)]))
            req.timeoutInterval = 12
            let (data, rep) = try await URLSession.shared.data(for: req)
            guard let http = rep as? HTTPURLResponse else { throw ErreurProduit.reseau }
            if http.statusCode == 404 {
                erreur = "Ce produit n'est pas dans la base ouverte. Lisez l'étiquette — et n'hésitez pas à l'ajouter sur Open Food Facts."
                return
            }
            guard http.statusCode == 200 else { throw ErreurProduit.reseau }
            let p = try JSONDecoder().decode(Produit.self, from: data)
            produit = p

            guard let texte = p.ingredientsTexte, !texte.isEmpty else {
                erreur = "La base n'a pas la liste d'ingrédients de ce produit. On ne peut pas se prononcer — lisez l'étiquette."
                return
            }
            // Le verdict vient du moteur, jamais des étiquettes de la base :
            // elles sont indicatives et incomplètes sur bien des produits.
            verdict = try await pont?.evaluerProduit(ingredientsBruts: texte,
                                                     allergenesEvites: evites,
                                                     ageMois: ageMois)
        } catch {
            erreur = "Consultation impossible. Vérifiez votre connexion — et dans le doute, lisez l'étiquette."
        }
    }

    enum ErreurProduit: Error { case reseau }
}

// MARK: - Écran

struct ScannerVue: View {
    @EnvironmentObject var etat: EtatApp
    @StateObject private var scanner = SessionScanner()
    @StateObject private var service = ServiceProduit()
    @State private var autorisation: AVAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            Group {
                switch autorisation {
                case .authorized:
                    contenuScanner
                case .denied, .restricted:
                    MessageCentre(
                        titre: "Caméra refusée",
                        corps: "Le scanner a besoin de la caméra pour lire les codes-barres. Vous pouvez l'autoriser dans Réglages.",
                        bouton: "Ouvrir Réglages") {
                            if let u = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(u)
                            }
                        }
                default:
                    MessageCentre(
                        titre: "Scanner un produit",
                        corps: "Pointez un code-barres : Bouchées lit la liste d'ingrédients et la passe dans le même moteur que vos recettes.",
                        bouton: "Autoriser la caméra") { demanderAcces() }
                }
            }
            .navigationTitle("Scanner")
        }
        .task { autorisation = AVCaptureDevice.authorizationStatus(for: .video) }
        .onDisappear { scanner.arreter() }
    }

    private var contenuScanner: some View {
        ZStack(alignment: .bottom) {
            AperçuCamera(session: scanner.session).ignoresSafeArea()
            CadreVisee()
            if service.enCours || service.produit != nil || service.erreur != nil {
                FicheProduit(service: service) { scanner.rearmer() }
                    .transition(.move(edge: .bottom))
            }
        }
        .onAppear { scanner.demarrer() }
        .onChange(of: scanner.code) { _, nouveau in
            guard let c = nouveau else { return }
            Task {
                await service.consulter(code: c, base: Reglages.baseServeur, pont: nil,
                                        evites: etat.contenu.profilActif.allergenes,
                                        ageMois: etat.contenu.profilActif.ageMois)
            }
        }
    }

    private func demanderAcces() {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            Task { @MainActor in autorisation = ok ? .authorized : .denied }
        }
    }
}

struct CadreVisee: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .strokeBorder(.white.opacity(0.9), lineWidth: 3)
            .frame(width: 260, height: 160)
            .shadow(radius: 12)
            .accessibilityHidden(true)
    }
}

struct FicheProduit: View {
    @ObservedObject var service: ServiceProduit
    let surFermeture: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if service.enCours {
                ProgressView("Lecture de l'étiquette…")
            } else if let e = service.erreur {
                Label(e, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color("Courge"))
            } else if let p = service.produit {
                Text(p.nom ?? "Produit \(p.code)").font(.title3.weight(.bold))
                if let m = p.marque { Text(m).font(.footnote).foregroundStyle(.secondary) }

                if let v = service.verdict {
                    BandeauVerdict(verdict: v)
                    if !v.ingredientsInconnus.isEmpty {
                        Text("Ingrédients non reconnus : \(v.ingredientsInconnus.joined(separator: ", ")). Dans le doute, lisez l'étiquette.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                // Attribution ODbL — obligatoire, et à sa place.
                Text(p.attribution).font(.caption2).foregroundStyle(.tertiary)
            }
            Button("Scanner un autre produit", action: surFermeture)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .padding(14)
    }
}

struct BandeauVerdict: View {
    let verdict: VerdictProduit

    private var couleur: Color {
        switch verdict.statut {
        case "sur": return Color("Pois")
        case "a_eviter": return Color("Canneberge")
        default: return Color("Courge")
        }
    }
    private var symbole: String {
        switch verdict.statut {
        case "sur": return "checkmark.circle.fill"
        case "a_eviter": return "xmark.octagon.fill"
        default: return "questionmark.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbole).foregroundStyle(couleur).font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(verdict.message).font(.callout.weight(.semibold))
                if !verdict.allergenesTrouves.isEmpty {
                    Text(verdict.allergenesTrouves.joined(separator: ", "))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(couleur.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct MessageCentre: View {
    let titre: String, corps: String, bouton: String
    let action: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "barcode.viewfinder").font(.system(size: 44))
                .foregroundStyle(Color("Betterave"))
            Text(titre).font(.title2.weight(.bold))
            Text(corps).multilineTextAlignment(.center)
                .foregroundStyle(.secondary).padding(.horizontal, 28)
            Button(bouton, action: action).buttonStyle(.borderedProminent)
        }
    }
}
