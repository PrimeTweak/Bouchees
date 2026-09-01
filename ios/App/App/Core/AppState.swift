// AppState.swift The central state.

import Foundation
import Observation

@MainActor
@Observable
final class AppState {

    // MARK: - Exposed state

    var profiles: [ChildProfile] = []
    var activeProfileID: String?
    /// Persisted: "Everyone" chosen in a store must still hold at home.
    var familyMode = false {
        didSet { local.writeFamilyMode(familyMode) }
    }

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
    struct SubstitutionOption: Sendable {
        let name: String
        let detail: String
        let chosen: Bool
    }

    /// The batches were always weekly; nothing in the UI ever showed it.
    /// `currentWeek` already holds the batch id, straight from the manifest.
    var plan: WeekPlan = .empty

    /// The day the strip is showing. Starts on today.
    ///
    /// Kept for the drag-and-drop and for Shopping, which still groups by day.
    var selectedDay: Int = WeekDay.today

    /// Which week the rail is showing: -1 past, 0 current, +1 next.
    var selectedWeek: Int = 0

    /// The three weeks the rail offers: built from the manifest rather than
    /// guessed: the batch ids carry the ISO week, and `unlocked` is what the
    /// server already decided.
    var weekSlots: [WeekSlot] {
        let ouvertes = batches.filter { $0.unlocked }.map(\.id)
        let courante = currentBatchID
        let index = courante.flatMap { id in batches.firstIndex { $0.id == id } }

        return [-1, 0, 1].map { decalage -> WeekSlot in
            guard let i = index else {
                return WeekSlot(offset: decalage, batchID: nil, count: 0,
                                unlocked: decalage == 0)
            }
            let j = i + decalage
            guard j >= 0, j < batches.count else {
                return WeekSlot(offset: decalage, batchID: nil, count: 0,
                                unlocked: false)
            }
            let lot = batches[j]
            let n = recipes.filter { $0.batch == lot.id }.count
            return WeekSlot(offset: decalage, batchID: lot.id,
                            count: n > 0 ? n : lot.count,
                            unlocked: ouvertes.contains(lot.id))
        }
    }

    /// The slot the rail has selected.
    var currentSlot: WeekSlot {
        weekSlots.first { $0.offset == selectedWeek }
            ?? WeekSlot(offset: 0, batchID: currentBatchID, count: 0, unlocked: true)
    }

    /// The recipes of the week the rail is showing: a locked week still
    /// returns its recipes: the list shows names, times and verdicts, and
    /// hides the rest.
    var selectedWeekRecipes: [Recipe] {
        guard selectedWeek != 0 else { return weekRecipes }
        guard let id = currentSlot.batchID else { return [] }
        return recipes.filter { $0.batch == id }
    }

    /// Which recipes fall on a day of the SELECTED week: the plan is stored
    /// for the current week only — a parent does not rearrange a week they
    /// cannot open.
    func recipesOfSelectedWeek(on day: Int) -> [Recipe] {
        if selectedWeek == 0 { return recipes(on: day) }
        let dishes = selectedWeekRecipes
        guard !dishes.isEmpty else { return [] }
        /* Weeknights first, the same shape the plan uses: five days carry a
         * recipe, two are left open on purpose. */
        return dishes.enumerated().compactMap { i, r in
            WeekPlan.defaultDay(forIndex: i) == day ? r : nil
        }
    }

    /// The recipes assigned to one day, in the order the parent put them.
    func recipes(on day: Int) -> [Recipe] {
        let ids = plan.recipes(on: day)
        return ids.compactMap { id in weekRecipes.first { $0.id == id } }
    }

    /// Moves a recipe to another day and writes it down straight away.
    func move(_ recipe: Recipe, to day: Int) {
        plan.move(recipe.id, to: day)
        if let id = currentBatchID { local.saveWeekPlan(plan, batch: id) }
    }

    /// Swaps two whole days.
    func swapDays(_ a: Int, _ b: Int) {
        plan.swap(a, b)
        if let id = currentBatchID { local.saveWeekPlan(plan, batch: id) }
    }

    /// Rebuilds the plan when the batch changes, keeping any day the parent
    /// already chose for a recipe that is still in the week.
    func refreshPlan() {
        guard let id = currentBatchID else { plan = .empty; return }
        let weekPairs = weekRecipes
        let connus = Set(weekPairs.map(\.id))

        var courant = local.loadWeekPlan(batch: id) ?? WeekPlan.initial(for: weekPairs)
        /* Drop anything no longer in the week, then place anything new. */
        for day in courant.days.keys {
            courant.days[day]?.removeAll { !connus.contains($0) }
            if courant.days[day]?.isEmpty == true { courant.days[day] = nil }
        }
        let places = Set(courant.days.values.flatMap { $0 })
        let neuves = weekPairs.filter { !places.contains($0.id) }
        if !neuves.isEmpty {
            let depart = WeekPlan.initial(for: neuves)
            for (day, ids) in depart.days {
                courant.days[day, default: []].append(contentsOf: ids)
            }
        }
        plan = courant
        local.saveWeekPlan(plan, batch: id)
    }

    /// The manifest's `currentWeek` names the week being PUBLISHED, which can
    /// be ahead of anything this reader can open — it says 2026-S35 while the
    /// newest unlocked batch is S34.
    var currentBatchID: String? {
        let mine = batches.filter { $0.unlocked }
        return mine.first(where: { $0.id == currentWeek })?.id ?? mine.last?.id
    }

    var weekRecipes: [Recipe] {
        guard let id = currentBatchID else { return recipes }
        /* One word, three symptoms: "This week · 15 recipes" instead of 7,
         * an empty shopping list, and meal groups drawn from the whole
         * corpus. The model called this `lot`; the JSON calls it `batch`. */
        let week = recipes.filter { $0.batch == id }
        return week.isEmpty ? recipes : week
    }

    /// The list for one day only. The week's shopping list, already adapted
    /// for the active profile.
    func shoppingList(on day: Int) -> [ShoppingItem] {
        let dishes = recipes(on: day)
        guard !dishes.isEmpty, let m = engine else { return [] }
        return (try? m.shoppingList(dishes, for: activeProfile)) ?? []
    }

    /// Queries the parent has run more than once.
    private(set) var recentSearches: [String] = []
    @ObservationIgnored private var searchCounts: [String: Int] = [:]

    func rememberSearch(_ raw: String) {
        let q = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count > 1 else { return }
        searchCounts[q, default: 0] += 1
        guard searchCounts[q]! >= 2 else { return }
        recentSearches.removeAll { $0 == q }
        recentSearches.insert(q, at: 0)
        if recentSearches.count > 6 { recentSearches.removeLast() }
    }

    var shoppingList: [ShoppingItem] {
        guard let engine, engine.pret else { return [] }
        return (try? engine.shoppingList(weekRecipes, for: activeProfile)) ?? []
    }

    var checkedItems: Set<String> {
        local.loadChecked(week: currentWeek ?? "")
    }

    func saveCheckedItems(_ ids: Set<String>) {
        local.saveChecked(ids, week: currentWeek ?? "")
    }

    /// Recipes cooked this week, by id. Set by the end of cooking mode.
    var cooked: Set<String> {
        local.loadCooked(week: currentWeek ?? "")
    }

    func markCooked(_ id: String) {
        local.markCooked(id, week: currentWeek ?? "")
    }

    /// Every option the table holds for an ingredient: `chosenName` is the
    /// substitute the engine actually took.
    func substitutionOptions(for ingredientName: String,
                             chosen chosenName: String? = nil) -> [SubstitutionOption] {
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
                /* Spelled out. "6 m+" is an abbreviation nothing on screen
                 * explains, in the one place a parent is checking whether a
                 * swap is safe for the age of their child. */
                detail += String(format: String(localized: "from %lld months"), age)
            }
            let pris = chosenName.map {
                nom.caseInsensitiveCompare($0) == .orderedSame
            } ?? false
            return SubstitutionOption(name: nom, detail: detail, chosen: pris)
        }
    }

    /// Whether a real generated photograph exists for this recipe. The
    /// drawing is a fallback, and it should not be treated as a photo.
    func hasPhoto(_ recipe: Recipe) -> Bool {
        recipe.image != nil && !(recipe.image?.isEmpty ?? true)
    }

    func adaptPreview(_ recipe: Recipe, for profile: ChildProfile) -> AdaptedRecipe? {
        guard let engine, engine.pret else { return nil }
        return try? engine.adapt([recipe], for: profile).first
    }

    func tally(for profile: ChildProfile) -> ProfileTally {
        var t = ProfileTally()
        guard let engine, engine.pret, !recipes.isEmpty,
              let results = try? engine.adapt(recipes, for: profile) else { return t }
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

    private var engine: RecipeEngine?
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
        if familyMode && profiles.count > 1 { return ChildProfile.family(profiles) }
        return profiles.first { $0.id == activeProfileID } ?? profiles.first ?? .defaut
    }

    /// The profile family mode resolves to, exposed so the picker can show its
    /// numbers alongside each child's.
    var familyProfile: ChildProfile { ChildProfile.family(profiles) }

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

    /// Local work first, then the network. The launch screen waits only for
    /// the local part; a cold server updates the screen when it answers.
    func start() async {
        isLoading = true
        /* The plan is keyed on the batch, so it is rebuilt whenever the set of
         * unlocked recipes could have changed. */
        defer { isLoading = false; refreshPlan() }

        theme = local.readTheme()
        profiles = local.readProfiles()
        activeProfileID = profiles.first?.id
        familyMode = local.readFamilyMode() && profiles.count > 1
        restoreLocalRatings()

        do {
            let m = try RecipeEngine()
            try m.chargerDonnees(
                ingredients: try Resources.data("ingredients", "json"),
                substitutions: try Resources.data("substitutions", "json"),
                base: try Resources.data("base", "json"),
                /* Optional: an older bundle without it still runs, with the
                 * narrower recognition it always had. */
                lexicon: try? Resources.data("label-lexicon", "json"))
            engine = m
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
        isLoading = false
        refreshPlan()
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
        refreshPlan()
    }

    // MARK: - Adaptation

    func recompute() {
        guard let engine, engine.pret, !recipes.isEmpty else {
            adapted = []
            return
        }
        do {
            adapted = try engine.adapt(recipes, for: activeProfile)
        } catch {
            adapted = []
            syncMessage = String(localized: "The engine could not adapt the recipes: \(error.localizedDescription)")
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

    func result(for id: String) -> AdaptedRecipe? {
        adapted.first { $0.id == id }
    }

    func recipe(for id: String) -> Recipe? {
        recipes.first { $0.id == id }
    }

    // MARK: - Profiles

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

    /// Without one, the note is the parent's own record and nothing asks them
    /// to sign in. Rating requires an account: without one, nothing stops a
    /// single person voting a hundred times.
    func rate(_ recetteId: String, note: Int?) async {
        local.writeLocalRating(recetteId, note: note)
        let mine = note
        let shared = ratings[recetteId]
        ratings[recetteId] = RatingSummary(votes: shared?.votes ?? 0,
                                           average: shared?.average, myRating: mine)
        guard let token = subscription.serverToken else { return }
        do {
            let a = try await serveur.rate(recetteId, note: note, token: token)
            ratings[recetteId] = a
        } catch {
            syncMessage = "The rating couldn’t be saved. Try again later."
        }
    }

    /// Local notes, restored under the shared summary when there is one.
    func restoreLocalRatings() {
        for (id, note) in local.readLocalRatings() where ratings[id]?.myRating == nil {
            let shared = ratings[id]
            ratings[id] = RatingSummary(votes: shared?.votes ?? 0,
                                        average: shared?.average, myRating: note)
        }
    }

    func loadTopRated() async {
        if let r = try? await serveur.topRated(token: subscription.serverToken) {
            topRated = r.recipes
            ratingThreshold = r.threshold
        }
    }

    /// Adapts a recipe outside the current batch — a saved one past the
    /// window, or an entry of the ranking.
    func resultFor(_ recipe: Recipe) -> AdaptedRecipe? {
        if let existing = adapted.first(where: { $0.id == recipe.id }) { return existing }
        return try? engine?.adapt(recipe, for: activeProfile)
    }

    func pairFor(for id: String) -> (recipe: Recipe, result: AdaptedRecipe)? {
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

    var knownAllergens: [Allergen] { engine?.base?.allergens ?? [] }

    func allergenName(_ id: String) -> String { engine?.allergenName(id) ?? id }

    func allergenNames(_ ids: [String]) -> [String] { engine?.allergenNames(ids) ?? ids }

    func definition(_ id: String) -> IngredientDefinition? { engine?.catalogue[id] }

    func stage(for ageMonths: Int) -> TextureStage? { try? engine?.stage(for: ageMonths) }

    // MARK: - Scanner

    func evaluateLabel(_ texte: String) throws -> ProductVerdict {
        guard let engine else { throw EngineError.exception("engine indisponible") }
        return try engine.evaluateLabel(texte, evites: activeProfile.allergens)
    }

    func lookUpProduct(code: String) async throws -> GroceryProduct {
        try await serveur.product(code: code, token: subscription.serverToken)
    }

    // MARK: - Compte

    func linkPurchase(_ jws: String) async {
        guard let token = subscription.serverToken else { return }
        if let r = try? await serveur.linkTransaction(jws, token: token), let a = r.subscribed {
            subscribed = a
            await sync()
        }
    }

    // MARK: - Lots

    var lockedBatches: [Batch] { batches.filter { !$0.unlocked } }

}

// MARK: - Shared formatting

enum Format {
    /// "milk, eggs and peanuts" rather than "milk, eggs, peanuts": the joining
    /// word is localised: French needs "et", English "and".
    static func number(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    static func list(_ items: [String]) -> String {
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
