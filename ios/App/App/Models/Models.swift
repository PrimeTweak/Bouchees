//  Models.swift
//
//  An exact mirror of the JSON the engine and the server produce. No field is
//  invented here: every property matches a key that is really emitted.
//
//  Enums fall back to an "unknown" case rather than failing to decode. An
//  allergy app that crashes because a new status appeared is worse than one
//  that cautiously says it cannot tell.

import Foundation

// MARK: - Tolerant quantity

/// Quantities arrive as numbers, sometimes as an empty string when ingestion
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

    /// Decimal comma when the locale calls for it.
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
    case safety
    case attention
    case info

    init(from decoder: Decoder) throws {
        let brut = try decoder.singleValueContainer().decode(String.self)
        self = AlertLevel(rawValue: brut) ?? .info
    }

    /// Short label shown ahead of the message.
    var label: String {
        switch self {
        case .bloquant: return "STOP"
        case .safety: return "ÂGE"
        case .attention: return "NOTE"
        case .info: return "ÉCH."
        }
    }
}

// MARK: - Reference data

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

/// base.json — allergen families and texture stages.
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

    /// Filename of a reviewed photo, set by publishing. Absent until a photo
    /// has passed the vision check.
    let image: String?

    /// Rating summary, present only in the Top rated response.
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

// MARK: - Adaptation result

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

    /// Stable identifier for ForEach: one ingredient can appear twice in a
    /// recipe (the flour in the roux and the flour in the batter).
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
    var ageGuidanceCount: Int { alerts.filter { $0.level == .safety }.count }
    var hasChanges: Bool { ingredients.contains { $0.status != .conserve } }

    /// The first swap, for the preview on a card.
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

// MARK: - Verdict on a scanned product

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

    /// Profile resolved when several children eat the same dish: the youngest
    /// age and the union of the allergens. This is the hard case in a family,
    /// and it has to be strict by construction.
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

/// Summary returned by /api/ratings — the public total, plus my own rating.
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
