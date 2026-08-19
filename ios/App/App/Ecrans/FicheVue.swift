//  FicheVue.swift
//
//  La fiche. Le cœur du produit, c'est le journal des ingrédients : ce qu'on
//  change, par quoi, et pourquoi. Un parent qui ne comprend pas un
//  remplacement ne le fera pas.

import SwiftUI

struct FicheVue: View {
    let recette: Recette
    let resultat: RecetteAdaptee
    let prenom: String

    @Environment(EtatApp.self) private var etat

    private var verdict: Verdict { Verdict(resultat, prenom: prenom) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PlatVue(resultat: resultat, categorie: recette.categorie)
                    .aspectRatio(16/10, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 280)
                    .clipped()

                VStack(alignment: .leading, spacing: 14) {
                    titre
                    banniereVerdict
                    blocTexture
                    alertes
                    blocIngredients
                    blocPreparation
                    blocProvenance
                    Text(Reglages.avertissementMedical)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 18)
            }
            .padding(.bottom, 36)
        }
        .background(Teinte.fond.ignoresSafeArea())
        .navigationTitle(recette.nom)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var titre: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recette.nom)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .lineLimit(3)
            Text(soustitre)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var soustitre: String {
        var bouts = [recette.sousTitre, "\(prenom), \(Formats.age(etat.profilActif.ageMois))"]
        let noms = etat.nomsAllergenes(etat.profilActif.allergenes)
        if !noms.isEmpty { bouts.append("sans \(Formats.liste(noms))") }
        return bouts.joined(separator: " · ")
    }

    private var banniereVerdict: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: verdict.symbole)
                .font(.title3)
                .foregroundStyle(verdict.couleur)
            VStack(alignment: .leading, spacing: 3) {
                Text(verdict.titre).font(.headline)
                Text(verdict.detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(verdict.couleur.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var blocTexture: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Texture — \(resultat.texture.nom)").font(.headline)
            Text(resultat.texture.texture).font(.subheadline)
            if let note = resultat.texture.note, !note.isEmpty {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle().frame(width: 4).foregroundStyle(Teinte.betterave)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }

    @ViewBuilder
    private var alertes: some View {
        let liste = resultat.alertesNonBloquantes
        if !liste.isEmpty {
            VStack(spacing: 8) {
                ForEach(liste) { a in
                    HStack(alignment: .top, spacing: 11) {
                        Text(a.niveau.etiquette)
                            .font(.caption2.weight(.bold))
                            .kerning(0.5)
                            .padding(.top, 2)
                        Text(a.message).font(.subheadline)
                    }
                    .foregroundStyle(a.niveau.couleur)
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(a.niveau.couleur.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var blocIngredients: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(resultat.aDesChangements ? "Ingrédients — ce qu’on change et pourquoi" : "Ingrédients")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .kerning(1.2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 12)

            ForEach(Array(resultat.ingredients.enumerated()), id: \.offset) { index, ing in
                LigneIngredient(ingredient: ing)
                if index < resultat.ingredients.count - 1 {
                    Divider().padding(.vertical, 2)
                }
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var blocPreparation: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Préparation")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .kerning(1.2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 12)

            ForEach(Array(resultat.etapes.enumerated()), id: \.offset) { index, etape in
                HStack(alignment: .top, spacing: 13) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Teinte.betterave)
                        .frame(width: 25, height: 25)
                        .overlay(Circle().strokeBorder(Teinte.betterave, lineWidth: 1.5))
                    Text(etape).font(.body)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 7)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Étape \(index + 1). \(etape)")
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var blocProvenance: some View {
        if let p = recette.provenance {
            VStack(alignment: .leading, spacing: 5) {
                Text("Source")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(1.2)
                    .foregroundStyle(.tertiary)
                Text(p.source).font(.caption.monospaced())
                if let url = p.url, !url.isEmpty {
                    Text(url).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                }
                Text("Licence : \(p.licence)").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

// MARK: - Ligne d'ingrédient

struct LigneIngredient: View {
    let ingredient: IngredientAdapte

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                nom
                Spacer(minLength: 8)
                Text(ingredient.quantiteAffichee)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: true, vertical: false)
            }

            if !etiquettes.isEmpty {
                FluxEtiquettes(etiquettes: etiquettes)
            }

            if let note = ingredient.note {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(descriptionAccessible)
    }

    @ViewBuilder
    private var nom: some View {
        switch ingredient.statut {
        case .substitue:
            (Text(ingredient.nom).strikethrough(true, color: Teinte.canneberge).foregroundStyle(.secondary)
             + Text("  →  ").foregroundStyle(Teinte.betterave)
             + Text(ingredient.nomVers ?? "").foregroundStyle(Teinte.betterave))
                .font(.subheadline.weight(.semibold))
        case .omis:
            (Text(ingredient.nom).strikethrough(true, color: Teinte.canneberge).foregroundStyle(.secondary)
             + Text("  →  ").foregroundStyle(Teinte.betterave)
             + Text("on l’enlève").foregroundStyle(Teinte.betterave))
                .font(.subheadline.weight(.semibold))
        case .impossible:
            Text(ingredient.nom)
                .strikethrough(true, color: Teinte.canneberge)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        case .conserve, .inconnu:
            Text(ingredient.nom).font(.subheadline.weight(.semibold))
        }
    }

    private var etiquettes: [(texte: String, couleur: Color)] {
        var out: [(String, Color)] = []
        if let m = ingredient.motif { out.append((m, Teinte.betterave)) }
        if let r = ingredient.ratio,
           ingredient.statut == .substitue || ingredient.statut == .omis {
            out.append((r, Teinte.pois))
        }
        if let p = ingredient.preparation { out.append((p, Teinte.courge)) }
        if ingredient.statut == .impossible {
            out.append(("aucun remplacement sûr", Teinte.canneberge))
        }
        return out.map { (texte: $0.0, couleur: $0.1) }
    }

    private var descriptionAccessible: String {
        switch ingredient.statut {
        case .substitue:
            return "\(ingredient.nom), remplacé par \(ingredient.nomVers ?? ""). \(ingredient.motif ?? "")"
        case .omis:
            return "\(ingredient.nom), retiré. \(ingredient.motif ?? "")"
        case .impossible:
            return "\(ingredient.nom), aucun remplacement sûr."
        default:
            return "\(ingredient.nom), \(ingredient.quantiteAffichee). \(ingredient.preparation ?? "")"
        }
    }
}

/// Étiquettes qui passent à la ligne, sans dépendre d'une API récente.
struct FluxEtiquettes: View {
    let etiquettes: [(texte: String, couleur: Color)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(etiquettes.enumerated()), id: \.offset) { _, e in
                Text(e.texte)
                    .font(.caption2)
                    .foregroundStyle(e.couleur)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(e.couleur.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
