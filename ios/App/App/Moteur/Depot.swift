//  Depot.swift
//
//  Tout ce qui entre et sort du disque et du réseau.
//
//  Deux principes qui gouvernent ce fichier :
//
//  1. HORS LIGNE PAR DÉFAUT. Le cas d'usage réel, c'est l'allée d'épicerie au
//     sous-sol, sans signal. Le contenu embarqué suffit à faire fonctionner
//     l'app dès la première ouverture, avant toute connexion.
//
//  2. LES PROFILS NE QUITTENT PAS L'APPAREIL. Prénom, âge et allergènes d'un
//     enfant restent dans le conteneur de l'app. Aucune route serveur ne les
//     reçoit. C'est ce qui est déclaré aux étiquettes de confidentialité, et
//     ça doit rester vrai dans le code.

import Foundation

// MARK: - Ressources embarquées

enum Ressources {
    /// Les fichiers sont copiés dans le bundle par le workflow, sous
    /// « Ressources ». On tente le sous-dossier, puis la racine, parce que la
    /// façon dont Xcode aplatit un dossier varie selon la configuration.
    static func url(_ nom: String, _ extension_: String) -> URL? {
        Bundle.main.url(forResource: nom, withExtension: extension_, subdirectory: "Ressources")
            ?? Bundle.main.url(forResource: nom, withExtension: extension_)
    }

    static func data(_ nom: String, _ extension_: String) throws -> Data {
        guard let u = url(nom, extension_) else {
            throw ErreurDepot.ressourceManquante("\(nom).\(extension_)")
        }
        return try Data(contentsOf: u)
    }

    /// Les lots gratuits embarqués dans l'app.
    static func lotsEmbarques() -> [URL] {
        let dossier = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Ressources/lots")
        return dossier ?? []
    }
}

enum ErreurDepot: LocalizedError {
    case ressourceManquante(String)
    case reseau(Int)
    case abonnementRequis
    case reponseIllisible

    var errorDescription: String? {
        switch self {
        case .ressourceManquante(let n): return "Ressource manquante dans l’app : \(n)"
        case .reseau(let c): return "Le serveur a répondu \(c)."
        case .abonnementRequis: return "Ce lot demande un abonnement."
        case .reponseIllisible: return "Réponse du serveur illisible."
        }
    }
}

// MARK: - Réglages

enum Reglages {
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
final class DepotLocal {

    private let fm = FileManager.default

    private var dossier: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Bouchees", isDirectory: true)
        if !fm.fileExists(atPath: base.path) {
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    private var fichierProfils: URL { dossier.appendingPathComponent("profils.json") }
    private var fichierCorpus: URL { dossier.appendingPathComponent("corpus.json") }
    private var fichierLots: URL { dossier.appendingPathComponent("lots.json") }

    // Profils — jamais envoyés nulle part.

    func lireProfils() -> [Profil] {
        guard let d = try? Data(contentsOf: fichierProfils),
              let p = try? JSONDecoder().decode([Profil].self, from: d) else { return [] }
        return p
    }

    func ecrireProfils(_ profils: [Profil]) {
        guard let d = try? JSONEncoder().encode(profils) else { return }
        try? d.write(to: fichierProfils, options: .atomic)
    }

    // Corpus téléchargé — ce qui permet de fonctionner hors ligne.

    func lireCorpus() -> [Recette]? {
        guard let d = try? Data(contentsOf: fichierCorpus) else { return nil }
        return try? JSONDecoder().decode([Recette].self, from: d)
    }

    func ecrireCorpus(_ recettes: [Recette]) {
        guard let d = try? JSONEncoder().encode(recettes) else { return }
        try? d.write(to: fichierCorpus, options: .atomic)
    }

    func lireLots() -> [Lot]? {
        guard let d = try? Data(contentsOf: fichierLots) else { return nil }
        return try? JSONDecoder().decode([Lot].self, from: d)
    }

    func ecrireLots(_ lots: [Lot]) {
        guard let d = try? JSONEncoder().encode(lots) else { return }
        try? d.write(to: fichierLots, options: .atomic)
    }

    var aDuContenu: Bool { fm.fileExists(atPath: fichierCorpus.path) }
}

// MARK: - Serveur

actor DepotServeur {

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    private func requete(_ chemin: String, jeton: String?, elements: [URLQueryItem] = []) -> URLRequest {
        var composants = URLComponents(
            url: Reglages.baseServeur.appendingPathComponent(chemin),
            resolvingAgainstBaseURL: false)
        if !elements.isEmpty { composants?.queryItems = elements }
        var r = URLRequest(url: composants?.url ?? Reglages.baseServeur.appendingPathComponent(chemin))
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let j = jeton { r.setValue("Bearer \(j)", forHTTPHeaderField: "Authorization") }
        return r
    }

    private func executer<T: Decodable>(_ type: T.Type, _ r: URLRequest) async throws -> T {
        let (data, reponse) = try await session.data(for: r)
        guard let http = reponse as? HTTPURLResponse else { throw ErreurDepot.reponseIllisible }
        if http.statusCode == 402 { throw ErreurDepot.abonnementRequis }
        guard (200..<300).contains(http.statusCode) else { throw ErreurDepot.reseau(http.statusCode) }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw ErreurDepot.reponseIllisible }
    }

    func manifeste(jeton: String?) async throws -> ManifesteReponse {
        try await executer(ManifesteReponse.self, requete("api/manifeste", jeton: jeton))
    }

    /// Le serveur ne renvoie que les lots auxquels le compte a droit. Le
    /// client ne filtre rien : un mur côté client n'est pas un mur.
    func recettes(jeton: String?) async throws -> RecettesReponse {
        try await executer(RecettesReponse.self, requete("api/recettes", jeton: jeton))
    }

    func produit(code: String, jeton: String?) async throws -> Produit {
        try await executer(Produit.self, requete("api/produit", jeton: jeton,
                                                 elements: [URLQueryItem(name: "code", value: code)]))
    }

    struct ReponseConnexion: Decodable { let jeton: String; let courriel: String; let abonne: Bool? }

    func connexion(courriel: String) async throws -> ReponseConnexion {
        var r = requete("api/connexion", jeton: nil)
        r.httpMethod = "POST"
        r.httpBody = try JSONEncoder().encode(["courriel": courriel])
        return try await executer(ReponseConnexion.self, r)
    }

    struct ReponseTransaction: Decodable { let ok: Bool?; let abonne: Bool?; let erreur: String? }

    func lierTransaction(_ jws: String, jeton: String) async throws -> ReponseTransaction {
        var r = requete("api/apple/transaction", jeton: jeton)
        r.httpMethod = "POST"
        r.httpBody = try JSONEncoder().encode(["signedTransaction": jws])
        return try await executer(ReponseTransaction.self, r)
    }
}
