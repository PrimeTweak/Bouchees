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
            return String(localized: "The engine could not start.")
        case .scriptIntrouvable(let n):
            return String(localized: "Engine file missing: \(n)")
        case .exception(let m):
            return String(localized: "The engine reported an error: \(m)")
        case .reponseVide(let f):
            return String(localized: "The engine returned nothing for \(f).")
        case .decodage(let m):
            return String(localized: "The engine's answer could not be read: \(m)")
        }
    }
}

@MainActor
final class RecipeEngine {

    private let context: JSContext
    private var pont: JSValue?
    private var derniereException: String?

    /// Cache per profile: recomputing 30 recipes on every redraw would be
    /// waste. The key changes as soon as the age or an allergen changes.
    private var cache: [String: [AdaptedRecipe]] = [:]

    private(set) var pret = false
    private(set) var catalogue: [String: IngredientDefinition] = [:]
    private(set) var base: ReferenceTables?

    // MARK: - Startup

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
            throw EngineError.exception("PONT not found after loading")
        }
        pont = p
    }

    /// Injects the safety tables. Until that is done the engine refuses to
    /// answer — never a silent default value.
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
        guard let pont else { throw EngineError.exception("bridge not initialised") }
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

    /// Adapts the whole corpus at once. One round trip into JS instead of
    /// thirty, and the result is cached for this profile.
    func adapter(_ recipes: [Recipe], pour profile: ChildProfile) throws -> [AdaptedRecipe] {
        guard pret else { throw EngineError.exception("data not loaded") }
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

    /// Reads the label of a scanned product.
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
