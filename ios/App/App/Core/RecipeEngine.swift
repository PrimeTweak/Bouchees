//  RecipeEngine.swift
//
//  The substitution engine runs inside JavaScriptCore. This is not a web view:
//  no HTML, no DOM, no WKWebView. It is a computation interpreter, called from
//  Swift, whose JSON output is decoded into Swift types. The interface itself
//  is entirely SwiftUI.
//
//  The choice is deliberate. The engine is covered by a test suite, including
//  an invariant checked across thousands of combinations. Porting it to Swift
//  would create a second truth, and a divergence between the two on food
//  allergies is not a display bug.

import Foundation
import JavaScriptCore

enum EngineError: LocalizedError {
    case contexteIndisponible
    case scriptIntrouvable(String)
    case exception(String)
    case reponseVide(String)
    case decodage(String)

    var errorDescription: String? {
        switch self {
        case .contexteIndisponible:
            return "Le moteur n’a pas pu démarrer."
        case .scriptIntrouvable(let n):
            return "Fichier moteur manquant : \(n)"
        case .exception(let m):
            return "Le moteur a signalé une error : \(m)"
        case .reponseVide(let f):
            return "Le moteur n’a rien retourné pour \(f)."
        case .decodage(let m):
            return "Réponse du moteur illisible : \(m)"
        }
    }
}

@MainActor
final class RecipeEngine {

    private let context: JSContext
    private var pont: JSValue?
    private var derniereException: String?

    /// Cache par profile : recompute 30 recipes à chaque redessin serait du
    /// gaspillage. La clé change dès que l'âge ou un allergène change.
    private var cache: [String: [AdaptedRecipe]] = [:]

    private(set) var pret = false
    private(set) var catalogue: [String: IngredientDefinition] = [:]
    private(set) var base: ReferenceTables?

    // MARK: - Démarrage

    init() throws {
        guard let ctx = JSContext() else { throw EngineError.contexteIndisponible }
        context = ctx
        context.exceptionHandler = { [weak self] _, exception in
            self?.derniereException = exception?.toString() ?? "exception inconnue"
        }
        try chargerScripts()
    }

    private func chargerScripts() throws {
        for name in ["engine", "native-bridge"] {
            guard let url = Resources.url(name, "js") else {
                throw EngineError.scriptIntrouvable("\(name).js")
            }
            let source = try String(contentsOf: url, encoding: .utf8)
            derniereException = nil
            context.evaluateScript(source)
            if let e = derniereException { throw EngineError.exception("\(name).js — \(e)") }
        }
        guard let p = context.objectForKeyedSubscript("PONT"), !p.isUndefined else {
            throw EngineError.exception("PONT introuvable après isLoading")
        }
        pont = p
    }

    /// Injecte les tables de sécurité. Tant que ce n'est pas fait, le moteur
    /// refuse de répondre — jamais de value par défaut silencieuse.
    func chargerDonnees(ingredients: Data, substitutions: Data, base baseData: Data) throws {
        let enveloppe = """
        {"ingredients":\(String(decoding: ingredients, as: UTF8.self)),\
        "substitutions":\(String(decoding: substitutions, as: UTF8.self)),\
        "base":\(String(decoding: baseData, as: UTF8.self))}
        """
        _ = try appeler("load", [enveloppe])

        let decodeur = JSONDecoder()
        catalogue = try decodeur.decode([String: IngredientDefinition].self, from: ingredients)
        base = try decodeur.decode(ReferenceTables.self, from: baseData)
        cache.removeAll()
        pret = true
    }

    // MARK: - Appels

    @discardableResult
    private func appeler(_ methode: String, _ arguments: [Any]) throws -> String {
        guard let pont else { throw EngineError.exception("pont non initialisé") }
        derniereException = nil
        let retour = pont.invokeMethod(methode, withArguments: arguments)
        if let e = derniereException { throw EngineError.exception("\(methode) — \(e)") }
        guard let texte = retour?.toString(), !texte.isEmpty, texte != "undefined" else {
            throw EngineError.reponseVide(methode)
        }
        return texte
    }

    private func decoder<T: Decodable>(_ type: T.Type, _ json: String, _ contexteErreur: String) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw EngineError.decodage("\(contexteErreur) : encodage impossible")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw EngineError.decodage("\(contexteErreur) : \(error)")
        }
    }

    private func key(_ profile: ChildProfile, _ nombreRecettes: Int) -> String {
        "\(profile.ageMonths)|\(profile.allergens.sorted().joined(separator: ","))|\(nombreRecettes)"
    }

    // MARK: - API publique

    /// Adapte tout le recipes d'un coup. Un seul aller-retour to JS plutôt
    /// que trente, et le résultat est mis en cache pour ce profile.
    func adapter(_ recipes: [Recipe], pour profile: ChildProfile) throws -> [AdaptedRecipe] {
        guard pret else { throw EngineError.exception("données non chargées") }
        let k = key(profile, recipes.count)
        if let deja = cache[k] { return deja }

        let encodeur = JSONEncoder()
        let jsonRecettes = String(decoding: try encodeur.encode(recipes), as: UTF8.self)
        let jsonProfil = String(decoding: try encodeur.encode(
            ProfilPourMoteur(ageMonths: profile.ageMonths, allergens: profile.allergens)), as: UTF8.self)

        let brut = try appeler("adaptBatch", [jsonRecettes, jsonProfil])
        let resultats = try decoder([AdaptedRecipe].self, brut, "adapterLot")
        cache[k] = resultats
        return resultats
    }

    func adapter(_ recipe: Recipe, pour profile: ChildProfile) throws -> AdaptedRecipe {
        let encodeur = JSONEncoder()
        let jsonRecette = String(decoding: try encodeur.encode(recipe), as: UTF8.self)
        let jsonProfil = String(decoding: try encodeur.encode(
            ProfilPourMoteur(ageMonths: profile.ageMonths, allergens: profile.allergens)), as: UTF8.self)
        let brut = try appeler("adapt", [jsonRecette, jsonProfil])
        return try decoder(AdaptedRecipe.self, brut, "adapter")
    }

    func stage(pour ageMonths: Int) throws -> TextureStage {
        let brut = try appeler("stage", [ageMonths])
        return try decoder(TextureStage.self, brut, "stage")
    }

    /// Analyse d'une étiquette de product scannée.
    func evaluateLabel(_ texte: String, evites: [String]) throws -> ProductVerdict {
        let jsonEvites = String(decoding: try JSONEncoder().encode(evites), as: UTF8.self)
        let brut = try appeler("evaluateLabel", [texte, jsonEvites])
        return try decoder(ProductVerdict.self, brut, "evaluateLabel")
    }

    func viderCache() { cache.removeAll() }

    // MARK: - Confort

    func name(deIngredient id: String) -> String { catalogue[id]?.name ?? id }

    func allergenName(_ id: String) -> String {
        base?.allergens.first { $0.id == id }?.name ?? id
    }

    func allergenNames(_ ids: [String]) -> [String] {
        ids.map { allergenName($0).lowercased() }
    }
}

/// Forme minimale attendue par le pont JS.
private struct ProfilPourMoteur: Encodable {
    let ageMonths: Int
    let allergens: [String]
}
