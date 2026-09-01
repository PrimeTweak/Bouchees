// The substitution engine runs inside JavaScriptCore. This is not a web view:
// no HTML, no DOM, no WKWebView.

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
    private var bridge: JSValue?
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
        bridge = p
    }

    /// Injects the safety tables: until that is done the engine refuses to
    /// answer — never a silent default value. - Parameter lexicon: label
    /// vocabulary for the scanner.
    func chargerDonnees(ingredients: Data, substitutions: Data, base baseData: Data,
                        lexicon: Data? = nil) throws {
        let lex = lexicon.map { String(decoding: $0, as: UTF8.self) } ?? "null"
        let enveloppe = """
        {"ingredients":\(String(decoding: ingredients, as: UTF8.self)),\
        "substitutions":\(String(decoding: substitutions, as: UTF8.self)),\
        "lexicon":\(lex),\
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
        guard let bridge else { throw EngineError.exception("bridge not initialised") }
        derniereException = nil
        let retour = bridge.invokeMethod(methode, withArguments: arguments)
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
    func adapt(_ recipes: [Recipe], for profile: ChildProfile) throws -> [AdaptedRecipe] {
        guard pret else { throw EngineError.exception("data not loaded") }
        let k = key(profile, recipes.count)
        if let existing = cache[k] { return existing }

        let encodeur = JSONEncoder()
        let jsonRecettes = String(decoding: try encodeur.encode(recipes), as: UTF8.self)
        let jsonProfil = String(decoding: try encodeur.encode(
            ProfilPourMoteur(ageMonths: profile.ageMonths, allergens: profile.allergens)), as: UTF8.self)

        let raw = try appeler("adaptBatch", [jsonRecettes, jsonProfil])
        let resultats = try decoder([AdaptedRecipe].self, raw, "adapterLot")
        cache[k] = resultats
        return resultats
    }

    func adapt(_ recipe: Recipe, for profile: ChildProfile) throws -> AdaptedRecipe {
        let encodeur = JSONEncoder()
        let jsonRecette = String(decoding: try encodeur.encode(recipe), as: UTF8.self)
        let jsonProfil = String(decoding: try encodeur.encode(
            ProfilPourMoteur(ageMonths: profile.ageMonths, allergens: profile.allergens)), as: UTF8.self)
        let raw = try appeler("adapt", [jsonRecette, jsonProfil])
        return try decoder(AdaptedRecipe.self, raw, "adapter")
    }

    func stage(for ageMonths: Int) throws -> TextureStage {
        let raw = try appeler("stage", [ageMonths])
        return try decoder(TextureStage.self, raw, "stage")
    }

    /// Reads the label of a scanned product. The engine aggregates; Swift only displays.
    func shoppingList(_ recipes: [Recipe], for profile: ChildProfile) throws -> [ShoppingItem] {
        guard pret else { throw EngineError.exception("data not loaded") }
        let encodeur = JSONEncoder()
        let jsonRecettes = String(decoding: try encodeur.encode(recipes), as: UTF8.self)
        let jsonProfil = String(decoding: try encodeur.encode(
            ProfilPourMoteur(ageMonths: profile.ageMonths,
                             allergens: profile.allergens)), as: UTF8.self)
        let raw = try appeler("shoppingList", [jsonRecettes, jsonProfil])
        return try decoder([ShoppingItem].self, raw, "shoppingList")
    }

    func evaluateLabel(_ texte: String, evites: [String]) throws -> ProductVerdict {
        let jsonEvites = String(decoding: try JSONEncoder().encode(evites), as: UTF8.self)
        let raw = try appeler("evaluateLabel", [texte, jsonEvites])
        return try decoder(ProductVerdict.self, raw, "evaluateLabel")
    }

    // MARK: - Confort

    func name(deIngredient id: String) -> String { catalogue[id]?.name ?? id }

    func allergenName(_ id: String) -> String {
        base?.allergens.first { $0.id == id }?.name ?? id
    }

    func allergenNames(_ ids: [String]) -> [String] {
        ids.map { allergenName($0).lowercased() }
    }
}

/// Forme minimale attendue par le bridge JS.
private struct ProfilPourMoteur: Encodable {
    let ageMonths: Int
    let allergens: [String]
}
