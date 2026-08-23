//  AppState.swift
//
//  L'état central. Une seule source de vérité pour les profiles, le recipes et
//  les résultats adaptés — les vues ne calculent rien, elles affichent.

import Foundation
import Observation

@MainActor
@Observable
final class AppState {

    // MARK: - État exposé

    var profiles: [ChildProfile] = []
    var activeProfileID: String?
    var familyMode = false

    private(set) var recipes: [Recipe] = []
    private(set) var adapted: [AdaptedRecipe] = []
    private(set) var batches: [Batch] = []

    private(set) var isLoading = true
    private(set) var isOffline = false
    private(set) var fatalError: String?
    private(set) var syncMessage: String?
    private(set) var lastSync: Date?

    var subscribed = false

    // MARK: - Dépendances

    private var moteur: RecipeEngine?
    private let local = LocalStore()
    private let serveur = RemoteStore()
    let subscription = Subscription()
    let saved = SavedRecipes()

    /// Agrégats de notes par recipe, rafraîchis avec le recipes.
    private(set) var notes: [String: RatingSummary] = [:]
    private(set) var topRated: [Recipe] = []
    private(set) var ratingThreshold = 5
    private(set) var currentWeek: String?

    // MARK: - ChildProfile courant

    var activeProfile: ChildProfile {
        if familyMode && profiles.count > 1 { return ChildProfile.famille(profiles) }
        return profiles.first { $0.id == activeProfileID } ?? profiles.first ?? .defaut
    }

    var needsOnboarding: Bool { profiles.isEmpty }

    // MARK: - Démarrage

    func start() async {
        isLoading = true
        defer { isLoading = false }

        profiles = local.lireProfils()
        activeProfileID = profiles.first?.id

        do {
            let m = try RecipeEngine()
            try m.chargerDonnees(
                ingredients: try Resources.data("ingredients", "json"),
                substitutions: try Resources.data("substitutions", "json"),
                base: try Resources.data("base", "json"))
            moteur = m
        } catch {
            // Sans moteur, l'app ne peut rien affirmer. On le dit franchement
            // plutôt que d'afficher des recipes non vérifiées.
            fatalError = error.localizedDescription
            return
        }

        chargerCorpusLocal()
        recompute()
        await sync()
    }

    /// Corpus téléchargé s'il existe, sinon les batches embarqués dans l'app.
    private func chargerCorpusLocal() {
        if let sauvegarde = local.lireCorpus(), !sauvegarde.isEmpty {
            recipes = sauvegarde
        } else {
            var embarquees: [Recipe] = []
            for url in Resources.lotsEmbarques() {
                if let d = try? Data(contentsOf: url),
                   let r = try? JSONDecoder().decode([Recipe].self, from: d) {
                    embarquees.append(contentsOf: r)
                }
            }
            recipes = embarquees.sorted { $0.name < $1.name }
        }
        if let l = local.lireLots() { batches = l }
    }

    // MARK: - Synchronisation

    func sync() async {
        guard fatalError == nil else { return }
        let token = subscription.serverToken
        do {
            let manif = try await serveur.manifeste(token: token)
            batches = manif.batches
            currentWeek = manif.currentWeek
            local.ecrireLots(manif.batches)
            if let a = manif.subscribed { subscribed = a }

            let rep = try await serveur.recipes(token: token)
            if !rep.recipes.isEmpty {
                recipes = rep.recipes
                local.ecrireCorpus(rep.recipes)
            }
            isOffline = false
            syncMessage = nil
            lastSync = Date()
            recompute()
            await loadRatings()
            await prunePhotos()
        } catch {
            isOffline = true
            syncMessage = recipes.isEmpty
                ? "No connection and nothing stored. Connect once to download the recipes."
                : "Offline — your downloaded recipes are still available."
        }
    }

    // MARK: - Adaptation

    func recompute() {
        guard let moteur, moteur.pret, !recipes.isEmpty else {
            adapted = []
            return
        }
        do {
            adapted = try moteur.adapter(recipes, pour: activeProfile)
        } catch {
            adapted = []
            syncMessage = "Le moteur n’a pas pu adapter les recipes : \(error.localizedDescription)"
        }
    }

    /// Paire recipe + résultat, dans l'ordre du recipes.
    var pairs: [(recipe: Recipe, result: AdaptedRecipe)] {
        let parId = Dictionary(uniqueKeysWithValues: adapted.map { ($0.id, $0) })
        return recipes.compactMap { r in
            guard let res = parId[r.id] else { return nil }
            return (r, res)
        }
    }

    func result(pour id: String) -> AdaptedRecipe? {
        adapted.first { $0.id == id }
    }

    func recipe(pour id: String) -> Recipe? {
        recipes.first { $0.id == id }
    }

    // MARK: - Profils

    func save(_ profile: ChildProfile) {
        if let i = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[i] = profile
        } else {
            profiles.append(profile)
            activeProfileID = profile.id
        }
        local.ecrireProfils(profiles)
        recompute()
    }

    func remove(_ profile: ChildProfile) {
        profiles.removeAll { $0.id == profile.id }
        if activeProfileID == profile.id { activeProfileID = profiles.first?.id }
        if profiles.count < 2 { familyMode = false }
        local.ecrireProfils(profiles)
        recompute()
    }

    func select(_ id: String) {
        activeProfileID = id
        familyMode = false
        recompute()
    }

    func toggleFamilyMode() {
        familyMode.toggle()
        recompute()
    }

    // MARK: - Notes

    /// Les agrégats de tout ce qui est visible, en un appel.
    func loadRatings() async {
        let ids = (recipes.map(\.id) + saved.recipes.map(\.id))
        guard !ids.isEmpty else { return }
        if let a = try? await serveur.notes(ids: Array(Set(ids)), token: subscription.serverToken) {
            notes = a
        }
    }

    /// Noter demande un compte : sans ça, rien n'empêche une même personne de
    /// voter cent fois. L'affichage se met à jour tout de suite, puis le
    /// serveur confirme — c'est lui qui fait foi.
    func rate(_ recetteId: String, note: Int?) async {
        guard let token = subscription.serverToken else {
            syncMessage = "Sign in from Settings to rate a recipe."
            return
        }
        do {
            let a = try await serveur.rate(recetteId, note: note, token: token)
            notes[recetteId] = a
        } catch {
            syncMessage = "The rating couldn’t be saved. Try again later."
        }
    }

    func loadTopRated() async {
        if let r = try? await serveur.topRated(token: subscription.serverToken) {
            topRated = r.recipes
            ratingThreshold = r.threshold
        }
    }

    /// Adapte une recipe qui n'est pas dans le recipes courant — une favorite
    /// out de la fenêtre, ou une entrée du ranking.
    func resultFor(_ recipe: Recipe) -> AdaptedRecipe? {
        if let deja = adapted.first(where: { $0.id == recipe.id }) { return deja }
        return try? moteur?.adapter(recipe, pour: activeProfile)
    }

    func pairFor(pour id: String) -> (recipe: Recipe, result: AdaptedRecipe)? {
        let source = recipes.first { $0.id == id }
            ?? topRated.first { $0.id == id }
            ?? saved.recipes.first { $0.id == id }
        guard let r = source, let res = resultFor(r) else { return nil }
        return (r, res)
    }

    /// Les semaines tournent : les photos hors fenêtre et hors saved n'ont
    /// plus à occuper le disque.
    private func prunePhotos() async {
        var garder = Set<String>()
        for r in recipes + saved.recipes + topRated {
            if let f = r.image { garder.insert(f) }
        }
        await PhotoCache.partage.nettoyer(garder: garder)
    }

    // MARK: - Références

    var knownAllergens: [Allergen] { moteur?.base?.allergens ?? [] }

    func allergenName(_ id: String) -> String { moteur?.allergenName(id) ?? id }

    func allergenNames(_ ids: [String]) -> [String] { moteur?.allergenNames(ids) ?? ids }

    func definition(_ id: String) -> IngredientDefinition? { moteur?.catalogue[id] }

    func stage(pour ageMonths: Int) -> TextureStage? { try? moteur?.stage(pour: ageMonths) }

    // MARK: - Scanner

    func evaluateLabel(_ texte: String) throws -> ProductVerdict {
        guard let moteur else { throw EngineError.exception("moteur indisponible") }
        return try moteur.evaluateLabel(texte, evites: activeProfile.allergens)
    }

    func lookUpProduct(code: String) async throws -> GroceryProduct {
        try await serveur.product(code: code, token: subscription.serverToken)
    }

    // MARK: - Compte

    func signIn(email: String) async throws {
        let r = try await serveur.connexion(email: email)
        subscription.setToken(r.token, email: r.email)
        subscribed = r.subscribed ?? false
        await subscription.refreshEntitlements()
        await sync()
    }

    func linkPurchase(_ jws: String) async {
        guard let token = subscription.serverToken else { return }
        if let r = try? await serveur.lierTransaction(jws, token: token), let a = r.subscribed {
            subscribed = a
            await sync()
        }
    }

    func signOut() async {
        subscription.clearToken()
        subscribed = false
        await sync()
    }

    // MARK: - Lots

    var lockedBatches: [Batch] { batches.filter { !$0.unlocked } }

    var lotLePlusRecentDeverrouille: Batch? {
        batches.filter(\.unlocked).sorted { $0.id < $1.id }.last
    }
}

// MARK: - Formatage partagé

enum Format {
    /// « lait, œufs et arachides » plutôt que « lait, œufs, arachides ».
    static func liste(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " et " + (items.last ?? "")
    }

    static func age(_ mois: Int) -> String {
        if mois < 24 { return "\(mois) mois" }
        let ans = mois / 12
        let others = mois % 12
        return others == 0 ? "\(ans) ans" : "\(ans) ans \(others) mois"
    }
}
