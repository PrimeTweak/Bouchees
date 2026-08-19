//  MoteurJS.swift
//
//  Le moteur de substitution tourne dans JavaScriptCore. Ce n'est pas une vue
//  web : aucun HTML, aucun DOM, aucune WKWebView. C'est un interpréteur de
//  calcul, appelé depuis Swift, dont la sortie est du JSON décodé en types
//  Swift. L'interface, elle, est entièrement SwiftUI.
//
//  Ce choix est délibéré. Le moteur est couvert par 90 tests, dont un
//  invariant vérifié sur des milliers de combinaisons. Le porter en Swift
//  créerait une deuxième vérité, et un écart entre les deux sur des allergies
//  alimentaires n'est pas un bogue d'affichage.

import Foundation
import JavaScriptCore

enum ErreurMoteur: LocalizedError {
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
            return "Le moteur a signalé une erreur : \(m)"
        case .reponseVide(let f):
            return "Le moteur n’a rien retourné pour \(f)."
        case .decodage(let m):
            return "Réponse du moteur illisible : \(m)"
        }
    }
}

@MainActor
final class MoteurJS {

    private let contexte: JSContext
    private var pont: JSValue?
    private var derniereException: String?

    /// Cache par profil : recalculer 30 recettes à chaque redessin serait du
    /// gaspillage. La clé change dès que l'âge ou un allergène change.
    private var cache: [String: [RecetteAdaptee]] = [:]

    private(set) var pret = false
    private(set) var catalogue: [String: DefinitionIngredient] = [:]
    private(set) var base: BaseReference?

    // MARK: - Démarrage

    init() throws {
        guard let ctx = JSContext() else { throw ErreurMoteur.contexteIndisponible }
        contexte = ctx
        contexte.exceptionHandler = { [weak self] _, exception in
            self?.derniereException = exception?.toString() ?? "exception inconnue"
        }
        try chargerScripts()
    }

    private func chargerScripts() throws {
        for nom in ["moteur", "pont-natif"] {
            guard let url = Ressources.url(nom, "js") else {
                throw ErreurMoteur.scriptIntrouvable("\(nom).js")
            }
            let source = try String(contentsOf: url, encoding: .utf8)
            derniereException = nil
            contexte.evaluateScript(source)
            if let e = derniereException { throw ErreurMoteur.exception("\(nom).js — \(e)") }
        }
        guard let p = contexte.objectForKeyedSubscript("PONT"), !p.isUndefined else {
            throw ErreurMoteur.exception("PONT introuvable après chargement")
        }
        pont = p
    }

    /// Injecte les tables de sécurité. Tant que ce n'est pas fait, le moteur
    /// refuse de répondre — jamais de valeur par défaut silencieuse.
    func chargerDonnees(ingredients: Data, substitutions: Data, base baseData: Data) throws {
        let enveloppe = """
        {"ingredients":\(String(decoding: ingredients, as: UTF8.self)),\
        "substitutions":\(String(decoding: substitutions, as: UTF8.self)),\
        "base":\(String(decoding: baseData, as: UTF8.self))}
        """
        _ = try appeler("charger", [enveloppe])

        let decodeur = JSONDecoder()
        catalogue = try decodeur.decode([String: DefinitionIngredient].self, from: ingredients)
        base = try decodeur.decode(BaseReference.self, from: baseData)
        cache.removeAll()
        pret = true
    }

    // MARK: - Appels

    @discardableResult
    private func appeler(_ methode: String, _ arguments: [Any]) throws -> String {
        guard let pont else { throw ErreurMoteur.exception("pont non initialisé") }
        derniereException = nil
        let retour = pont.invokeMethod(methode, withArguments: arguments)
        if let e = derniereException { throw ErreurMoteur.exception("\(methode) — \(e)") }
        guard let texte = retour?.toString(), !texte.isEmpty, texte != "undefined" else {
            throw ErreurMoteur.reponseVide(methode)
        }
        return texte
    }

    private func decoder<T: Decodable>(_ type: T.Type, _ json: String, _ contexteErreur: String) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw ErreurMoteur.decodage("\(contexteErreur) : encodage impossible")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ErreurMoteur.decodage("\(contexteErreur) : \(error)")
        }
    }

    private func cle(_ profil: Profil, _ nombreRecettes: Int) -> String {
        "\(profil.ageMois)|\(profil.allergenes.sorted().joined(separator: ","))|\(nombreRecettes)"
    }

    // MARK: - API publique

    /// Adapte tout le corpus d'un coup. Un seul aller-retour vers JS plutôt
    /// que trente, et le résultat est mis en cache pour ce profil.
    func adapter(_ recettes: [Recette], pour profil: Profil) throws -> [RecetteAdaptee] {
        guard pret else { throw ErreurMoteur.exception("données non chargées") }
        let k = cle(profil, recettes.count)
        if let deja = cache[k] { return deja }

        let encodeur = JSONEncoder()
        let jsonRecettes = String(decoding: try encodeur.encode(recettes), as: UTF8.self)
        let jsonProfil = String(decoding: try encodeur.encode(
            ProfilPourMoteur(ageMois: profil.ageMois, allergenes: profil.allergenes)), as: UTF8.self)

        let brut = try appeler("adapterLot", [jsonRecettes, jsonProfil])
        let resultats = try decoder([RecetteAdaptee].self, brut, "adapterLot")
        cache[k] = resultats
        return resultats
    }

    func adapter(_ recette: Recette, pour profil: Profil) throws -> RecetteAdaptee {
        let encodeur = JSONEncoder()
        let jsonRecette = String(decoding: try encodeur.encode(recette), as: UTF8.self)
        let jsonProfil = String(decoding: try encodeur.encode(
            ProfilPourMoteur(ageMois: profil.ageMois, allergenes: profil.allergenes)), as: UTF8.self)
        let brut = try appeler("adapter", [jsonRecette, jsonProfil])
        return try decoder(RecetteAdaptee.self, brut, "adapter")
    }

    func stade(pour ageMois: Int) throws -> Stade {
        let brut = try appeler("stade", [ageMois])
        return try decoder(Stade.self, brut, "stade")
    }

    /// Analyse d'une étiquette de produit scannée.
    func evaluerEtiquette(_ texte: String, evites: [String]) throws -> VerdictProduit {
        let jsonEvites = String(decoding: try JSONEncoder().encode(evites), as: UTF8.self)
        let brut = try appeler("evaluerEtiquette", [texte, jsonEvites])
        return try decoder(VerdictProduit.self, brut, "evaluerEtiquette")
    }

    func viderCache() { cache.removeAll() }

    // MARK: - Confort

    func nom(deIngredient id: String) -> String { catalogue[id]?.nom ?? id }

    func nomAllergene(_ id: String) -> String {
        base?.allergenes.first { $0.id == id }?.nom ?? id
    }

    func nomsAllergenes(_ ids: [String]) -> [String] {
        ids.map { nomAllergene($0).lowercased() }
    }
}

/// Forme minimale attendue par le pont JS.
private struct ProfilPourMoteur: Encodable {
    let ageMois: Int
    let allergenes: [String]
}
