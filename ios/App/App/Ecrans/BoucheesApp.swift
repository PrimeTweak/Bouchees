//  BoucheesApp.swift
//
//  Point d'entrée et navigation. Quatre onglets natifs, et un accueil guidé
//  au premier lancement — pas un profil bidon qu'il faudrait corriger.

import SwiftUI

@main
@MainActor
struct BoucheesApp: App {
    @State private var etat = EtatApp()

    var body: some Scene {
        WindowGroup {
            RacineVue()
                .environment(etat)
                .task { await etat.demarrer() }
        }
    }
}

struct RacineVue: View {
    @Environment(EtatApp.self) private var etat
    @State private var onglet = 0

    var body: some View {
        Group {
            if let erreur = etat.erreurCritique {
                EcranErreurCritique(message: erreur)
            } else if etat.chargement && etat.corpus.isEmpty {
                ProgressView("Préparation…").controlSize(.large)
            } else if etat.aBesoinAccueil {
                AccueilVue()
            } else {
                onglets
            }
        }
        .animation(.easeInOut(duration: 0.25), value: etat.aBesoinAccueil)
    }

    private var onglets: some View {
        TabView(selection: $onglet) {
            RecettesVue()
                .tabItem { Label("Recettes", systemImage: "fork.knife") }
                .tag(0)

            ScannerVue()
                .tabItem { Label("Scanner", systemImage: "barcode.viewfinder") }
                .tag(1)

            ProfilsVue()
                .tabItem { Label("Enfants", systemImage: "person.2") }
                .tag(2)

            ReglagesVue()
                .tabItem { Label("Réglages", systemImage: "gearshape") }
                .tag(3)
        }
        .tint(Teinte.betterave)
    }
}

/// Sans moteur, l'app ne peut rien affirmer. On le dit franchement plutôt que
/// d'afficher des recettes qui n'ont pas été vérifiées.
struct EcranErreurCritique: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Teinte.canneberge)
            Text("Bouchées ne peut pas démarrer")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text("Les tables de sécurité n’ont pas pu être chargées, alors l’app ne peut se prononcer sur aucune recette. Réinstaller l’application règle généralement le problème.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
        }
        .padding(28)
    }
}

// MARK: - Accueil guidé

struct AccueilVue: View {
    @Environment(EtatApp.self) private var etat
    @State private var etape = 0
    @State private var brouillon = Profil(nom: "", ageMois: 9, allergenes: [])
    @State private var autresOuverts = false
    @FocusState private var champNomActif: Bool

    private var prenom: String {
        let n = brouillon.nom.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "votre enfant" : n
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                jauge.padding(.bottom, 28)

                switch etape {
                case 0: etapePrenom
                case 1: etapeAge
                default: etapeAllergenes
                }
            }
            .padding(22)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Teinte.fond.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.2), value: etape)
    }

    private var jauge: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .frame(height: 4)
                    .foregroundStyle(i <= etape ? Teinte.betterave : Color.primary.opacity(0.12))
            }
        }
        .accessibilityLabel("Étape \(etape + 1) sur 3")
    }

    // Étape 1 — le prénom

    private var etapePrenom: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text("Bouchées") + Text(".").foregroundColor(Teinte.betterave))
                .font(.system(size: 34, weight: .heavy, design: .rounded))

            Text("La question de tous les jours : « est-ce qu’il peut manger ça ? » On y répond — et on montre exactement ce qu’on change.")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .padding(.bottom, 32)

            Text("Pour qui on cuisine ?")
                .font(.title2.weight(.bold))
            Text("Juste un prénom. Il sert à personnaliser chaque réponse.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .padding(.bottom, 20)

            TextField("Prénom", text: $brouillon.nom)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .font(.title3.weight(.semibold))
                .padding(15)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .focused($champNomActif)
                .submitLabel(.next)
                .onSubmit { etape = 1 }

            HStack(spacing: 14) {
                Button("Continuer") { etape = 1 }
                    .buttonStyle(.borderedProminent)
                    .tint(Teinte.betterave)
                    .controlSize(.large)
                Button("Passer pour l’instant") {
                    brouillon.nom = "Mon enfant"
                    etape = 1
                }
                .foregroundStyle(.secondary)
            }
            .padding(.top, 28)
        }
        .onAppear { champNomActif = true }
    }

    // Étape 2 — l'âge

    private var etapeAge: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Quel âge a \(prenom) ?")
                .font(.title2.weight(.bold))
            Text("Ça détermine les textures et les consignes de sécurité.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .padding(.bottom, 20)

            SelecteurAge(ageMois: $brouillon.ageMois)

            HStack(spacing: 14) {
                Button("Continuer") { etape = 2 }
                    .buttonStyle(.borderedProminent)
                    .tint(Teinte.betterave)
                    .controlSize(.large)
                Button("Retour") { etape = 0 }.foregroundStyle(.secondary)
            }
            .padding(.top, 28)
        }
    }

    // Étape 3 — les allergènes

    private var etapeAllergenes: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Qu’est-ce qu’on évite pour \(prenom) ?")
                .font(.title2.weight(.bold))
            Text("On retire ces ingrédients de toutes les recettes et on propose un remplacement.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .padding(.bottom, 20)

            GrilleAllergenes(selection: $brouillon.allergenes,
                             autresOuverts: $autresOuverts,
                             allergenes: etat.allergenesConnus)

            if brouillon.allergenes.isEmpty {
                Text("Aucun pour l’instant — c’est correct, ça se change en tout temps.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 14)
            }

            HStack(spacing: 14) {
                Button("Voir les recettes") { terminer() }
                    .buttonStyle(.borderedProminent)
                    .tint(Teinte.betterave)
                    .controlSize(.large)
                Button("Retour") { etape = 1 }.foregroundStyle(.secondary)
            }
            .padding(.top, 28)
        }
    }

    private func terminer() {
        if brouillon.nom.trimmingCharacters(in: .whitespaces).isEmpty {
            brouillon.nom = "Mon enfant"
        }
        etat.enregistrer(brouillon)
    }
}

// MARK: - Sélecteur d'âge

/// Stades d'abord, réglage fin ensuite. Monter à six ans avec un pas d'un mois
/// demanderait soixante-six tapes.
struct SelecteurAge: View {
    @Binding var ageMois: Int

    private static let stades: [(min: Int, nom: String, texte: String)] = [
        (6, "6–8 mois", "Purées lisses et gros bâtonnets fondants"),
        (9, "9–11 mois", "Écrasé grossier et petits morceaux fondants"),
        (12, "1–2 ans", "Morceaux tendres, la plupart des plats familiaux"),
        (24, "2–3 ans", "Coupe normale prudente"),
        (48, "4 ans et +", "Texture libre")
    ]

    private func borneSuivante(_ index: Int) -> Int {
        index + 1 < Self.stades.count ? Self.stades[index + 1].min : 999
    }

    var body: some View {
        VStack(spacing: 9) {
            ForEach(Array(Self.stades.enumerated()), id: \.offset) { index, stade in
                let actif = ageMois >= stade.min && ageMois < borneSuivante(index)
                Button {
                    ageMois = stade.min
                } label: {
                    HStack(spacing: 14) {
                        Text(LocalizedStringKey(stade.nom))
                            .font(.headline)
                            .frame(width: 82, alignment: .leading)
                        Text(LocalizedStringKey(stade.texte))
                            .font(.footnote)
                            .foregroundStyle(actif ? Teinte.betterave : .secondary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(actif ? Teinte.betterave.opacity(0.1) : Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(actif ? Teinte.betterave : Color.primary.opacity(0.1),
                                          lineWidth: actif ? 2 : 1.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(actif ? [.isSelected] : [])
            }

            HStack(spacing: 14) {
                Button { ageMois = max(6, ageMois - 1) } label: {
                    Image(systemName: "minus").frame(width: 40, height: 40)
                }
                .accessibilityLabel("Un mois de moins")

                VStack(spacing: 0) {
                    Text("\(ageMois)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("mois exactement").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(minWidth: 110)

                Button { ageMois = min(72, ageMois + 1) } label: {
                    Image(systemName: "plus").frame(width: 40, height: 40)
                }
                .accessibilityLabel("Un mois de plus")
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Âge exact : \(ageMois) mois")
        }
    }
}

// MARK: - Grille d'allergènes

struct GrilleAllergenes: View {
    @Binding var selection: [String]
    @Binding var autresOuverts: Bool
    let allergenes: [Allergene]

    private static let courants = ["lait", "oeuf", "arachide", "noix", "ble", "soya"]

    private var visibles: [Allergene] {
        autresOuverts ? allergenes : allergenes.filter { Self.courants.contains($0.id) }
    }

    private var nombreAutres: Int { max(0, allergenes.count - Self.courants.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 9)], spacing: 9) {
                ForEach(visibles) { a in
                    BoutonAllergene(allergene: a, actif: selection.contains(a.id)) {
                        if let i = selection.firstIndex(of: a.id) {
                            selection.remove(at: i)
                        } else {
                            selection.append(a.id)
                        }
                    }
                }
            }

            if !autresOuverts && nombreAutres > 0 {
                Button {
                    autresOuverts = true
                } label: {
                    Label(String(format: String(localized: "Voir les %lld autres allergènes"),
                                 nombreAutres), systemImage: "plus.circle")
                        .font(.subheadline.weight(.semibold))
                }
                .tint(Teinte.betterave)
            }
        }
    }
}
