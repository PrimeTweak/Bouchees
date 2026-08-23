//  RecettesVue.swift
//
//  L'écran principal. La question du parent est « peut-il manger ça ? », alors
//  le tri se fait par réponse : ce qui marche tel quel, ce qui demande des
//  échanges, ce qui ne passe pas cette fois.

import SwiftUI

struct RecettesVue: View {
    @Environment(EtatApp.self) private var etat
    @State private var recherche = ""
    @State private var categorie = "Tout"
    @State private var rapideSeulement = false
    @State private var ficheOuverte: String?
    @State private var paywallOuvert = false

    /// Les catégories arrivent en français depuis les données; on traduit à
    /// l'affichage seulement, pour que la comparaison avec recette.categorie
    /// reste exacte.
    private static let categories = ["Tout", "Déjeuner", "Repas", "Collation", "Dessert"]

    private var profil: Profil { etat.profilActif }

    private var paires: [(recette: Recette, resultat: RecetteAdaptee)] {
        etat.paires.filter { paire in
            if categorie != "Tout" && paire.recette.categorie != categorie { return false }
            if rapideSeulement && !(paire.recette.tempsMin.map { $0 <= 30 } ?? false) { return false }
            let q = recherche.trimmingCharacters(in: .whitespaces)
            if !q.isEmpty && !correspond(paire.recette, q) { return false }
            return true
        }
    }

    private func correspond(_ r: Recette, _ requete: String) -> Bool {
        let cible = ([r.nom, r.categorie] + r.ingredients.map { etat.definition($0.id)?.nom ?? $0.id })
            .joined(separator: " ")
        return cible.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .contains(requete.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current))
    }

    private var sansFiltre: Bool {
        recherche.trimmingCharacters(in: .whitespaces).isEmpty
            && categorie == "Tout" && !rapideSeulement
    }

    /// La suggestion du jour : prête telle quelle et rapide si possible.
    private var hero: (recette: Recette, resultat: RecetteAdaptee)? {
        guard sansFiltre else { return nil }
        return paires.first { $0.resultat.statut == .telleQuelle && ($0.recette.tempsMin ?? 99) <= 30 }
            ?? paires.first { $0.resultat.statut == .telleQuelle }
            ?? paires.first { $0.resultat.statut == .adaptee }
    }

    private var reste: [(recette: Recette, resultat: RecetteAdaptee)] {
        guard let hero else { return paires }
        return paires.filter { $0.recette.id != hero.recette.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22, pinnedViews: []) {
                    enTete

                    if let message = etat.messageSynchro {
                        BandeauMessage(texte: message)
                    }

                    if let hero {
                        CarteHero(recette: hero.recette, resultat: hero.resultat, prenom: profil.nom)
                            .onTapGesture { ficheOuverte = hero.recette.id }
                    }

                    filtres

                    if paires.isEmpty {
                        EtatVide(symbole: "magnifyingglass",
                                 titre: "Rien ne correspond",
                                 message: "Essayez un autre mot, ou enlevez un filtre.")
                    } else {
                        section(String(localized: "Prêtes telles quelles"), reste.filter { $0.resultat.statut == .telleQuelle })
                        section(String(localized: "Avec quelques échanges"), reste.filter { $0.resultat.statut == .adaptee })
                        section(String(localized: "Pas cette fois"), reste.filter { $0.resultat.statut == .nonAdaptable })
                    }

                    lotsVerrouilles
                    pied
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
            .background(Teinte.fond.ignoresSafeArea())
            .navigationTitle("Recettes")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await etat.synchroniser() }
            .searchable(text: $recherche, prompt: "Chercher — poulet, muffins, courge…")
            .navigationDestination(item: $ficheOuverte) { id in
                if let r = etat.recette(pour: id), let res = etat.resultat(pour: id) {
                    FicheVue(recette: r, resultat: res, prenom: profil.nom)
                }
            }
            .sheet(isPresented: $paywallOuvert) { PaywallVue() }
        }
    }

    // MARK: - Morceaux

    private var enTete: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Aujourd’hui")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .kerning(1.4)
                .foregroundStyle(.tertiary)

            (Text("On cuisine pour ")
             + Text(etat.modeFamille && etat.profils.count > 1
                    ? Formats.liste(etat.profils.map(\.nom))
                    : profil.nom).foregroundColor(Teinte.betterave))
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .lineLimit(3)

            Text(descriptionProfil)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private var descriptionProfil: String {
        let noms = etat.nomsAllergenes(profil.allergenes)
        if etat.modeFamille && etat.profils.count > 1 {
            let base = "On prend l’âge du plus jeune (\(Formats.age(profil.ageMois))) et on évite tout ce que chacun évite"
            return noms.isEmpty ? base + "." : base + " : \(Formats.liste(noms))."
        }
        return noms.isEmpty
            ? "\(Formats.age(profil.ageMois)) — aucun allergène évité pour l’instant."
            : "\(Formats.age(profil.ageMois)) — sans \(Formats.liste(noms))."
    }

    private var filtres: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.categories, id: \.self) { c in
                    PiluleFiltre(titre: String(localized: String.LocalizationValue(c)),
                                 actif: categorie == c) { categorie = c }
                }
                PiluleFiltre(titre: String(localized: "30 min et moins"), actif: rapideSeulement) {
                    rapideSeulement.toggle()
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func section(_ titre: String,
                         _ elements: [(recette: Recette, resultat: RecetteAdaptee)]) -> some View {
        if !elements.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                EnTeteSection(titre: titre, compte: elements.count)
                LazyVGrid(columns: Grille.colonnes, spacing: 14) {
                    ForEach(elements, id: \.recette.id) { paire in
                        Button {
                            ficheOuverte = paire.recette.id
                        } label: {
                            CarteRecette(recette: paire.recette, resultat: paire.resultat)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var lotsVerrouilles: some View {
        let verrous = etat.lotsVerrouilles
        if !verrous.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(verrous) { lot in
                    VStack(alignment: .leading, spacing: 10) {
                        EnTeteSection(titre: lot.titre, compte: lot.nombre)
                        if let note = lot.note {
                            Text(note).font(.footnote).foregroundStyle(.secondary)
                        }
                        Button {
                            paywallOuvert = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "lock.fill")
                                    .font(.title3)
                                    .foregroundStyle(Teinte.betterave)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(lot.nombre) recettes verrouillées").font(.subheadline.weight(.semibold))
                                    Text("Voir ce que l’abonnement ajoute")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(15)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Teinte.betterave.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var pied: some View {
        Text(Reglages.avertissementMedical)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 12)
    }
}

// MARK: - Carte héro

struct CarteHero: View {
    let recette: Recette
    let resultat: RecetteAdaptee
    let prenom: String

    private var pourquoi: String {
        resultat.statut == .telleQuelle
            ? "Rien à changer : telle quelle, elle convient à \(prenom)."
            : "\(resultat.nbSubstitutions) échange\(resultat.nbSubstitutions > 1 ? "s" : "") et c’est prêt pour \(prenom)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VisuelRecette(recette: recette, resultat: resultat)
                .aspectRatio(16/10, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()

            VStack(alignment: .leading, spacing: 8) {
                Text("Notre choix · \(recette.sousTitre)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
                Text(recette.nom)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .lineLimit(2)
                Text(pourquoi)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Voir la recette")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.primary, in: Capsule())
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

struct PiluleFiltre: View {
    let titre: String
    let actif: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(titre)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .foregroundStyle(actif ? Color(.systemBackground) : .primary)
                .background(actif ? Color.primary : Color(.secondarySystemGroupedBackground), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(actif ? 0 : 0.1), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(actif ? [.isSelected] : [])
    }
}
