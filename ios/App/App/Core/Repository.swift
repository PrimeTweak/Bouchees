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

// MARK: - Resources embarquées

enum Resources {
    /// Les fichiers sont copiés dans le bundle par le workflow, sous
    /// « Resources ». On tente le sous-folder, puis la racine, parce que la
    /// façon dont Xcode aplatit un folder varie selon la configuration.
    static func url(_ name: String, _ extension_: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: extension_, subdirectory: "Resources")
            ?? Bundle.main.url(forResource: name, withExtension: extension_)
    }

    static func data(_ name: String, _ extension_: String) throws -> Data {
        guard let u = url(name, extension_) else {
            throw RepositoryError.ressourceManquante("\(name).\(extension_)")
        }
        return try Data(contentsOf: u)
    }

    /// Les batches gratuits embarqués dans l'app.
    static func lotsEmbarques() -> [URL] {
        let folder = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Resources/batches")
        return folder ?? []
    }
}

enum RepositoryError: LocalizedError {
    case ressourceManquante(String)
    case reseau(Int)
    case abonnementRequis
    case reponseIllisible

    var errorDescription: String? {
        switch self {
        case .ressourceManquante(let n): return "Ressource manquante dans l’app : \(n)"
        case .reseau(let c): return "Le serveur a répondu \(c)."
        case .abonnementRequis: return "Ce lot demande un subscription."
        case .reponseIllisible: return "Réponse du serveur illisible."
        }
    }
}

// MARK: - Réglages

enum Settings {
    /// À remplacer par l'adresse de ton service déployé.
    static var baseServeur: URL {
        if let s = ProcessInfo.processInfo.environment["BOUCHEES_SERVEUR"], let u = URL(string: s) {
            return u
        }
        if let s = Bundle.main.object(forInfoDictionaryKey: "BoucheesServeur") as? String,
           let u = URL(string: s) {
            return u
        }
        return URL(string: "https://bouchees.onrender.com")!
    }

    /// Servies par le serveur lui-même — pas de site séparé à maintenir,
    /// et pas de lien mort au moment de la révision App Store.
    static var conditions: URL { baseServeur.appendingPathComponent("conditions") }
    static var confidentialite: URL { baseServeur.appendingPathComponent("confidentialite") }

    static let avertissementMedical = """
    Bouchées ne remplace pas un avis médical. Les échanges d’ingrédients et les repères d’âge \
    viennent de tables déterministes, à faire valider par un professionnel. En cas d’allergie \
    diagnostiquée, le plan de votre allergologue a toujours préséance.
    """
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

    private var fichierProfils: URL { folder.appendingPathComponent("profiles.json") }
    private var fichierCorpus: URL { folder.appendingPathComponent("recipes.json") }
    private var fichierLots: URL { folder.appendingPathComponent("batches.json") }

    // Profils — jamais envoyés nulle part.

    func lireProfils() -> [ChildProfile] {
        guard let d = try? Data(contentsOf: fichierProfils),
              let p = try? JSONDecoder().decode([ChildProfile].self, from: d) else { return [] }
        return p
    }

    func ecrireProfils(_ profiles: [ChildProfile]) {
        guard let d = try? JSONEncoder().encode(profiles) else { return }
        try? d.write(to: fichierProfils, options: .atomic)
    }

    // Corpus téléchargé — ce qui permet de fonctionner hors ligne.

    func lireCorpus() -> [Recipe]? {
        guard let d = try? Data(contentsOf: fichierCorpus) else { return nil }
        return try? JSONDecoder().decode([Recipe].self, from: d)
    }

    func ecrireCorpus(_ recipes: [Recipe]) {
        guard let d = try? JSONEncoder().encode(recipes) else { return }
        try? d.write(to: fichierCorpus, options: .atomic)
    }

    func lireLots() -> [Batch]? {
        guard let d = try? Data(contentsOf: fichierLots) else { return nil }
        return try? JSONDecoder().decode([Batch].self, from: d)
    }

    func ecrireLots(_ batches: [Batch]) {
        guard let d = try? JSONEncoder().encode(batches) else { return }
        try? d.write(to: fichierLots, options: .atomic)
    }

    var aDuContenu: Bool { fm.fileExists(atPath: fichierCorpus.path) }
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
            url: Settings.baseServeur.appendingPathComponent(path),
            resolvingAgainstBaseURL: false)
        if !items.isEmpty { composants?.queryItems = items }
        var r = URLRequest(url: composants?.url ?? Settings.baseServeur.appendingPathComponent(path))
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let j = token { r.setValue("Bearer \(j)", forHTTPHeaderField: "Authorization") }
        return r
    }

    private func execute<T: Decodable>(_ type: T.Type, _ r: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: r)
        guard let http = response as? HTTPURLResponse else { throw RepositoryError.reponseIllisible }
        if http.statusCode == 402 { throw RepositoryError.abonnementRequis }
        guard (200..<300).contains(http.statusCode) else { throw RepositoryError.reseau(http.statusCode) }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw RepositoryError.reponseIllisible }
    }

    func manifeste(token: String?) async throws -> ManifestResponse {
        try await execute(ManifestResponse.self, request("api/manifeste", token: token))
    }

    /// Le serveur ne renvoie que les batches auxquels le compte a droit. Le
    /// client ne filtre rien : a wall on the client is not a wall.
    func recipes(token: String?) async throws -> RecipesResponse {
        try await execute(RecipesResponse.self, request("api/recipes", token: token))
    }

    func notes(ids: [String], token: String?) async throws -> [String: RatingSummary] {
        try await execute([String: RatingSummary].self,
            request("api/notes", token: token,
                    items: [URLQueryItem(name: "ids", value: ids.joined(separator: ","))]))
    }

    struct ReponseNote: Decodable { let ok: Bool?; let summary: AgregatBrut? }
    struct AgregatBrut: Decodable { let votes: Int; let average: Double? }

    func rate(_ recetteId: String, note: Int?, token: String) async throws -> RatingSummary {
        var r = request("api/note", token: token)
        r.httpMethod = "POST"
        let charge: [String: Any] = ["recipe": recetteId, "note": note as Any]
        r.httpBody = try JSONSerialization.data(withJSONObject: charge)
        let rep = try await execute(ReponseNote.self, r)
        return RatingSummary(votes: rep.summary?.votes ?? 0,
                           average: rep.summary?.average,
                           myRating: note)
    }

    func topRated(token: String?) async throws -> TopRatedResponse {
        try await execute(TopRatedResponse.self, request("api/topRated", token: token))
    }

    func product(code: String, token: String?) async throws -> GroceryProduct {
        try await execute(GroceryProduct.self, request("api/product", token: token,
                                                 items: [URLQueryItem(name: "code", value: code)]))
    }

    struct ReponseConnexion: Decodable { let token: String; let email: String; let subscribed: Bool? }

    func connexion(email: String) async throws -> ReponseConnexion {
        var r = request("api/connexion", token: nil)
        r.httpMethod = "POST"
        r.httpBody = try JSONEncoder().encode(["email": email])
        return try await execute(ReponseConnexion.self, r)
    }

    struct ReponseTransaction: Decodable { let ok: Bool?; let subscribed: Bool?; let error: String? }

    func lierTransaction(_ jws: String, token: String) async throws -> ReponseTransaction {
        var r = request("api/apple/transaction", token: token)
        r.httpMethod = "POST"
        r.httpBody = try JSONEncoder().encode(["signedTransaction": jws])
        return try await execute(ReponseTransaction.self, r)
    }
}
