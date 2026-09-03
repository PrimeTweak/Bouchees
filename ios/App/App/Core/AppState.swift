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

    /// The parent's overrides on the sequence, per week index.
    var plan: WeekPlan = .empty

    /// The day the strip is showing. Starts on today.
    var selectedDay: Int = WeekDay.today

    /// Which week the rail is showing: -1 past, 0 current, +1 next.
    var selectedWeek: Int = 0

    /// The sequence this device follows, and the days it has already shown.
    private(set) var sequence = RecipeSequence(seed: 1, epoch: Date(), rotationWeeks: 16)
    private(set) var history: [Int: DayPick] = [:]

    /// The day index of today in the sequence.
    var todayIndex: Int { sequence.dayIndex(of: Date()) }

    /// The Monday index of the week the rail shows.
    private func weekStart(_ offset: Int) -> Int { todayIndex - WeekDay.today + offset * 7 }

    /// The two ids the sequence puts on a day of a week; overrides applied
    /// on the current week only.
    func picks(week offset: Int) -> [Int: DayPick] {
        let start = weekStart(offset)
        let key = "\(start)/\(recipes.count)/\(history.count)/\(subscribed)/\(activeProfile.id)"
        if let hit = picksCache[key] { return hit }
        let out = sequence.picks(from: start, to: start + 6, pool: servablePool, history: history)
        if picksCache.count > 12 { picksCache.removeAll() }
        picksCache[key] = out
        return out
    }
    /// The weeks already computed; the key moves with the pool and the history.
    @ObservationIgnored private var picksCache: [String: [Int: DayPick]] = [:]

    /// The three weeks the rail offers. A week is unlocked when every body
    /// it needs is here; a locked week still shows its names.
    var weekSlots: [WeekSlot] {
        [-1, 0, 1].map { offset in
            let ids = picks(week: offset).values.flatMap { [$0.meal, $0.snack] }.compactMap { $0 }
            let known = ids.compactMap { id in recipes.first { $0.id == id } }
            return WeekSlot(offset: offset, count: known.count,
                            unlocked: !known.isEmpty && known.allSatisfy { $0.hasBody })
        }
    }

    var currentSlot: WeekSlot {
        weekSlots.first { $0.offset == selectedWeek } ?? WeekSlot(offset: 0, count: 0, unlocked: true)
    }

    /// One day of the selected week: the meal first, then the snack. On the
    /// current week the parent's moves apply.
    func recipesOfSelectedWeek(on day: Int) -> [Recipe] {
        if selectedWeek == 0 { return recipes(on: day) }
        guard let p = picks(week: selectedWeek)[weekStart(selectedWeek) + day] else { return [] }
        return [p.meal, p.snack].compactMap { id in id.flatMap { recipeByID($0) } }
    }

    /// The current week, with the plan's moves.
    func recipes(on day: Int) -> [Recipe] {
        plan.recipes(on: day).compactMap { recipeByID($0) }
    }

    func recipeByID(_ id: String) -> Recipe? { recipes.first { $0.id == id } }

    /// Today's meal: what the hero shows.
    var tonight: Recipe? {
        recipes(on: WeekDay.today).first { $0.isMeal } ?? recipes(on: WeekDay.today).first
    }

    /// Moves a recipe to another day and writes it down straight away.
    func move(_ recipe: Recipe, to day: Int) {
        plan.move(recipe.id, to: day)
        local.saveWeekPlan(plan, week: weekStart(0))
    }

    /// Swaps two whole days.
    func swapDays(_ a: Int, _ b: Int) {
        plan.swap(a, b)
        local.saveWeekPlan(plan, week: weekStart(0))
    }

    /// Rebuilds the current week's plan from the sequence, keeping the days
    /// the parent already chose, and freezes today and the days before it.
    func refreshPlan() {
        let start = weekStart(0)
        let week = picks(week: 0)
        /* Freeze every day up to today, so a recipe joining the pool changes
         * only the days to come. */
        /* Never freeze an empty day: an old cache or a sync not yet answered
         * would lock today at nothing. Repair any such entry from before. */
        var frozen = history.filter { $0.value.meal != nil || $0.value.snack != nil }
        for d in (start...(start + 6)) where d <= todayIndex {
            if let p = week[d], p.meal != nil || p.snack != nil { frozen[d] = p }
        }
        if frozen != history { history = frozen; local.writeHistory(history) }

        var base = WeekPlan.empty
        for day in 0..<7 {
            if let p = week[start + day] {
                base.days[day] = [p.meal, p.snack].compactMap { $0 }
            }
        }
        let ids = Set(base.days.values.flatMap { $0 })
        var current = local.loadWeekPlan(week: start) ?? base
        /* Drop what the sequence no longer holds, add what it now does. */
        for day in current.days.keys {
            current.days[day]?.removeAll { !ids.contains($0) }
            if current.days[day]?.isEmpty == true { current.days[day] = nil }
        }
        let placed = Set(current.days.values.flatMap { $0 })
        for (day, list) in base.days {
            for id in list where !placed.contains(id) { current.days[day, default: []].append(id) }
        }
        plan = current
        local.saveWeekPlan(plan, week: start)
    }

    /// The fourteen recipes of the current week.
    var weekRecipes: [Recipe] {
        (0..<7).flatMap { recipes(on: $0) }
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
        local.loadChecked(week: "w\(weekStart(0))")
    }

    func saveCheckedItems(_ ids: Set<String>) {
        local.saveChecked(ids, week: "w\(weekStart(0))")
    }

    /// Recipes cooked this week, by id. Set by the end of cooking mode.
    var cooked: Set<String> {
        local.loadCooked(week: "w\(weekStart(0))")
    }

    func markCooked(_ id: String) {
        local.markCooked(id, week: "w\(weekStart(0))")
        cookedTick += 1
    }

    /// Undo, for a swipe made by mistake.
    func unmarkCooked(_ id: String) {
        local.unmarkCooked(id, week: "w\(weekStart(0))")
        cookedTick += 1
    }

    /// `cooked` reads the disk, which Observation cannot watch. Bumping this
    /// is what tells the week to redraw after a swipe.
    private(set) var cookedTick = 0

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
        sequence = RecipeSequence(seed: local.sequenceSeed(), epoch: local.sequenceEpoch(), rotationWeeks: 16)
        history = local.readHistory()
        /* A cache from before the pool has no catalogue fields: it cannot
         * feed the sequence and is dropped for the bundled catalogue. */
        if let saved = local.readRecipes(), !saved.isEmpty,
           saved.contains(where: { $0.adaptability != nil }) {
            recipes = saved
        } else {
            recipes = bundledCatalogue()
        }
    }

    /// The catalogue shipped in the app, with the free bodies merged in.
    private func bundledCatalogue() -> [Recipe] {
        guard let url = Resources.bundledCatalogue(),
              let d = try? Data(contentsOf: url),
              var cards = (try? JSONDecoder().decode(LossyArray<Recipe>.self, from: d))?.items else { return [] }
        var bodies: [String: Recipe] = [:]
        for u in Resources.bundledBodies() {
            if let bd = try? Data(contentsOf: u), let b = try? JSONDecoder().decode(Recipe.self, from: bd) {
                bodies[b.id] = b
            }
        }
        cards = cards.map { c in bodies[c.id].map { c.with(body: $0) } ?? c }
        return cards.sorted { $0.name < $1.name }
    }

    // MARK: - Synchronisation

    /// The catalogue first, then the bodies the three weeks need. A body the
    /// account is not entitled to stays a card, and the day shows locked.
    func sync() async {
        guard fatalError == nil else { return }
        /* The key for bodies: a session when one exists, otherwise the signed
         * Apple transaction. `??` evaluates its right side in an autoclosure,
         * which cannot await, so the fallback is spelled out. */
        var token = subscription.serverToken
        if token == nil { token = await subscription.currentTransaction() }
        do {
            let manif = try await serveur.manifest(token: token)
            if let a = manif.subscribed { subscribed = a }
            if let r = manif.rotationWeeks, r != sequence.rotationWeeks {
                sequence = RecipeSequence(seed: sequence.seed, epoch: sequence.epoch, rotationWeeks: r)
            }
            let cat = try await serveur.catalogue().catalogue
            /* Keep every body already here; take the card's fields fresh. */
            let bodies = Dictionary(uniqueKeysWithValues: recipes.filter { $0.hasBody }.map { ($0.id, $0) })
            recipes = cat.map { c in bodies[c.id].map { c.with(body: $0) } ?? c }.sorted { $0.name < $1.name }

            await fetchMissingBodies(token: token)
            local.writeRecipes(recipes)
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

    /// Bodies for the three weeks on the rail, asked for together; on a
    /// refusal, the free ones are asked for alone.
    private func fetchMissingBodies(token: String?) async {
        /* A subscriber gets the whole pool, so search reaches all of it;
         * anyone else gets the three weeks on the rail. */
        let needed: [String] = subscribed
            ? recipes.map(\.id)
            : [-1, 0, 1].flatMap { picks(week: $0).values.flatMap { [$0.meal, $0.snack] } }.compactMap { $0 }
        let missing = Array(Set(needed)).filter { id in recipeByID(id)?.hasBody == false }
        guard !missing.isEmpty else { return }
        func merge(_ got: [Recipe]) {
            let byId = Dictionary(uniqueKeysWithValues: got.map { ($0.id, $0) })
            recipes = recipes.map { c in byId[c.id].map { c.with(body: $0) } ?? c }
        }
        do {
            for chunk in stride(from: 0, to: missing.count, by: 100) {
                let ids = Array(missing[chunk..<min(chunk + 100, missing.count)])
                merge(try await serveur.recipes(ids: ids, token: token).recipes)
            }
        } catch RepositoryError.subscriptionRequired {
            let free = missing.filter { recipeByID($0)?.free == true }
            if !free.isEmpty, let r = try? await serveur.recipes(ids: free, token: token) { merge(r.recipes) }
        } catch {}
    }

    // MARK: - Adaptation

    func recompute() {
        guard let engine, engine.pret, !recipes.isEmpty else {
            adapted = []
            return
        }
        do {
            adapted = try engine.adapt(recipes.filter { $0.hasBody }, for: activeProfile)
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

    /// The four cuts of Search, over every recipe this account can open. A
    /// free account opens its two weeks and the free ones; a subscriber, the
    /// pool. That is the limit, by construction.
    func searchGroups() -> [(heading: String, dishes: [(recipe: Recipe, result: AdaptedRecipe)])] {
        let open = recipes.filter { $0.hasBody }.compactMap { r in
            resultFor(r).map { (recipe: r, result: $0) }
        }
        var out: [(heading: String, dishes: [(recipe: Recipe, result: AdaptedRecipe)])] = []
        var seen = Set<String>()
        func add(_ heading: String, _ dishes: [(recipe: Recipe, result: AdaptedRecipe)]) {
            let fresh = dishes.filter { !seen.contains($0.recipe.id) }
            guard !fresh.isEmpty else { return }
            out.append((heading, fresh))
            seen.formUnion(fresh.map(\.recipe.id))
        }
        let todayIDs = Set(recipes(on: WeekDay.today).map(\.id))
        add(String(localized: "Tonight"), open.filter { todayIDs.contains($0.recipe.id) })
        add(String(format: String(localized: "Ready for %@"), activeProfile.name),
            open.filter { $0.result.status == .asIs })
        add(String(localized: "Under 20 minutes"), open.filter { ($0.recipe.timeMinutes ?? 99) <= 20 })
        /* Recipes whose ingredients are mostly already checked off the list. */
        let bought = checkedItems
        if !bought.isEmpty {
            add(String(localized: "With what's on your list"), open.filter { p in
                let names = p.result.ingredients.map { $0.name.lowercased() }
                guard names.count >= 2 else { return false }
                return names.filter { bought.contains($0) }.count * 2 >= names.count
            })
        }
        return out
    }

    /// The verdict for any recipe: adapted when the body is here, from the
    /// catalogue's matrix when it is not.
    func resultFor(_ recipe: Recipe) -> AdaptedRecipe? {
        if let existing = adapted.first(where: { $0.id == recipe.id }) { return existing }
        guard recipe.hasBody else { return liteResult(for: recipe) }
        return try? engine?.adapt(recipe, for: activeProfile)
    }

    /// What the sequence may serve: nothing the engine cannot adapt for this
    /// child, nothing under their age. A category the filter would empty
    /// falls back on the whole pool rather than on an empty day.
    var servablePool: [Recipe] {
        let ok = recipes.filter { card in
            guard card.minAgeMonths <= activeProfile.ageMonths else { return false }
            guard let matrix = card.adaptability else { return true }
            return !activeProfile.allergens.contains { matrix[$0] == "not_adaptable" }
        }
        let meals = ok.filter(\.isMeal), snacks = ok.filter(\.isSnack)
        return meals.isEmpty || snacks.isEmpty ? recipes : ok
    }

    /// A verdict for a card without a body, from the catalogue's matrix: the
    /// worst answer among the child's allergens. Locked days stay honest.
    func liteResult(for card: Recipe) -> AdaptedRecipe? {
        guard let matrix = card.adaptability, let engine = engine,
              let stage = try? engine.stage(for: activeProfile.ageMonths) else { return nil }
        let answers = activeProfile.allergens.compactMap { matrix[$0] }
        let status: RecipeStatus = answers.contains("not_adaptable") ? .notAdaptable
            : answers.contains("adapted") ? .adapted : .asIs
        return AdaptedRecipe(id: card.id, name: card.name, status: status, swapCount: 0,
                             ingredients: [], alerts: [], texture: stage, steps: [],
                             stepsOriginal: nil, remainingAllergens: [])
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
            /* The thumbnail too: it is a separate file, and pruning without
             * it deleted every list thumbnail on each sync. */
            if let t = r.thumb { garder.insert(t) }
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
