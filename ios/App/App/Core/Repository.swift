//  Repository.swift
//
//  Everything that touches disk or network.
//
//  Two principles govern this file:
//
//  1. OFFLINE FIRST. The real use case is a grocery aisle in a basement with
//     no signal. Bundled content is enough to make the app work on first
//     launch, before any connection.
//
//  2. PROFILES NEVER LEAVE THE DEVICE. A child's first name, age and avoided
//     allergens stay in the app container. No server route receives them.
//     That is what the App Store privacy labels declare, and it has to stay
//     true in the code.

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

    /// The free batches shipped inside the app.
    static func bundledBatches() -> [URL] {
        let folder = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Bundled/batches")
        return folder ?? []
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
    private var batchesFile: URL { folder.appendingPathComponent("batches.json") }

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
        return try? JSONDecoder().decode([Recipe].self, from: d)
    }

    func writeRecipes(_ recipes: [Recipe]) {
        guard let d = try? JSONEncoder().encode(recipes) else { return }
        try? d.write(to: recipesFile, options: .atomic)
    }

    func readBatches() -> [Batch]? {
        guard let d = try? Data(contentsOf: batchesFile) else { return nil }
        return try? JSONDecoder().decode([Batch].self, from: d)
    }

    func writeBatches(_ batches: [Batch]) {
        guard let d = try? JSONEncoder().encode(batches) else { return }
        try? d.write(to: batchesFile, options: .atomic)
    }

    var hasContent: Bool { fm.fileExists(atPath: recipesFile.path) }
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

    /// Le serveur ne renvoie que les batches auxquels le compte a droit. Le
    /// client ne filtre rien : a wall on the client is not a wall.
    func recipes(token: String?) async throws -> RecipesResponse {
        try await execute(RecipesResponse.self, request("api/recipes", token: token))
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
