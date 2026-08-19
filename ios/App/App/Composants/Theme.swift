//  Theme.swift
//
//  Le langage visuel, en un seul endroit. Les couleurs viennent des assets
//  (clair et sombre), pas de valeurs codées dans les vues.

import SwiftUI

enum Teinte {
    static let betterave = Color("Betterave")
    static let pois = Color("Pois")
    static let courge = Color("Courge")
    static let courgePale = Color("CourgePale")
    static let canneberge = Color("Canneberge")
    static let fond = Color("Fond")
}

extension StatutRecette {
    var couleur: Color {
        switch self {
        case .telleQuelle: return Teinte.pois
        case .adaptee: return Teinte.betterave
        case .nonAdaptable: return Teinte.canneberge
        case .inconnu: return .secondary
        }
    }

    var symbole: String {
        switch self {
        case .telleQuelle: return "checkmark.circle.fill"
        case .adaptee: return "arrow.triangle.swap"
        case .nonAdaptable: return "xmark.octagon.fill"
        case .inconnu: return "questionmark.circle.fill"
        }
    }
}

extension NiveauAlerte {
    var couleur: Color {
        switch self {
        case .bloquant: return Teinte.canneberge
        case .securite, .attention: return Teinte.courge
        case .info: return Teinte.betterave
        }
    }
}

// MARK: - Verdict

/// Le verdict, formulé comme un parent le poserait : « peut-il manger ça ? »
struct Verdict {
    let titre: String
    let detail: String
    let couleur: Color
    let symbole: String

    init(_ resultat: RecetteAdaptee, prenom: String) {
        couleur = resultat.statut.couleur
        symbole = resultat.statut.symbole
        switch resultat.statut {
        case .telleQuelle:
            titre = "Oui, telle quelle"
            detail = "Aucun ingrédient à changer pour \(prenom)."
        case .adaptee:
            let n = resultat.nbSubstitutions
            titre = "Oui — avec \(n) échange\(n > 1 ? "s" : "")"
            detail = "Ce qu’on remplace, par quoi et pourquoi : tout est détaillé plus bas."
        case .nonAdaptable:
            titre = "Pas cette fois pour \(prenom)"
            detail = resultat.alerteBloquante?.message ?? "Un ingrédient n’a pas de remplacement sûr."
        case .inconnu:
            titre = "On ne peut pas se prononcer"
            detail = "Cette recette n’a pas pu être analysée. Ne la servez pas sans vérifier vous-même."
        }
    }

    /// Version courte pour une carte.
    static func jeton(_ resultat: RecetteAdaptee) -> String {
        switch resultat.statut {
        case .telleQuelle: return "Telle quelle"
        case .adaptee:
            let n = resultat.nbSubstitutions
            return "\(n) échange\(n > 1 ? "s" : "")"
        case .nonAdaptable: return "Pas cette fois"
        case .inconnu: return "À vérifier"
        }
    }
}

// MARK: - Composants

struct JetonVerdict: View {
    let resultat: RecetteAdaptee

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: resultat.statut.symbole)
                .font(.system(size: 10, weight: .bold))
            Text(Verdict.jeton(resultat))
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(resultat.statut.couleur)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
    }
}

struct JetonConsignes: View {
    let nombre: Int

    var body: some View {
        Text("\(nombre) consigne\(nombre > 1 ? "s" : "")")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Teinte.courge)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
            .accessibilityLabel("\(nombre) consigne\(nombre > 1 ? "s" : "") de sécurité liée\(nombre > 1 ? "s" : "") à l’âge")
    }
}

struct CarteRecette: View {
    let recette: Recette
    let resultat: RecetteAdaptee

    private var estBloquee: Bool { resultat.statut == .nonAdaptable }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlatVue(resultat: resultat, categorie: recette.categorie)
                .aspectRatio(4/3, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()
                .saturation(estBloquee ? 0.35 : 1)
                .opacity(estBloquee ? 0.75 : 1)
                .overlay(alignment: .topLeading) {
                    JetonVerdict(resultat: resultat).padding(9)
                }
                .overlay(alignment: .topTrailing) {
                    if !estBloquee && resultat.nbConsignesAge > 0 {
                        JetonConsignes(nombre: resultat.nbConsignesAge).padding(9)
                    }
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(recette.nom)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)

                Text(recette.sousTitre)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let bloquante = resultat.alerteBloquante {
                    Text(bloquante.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .padding(.top, 4)
                } else if let e = resultat.premierEchange {
                    EchangeCourt(de: e.de, vers: e.vers, autres: resultat.nbSubstitutions - 1)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(estBloquee ? Teinte.canneberge.opacity(0.25) : Color.primary.opacity(0.07),
                              style: StrokeStyle(lineWidth: 1, dash: estBloquee ? [4, 3] : []))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(recette.nom). \(Verdict.jeton(resultat)).")
    }
}

/// L'aperçu d'échange : original barré, flèche, remplacement.
struct EchangeCourt: View {
    let de: String
    let vers: String
    var autres: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().padding(.bottom, 7)
            (Text(de).strikethrough(true, color: Teinte.canneberge).foregroundStyle(.secondary)
             + Text("  →  ").foregroundStyle(Teinte.betterave)
             + Text(vers).foregroundStyle(Teinte.betterave).fontWeight(.semibold)
             + Text(autres > 0 ? "  +\(autres)" : "").foregroundStyle(.tertiary))
                .font(.caption)
                .lineLimit(2)
        }
    }
}

struct EtatVide: View {
    let symbole: String
    let titre: String
    let message: String
    var titreAction: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbole)
                .font(.system(size: 40))
                .foregroundStyle(Teinte.betterave.opacity(0.7))
            Text(titre).font(.title3.weight(.bold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if let action, let titreAction {
                Button(titreAction, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Teinte.betterave)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

struct BandeauMessage: View {
    let texte: String
    var couleur: Color = Teinte.courge

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "wifi.slash").font(.caption)
            Text(texte).font(.footnote)
        }
        .foregroundStyle(couleur)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(couleur.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct EnTeteSection: View {
    let titre: String
    let compte: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(titre).font(.title3.weight(.bold))
            Text("\(compte)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            Rectangle().frame(height: 1).foregroundStyle(.quaternary)
        }
    }
}

// MARK: - Grille adaptative

enum Grille {
    static let colonnes = [GridItem(.adaptive(minimum: 158), spacing: 14)]
}
