//  Abonnement.swift — StoreKit 2 (bloc I)
//
//  Règle 3.1.1 : sur iOS, déverrouiller du contenu numérique passe par l'achat
//  intégré. Stripe reste en place pour le web; les deux se rejoignent sur le
//  serveur, qui reste seul juge des droits.
//
//  Point important : on n'accorde JAMAIS l'accès sur la foi du client. La
//  transaction signée part au serveur, qui vérifie la chaîne de certificats
//  Apple avant d'ouvrir quoi que ce soit. Un `Transaction.currentEntitlements`
//  qui dit oui sur un appareil jailbreaké ne suffit pas.

import Foundation
import StoreKit
import SwiftUI

// StoreKit et SwiftUI définissent tous les deux un type « Transaction ».
// Cet alias tranche une fois pour toutes, au lieu de qualifier chaque usage.
typealias TransactionAchat = StoreKit.Transaction

@MainActor
final class Abonnement: ObservableObject {
    @Published private(set) var produits: [Product] = []
    @Published private(set) var estActif = false
    @Published private(set) var enCours = false
    @Published var message: String?

    private(set) var jetonServeur: String?
    private var ecoute: Task<Void, Never>?

    /// Identifiants déclarés dans App Store Connect.
    static let identifiants = ["ca.bouchees.abo.mensuel", "ca.bouchees.abo.annuel"]

    init() {
        ecoute = Task.detached { [weak self] in
            // Les renouvellements et remboursements arrivent ici, hors achat.
            for await maj in TransactionAchat.updates {
                await self?.traiter(maj)
            }
        }
    }
    // Pas de cleanup dans deinit : accéder à une propriété depuis le deinit
    // d'une classe @MainActor est refusé selon la version du compilateur.
    // La tâche vit aussi longtemps que l'objet, ce qui est le comportement voulu.

    func charger() async {
        do {
            produits = try await Product.products(for: Self.identifiants)
                .sorted { $0.price < $1.price }
        } catch {
            message = "Les abonnements n'ont pas pu être chargés. Réessayez plus tard."
        }
        await verifierDroits()
    }

    /// Achat. Le résultat n'est pas cru sur parole : il est vérifié
    /// localement, puis envoyé au serveur pour vérification indépendante.
    func acheter(_ produit: Product) async {
        enCours = true
        defer { enCours = false }
        do {
            let resultat = try await produit.purchase()
            switch resultat {
            case .success(let verification):
                await traiter(verification)
            case .userCancelled:
                message = nil
            case .pending:
                message = "Achat en attente d'approbation. L'accès s'ouvrira dès qu'il sera confirmé."
            @unknown default:
                message = "Résultat d'achat inattendu."
            }
        } catch {
            message = "L'achat n'a pas abouti. Rien n'a été facturé."
        }
    }

    /// Apple exige un bouton de restauration explicite (règle 3.1.1).
    func restaurer() async {
        enCours = true
        defer { enCours = false }
        do {
            try await AppStore.sync()
            await verifierDroits()
            message = estActif ? "Abonnement restauré." : "Aucun abonnement actif sur ce compte Apple."
        } catch {
            message = "La restauration a échoué. Réessayez dans un moment."
        }
    }

    func presenterAchat() async {
        if produits.isEmpty { await charger() }
        NotificationCenter.default.post(name: .ouvrirPaywall, object: nil)
    }

    // MARK: - Vérification

    private func traiter(_ v: VerificationResult<TransactionAchat>) async {
        guard case .verified(let transaction) = v else {
            // Signature locale invalide : on ne touche à rien.
            message = "Transaction non vérifiable sur cet appareil."
            return
        }
        await transmettreAuServeur(v)
        await transaction.finish()
        await verifierDroits()
    }

    private func verifierDroits() async {
        var actif = false
        for await droit in TransactionAchat.currentEntitlements {
            guard case .verified(let t) = droit else { continue }
            if Self.identifiants.contains(t.productID),
               t.revocationDate == nil,
               (t.expirationDate ?? .distantFuture) > Date() {
                actif = true
                await transmettreAuServeur(droit)
            }
        }
        // L'état local sert l'affichage; le serveur reste l'autorité pour
        // livrer le contenu. Un appareil qui ment ne reçoit rien de plus.
        estActif = actif
    }

    /// Envoie la représentation JWS signée par Apple. Le serveur vérifie la
    /// chaîne x5c jusqu'à la racine Apple épinglée avant d'accorder l'accès.
    private func transmettreAuServeur(_ v: VerificationResult<TransactionAchat>) async {
        guard let jeton = jetonServeur else { return }   // pas connecté : rien à lier
        let jws = v.jwsRepresentation
        var req = URLRequest(url: Reglages.baseServeur.appendingPathComponent("api/apple/transaction"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(jeton)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["signedTransaction": jws])
        do {
            let (data, rep) = try await URLSession.shared.data(for: req)
            if let http = rep as? HTTPURLResponse, http.statusCode == 409 {
                message = "Cet abonnement est déjà lié à un autre compte Bouchées."
                return
            }
            if let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let abonne = o["abonne"] as? Bool {
                estActif = abonne
            }
        } catch {
            // Hors ligne : le droit local tient jusqu'à la prochaine synchro.
            // Le contenu déjà téléchargé reste accessible; le nouveau, non.
        }
    }

    func lierCompte(jeton: String) async {
        jetonServeur = jeton
        await verifierDroits()
    }
}

extension Notification.Name {
    static let ouvrirPaywall = Notification.Name("bouchees.ouvrirPaywall")
}

// MARK: - Paywall natif

struct PaywallVue: View {
    @EnvironmentObject var etat: EtatApp
    @ObservedObject var abonnement: Abonnement
    @Environment(\.dismiss) private var fermer

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("De nouvelles recettes chaque mois")
                        .font(.largeTitle.weight(.heavy))
                    Text("Ciblées là où votre profil manque de choix — pas au hasard.")
                        .foregroundStyle(.secondary)

                    ComparatifVue()

                    ForEach(abonnement.produits, id: \.id) { p in
                        Button {
                            Task { await abonnement.acheter(p) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(p.displayName).font(.headline)
                                    Text(p.description).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(p.displayPrice).font(.headline)
                            }
                            .padding(14)
                        }
                        .buttonStyle(.bordered)
                        .disabled(abonnement.enCours)
                    }

                    Button("Restaurer mes achats") {
                        Task { await abonnement.restaurer() }
                    }
                    .font(.footnote)

                    if let m = abonnement.message {
                        Text(m).font(.footnote).foregroundStyle(Color("Courge"))
                    }

                    // Mentions exigées par Apple pour un abonnement auto-renouvelable.
                    Text("""
                    L'abonnement se renouvelle automatiquement à moins d'être annulé au moins 24 h avant la fin de la période. \
                    Le paiement est porté à votre compte Apple à la confirmation. Gérez ou annulez dans les réglages de votre compte Apple.
                    """)
                    .font(.caption2).foregroundStyle(.tertiary)

                    HStack(spacing: 16) {
                        Link("Conditions", destination: Reglages.conditions)
                        Link("Confidentialité", destination: Reglages.confidentialite)
                    }
                    .font(.caption)
                }
                .padding(20)
            }
            .navigationTitle("Abonnement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { fermer() }
                }
            }
        }
    }
}

struct ComparatifVue: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Bloc(titre: "Toujours gratuit", lignes: [
                "Les échanges d'ingrédients pour chaque allergène",
                "Les repères d'âge et de texture",
                "Le scanner de produits",
                "Les profils de vos enfants",
                "Les recettes de départ"
            ], accent: Color("Pois"))
            Bloc(titre: "Avec l'abonnement", lignes: [
                "Un nouveau lot de recettes chaque mois",
                "Ciblé sur les profils que vous avez créés",
                "Tous les lots précédents"
            ], accent: Color("Betterave"))
        }
    }

    struct Bloc: View {
        let titre: String, lignes: [String], accent: Color
        var body: some View {
            VStack(alignment: .leading, spacing: 7) {
                Text(titre).font(.headline).foregroundStyle(accent)
                ForEach(lignes, id: \.self) { l in
                    Label(l, systemImage: "checkmark").font(.footnote)
                        .labelStyle(.titleAndIcon)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
