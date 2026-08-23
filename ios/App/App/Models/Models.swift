//  Models.swift
//
//  An exact mirror of the JSON the engine and the server produce. No field is
//  invented here: every property matches a key that is really emitted.
//
//  Enums fall back to an "unknown" case rather than failing to decode. An
//  allergy app that crashes because a new status appeared is worse than one
//  that cautiously says it cannot tell.

import Foundation

// MARK: - Quantité tolérante

/// Les quantités arrivent en count, parfois en chaîne vide quand l'ingestion
/// n'a rien pu extraire. On accepte les deux sans faire tomber la recipe.
struct Quantity: Codable, Hashable, Sendable {
    let value: Double?

    init(_ value: Double?) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) {
            value = d
        } else if let s = try? c.decode(String.self) {
            value = Double(s.replacingOccurrences(of: ",", with: "."))
        } else {
            value = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let v = value { try c.encode(v) } else { try c.encode("") }
    }

    /// « 2,5 » plutôt que « 2.5 » — on écrit en français.
    var affichage: String {
        guard let v = value else { return "" }
        if v == v.rounded() && abs(v) < 1_000_000 {
            return String(Int(v))
        }
        return String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: - Statuts

enum RecipeStatus: String, Codable, Sendable {
    case telleQuelle = "telle_quelle"
    case adaptee
    case nonAdaptable = "non_adaptable"
    case inconnu

    init(from decoder: Decoder) throws {
        let brut = try decoder.singleValueContainer().decode(String.self)
        self = RecipeStatus(rawValue: brut) ?? .inconnu
    }
}

enum IngredientStatus: String, Codable, Sendable {
    case conserve
    case substitue
    case omis
    case impossible
    case inconnu

    init(from decoder: Decoder) throws {
        let brut = try decoder.singleValueContainer().decode(String.self)
        self = IngredientStatus(rawValue: brut) ?? .inconnu
    }
}

enum AlertLevel: String, Codable, Sendable {
    case bloquant
    case securite
    case attention
    case info

    init(from decoder: Decoder) throws {
        let brut = try decoder.singleValueContainer().decode(String.self)
        self = AlertLevel(rawValue: brut) ?? .info
    }

    /// Étiquette courte affichée devant le message.
    var label: String {
        switch self {
        case .bloquant: return "STOP"
        case .securite: return "ÂGE"
        case .attention: return "NOTE"
        case .info: return "ÉCH."
        }
    }
}

// MARK: - Données de référence

struct Allergen: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
}

struct TextureStage: Codable, Hashable, Sendable {
    let min: Int
    let max: Int
    let name: String
    let texture: String
    let note: String?
}

struct IngredientDefinition: Codable, Hashable, Sendable {
    let name: String
    let allergens: [String]
    let roles: [String]
    let note: String?
}

/// base.json — familles d'allergènes et stades de texture.
struct ReferenceTables: Codable, Sendable {
    let allergens: [Allergen]
    let stades: [TextureStage]
}

// MARK: - Recipe

struct RecipeIngredient: Codable, Hashable, Sendable {
    let id: String
    let qty: Quantity
    let unit: String
    let role: String?
}

struct RecipeSource: Codable, Hashable, Sendable {
    let source: String
    let url: String?
    let license: String
}

struct Recipe: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let category: String
    let servings: String?
    let minAgeMonths: Int
    let timeMinutes: Int?
    let ingredients: [RecipeIngredient]
    let steps: [String]
    let lot: String?
    let source: RecipeSource?

    /// Nom de file d'une photo révisée, posé par la publication. Absent
    /// tant qu'aucune photo n'a passé la vérification par vision.
    let image: String?

    /// Agrégat de notes, présent seulement dans la réponse des Meilleures.
    let votes: Int?
    let average: Double?
    let myRating: Int?

    var subtitle: String {
        var bouts = [category]
        if let t = timeMinutes { bouts.append("\(t) min") }
        if let p = servings, !p.isEmpty { bouts.append(p) }
        return bouts.joined(separator: " · ")
    }
}

// MARK: - Résultat de l'adaptation

struct AdaptedIngredient: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let qty: Quantity
    let unit: String
    let role: String
    let status: IngredientStatus
    let to: String?
    let toName: String?
    let ratio: String?
    let reason: String?
    let prep: String?
    let ingredientNote: String?
    let substituteNote: String?

    /// Identifiant stable pour ForEach : un ingrédient peut apparaître deux
    /// fois dans une recipe (la farine du roux et celle de la pâte).
    var listID: String { id + "-" + role }
    var note: String? { substituteNote ?? ingredientNote }

    var displayQuantity: String {
        let q = qty.affichage
        var u = unit
        if u == "unité", let v = qty.value, v > 1 { u = "unités" }
        return q.isEmpty ? u : "\(q) \(u)"
    }
}

struct Alert: Codable, Hashable, Identifiable, Sendable {
    let level: AlertLevel
    let message: String
    var id: String { level.rawValue + message }
}

struct AdaptedRecipe: Codable, Sendable {
    let id: String
    let name: String
    let status: RecipeStatus
    let swapCount: Int
    let ingredients: [AdaptedIngredient]
    let alerts: [Alert]
    let texture: TextureStage
    let steps: [String]
    let remainingAllergens: [String]

    var blockingAlert: Alert? { alerts.first { $0.level == .bloquant } }
    var nonBlockingAlerts: [Alert] { alerts.filter { $0.level != .bloquant } }
    var ageGuidanceCount: Int { alerts.filter { $0.level == .securite }.count }
    var hasChanges: Bool { ingredients.contains { $0.status != .conserve } }

    /// Le premier échange, pour l'aperçu sur une carte.
    var firstSwap: (de: String, to: String)? {
        if let s = ingredients.first(where: { $0.status == .substitue }), let v = s.toName {
            return (s.name, v)
        }
        if let o = ingredients.first(where: { $0.status == .omis }) {
            return (o.name, "we leave it out")
        }
        return nil
    }
}

// MARK: - Verdict d'un product scanné

struct ProductVerdict: Codable, Sendable {
    enum Statut: String, Codable, Sendable {
        case sur, aEviter = "a_eviter", incertain
        init(from decoder: Decoder) throws {
            let brut = try decoder.singleValueContainer().decode(String.self)
            self = Statut(rawValue: brut) ?? .incertain
        }
    }
    let status: Statut
    let allergensFound: [String]
    let unknownIngredients: [String]
    let message: String
}

struct GroceryProduct: Codable, Sendable {
    let code: String
    let name: String?
    let marque: String?
    let ingredientsText: String?
    let attribution: String?
}

// MARK: - ChildProfile

struct ChildProfile: Codable, Hashable, Identifiable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var ageMonths: Int
    var allergens: [String]

    static let defaut = ChildProfile(name: "Mon enfant", ageMonths: 9, allergens: [])

    /// ChildProfile résolu quand plusieurs enfants mangent le même plat : on prend
    /// l'âge du plus jeune et l'union des allergènes. C'est le vrai cas
    /// difficile d'une famille, et il doit être strict par construction.
    static func famille(_ profiles: [ChildProfile]) -> ChildProfile {
        guard !profiles.isEmpty else { return .defaut }
        let age = profiles.map(\.ageMonths).min() ?? 9
        var union: [String] = []
        for p in profiles where !p.allergens.isEmpty {
            for a in p.allergens where !union.contains(a) { union.append(a) }
        }
        return ChildProfile(id: "famille", name: "tout le monde", ageMonths: age, allergens: union.sorted())
    }
}

// MARK: - Lots et subscription

struct Batch: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let date: String?
    let access: String
    let note: String?
    let count: Int
    var unlocked: Bool
    var weekly: Bool?
    var inWindow: Bool?

    var isFree: Bool { access == "libre" }
    var isWeekly: Bool { weekly ?? false }
}

struct ManifestResponse: Codable, Sendable {
    let version: String?
    let subscribed: Bool?
    let currentWeek: String?
    let windowSize: Int?
    let batches: [Batch]
}

/// Agrégat renvoyé par /api/notes — le total public, plus ma propre note.
struct RatingSummary: Codable, Hashable, Sendable {
    let votes: Int
    let average: Double?
    let myRating: Int?
}

struct TopRatedResponse: Codable, Sendable {
    let threshold: Int
    let recipes: [Recipe]
}

struct RecipesResponse: Codable, Sendable {
    let subscribed: Bool?
    let batches: [String]?
    let recipes: [Recipe]
}
