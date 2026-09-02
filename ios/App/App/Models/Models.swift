// No field is invented here: every property matches a key that is really
// emitted. An allergy app that crashes because a new status appeared is worse
// than one that cautiously says it cannot tell.

import Foundation
/* LocalizedStringKey lives in SwiftUI. The models are otherwise
 * Foundation-only, and stay that way. */
import SwiftUI

// MARK: - Tolerant quantity

/// A quantity arrives as a number, or as an empty string when ingestion
/// could not extract one. Both decode; neither fails the recipe.
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

/* They are the one place where a rename on one side alone shows no error: an
 * unknown case falls back to `unknown`, every recipe lands outside every
 * section, and the list goes silently empty. That is exactly what happened. */

enum RecipeStatus: String, Codable, Sendable {
    case asIs = "as_is"
    case adapted
    case notAdaptable = "not_adaptable"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RecipeStatus(rawValue: raw) ?? .unknown
    }
}

enum IngredientStatus: String, Codable, Sendable {
    case kept
    case swapped
    case omitted
    case blocked
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = IngredientStatus(rawValue: raw) ?? .unknown
    }
}

enum AlertLevel: String, Codable, Sendable {
    case blocking
    case safety
    case caution
    case info

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AlertLevel(rawValue: raw) ?? .info
    }

    /// Short label shown ahead of the message.
    var label: String {
        switch self {
        case .blocking: return String(localized: "STOP")
        case .safety:   return String(localized: "AGE")
        case .caution:  return String(localized: "NOTE")
        case .info:     return String(localized: "SWAP")
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
    let stages: [TextureStage]
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
    /// The body. Empty on a catalogue card until the server hands it over.
    let ingredients: [RecipeIngredient]
    let steps: [String]
    let source: RecipeSource?

    /// Filename of a reviewed photo, set by publishing. Absent until a photo
    /// has passed the vision check.
    let image: String?
    /// A 480px version for thumbnails, when the pipeline made one.
    let thumb: String?

    /// Card fields from the catalogue: served to everyone, no body needed.
    let free: Bool?
    let allergens: [String]?
    /// Per allergen family: as_is, adapted or not_adaptable, from the engine.
    let adaptability: [String: String]?

    /// Rating summary, present only in the Top rated response.
    let votes: Int?
    let average: Double?
    let myRating: Int?

    /// True once the ingredients and steps are here.
    var hasBody: Bool { !steps.isEmpty }
    var isMeal: Bool { category == "Meal" }
    var isSnack: Bool { category == "Snack" }

    enum CodingKeys: String, CodingKey {
        case id, name, category, servings, minAgeMonths, timeMinutes, ingredients, steps,
             source, image, thumb, free, allergens, adaptability, votes, average, myRating
    }

    /// A card decodes without a body: the two lists default to empty.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decode(String.self, forKey: .category)
        servings = try c.decodeIfPresent(String.self, forKey: .servings)
        minAgeMonths = try c.decode(Int.self, forKey: .minAgeMonths)
        timeMinutes = try c.decodeIfPresent(Int.self, forKey: .timeMinutes)
        ingredients = try c.decodeIfPresent([RecipeIngredient].self, forKey: .ingredients) ?? []
        steps = try c.decodeIfPresent([String].self, forKey: .steps) ?? []
        source = try c.decodeIfPresent(RecipeSource.self, forKey: .source)
        image = try c.decodeIfPresent(String.self, forKey: .image)
        thumb = try c.decodeIfPresent(String.self, forKey: .thumb)
        free = try c.decodeIfPresent(Bool.self, forKey: .free)
        allergens = try c.decodeIfPresent([String].self, forKey: .allergens)
        adaptability = try c.decodeIfPresent([String: String].self, forKey: .adaptability)
        votes = try c.decodeIfPresent(Int.self, forKey: .votes)
        average = try c.decodeIfPresent(Double.self, forKey: .average)
        myRating = try c.decodeIfPresent(Int.self, forKey: .myRating)
    }

    /// The card, with a body merged in.
    func with(body: Recipe) -> Recipe {
        Recipe(card: self, ingredients: body.ingredients, steps: body.steps)
    }

    init(card: Recipe, ingredients: [RecipeIngredient], steps: [String]) {
        id = card.id; name = card.name; category = card.category; servings = card.servings
        minAgeMonths = card.minAgeMonths; timeMinutes = card.timeMinutes
        self.ingredients = ingredients; self.steps = steps
        source = card.source; image = card.image; thumb = card.thumb
        free = card.free; allergens = card.allergens; adaptability = card.adaptability
        votes = card.votes; average = card.average; myRating = card.myRating
    }

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
        if u == "unit", let v = qty.value, v > 1 { u = String(localized: "units") }
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
    /// The text before the swapped names were substituted in. Optional so an
    /// older cached payload still decodes.
    let stepsOriginal: [String]?
    let remainingAllergens: [String]

    var blockingAlert: Alert? { alerts.first { $0.level == .blocking } }
    var nonBlockingAlerts: [Alert] { alerts.filter { $0.level != .blocking } }
    var ageGuidanceCount: Int { alerts.filter { $0.level == .safety }.count }
    var hasChanges: Bool { ingredients.contains { $0.status != .kept } }

    /// The first swap, for the preview on a card.
    var firstSwap: (de: String, to: String)? {
        if let s = ingredients.first(where: { $0.status == .swapped }), let v = s.toName {
            return (s.name, v)
        }
        if let o = ingredients.first(where: { $0.status == .omitted }) {
            return (o.name, "we leave it out")
        }
        return nil
    }
}

// MARK: - Verdict on a scanned product

struct ProductVerdict: Codable, Sendable {
    /* This declared sur / a_eviter / incertain, so EVERY scanned product fell
     * through to the fallback and came back "uncertain" — the scanner has
     * been silently broken since the conversion, and nothing could see. */
    enum Statut: String, Codable, Sendable {
        /* `caution` is a declared factory warning: the ingredient list itself
         * came back clean, and the label says the product may have met the
         * allergen elsewhere. */
        case safe, avoid, uncertain, caution
        init(from decoder: Decoder) throws {
            let rawText = try decoder.singleValueContainer().decode(String.self)
            /* An unknown state falls to `uncertain`, never to `safe`. */
            self = Statut(rawValue: rawText) ?? .uncertain
        }
    }
    let status: Statut
    let allergensFound: [String]
    /* Allergens the label warns about without declaring. Always present, even
     * when the status is driven by something else, so a screen can show the
     * warning beside an `avoid` or an `uncertain`. */
    let mayContain: [String]
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

    /// What the header says. A first name is what a parent recognises at a
    /// glance; the full stored name may carry more than that.
    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    static let defaut = ChildProfile(name: String(localized: "My child"), ageMonths: 9, allergens: [])

    /// Profile resolved when several children eat the same dish: the youngest
    /// age and the union of the allergens. This is the hard case in a family,
    /// and it has to be strict by construction.
    static func family(_ profiles: [ChildProfile]) -> ChildProfile {
        guard !profiles.isEmpty else { return .defaut }
        let age = profiles.map(\.ageMonths).min() ?? 9
        var union: [String] = []
        for p in profiles where !p.allergens.isEmpty {
            for a in p.allergens where !union.contains(a) { union.append(a) }
        }
        return ChildProfile(id: "family", name: String(localized: "Everyone"), ageMonths: age, allergens: union.sorted())
    }
}

// MARK: - Catalogue and subscription

struct ManifestResponse: Codable, Sendable {
    let version: String?
    let subscribed: Bool?
    let rotationWeeks: Int?
    let catalogueChecksum: String?
}

struct CatalogueResponse: Codable, Sendable {
    let catalogue: [Recipe]
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
    let recipes: [Recipe]
    let unknown: [String]?
}

// MARK: - Substitution table, for display

/// The shape of substitutions.json, decoded so the app can SHOW the rule that
/// produced a swap — every option, in order, with its ratio and minimum age.
/// The engine reads its own copy through the bridge.
struct SubstitutionEntry: Codable, Sendable {
    let role: String
    let target: String
    let options: [SubstitutionOptionRaw]
}

struct SubstitutionOptionRaw: Codable, Sendable {
    let id: String
    let ratio: String?
    let note: String?
    let minAgeMonths: Int?
}

// MARK: - Shopping

/// `quantities` is a LIST, not a number: the corpus mixes "125 ml" with "1
/// unit", and a single total across those would be wrong on a shopping list.
/// One line of the week's shopping list, as the engine produces it.
struct ShoppingItem: Codable, Identifiable, Hashable, Sendable {
    let name: String
    let aisle: String
    let quantities: [ShoppingQuantity]
    let recipes: [String]
    /// The ingredient this one stands in for, when the engine swapped it.
    let replaces: String?

    var id: String { name.lowercased() }

    /// "375 ml", or "1 unit + 250 ml" when the units do not add up.
    var quantityLabel: String {
        quantities.map { q in
            q.unit.isEmpty ? Format.number(q.value)
                           : "\(Format.number(q.value)) \(q.unit)"
        }
        .joined(separator: " + ")
    }
}

struct ShoppingQuantity: Codable, Hashable, Sendable {
    let value: Double
    let unit: String
}

// MARK: - The week

/// Which recipe sits on which day: the plan is a map from a day index to
/// recipe ids — not a list, because a day can hold two things and another
/// none.
struct WeekPlan: Codable, Equatable {
    /// Monday is 0. Matches the ISO week the batch is named after.
    var days: [Int: [String]]

    static let empty = WeekPlan(days: [:])

    /// The day a recipe currently sits on, if any.
    func day(of recipeID: String) -> Int? {
        days.first { $0.value.contains(recipeID) }?.key
    }

    func recipes(on day: Int) -> [String] { days[day] ?? [] }

    var assignedCount: Int { days.values.reduce(0) { $0 + $1.count } }

    /// Moves a recipe to another day, removing it from wherever it was.
    mutating func move(_ recipeID: String, to day: Int) {
        for key in days.keys {
            days[key]?.removeAll { $0 == recipeID }
            if days[key]?.isEmpty == true { days[key] = nil }
        }
        days[day, default: []].append(recipeID)
    }

    /// Swaps everything between two days. What a long press offers.
    mutating func swap(_ a: Int, _ b: Int) {
        let left = days[a]
        days[a] = days[b]
        days[b] = left
        if days[a]?.isEmpty ?? true { days[a] = nil }
        if days[b]?.isEmpty ?? true { days[b] = nil }
    }

    /// The first plan for a batch: spread across the days a family actually
    /// cooks, weekend last. Deterministic, so the same week always opens the
    /// same way until the parent moves something.
    static func initial(for recipes: [Recipe]) -> WeekPlan {
        var plan = WeekPlan.empty
        /* Weeknights first — Monday through Friday is when a plan helps. The
         * weekend is left open on purpose. */
        for (i, r) in recipes.enumerated() {
            plan.days[defaultDay(forIndex: i), default: []].append(r.id)
        }
        return plan
    }

    /// Which day a recipe lands on, by position: exposed rather than inlined:
    /// a week the parent cannot rearrange — a locked one — is laid out with
    /// this same rule, and two copies of it would drift.
    static func defaultDay(forIndex i: Int) -> Int { i % 7 }
}

/// Day names, short, for the strip: the rail replaced seven day pills.
struct WeekSlot: Identifiable, Hashable {
    /// -1 past, 0 current, +1 next. The id, since only three exist.
    let offset: Int
    /// How many recipes it holds — shown even when the week is locked.
    let count: Int
    /// False when the parent has to subscribe to open it.
    let unlocked: Bool

    var id: Int { offset }

    /// Monday of this slot.
    func monday(calendar: Calendar = .current) -> Date? {
        let base = calendar.date(byAdding: .day, value: -WeekDay.today, to: Date())
        return base.flatMap { calendar.date(byAdding: .day, value: offset * 7, to: $0) }
    }

    /// The span, formatted in the parent locale.
    func span(calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard let monday_ = monday(calendar: calendar),
              let sunday_ = calendar.date(byAdding: .day, value: 6, to: monday_)
        else { return "" }

        let day_ = DateFormatter()
        day_.locale = locale
        day_.setLocalizedDateFormatFromTemplate("d")

        let dayMonth = DateFormatter()
        dayMonth.locale = locale
        dayMonth.setLocalizedDateFormatFromTemplate("dMMM")

        /* The month is named once when the week does not cross one, and twice
         * when it does. Naming it once on a week that crosses a month hides
         * that the week started in the previous one. */
        let sameMonth = calendar.component(.month, from: monday_)
            == calendar.component(.month, from: sunday_)
        let start = sameMonth ? day_.string(from: monday_) : dayMonth.string(from: monday_)
        return start + " – " + dayMonth.string(from: sunday_)
    }

    /// The calendar date of a day within this slot.
    func date(day: Int, calendar: Calendar = .current) -> Date? {
        monday(calendar: calendar).flatMap {
            calendar.date(byAdding: .day, value: day, to: $0)
        }
    }
}

enum WeekDay {
    static let short: [LocalizedStringKey] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    /// The same names as `full`, resolvable to a String: `LocalizedStringKey`
    /// is what a `Text` accepts; it is NOT what `String(localized:)` accepts,
    /// which wants a `String.LocalizationValue`.
    static let fullValues: [String.LocalizationValue] =
        ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    static let full: [LocalizedStringKey] = ["Monday", "Tuesday", "Wednesday",
                                             "Thursday", "Friday", "Saturday", "Sunday"]

    /// Monday is 0. Calendar gives Sunday as 1, so it shifts.
    static var today: Int {
        let c = Calendar.current.component(.weekday, from: Date())
        return (c + 5) % 7
    }

    /// The calendar date for a slot in the plan: on Monday 31 August it read
    /// "Mon 1", which looks like a date and is not one, and the mismatch is
    /// worse than no number at all.
    static func dateFor(day: Int, calendar: Calendar = .current) -> Date? {
        let maintenant = Date()
        let monday_ = calendar.date(byAdding: .day, value: -today, to: maintenant)
        return monday_.flatMap { calendar.date(byAdding: .day, value: day, to: $0) }
    }

    /// The day of the month for a slot, or the index if the date cannot be
    /// resolved — a number is better than a blank tile.
    static func dayNumber(for day: Int, calendar: Calendar = .current) -> Int {
        guard let d = dateFor(day: day, calendar: calendar) else { return day + 1 }
        return calendar.component(.day, from: d)
    }
}
