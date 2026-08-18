//  EcransSecondaires.swift — profils et réglages natifs (bloc H)

import SwiftUI

struct ProfilsVue: View {
    @EnvironmentObject var etat: EtatApp
    @State private var edition: Profil?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(etat.contenu.profils) { p in
                        Button { etat.contenu.profilActifId = p.id } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(p.nom).font(.headline)
                                    Text(resume(p)).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if p.id == etat.contenu.profilActifId {
                                    Image(systemName: "checkmark").foregroundStyle(Color("Betterave"))
                                }
                            }
                        }
                        .swipeActions {
                            Button("Modifier") { edition = p }.tint(Color("Betterave"))
                        }
                    }
                    .onDelete { idx in
                        etat.contenu.profils.remove(atOffsets: idx)
                        etat.contenu.sauverProfils()
                    }
                } header: {
                    Text("Vos enfants")
                } footer: {
                    Text("L'âge détermine les textures et les consignes de sécurité. Les allergènes sont retirés de toutes les recettes, avec un remplacement proposé.")
                }

                Section {
                    Button("Ajouter un enfant") {
                        edition = Profil(nom: "", ageMois: 9, allergenes: [])
                    }
                }
            }
            .navigationTitle("Enfants")
            .sheet(item: $edition) { p in EditeurProfil(profil: p) }
        }
    }

    private func resume(_ p: Profil) -> String {
        p.allergenes.isEmpty
            ? "\(p.ageMois) mois — aucun allergène évité"
            : "\(p.ageMois) mois — sans \(p.allergenes.joined(separator: ", "))"
    }
}

struct EditeurProfil: View {
    @EnvironmentObject var etat: EtatApp
    @Environment(\.dismiss) private var fermer
    @State var profil: Profil

    private let courants = ["lait", "oeuf", "arachide", "noix", "ble", "soya"]
    private let autres = ["sesame", "poisson", "crustaces_mollusques", "moutarde", "sulfites"]
    @State private var montrerAutres = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Prénom") {
                    TextField("Prénom", text: $profil.nom).textInputAutocapitalization(.words)
                }
                Section("Âge") {
                    Stepper("\(profil.ageMois) mois", value: $profil.ageMois, in: 6...72)
                }
                Section("Allergènes à éviter") {
                    ForEach(courants + (montrerAutres ? autres : []), id: \.self) { a in
                        Toggle(nomLisible(a), isOn: lien(a))
                    }
                    if !montrerAutres {
                        Button("Voir les 5 autres allergènes") { montrerAutres = true }
                    }
                }
            }
            .navigationTitle(profil.nom.isEmpty ? "Nouvel enfant" : profil.nom)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        if profil.nom.trimmingCharacters(in: .whitespaces).isEmpty { profil.nom = "Mon enfant" }
                        if let i = etat.contenu.profils.firstIndex(where: { $0.id == profil.id }) {
                            etat.contenu.profils[i] = profil
                        } else {
                            etat.contenu.profils.append(profil)
                            etat.contenu.profilActifId = profil.id
                        }
                        etat.contenu.sauverProfils()
                        fermer()
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { fermer() } }
            }
        }
    }

    private func lien(_ a: String) -> Binding<Bool> {
        Binding(
            get: { profil.allergenes.contains(a) },
            set: { on in
                if on { profil.allergenes.append(a) }
                else { profil.allergenes.removeAll { $0 == a } }
            })
    }

    private func nomLisible(_ id: String) -> String {
        [ "lait": "Lait", "oeuf": "Œufs", "arachide": "Arachides", "noix": "Noix",
          "ble": "Blé et triticale", "soya": "Soya", "sesame": "Sésame",
          "poisson": "Poisson", "crustaces_mollusques": "Crustacés et mollusques",
          "moutarde": "Moutarde", "sulfites": "Sulfites" ][id] ?? id
    }
}

struct ReglagesVue: View {
    @EnvironmentObject var etat: EtatApp
    @State private var paywall = false

    var body: some View {
        NavigationStack {
            List {
                Section("Abonnement") {
                    HStack {
                        Text(etat.abonne ? "Actif" : "Aucun abonnement")
                        Spacer()
                        Button(etat.abonne ? "Gérer" : "S'abonner") { paywall = true }
                    }
                    Button("Restaurer mes achats") {
                        Task { await etat.abonnement.restaurer() }
                    }
                }

                Section("Contenu") {
                    HStack {
                        Text("Dernière mise à jour")
                        Spacer()
                        Text(etat.derniereSynchro.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "jamais")
                            .foregroundStyle(.secondary)
                    }
                    Button("Actualiser maintenant") { Task { await etat.synchroniser() } }
                }

                Section {
                    Link("Conditions d'utilisation", destination: Reglages.conditions)
                    Link("Confidentialité", destination: Reglages.confidentialite)
                } footer: {
                    Text("""
                    Bouchées ne remplace pas un avis médical. Les échanges d'ingrédients et les repères d'âge \
                    viennent de tables déterministes, à faire valider par un professionnel. En cas d'allergie \
                    diagnostiquée, le plan de votre allergologue a toujours préséance.

                    Données de produits : Open Food Facts, sous licence ODbL.
                    """)
                }
            }
            .navigationTitle("Réglages")
            .sheet(isPresented: $paywall) {
                PaywallVue(abonnement: etat.abonnement)
            }
            .onReceive(NotificationCenter.default.publisher(for: .ouvrirPaywall)) { _ in
                paywall = true
            }
        }
    }
}
