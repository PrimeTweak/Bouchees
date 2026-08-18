//  PontMoteur.swift — le pont entre le natif et le moteur (bloc H)
//
//  Deux directions :
//    Swift → JS : appeler adapterRecette() sur une liste d'ingrédients venue
//                 du scanner, et récupérer un verdict structuré.
//    JS → Swift : le web demande d'ouvrir le paywall StoreKit (obligatoire :
//                 un paiement Apple ne peut pas passer par une page web).
//
//  C'est cette intégration qui distingue une app d'un signet. Le scanner est
//  natif, le verdict vient du moteur testé, l'affichage est natif.

import SwiftUI
import WebKit
import UIKit

// MARK: - Verdict rendu au natif

struct VerdictProduit: Codable {
    let statut: String            // "sur" | "a_eviter" | "incertain"
    let allergenesTrouves: [String]
    let ingredientsInconnus: [String]
    let message: String
}

// MARK: - Le pont

@MainActor
final class Pont: NSObject, ObservableObject, @preconcurrency WKScriptMessageHandler, WKNavigationDelegate {
    let vueWeb: WKWebView
    @Published var pret = false
    var surDemandeAbonnement: (() -> Void)?

    override init() {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        // Aucun contenu distant : tout est local, donc rien à injecter.
        config.suppressesIncrementalRendering = false
        vueWeb = WKWebView(frame: .zero, configuration: config)
        super.init()
        config.userContentController.add(self, name: "bouchees")
        vueWeb.navigationDelegate = self
        vueWeb.allowsBackForwardNavigationGestures = false
        vueWeb.isOpaque = false
        vueWeb.backgroundColor = UIColor(named: "Fond")
    }

    func charger(dossier: URL) {
        let index = dossier.appendingPathComponent("index.html")
        guard FileManager.default.fileExists(atPath: index.path) else { return }
        vueWeb.loadFileURL(index, allowingReadAccessTo: dossier)
    }

    func webView(_ w: WKWebView, didFinish nav: WKNavigation!) { pret = true }

    /// Messages venus du JS. Un seul canal, une liste fermée d'actions.
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let corps = message.body as? [String: Any],
              let action = corps["action"] as? String else { return }
        Task { @MainActor in
            switch action {
            case "abonnement":
                self.surDemandeAbonnement?()
            case "hapticSucces":
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case "hapticAvertissement":
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            default:
                break   // action inconnue : ignorée, jamais évaluée
            }
        }
    }

    /// Passe une liste d'ingrédients bruts (issue d'une étiquette scannée) au
    /// moteur JS, qui la normalise et dérive les allergènes avec le catalogue.
    /// Le natif ne décide RIEN : il pose la question et affiche la réponse.
    func evaluerProduit(ingredientsBruts: String,
                        allergenesEvites: [String],
                        ageMois: Int) async throws -> VerdictProduit {
        let charge: [String: Any] = [
            "texte": ingredientsBruts,
            "evites": allergenesEvites,
            "ageMois": ageMois
        ]
        let json = String(data: try JSONSerialization.data(withJSONObject: charge), encoding: .utf8)!
        let script = "window.evaluerProduitScanne(\(json))"
        let brut = try await vueWeb.evaluateJavaScript(script)
        guard let dict = brut as? [String: Any] else {
            throw ErreurPont.reponseInattendue
        }
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(VerdictProduit.self, from: data)
    }

    /// Applique le profil actif dans le moteur (les profils vivent côté natif
    /// pour survivre à un vidage de cache web).
    func appliquerProfil(nom: String, ageMois: Int, allergenes: [String]) {
        let charge: [String: Any] = ["nom": nom, "ageMois": ageMois, "allergenes": allergenes]
        guard let d = try? JSONSerialization.data(withJSONObject: charge),
              let json = String(data: d, encoding: .utf8) else { return }
        vueWeb.evaluateJavaScript("window.appliquerProfilNatif(\(json))")
    }

    func informerAbonnement(actif: Bool) {
        vueWeb.evaluateJavaScript("window.majAbonnementNatif(\(actif ? "true" : "false"))")
    }

    enum ErreurPont: Error { case reponseInattendue }
}

// MARK: - Enveloppe SwiftUI

struct PontMoteur: UIViewRepresentable {
    let dossier: URL
    @EnvironmentObject var etat: EtatApp

    func makeUIView(context: Context) -> WKWebView {
        let pont = context.coordinator
        pont.surDemandeAbonnement = { [weak etat] in
            Task { await etat?.abonnement.presenterAchat() }
        }
        pont.charger(dossier: dossier)
        return pont.vueWeb
    }

    func updateUIView(_ v: WKWebView, context: Context) {
        context.coordinator.informerAbonnement(actif: etat.abonne)
    }

    func makeCoordinator() -> Pont { Pont() }
}
