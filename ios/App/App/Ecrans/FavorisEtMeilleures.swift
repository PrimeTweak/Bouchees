//  FavorisEtMeilleures.swift
//
//  DEUX FAÇONS DE RETROUVER UNE RECETTE SORTIE DE LA FENÊTRE
//
//  1. LES FAVORIS. Un parent trouve une recette qu'il adore. Trois semaines
//     plus tard, elle sort de la fenêtre. S'il la perd, il a raison d'être
//     fâché — et la fenêtre glissante se retourne contre le produit.
//     Donc : enregistrer une recette en garde une COPIE COMPLÈTE sur
//     l'appareil. Elle survit à la rotation, au réseau, à l'expiration de
//     l'abonnement. Elle est à lui.
//
//  2. L'ONGLET MEILLEURES. Les recettes que cinq personnes ou plus ont notées
//     reviennent par mérite. Pas de rotation artificielle : une recette
//     revient parce que des parents l'ont aimée, pas parce qu'un script l'a
//     repêchée.

import SwiftUI
import UIKit
import Observation

// MARK: - Favoris

@MainActor
@Observable
final class Favoris {

    private(set) var recettes: [Recette] = []

    @ObservationIgnored private let fm = FileManager.default

    private var fichier: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Bouchees", isDirectory: true)
        if !fm.fileExists(atPath: base.path) {
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base.appendingPathComponent("favoris.json")
    }

    init() { charger() }

    private func charger() {
        guard let d = try? Data(contentsOf: fichier),
              let r = try? JSONDecoder().decode([Recette].self, from: d) else { return }
        recettes = r
    }

    private func sauver() {
        guard let d = try? JSONEncoder().encode(recettes) else { return }
        try? d.write(to: fichier, options: .atomic)
    }

    func contient(_ id: String) -> Bool { recettes.contains { $0.id == id } }

    /// On garde la recette entière, pas seulement son identifiant. C'est tout
    /// l'intérêt : elle doit rester lisible quand le serveur ne la sert plus.
    func basculer(_ recette: Recette) {
        if let i = recettes.firstIndex(where: { $0.id == recette.id }) {
            recettes.remove(at: i)
        } else {
            recettes.append(recette)
        }
        sauver()
    }

    func retirer(_ id: String) {
        recettes.removeAll { $0.id == id }
        sauver()
    }
}

// MARK: - Bouton favori

struct BoutonFavori: View {
    let recette: Recette
    @Environment(EtatApp.self) private var etat

    private var actif: Bool { etat.favoris.contient(recette.id) }

    var body: some View {
        Button {
            etat.favoris.basculer(recette)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: actif ? "bookmark.fill" : "bookmark")
                .foregroundStyle(actif ? Teinte.betterave : Color.secondary)
        }
        .accessibilityLabel(actif ? "Retirer des favoris" : "Enregistrer dans les favoris")
        .accessibilityHint("Une recette enregistrée reste accessible même après sa semaine.")
    }
}

// MARK: - Onglet Meilleures

struct MeilleuresVue: View {
    @Environment(EtatApp.self) private var etat
    @State private var ficheOuverte: String?
    @State private var section = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("", selection: $section) {
                        Text("Les mieux notées").tag(0)
                        Text("Mes favoris").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if section == 0 { classement } else { favoris }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
            .background(Teinte.fond.ignoresSafeArea())
            .navigationTitle("Meilleures")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await etat.chargerMeilleures() }
            .navigationDestination(item: $ficheOuverte) { id in
                if let paire = etat.paireLibre(pour: id) {
                    FicheVue(recette: paire.recette, resultat: paire.resultat,
                             prenom: etat.profilActif.nom)
                }
            }
        }
        .task { await etat.chargerMeilleures() }
    }

    @ViewBuilder
    private var classement: some View {
        if etat.meilleures.isEmpty {
            EtatVide(symbole: "star",
                     titre: "Le classement se construit",
                     message: "Une recette entre ici dès que \(etat.seuilVotes) personnes l’ont notée. Notez celles que vous essayez — c’est ce qui fait remonter les bonnes.")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text("Les recettes notées par au moins \(etat.seuilVotes) personnes. Elles restent accessibles même une fois leur semaine passée.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(Array(etat.meilleures.enumerated()), id: \.element.id) { rang, recette in
                    if let res = etat.resultatPour(recette) {
                        Button {
                            ficheOuverte = recette.id
                        } label: {
                            LigneClassement(rang: rang + 1, recette: recette, resultat: res)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var favoris: some View {
        if etat.favoris.recettes.isEmpty {
            EtatVide(symbole: "bookmark",
                     titre: "Aucun favori",
                     message: "Enregistrez une recette et elle restera ici pour toujours — même après que sa semaine soit passée.")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text("Vos recettes enregistrées restent sur cet appareil, hors du roulement des semaines.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: Grille.colonnes, spacing: 14) {
                    ForEach(etat.favoris.recettes) { recette in
                        if let res = etat.resultatPour(recette) {
                            Button {
                                ficheOuverte = recette.id
                            } label: {
                                CarteRecette(recette: recette, resultat: res)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

struct LigneClassement: View {
    let rang: Int
    let recette: Recette
    let resultat: RecetteAdaptee

    private var couleurRang: Color {
        switch rang {
        case 1: return Teinte.courge
        case 2, 3: return Teinte.betterave
        default: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 13) {
            Text("\(rang)")
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(couleurRang)
                .frame(width: 28)

            VisuelRecette(recette: recette, resultat: resultat)
                .frame(width: 76, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(recette.nom).font(.subheadline.weight(.semibold)).lineLimit(2)
                HStack(spacing: 8) {
                    BadgeNote(votes: recette.votes ?? 0, moyenne: recette.moyenne)
                    Text(Verdict.jeton(resultat))
                        .font(.caption2)
                        .foregroundStyle(resultat.statut.couleur)
                }
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(11)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rang \(rang). \(recette.nom).")
    }
}

// MARK: - Bloc de notation, dans la fiche

struct BlocNotation: View {
    let recette: Recette
    @Environment(EtatApp.self) private var etat
    @State private var enCours = false

    private var agregat: AgregatNote? { etat.notes[recette.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Votre note")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .kerning(1.2)
                .foregroundStyle(.tertiary)

            HStack {
                EtoilesNote(note: agregat?.maNote) { nouvelle in
                    Task {
                        enCours = true
                        await etat.noter(recette.id, note: nouvelle)
                        enCours = false
                    }
                }
                Spacer()
                if enCours { ProgressView() }
                else if let a = agregat, a.votes > 0 {
                    BadgeNote(votes: a.votes, moyenne: a.moyenne)
                }
            }

            if etat.abonnement.jetonServeur == nil {
                Text("Connectez-vous dans les réglages pour noter — sans compte, une même personne pourrait voter cent fois.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let a = agregat, a.votes > 0, a.votes < etat.seuilVotes {
                Text("\(etat.seuilVotes - a.votes) note\(etat.seuilVotes - a.votes > 1 ? "s" : "") de plus et cette recette peut entrer au classement.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
