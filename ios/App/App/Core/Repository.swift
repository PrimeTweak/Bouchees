// The real use case is a grocery aisle in a basement with no signal. That is
// what the App Store privacy labels declare, and it has to stay true in the
// code.

import Foundation

// MARK: - Bundled resources

enum Resources {
    /// The files are copied into the bundle by the workflow, under
    /// Try the subdirectory first, then the bundle root: how Xcode flattens a
    /// folder reference varies with the configuration.
    static func url(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Bundled")
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }

    static func data(_ name: String, _ ext: String) throws -> Data {
        guard let u = url(name, ext) else {
            throw RepositoryError.missingResource("\(name).\(ext)")
        }
        return try Data(contentsOf: u)
    }

    /// The catalogue shipped inside the app, and the free bodies with it.
    static func bundledCatalogue() -> URL? {
        Bundle.main.url(forResource: "catalogue", withExtension: "json", subdirectory: "Bundled")
    }
    static func bundledBodies() -> [URL] {
        Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Bundled/recipes") ?? []
    }
}

enum RepositoryError: LocalizedError {
    case missingResource(String)
    case network(Int)
    case subscriptionRequired
    case unreadableResponse

    var errorDescription: String? {
        switch self {
        case .missingResource(let n): return String(localized: "Missing resource in the app: \(n)")
        case .network(let c): return String(localized: "The server answered \(c).")
        case .subscriptionRequired: return "Ce lot demande un subscription."
        case .unreadableResponse: return String(localized: "The server's answer could not be read.")
        }
    }
}

// MARK: - Settings

enum Settings {
    /// Replace with the address of your deployed service.
    static var serverBase: URL {
        if let s = ProcessInfo.processInfo.environment["BOUCHEES_SERVEUR"], let u = URL(string: s) {
            return u
        }
        if let s = Bundle.main.object(forInfoDictionaryKey: "BoucheesServeur") as? String,
           let u = URL(string: s) {
            return u
        }
        return URL(string: "https://bouchees.onrender.com")!
    }

    /// Served by the server itself — no separate site to maintain, and no dead
    /// link at App Store review time.
    static var terms: URL { serverBase.appendingPathComponent("terms") }
    static var privacy: URL { serverBase.appendingPathComponent("privacy") }

    /// Localised: the French build must read as French, not as a half-translated
    /// app. The key is the English text, as everywhere else.
    static var medicalDisclaimer: String {
        String(localized: """
        Bouchées is not medical advice. Ingredient swaps and age guidance come from \
        deterministic tables that a professional should review. For a diagnosed allergy, \
        your allergist's plan always takes precedence.
        """)
    }
}

// MARK: - Persistance locale

@MainActor
final class LocalStore {

    /* Ticked items, per week. A shopping list without memory is useless in an
     * aisle — you put the phone away to pick something up and lose your place.
     * Keyed by week index so a new week starts clean on its own. */
    /// The week plan, per batch. Moving a recipe to another day has to
    /// survive a relaunch — it is a decision the parent made.
    func saveWeekPlan(_ plan: WeekPlan, week: Int) {
        let paires = plan.days.map { ["day": $0.key, "ids": $0.value] as [String: Any] }
        guard let d = try? JSONSerialization.data(withJSONObject: paires) else { return }
        try? d.write(to: folder.appendingPathComponent("plan-w\(week).json"), options: .atomic)
    }

    func loadWeekPlan(week: Int) -> WeekPlan? {
        guard let d = try? Data(contentsOf: folder.appendingPathComponent("plan-w\(week).json")),
              let rawText = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]]
        else { return nil }
        var days: [Int: [String]] = [:]
        for p in rawText {
            if let day = p["day"] as? Int, let ids = p["ids"] as? [String] {
                days[day] = ids
            }
        }
        return days.isEmpty ? nil : WeekPlan(days: days)
    }

    func saveChecked(_ ids: Set<String>, week: String) {
        UserDefaults.standard.set(Array(ids), forKey: "checked.\(week)")
    }

    func loadChecked(week: String) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "checked.\(week)") ?? [])
    }

    /* WHAT GOT COOKED. Recorded when "Done" is tapped at the end of cooking
     * mode, nothing asked. Same shape as the shopping checkmarks: one small
     * list per week, in UserDefaults, and gone with the week. */
    func markCooked(_ id: String, week: String) {
        var ids = loadCooked(week: week)
        ids.insert(id)
        UserDefaults.standard.set(Array(ids), forKey: "cooked.\(week)")
    }

    /// One note per recipe, on the device. Synced to the ranking later.
    func writeLocalRating(_ id: String, note: Int?) {
        var all = readLocalRatings()
        if let n = note { all[id] = n } else { all.removeValue(forKey: id) }
        UserDefaults.standard.set(all, forKey: "localRatings")
    }
    func readLocalRatings() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: "localRatings") as? [String: Int] ?? [:]
    }

    func writeFamilyMode(_ on: Bool) { UserDefaults.standard.set(on, forKey: "familyMode") }
    func readFamilyMode() -> Bool { UserDefaults.standard.bool(forKey: "familyMode") }

    func loadCooked(week: String) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "cooked.\(week)") ?? [])
    }


    private let fm = FileManager.default

    private var folder: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Bouchees", isDirectory: true)
        if !fm.fileExists(atPath: base.path) {
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    private var profilesFile: URL { folder.appendingPathComponent("profiles.json") }
    private var recipesFile: URL { folder.appendingPathComponent("recipes.json") }

    // Profiles — never sent anywhere.

    func readProfiles() -> [ChildProfile] {
        guard let d = try? Data(contentsOf: profilesFile),
              let p = try? JSONDecoder().decode([ChildProfile].self, from: d) else { return [] }
        return p
    }

    func writeProfiles(_ profiles: [ChildProfile]) {
        guard let d = try? JSONEncoder().encode(profiles) else { return }
        try? d.write(to: profilesFile, options: .atomic)
    }

    // Appearance — a single stored word, in UserDefaults rather than a file:
    // it is read before the first frame, and a file read there would flash.

    private static let themeKey = "appearance"

    func readTheme() -> AppTheme {
        guard let raw = UserDefaults.standard.string(forKey: Self.themeKey),
              let t = AppTheme(rawValue: raw) else { return .system }
        return t
    }

    func writeTheme(_ t: AppTheme) {
        UserDefaults.standard.set(t.rawValue, forKey: Self.themeKey)
    }

    // Downloaded corpus — what makes offline work possible.

    func readRecipes() -> [Recipe]? {
        guard let d = try? Data(contentsOf: recipesFile) else { return nil }
        return (try? JSONDecoder().decode(LossyArray<Recipe>.self, from: d))?.items
    }

    func writeRecipes(_ recipes: [Recipe]) {
        guard let d = try? JSONEncoder().encode(recipes) else { return }
        try? d.write(to: recipesFile, options: .atomic)
    }

    // The sequence: a seed and an epoch, made once; the days already shown.

    /// The seed, drawn on first use. Not a secret: it makes this device's
    /// sequence its own, nothing more.
    func sequenceSeed() -> UInt64 {
        if let s = UserDefaults.standard.string(forKey: "sequenceSeed"), let v = UInt64(s) { return v }
        let v = UInt64.random(in: 1...UInt64.max)
        UserDefaults.standard.set(String(v), forKey: "sequenceSeed")
        return v
    }

    /// Day zero: the Monday of the week of first use.
    func sequenceEpoch() -> Date {
        if let t = UserDefaults.standard.object(forKey: "sequenceEpoch") as? Double { return Date(timeIntervalSince1970: t) }
        let cal = Calendar.current
        let monday = cal.date(byAdding: .day, value: -WeekDay.today, to: cal.startOfDay(for: Date())) ?? Date()
        UserDefaults.standard.set(monday.timeIntervalSince1970, forKey: "sequenceEpoch")
        return monday
    }

    private var historyFile: URL { folder.appendingPathComponent("sequence-history.json") }

    func readHistory() -> [Int: DayPick] {
        guard let d = try? Data(contentsOf: historyFile),
              let raw = try? JSONDecoder().decode([String: DayPick].self, from: d) else { return [:] }
        var out: [Int: DayPick] = [:]
        for (k, v) in raw { if let i = Int(k) { out[i] = v } }
        return out
    }

    func writeHistory(_ h: [Int: DayPick]) {
        let raw = Dictionary(uniqueKeysWithValues: h.map { (String($0.key), $0.value) })
        guard let d = try? JSONEncoder().encode(raw) else { return }
        try? d.write(to: historyFile, options: .atomic)
    }
}

// MARK: - Serveur

actor RemoteStore {

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    private func request(_ path: String, token: String?, items: [URLQueryItem] = []) -> URLRequest {
        var composants = URLComponents(
            url: Settings.serverBase.appendingPathComponent(path),
            resolvingAgainstBaseURL: false)
        if !items.isEmpty { composants?.queryItems = items }
        var r = URLRequest(url: composants?.url ?? Settings.serverBase.appendingPathComponent(path))
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let j = token { r.setValue("Bearer \(j)", forHTTPHeaderField: "Authorization") }
        return r
    }

    private func execute<T: Decodable>(_ type: T.Type, _ r: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: r)
        guard let http = response as? HTTPURLResponse else { throw RepositoryError.unreadableResponse }
        if http.statusCode == 402 { throw RepositoryError.subscriptionRequired }
        guard (200..<300).contains(http.statusCode) else { throw RepositoryError.network(http.statusCode) }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw RepositoryError.unreadableResponse }
    }

    func manifest(token: String?) async throws -> ManifestResponse {
        try await execute(ManifestResponse.self, request("api/manifest", token: token))
    }

    /// The public catalogue: every card, no body.
    func catalogue() async throws -> CatalogueResponse {
        try await execute(CatalogueResponse.self, request("api/catalogue", token: nil))
    }

    /// Bodies by id. The server hands over only what the account is entitled
    /// to and answers 402 otherwise; the client filters nothing.
    func recipes(ids: [String], token: String?) async throws -> RecipesResponse {
        try await execute(RecipesResponse.self,
            request("api/recipes", token: token,
                    items: [URLQueryItem(name: "ids", value: ids.joined(separator: ","))]))
    }

    func ratings(ids: [String], token: String?) async throws -> [String: RatingSummary] {
        try await execute([String: RatingSummary].self,
            request("api/ratings", token: token,
                    items: [URLQueryItem(name: "ids", value: ids.joined(separator: ","))]))
    }

    struct RatingResponse: Decodable { let ok: Bool?; let summary: RawSummary? }
    struct RawSummary: Decodable { let votes: Int; let average: Double? }

    func rate(_ recetteId: String, note: Int?, token: String) async throws -> RatingSummary {
        var r = request("api/rating", token: token)
        r.httpMethod = "POST"
        let charge: [String: Any] = ["recipe": recetteId, "note": note as Any]
        r.httpBody = try JSONSerialization.data(withJSONObject: charge)
        let rep = try await execute(RatingResponse.self, r)
        return RatingSummary(votes: rep.summary?.votes ?? 0,
                           average: rep.summary?.average,
                           myRating: note)
    }

    func topRated(token: String?) async throws -> TopRatedResponse {
        try await execute(TopRatedResponse.self, request("api/top-rated", token: token))
    }

    func product(code: String, token: String?) async throws -> GroceryProduct {
        try await execute(GroceryProduct.self, request("api/product", token: token,
                                                 items: [URLQueryItem(name: "code", value: code)]))
    }

    struct LoginResponse: Decodable { let token: String; let email: String; let subscribed: Bool? }

    func login(email: String) async throws -> LoginResponse {
        var r = request("api/login", token: nil)
        r.httpMethod = "POST"
        r.httpBody = try JSONEncoder().encode(["email": email])
        return try await execute(LoginResponse.self, r)
    }

    struct TransactionResponse: Decodable { let ok: Bool?; let subscribed: Bool?; let error: String? }

    func linkTransaction(_ jws: String, token: String) async throws -> TransactionResponse {
        var r = request("api/apple/transaction", token: token)
        r.httpMethod = "POST"
        r.httpBody = try JSONEncoder().encode(["signedTransaction": jws])
        return try await execute(TransactionResponse.self, r)
    }
}
