//  AppState.swift
//
//  The central state. One source of truth for profiles, recipes and adapted
//  results — the views compute nothing, they display.

import Foundation
import Observation

@MainActor
@Observable
final class AppState {

    // MARK: - Exposed state

    var profiles: [ChildProfile] = []
    var activeProfileID: String?
    var familyMode = false

    /// Light, dark, or whatever the phone is set to. System is the default.
    var theme: AppTheme = .system {
        didSet { local.writeTheme(theme) }
    }

    private(set) var recipes: [Recipe] = []
    private(set) var adapted: [AdaptedRecipe] = []

    /// How many recipes come out as is, adapted, or blocked for a given child.
    /// This is the question a parent actually has — "what can they eat" — and
    /// the Children screen was showing an empty page instead of answering it.
    struct ProfileTally: Sendable {
        var asIs = 0
        var adapted = 0
        var blocked = 0
        var total: Int { asIs + adapted + blocked }
    }

    /// Adapt one recipe for a profile that is not the active one — what the
    /// onboarding demo runs on. The engine is local and takes under a
    /// millisecond, so this is cheap enough to recompute on every tap.
    /// Every replacement the table holds for an ingredient, in the order the
    /// engine ranks them, with the one actually used marked.
    ///
    /// This is the payoff of a deterministic engine: the reasoning can be
    /// shown because it exists. A generated recommendation has nothing to
    /// open.
    struct SubstitutionOption: Sendable {
        let name: String
        let detail: String
        let chosen: Bool
    }

    /// The recipes of the current batch — the week the subscription promises.
    /// The batches were always weekly; nothing in the UI ever showed it.
    ///
    /// `currentWeek` already holds the batch id, straight from the manifest.
    /// Deriving it from `batches.last` would be a second, weaker answer to a
    /// question the server already answered.
    var weekRecipes: [Recipe] {
        guard let id = currentWeek ?? batches.last(where: { $0.unlocked })?.id else {
            return recipes
        }
        let week = recipes.filter { $0.lot == id }
        return week.isEmpty ? recipes : week
    }

    /// The week's shopping list, already adapted for the active profile.
    var shoppingList: [ShoppingItem] {
        guard let moteur, moteur.pret else { return [] }
        return (try? moteur.shoppingList(weekRecipes, pour: activeProfile)) ?? []
    }

    var checkedItems: Set<String> {
        local.loadChecked(week: currentWeek ?? "")
    }

    func saveCheckedItems(_ ids: Set<String>) {
        local.saveChecked(ids, week: currentWeek ?? "")
    }

    func substitutionOptions(for ingredientName: String) -> [SubstitutionOption] {
        /* Read from the table the app already carries rather than crossing the
         * bridge: the data is local, small, and this is a display concern. */
        guard let table = substitutionTable else { return [] }
        guard let entry = table.first(where: { e in
            definition(e.target)?.name.caseInsensitiveCompare(ingredientName) == .orderedSame
                || e.target.caseInsensitiveCompare(ingredientName) == .orderedSame
        }) else { return [] }

        return entry.options.map { o in
            let nom = definition(o.id)?.name ?? o.id
            var detail = o.ratio ?? ""
            if let age = o.minAgeMonths, age > 0 {
                detail += detail.isEmpty ? "" : " · "
                detail += String(format: String(localized: "%lld m+"), age)
            }
            return SubstitutionOption(name: nom, detail: detail, chosen: false)
        }
    }

    /// Whether a real generated photograph exists for this recipe. The
    /// drawing is a fallback, and it should not be treated as a photo.
    func hasPhoto(_ recipe: Recipe) -> Bool {
        recipe.image != nil && !(recipe.image?.isEmpty ?? true)
    }

    func adaptPreview(_ recipe: Recipe, for profile: ChildProfile) -> AdaptedRecipe? {
        guard let moteur, moteur.pret else { return nil }
        return try? moteur.adapter([recipe], pour: profile).first
    }

    func tally(for profile: ChildProfile) -> ProfileTally {
        var t = ProfileTally()
        guard let moteur, moteur.pret, !recipes.isEmpty,
              let results = try? moteur.adapter(recipes, pour: profile) else { return t }
        for r in results {
            switch r.status {
            case .asIs: t.asIs += 1
            case .adapted: t.adapted += 1
            case .notAdaptable: t.blocked += 1
            case .unknown: break
            }
        }
        return t
    }
    private(set) var batches: [Batch] = []

    private(set) var isLoading = true
    private(set) var isOffline = false
    private(set) var fatalError: String?
    private(set) var syncMessage: String?
    private(set) var lastSync: Date?

    var subscribed = false

    // MARK: - Dependencies

    private var moteur: RecipeEngine?
    private let local = LocalStore()

    /// The substitution table, decoded once for display. The engine uses its
    /// own copy through the bridge; this is only for showing the reasoning.
    private(set) var substitutionTable: [SubstitutionEntry]?
    private let serveur = RemoteStore()
    let subscription = Subscription()
    let saved = SavedRecipes()

    /// Rating summaries per recipe, refreshed along with the recipes.
    private(set) var ratings: [String: RatingSummary] = [:]
    private(set) var topRated: [Recipe] = []
    private(set) var ratingThreshold = 5
    private(set) var currentWeek: String?

    // MARK: - ChildProfile courant

    var activeProfile: ChildProfile {
        if familyMode && profiles.count > 1 { return ChildProfile.famille(profiles) }
        return profiles.first { $0.id == activeProfileID } ?? profiles.first ?? .defaut
    }

    /// The profile family mode resolves to, exposed so the picker can show its
    /// numbers alongside each child's.
    var familyProfile: ChildProfile { ChildProfile.famille(profiles) }

    /// When the corpus last came down, in words. A date is precise and
    /// unreadable; "Today" is what a parent wants to know.
    var lastSyncLabel: String {
        guard let d = lastSync else { return String(localized: "Never") }
        if Calendar.current.isDateInToday(d) { return String(localized: "Today") }
        if Calendar.current.isDateInYesterday(d) { return String(localized: "Yesterday") }
        return d.formatted(.dateTime.day().month(.abbreviated))
    }

    var needsOnboarding: Bool { profiles.isEmpty }

    // MARK: - Startup

    func start() async {
        isLoading = true
        defer { isLoading = false }

        theme = local.readTheme()
        profiles = local.readProfiles()
        activeProfileID = profiles.first?.id

        do {
            let m = try RecipeEngine()
            try m.chargerDonnees(
                ingredients: try Resources.data("ingredients", "json"),
                substitutions: try Resources.data("substitutions", "json"),
                base: try Resources.data("base", "json"))
            moteur = m
            /* The same bytes the engine just loaded, decoded a second time for
             * display. Cheap, and it keeps the rule sheet honest: what it
             * shows is what the engine used. */
            if let d = try? Resources.data("substitutions", "json") {
                substitutionTable = try? JSONDecoder().decode([SubstitutionEntry].self, from: d)
            }
        } catch {
            // With no engine the app can assert nothing. Say so plainly
            // rather than showing recipes that were never verified.
            fatalError = error.localizedDescription
            return
        }

        chargerCorpusLocal()
        recompute()
        await sync()
    }

    /// Downloaded corpus if there is one, otherwise the batches shipped in the app.
    private func chargerCorpusLocal() {
        if let sauvegarde = local.readRecipes(), !sauvegarde.isEmpty {
            recipes = sauvegarde
        } else {
            var embarquees: [Recipe] = []
            for url in Resources.bundledBatches() {
                if let d = try? Data(contentsOf: url),
                   let r = try? JSONDecoder().decode([Recipe].self, from: d) {
                    embarquees.append(contentsOf: r)
                }
            }
            recipes = embarquees.sorted { $0.name < $1.name }
        }
        if let l = local.readBatches() { batches = l }
    }

    // MARK: - Synchronisation

    func sync() async {
        guard fatalError == nil else { return }
        let token = subscription.serverToken
        do {
            let manif = try await serveur.manifest(token: token)
            batches = manif.batches
            currentWeek = manif.currentWeek
            local.writeBatches(manif.batches)
            if let a = manif.subscribed { subscribed = a }

            let rep = try await serveur.recipes(token: token)
            if !rep.recipes.isEmpty {
                recipes = rep.recipes
                local.writeRecipes(rep.recipes)
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

    /// Recipe and result paired, in corpus order.
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
        local.writeProfiles(profiles)
        recompute()
    }

    func remove(_ profile: ChildProfile) {
        profiles.removeAll { $0.id == profile.id }
        if activeProfileID == profile.id { activeProfileID = profiles.first?.id }
        if profiles.count < 2 { familyMode = false }
        local.writeProfiles(profiles)
        recompute()
    }

    func select(_ id: String) {
        activeProfileID = id
        familyMode = false
        recompute()
    }

    func toggleFamilyMode(_ on: Bool) {
        familyMode = on
        recompute()
    }

    func toggleFamilyMode() {
        familyMode.toggle()
        recompute()
    }

    // MARK: - Notes

    /// Summaries for everything visible, in one call.
    func loadRatings() async {
        let ids = (recipes.map(\.id) + saved.recipes.map(\.id))
        guard !ids.isEmpty else { return }
        if let a = try? await serveur.ratings(ids: Array(Set(ids)), token: subscription.serverToken) {
            ratings = a
        }
    }

    /// Rating requires an account: without one, nothing stops a single person
    /// voting a hundred times. The display updates at once, then the
    /// serveur confirme — c'est lui qui fait foi.
    func rate(_ recetteId: String, note: Int?) async {
        guard let token = subscription.serverToken else {
            syncMessage = "Sign in from Settings to rate a recipe."
            return
        }
        do {
            let a = try await serveur.rate(recetteId, note: note, token: token)
            ratings[recetteId] = a
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
    /// outside the window, or an entry in the ranking.
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

    /// Weeks rotate: photos outside the window and not saved no longer need to
    /// take up disk space.
    private func prunePhotos() async {
        var garder = Set<String>()
        for r in recipes + saved.recipes + topRated {
            if let f = r.image { garder.insert(f) }
        }
        await PhotoCache.partage.nettoyer(garder: garder)
    }

    // MARK: - Lookups

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
        let r = try await serveur.login(email: email)
        subscription.setToken(r.token, email: r.email)
        subscribed = r.subscribed ?? false
        await subscription.refreshEntitlements()
        await sync()
    }

    func linkPurchase(_ jws: String) async {
        guard let token = subscription.serverToken else { return }
        if let r = try? await serveur.linkTransaction(jws, token: token), let a = r.subscribed {
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

    var mostRecentUnlockedBatch: Batch? {
        batches.filter(\.unlocked).sorted { $0.id < $1.id }.last
    }
}

// MARK: - Shared formatting

enum Format {
    /// "milk, eggs and peanuts" rather than "milk, eggs, peanuts".
    /// The joining word is localised: French needs "et", English "and".
    /// A quantity without a trailing ".0". "375", not "375.0" — a shopping
    /// list is read at a glance.
    static func number(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    static func liste(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        let et = String(localized: "and", comment: "joins the last two items of a list")
        return items.dropLast().joined(separator: ", ") + " " + et + " " + (items.last ?? "")
    }

    static func age(_ months: Int) -> String {
        if months < 24 { return String(localized: "\(months) months") }
        let years = months / 12
        let rest = months % 12
        return rest == 0 ? String(localized: "\(years) years")
                         : String(localized: "\(years) years \(rest) months")
    }
}
