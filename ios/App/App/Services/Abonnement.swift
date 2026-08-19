//  Abonnement.swift
//
//  Règle 3.1.1 : sur iOS, déverrouiller du contenu numérique passe par l'achat
//  intégré. Stripe reste en place pour le web; les deux se rejoignent sur le
//  serveur, qui reste seul juge des droits.
//
//  On n'accorde JAMAIS l'accès sur la foi du client. La transaction signée
//  part au serveur, qui vérifie la chaîne de certificats Apple avant d'ouvrir
//  quoi que ce soit. Un appareil modifié peut mentir; le serveur, non.

import Foundation
import StoreKit
import Observation

/// StoreKit et SwiftUI définissent tous les deux un type « Transaction ».
/// Cet alias tranche une fois pour toutes.
typealias TransactionAchat = StoreKit.Transaction

@MainActor
@Observable
final class Abonnement {

    private(set) var produits: [Product] = []
    private(set) var actifLocalement = false
    var message: String?

    private(set) var jetonServeur: String?
    private(set) var courriel: String?

    @ObservationIgnored private var ecoute: Task<Void, Never>?
    @ObservationIgnored private let clefJeton = "bouchees.jeton"
    @ObservationIgnored private let clefCourriel = "bouchees.courriel"

    /// Identifiants déclarés dans App Store Connect.
    static let identifiants = ["ca.bouchees.abo.mensuel", "ca.bouchees.abo.annuel"]

    init() {
        jetonServeur = UserDefaults.standard.string(forKey: clefJeton)
        courriel = UserDefaults.standard.string(forKey: clefCourriel)
        ecoute = Task { [weak self] in
            // Renouvellements et remboursements arrivent ici, hors achat.
            for await maj in TransactionAchat.updates {
                await self?.traiter(maj)
            }
        }
    }

    // MARK: - Compte

    func definirJeton(_ jeton: String, courriel adresse: String) {
        jetonServeur = jeton
        courriel = adresse
        UserDefaults.standard.set(jeton, forKey: clefJeton)
        UserDefaults.standard.set(adresse, forKey: clefCourriel)
    }

    func oublierJeton() {
        jetonServeur = nil
        courriel = nil
        UserDefaults.standard.removeObject(forKey: clefJeton)
        UserDefaults.standard.removeObject(forKey: clefCourriel)
    }

    // MARK: - Catalogue

    func charger() async {
        do {
            produits = try await Product.products(for: Self.identifiants)
                .sorted { $0.price < $1.price }
        } catch {
            // En sideload avec un certificat resigné, StoreKit ne répond pas.
            // Ce n'est pas un bogue : l'écran le dit à l'utilisateur.
            produits = []
        }
        await verifierDroits()
    }

    // MARK: - Achat

    /// Retourne la représentation JWS signée par Apple, à transmettre au
    /// serveur pour vérification indépendante.
    func acheter(_ produit: Product) async -> String? {
        do {
            let resultat = try await produit.purchase()
            switch resultat {
            case .success(let verification):
                let jws = await traiter(verification)
                return jws
            case .userCancelled:
                message = nil
                return nil
            case .pending:
                message = "Achat en attente d’approbation. L’accès s’ouvrira dès qu’il sera confirmé."
                return nil
            @unknown default:
                message = "Résultat d’achat inattendu."
                return nil
            }
        } catch {
            message = "L’achat n’a pas abouti. Rien n’a été facturé."
            return nil
        }
    }

    /// Apple exige un bouton de restauration explicite (règle 3.1.1).
    func restaurer() async {
        do {
            try await AppStore.sync()
            await verifierDroits()
            message = actifLocalement ? "Abonnement restauré." : "Aucun abonnement actif sur ce compte Apple."
        } catch {
            message = "La restauration a échoué. Réessayez dans un moment."
        }
    }

    // MARK: - Vérification

    @discardableResult
    private func traiter(_ v: VerificationResult<TransactionAchat>) async -> String? {
        guard case .verified(let transaction) = v else {
            message = "Transaction non vérifiable sur cet appareil."
            return nil
        }
        await transaction.finish()
        await verifierDroits()
        return v.jwsRepresentation
    }

    func verifierDroits() async {
        var actif = false
        for await droit in TransactionAchat.currentEntitlements {
            guard case .verified(let t) = droit else { continue }
            guard Self.identifiants.contains(t.productID) else { continue }
            guard t.revocationDate == nil else { continue }
            if (t.expirationDate ?? .distantFuture) > Date() { actif = true }
        }
        // L'état local sert l'affichage. Le serveur reste l'autorité pour
        // livrer le contenu : un appareil qui ment ne reçoit rien de plus.
        actifLocalement = actif
    }

    /// La transaction courante, pour lier le compte au démarrage.
    func transactionCourante() async -> String? {
        for await droit in TransactionAchat.currentEntitlements {
            guard case .verified(let t) = droit, Self.identifiants.contains(t.productID) else { continue }
            return droit.jwsRepresentation
        }
        return nil
    }
}
