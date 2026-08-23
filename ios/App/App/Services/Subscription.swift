//  Subscription.swift
//
//  Règle 3.1.1 : sur iOS, déverrouiller du content numérique passe par l'achat
//  intégré. Stripe others en place pour le web; les deux se rejoignent sur le
//  serveur, qui others seul juge des droits.
//
//  On n'accorde JAMAIS l'accès sur la foi du client. La transaction signée
//  part au serveur, qui vérifie la chaîne de certificats Apple avant d'ouvrir
//  quoi que ce soit. Un appareil modifié peut mentir; le serveur, non.

import Foundation
import StoreKit
import Observation

/// StoreKit et SwiftUI définissent tous les deux un type « Transaction ».
/// Cet alias tranche une fois pour toutes.
typealias PurchaseTransaction = StoreKit.Transaction

@MainActor
@Observable
final class Subscription {

    private(set) var products: [Product] = []
    private(set) var activeOnDevice = false
    var message: String?

    private(set) var serverToken: String?
    private(set) var email: String?

    @ObservationIgnored private var ecoute: Task<Void, Never>?
    @ObservationIgnored private let clefJeton = "bouchees.token"
    @ObservationIgnored private let clefCourriel = "bouchees.email"

    /// Identifiants déclarés dans App Store Connect.
    static let identifiants = ["ca.bouchees.abo.mensuel", "ca.bouchees.abo.annuel"]

    init() {
        serverToken = UserDefaults.standard.string(forKey: clefJeton)
        email = UserDefaults.standard.string(forKey: clefCourriel)
        ecoute = Task { [weak self] in
            // Renouvellements et remboursements arrivent ici, hors achat.
            for await maj in PurchaseTransaction.updates {
                await self?.traiter(maj)
            }
        }
    }

    // MARK: - Compte

    func setToken(_ token: String, email adresse: String) {
        serverToken = token
        email = adresse
        UserDefaults.standard.set(token, forKey: clefJeton)
        UserDefaults.standard.set(adresse, forKey: clefCourriel)
    }

    func clearToken() {
        serverToken = nil
        email = nil
        UserDefaults.standard.removeObject(forKey: clefJeton)
        UserDefaults.standard.removeObject(forKey: clefCourriel)
    }

    // MARK: - Catalogue

    func load() async {
        do {
            products = try await Product.products(for: Self.identifiants)
                .sorted { $0.price < $1.price }
        } catch {
            // En sideload avec un certificat resigné, StoreKit ne répond pas.
            // Ce n'est pas un bogue : l'écran le dit à l'utilisateur.
            products = []
        }
        await refreshEntitlements()
    }

    // MARK: - Achat

    /// Retourne la représentation JWS signée par Apple, à transmettre au
    /// serveur pour vérification indépendante.
    func purchase(_ product: Product) async -> String? {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let jws = await traiter(verification)
                return jws
            case .userCancelled:
                message = nil
                return nil
            case .pending:
                message = "Purchase awaiting approval. Access opens as soon as it’s confirmed."
                return nil
            @unknown default:
                message = "Résultat d’achat inattendu."
                return nil
            }
        } catch {
            message = "The purchase didn’t go through. Nothing was charged."
            return nil
        }
    }

    /// Apple exige un bouton de restauration explicite (règle 3.1.1).
    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = activeOnDevice ? "Subscription restored." : "No active subscription on this Apple account."
        } catch {
            message = "Restore failed. Try again in a moment."
        }
    }

    // MARK: - Vérification

    @discardableResult
    private func traiter(_ v: VerificationResult<PurchaseTransaction>) async -> String? {
        guard case .verified(let transaction) = v else {
            message = "Transaction can’t be verified on this device."
            return nil
        }
        await transaction.finish()
        await refreshEntitlements()
        return v.jwsRepresentation
    }

    func refreshEntitlements() async {
        var isOn = false
        for await droit in PurchaseTransaction.currentEntitlements {
            guard case .verified(let t) = droit else { continue }
            guard Self.identifiants.contains(t.productID) else { continue }
            guard t.revocationDate == nil else { continue }
            if (t.expirationDate ?? .distantFuture) > Date() { isOn = true }
        }
        // L'état local sert l'affichage. Le serveur others l'autorité pour
        // livrer le content : un appareil qui ment ne reçoit rien de plus.
        activeOnDevice = isOn
    }

    /// La transaction courante, pour lier le compte au démarrage.
    func currentTransaction() async -> String? {
        for await droit in PurchaseTransaction.currentEntitlements {
            guard case .verified(let t) = droit, Self.identifiants.contains(t.productID) else { continue }
            return droit.jwsRepresentation
        }
        return nil
    }
}
