//  Modeles.swift
//
//  Miroir exact des JSON produits par le moteur. Aucun champ n'est inventé :
//  chaque propriété correspond à une clé réellement émise par moteur.js.
//
//  Les enums utilisent un cas « inconnu » plutôt que d'échouer au décodage.
//  Une app d'allergies qui plante parce qu'un nouveau statut est apparu, c'est
//  pire qu'une app qui affiche prudemment « on ne peut pas se prononcer ».

import Foundation

// MARK: - Quantité tolérante

/// Les quantités arrivent en nombre, parfois en chaîne vide quand l'ingestion
/// n'a rien pu extraire. On accepte les deux sans faire tomber la recette.
struct Quantite: Codable, Hashable, Sendable {
    let valeur: Double?

    init(_ valeur: Double?) { self.valeur = valeur }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) {
            valeur = d
        } else if let s = try? c.decode(String.self) {
            valeur = Double(s.replacingOccurrences(of: ",", with: "."))
        } else {
            valeur = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let v = valeur { try c.encode(v) } else { try c.encode("") }
    }

    /// « 2,5 » plutôt que « 2.5 » — on écrit en français.
    var affichage: String {
        guard let v = valeur else { return "" }
        if v == v.rounded() && abs(v) < 1_000_000 {
            return String(Int(v))
        }
        return String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: - Statuts

enum StatutRecette: String, Codable, Sendable {
    case telleQuelle = "telle_quelle"
    case adaptee
    case nonAdaptable = "non_adaptable"
    case inconnu

    init(from decoder: Decoder) throws {
        let brut = try decoder.singleValueContainer().decode(String.self)
        self = StatutRecette(rawValue: brut) ?? .inconnu
    }
}

enum StatutIngredient: String, Codable, Sendable {
    case conserve
    case substitue
    case omis
    case impossible
    case inconnu

    init(from decoder: Decoder) throws {
        let brut = try decoder.singleValueContainer().decode(String.self)
        self = StatutIngredient(rawValue: brut) ?? .inconnu
    }
}

enum NiveauAlerte: String, Codable, Sendable {
    case bloquant
    case securite
    case attention
    case info

    init(from decoder: Decoder) throws {
        let brut = try decoder.singleValueContainer().decode(String.self)
        self = NiveauAlerte(rawValue: brut) ?? .info
    }

    /// Étiquette courte affichée devant le message.
    var etiquette: String {
        switch self {
        case .bloquant: return "STOP"
        case .securite: return "ÂGE"
        case .attention: return "NOTE"
        case .info: return "ÉCH."
        }
    }
}

// MARK: - Données de référence

struct Allergene: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let nom: String
}

struct Stade: Codable, Hashable, Sendable {
    let min: Int
    let max: Int
    let nom: String
    let texture: String
    let note: String?
}

struct DefinitionIngredient: Codable, Hashable, Sendable {
    let nom: String
    let allergenes: [String]
    let roles: [String]
    let note: String?
}

/// base.json — familles d'allergènes et stades de texture.
struct BaseReference: Codable, Sendable {
    let allergenes: [Allergene]
    let stades: [Stade]
}

// MARK: - Recette

struct UsageIngredient: Codable, Hashable, Sendable {
    let id: String
    let qte: Quantite
    let unite: String
    let role: String?
}

struct Provenance: Codable, Hashable, Sendable {
    let source: String
    let url: String?
    let licence: String
}

struct Recette: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let nom: String
    let categorie: String
    let portions: String?
    let ageMinBase: Int
    let tempsMin: Int?
    let ingredients: [UsageIngredient]
    let etapes: [String]
    let lot: String?
    let provenance: Provenance?

    /// Nom de fichier d'une photo révisée, posé par la publication. Absent
    /// tant qu'aucune photo n'a passé la vérification par vision.
    let image: String?

    /// Agrégat de notes, présent seulement dans la réponse des Meilleures.
    let votes: Int?
    let moyenne: Double?
    let maNote: Int?

    var sousTitre: String {
        var bouts = [categorie]
        if let t = tempsMin { bouts.append("\(t) min") }
        if let p = portions, !p.isEmpty { bouts.append(p) }
        return bouts.joined(separator: " · ")
    }
}

// MARK: - Résultat de l'adaptation

struct IngredientAdapte: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let nom: String
    let qte: Quantite
    let unite: String
    let role: String
    let statut: StatutIngredient
    let vers: String?
    let nomVers: String?
    let ratio: String?
    let motif: String?
    let preparation: String?
    let noteIngredient: String?
    let noteSubstitut: String?

    /// Identifiant stable pour ForEach : un ingrédient peut apparaître deux
    /// fois dans une recette (la farine du roux et celle de la pâte).
    var identifiantListe: String { id + "-" + role }
    var note: String? { noteSubstitut ?? noteIngredient }

    var quantiteAffichee: String {
        let q = qte.affichage
        var u = unite
        if u == "unité", let v = qte.valeur, v > 1 { u = "unités" }
        return q.isEmpty ? u : "\(q) \(u)"
    }
}

struct Alerte: Codable, Hashable, Identifiable, Sendable {
    let niveau: NiveauAlerte
    let message: String
    var id: String { niveau.rawValue + message }
}

struct RecetteAdaptee: Codable, Sendable {
    let id: String
    let nom: String
    let statut: StatutRecette
    let nbSubstitutions: Int
    let ingredients: [IngredientAdapte]
    let alertes: [Alerte]
    let texture: Stade
    let etapes: [String]
    let allergenesRestants: [String]

    var alerteBloquante: Alerte? { alertes.first { $0.niveau == .bloquant } }
    var alertesNonBloquantes: [Alerte] { alertes.filter { $0.niveau != .bloquant } }
    var nbConsignesAge: Int { alertes.filter { $0.niveau == .securite }.count }
    var aDesChangements: Bool { ingredients.contains { $0.statut != .conserve } }

    /// Le premier échange, pour l'aperçu sur une carte.
    var premierEchange: (de: String, vers: String)? {
        if let s = ingredients.first(where: { $0.statut == .substitue }), let v = s.nomVers {
            return (s.nom, v)
        }
        if let o = ingredients.first(where: { $0.statut == .omis }) {
            return (o.nom, "on l’enlève")
        }
        return nil
    }
}

// MARK: - Verdict d'un produit scanné

struct VerdictProduit: Codable, Sendable {
    enum Statut: String, Codable, Sendable {
        case sur, aEviter = "a_eviter", incertain
        init(from decoder: Decoder) throws {
            let brut = try decoder.singleValueContainer().decode(String.self)
            self = Statut(rawValue: brut) ?? .incertain
        }
    }
    let statut: Statut
    let allergenesTrouves: [String]
    let ingredientsInconnus: [String]
    let message: String
}

struct Produit: Codable, Sendable {
    let code: String
    let nom: String?
    let marque: String?
    let ingredientsTexte: String?
    let attribution: String?
}

// MARK: - Profil

struct Profil: Codable, Hashable, Identifiable, Sendable {
    var id: String = UUID().uuidString
    var nom: String
    var ageMois: Int
    var allergenes: [String]

    static let defaut = Profil(nom: "Mon enfant", ageMois: 9, allergenes: [])

    /// Profil résolu quand plusieurs enfants mangent le même plat : on prend
    /// l'âge du plus jeune et l'union des allergènes. C'est le vrai cas
    /// difficile d'une famille, et il doit être strict par construction.
    static func famille(_ profils: [Profil]) -> Profil {
        guard !profils.isEmpty else { return .defaut }
        let age = profils.map(\.ageMois).min() ?? 9
        var union: [String] = []
        for p in profils where !p.allergenes.isEmpty {
            for a in p.allergenes where !union.contains(a) { union.append(a) }
        }
        return Profil(id: "famille", nom: "tout le monde", ageMois: age, allergenes: union.sorted())
    }
}

// MARK: - Lots et abonnement

struct Lot: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let titre: String
    let date: String?
    let acces: String
    let note: String?
    let nombre: Int
    var deverrouille: Bool
    var hebdomadaire: Bool?
    var dansFenetre: Bool?

    var estLibre: Bool { acces == "libre" }
    var estHebdomadaire: Bool { hebdomadaire ?? false }
}

struct ManifesteReponse: Codable, Sendable {
    let version: String?
    let abonne: Bool?
    let semaineCourante: String?
    let taillesFenetre: Int?
    let lots: [Lot]
}

/// Agrégat renvoyé par /api/notes — le total public, plus ma propre note.
struct AgregatNote: Codable, Hashable, Sendable {
    let votes: Int
    let moyenne: Double?
    let maNote: Int?
}

struct MeilleuresReponse: Codable, Sendable {
    let seuil: Int
    let recettes: [Recette]
}

struct RecettesReponse: Codable, Sendable {
    let abonne: Bool?
    let lots: [String]?
    let recettes: [Recette]
}
