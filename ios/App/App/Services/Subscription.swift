// Stripe stays in place for the web; the two meet on the serveur, qui others
// seul juge des droits. Access is NEVER granted on the client's word.

import Foundation
import StoreKit
import Observation

/// StoreKit and SwiftUI both define a type named Transaction.
/// Cet alias tranche une fois pour toutes.
typealias PurchaseTransaction = StoreKit.Transaction

@MainActor
@Observable
final class Subscription {

    private(set) var products: [Product] = []

    /// The price as the App Store gives it, in the user's currency and store.
    /// A hard-coded "$4.99" is wrong the moment a price differs by country,
    /// a promotion runs, or the price changes — and Apple refuses that.
    var displayPrice: String? { products.first?.displayPrice }

    /// The renewal period, spelled by StoreKit rather than by us.
    var displayPeriod: String? {
        guard let unit = products.first?.subscription?.subscriptionPeriod.unit else { return nil }
        switch unit {
        case .day: return String(localized: "day")
        case .week: return String(localized: "week")
        case .month: return String(localized: "month")
        case .year: return String(localized: "year")
        @unknown default: return nil
        }
    }
    private(set) var activeOnDevice = false
    var message: String?

    private(set) var serverToken: String?
    private(set) var email: String?

    @ObservationIgnored private var ecoute: Task<Void, Never>?
    @ObservationIgnored private let clefJeton = "bouchees.token"
    @ObservationIgnored private let clefCourriel = "bouchees.email"

    /// Identifiers declared in App Store Connect.
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
            // Sideloaded with a resigned certificate, StoreKit does not answer.
            // That is not a bug: the screen says so to the user.
            products = []
        }
        await refreshEntitlements()
    }

    // MARK: - Achat

    /// Returns the JWS representation signed by Apple, to be passed to the
    /// server for independent verification.
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
                message = String(localized: "Unexpected purchase result.")
                return nil
            }
        } catch {
            message = "The purchase didn’t go through. Nothing was charged."
            return nil
        }
    }

    /// Apple requires an explicit restore button (rule 3.1.1).
    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = activeOnDevice ? "Subscription restored." : "No active subscription on this Apple account."
        } catch {
            message = "Restore failed. Try again in a moment."
        }
    }

    // MARK: - Verification

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
        // Local state drives the display. The server keeps the authority to
        // deliver content: a device that lies receives nothing extra.
        activeOnDevice = isOn
    }

    /// The current transaction, used to link the account at startup.
    func currentTransaction() async -> String? {
        for await droit in PurchaseTransaction.currentEntitlements {
            guard case .verified(let t) = droit, Self.identifiants.contains(t.productID) else { continue }
            return droit.jwsRepresentation
        }
        return nil
    }
}
