//  ProfilsEtReglages.swift
//
//  Les profils vivent sur l'appareil et n'en sortent jamais : aucune route
//  serveur ne les reçoit. C'est ce qui est déclaré aux étiquettes de
//  confidentialité de l'App Store, et ça doit rester vrai dans le code.

import SwiftUI
import StoreKit

// MARK: - Profils

struct ProfilsVue: View {
    @Environment(EtatApp.self) private var etat
    @State private var edition: Profil?
    @State private var confirmationSuppression: Profil?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(etat.profils) { p in
                        Button {
                            etat.choisir(p.id)
                        } label: {
                            LigneProfil(profil: p,
                                        actif: !etat.modeFamille && p.id == etat.identifiantActif,
                                        noms: etat.nomsAllergenes(p.allergenes))
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                confirmationSuppression = p
                            } label: { Label("Retirer", systemImage: "trash") }

                            Button {
                                edition = p
                            } label: { Label("Modifier", systemImage: "pencil") }
                            .tint(Teinte.betterave)
                        }
                    }
                } header: {
                    Text("Vos enfants")
                } footer: {
                    Text("L’âge détermine les textures et les consignes de sécurité. Les allergènes sont retirés de toutes les recettes, avec un remplacement proposé.")
                }

                if etat.profils.count > 1 {
                    Section {
                        Toggle(isOn: Binding(
                            get: { etat.modeFamille },
                            set: { _ in etat.basculerFamille() })) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Tout le monde à table").font(.body)
                                    Text("Âge du plus jeune, et tout ce que chacun évite")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .tint(Teinte.betterave)
                    }
                }

                Section {
                    Button {
                        edition = Profil(nom: "", ageMois: 9, allergenes: [])
                    } label: {
                        Label("Ajouter un enfant", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle("Enfants")
            .sheet(item: $edition) { p in
                EditeurProfil(profil: p)
            }
            .alert("Retirer ce profil ?",
                   isPresented: Binding(get: { confirmationSuppression != nil },
                                        set: { if !$0 { confirmationSuppression = nil } }),
                   presenting: confirmationSuppression) { p in
                Button("Retirer", role: .destructive) { etat.supprimer(p) }
                Button("Annuler", role: .cancel) { }
            } message: { p in
                Text("Le profil de \(p.nom) et ses allergènes seront effacés de cet appareil.")
            }
        }
    }
}

struct LigneProfil: View {
    let profil: Profil
    let actif: Bool
    let noms: [String]

    private var pastille: Color {
        let teintes: [Color] = [Teinte.betterave, Teinte.pois, Teinte.courge, Teinte.canneberge]
        var somme = 0
        for octet in profil.nom.utf8 { somme = (somme &* 31 &+ Int(octet)) % 9973 }
        return teintes[somme % teintes.count]
    }

    var body: some View {
        HStack(spacing: 13) {
            Text(String(profil.nom.prefix(1)).uppercased())
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(pastille, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(profil.nom).font(.headline).foregroundStyle(.primary)
                Text(noms.isEmpty
                     ? "\(Formats.age(profil.ageMois)) — aucun allergène évité"
                     : "\(Formats.age(profil.ageMois)) — sans \(Formats.liste(noms))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if actif {
                Image(systemName: "checkmark").foregroundStyle(Teinte.betterave).font(.headline)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(actif ? [.isSelected] : [])
    }
}

struct EditeurProfil: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.dismiss) private var fermer
    @State var profil: Profil
    @State private var autresOuverts = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 9) {
                        EtiquetteChamp("Prénom")
                        TextField("Prénom", text: $profil.nom)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .font(.title3.weight(.semibold))
                            .padding(14)
                            .background(Color(.secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        EtiquetteChamp("Âge")
                        SelecteurAge(ageMois: $profil.ageMois)
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        EtiquetteChamp("Allergènes évités")
                        GrilleAllergenes(selection: $profil.allergenes,
                                         autresOuverts: $autresOuverts,
                                         allergenes: etat.allergenesConnus)
                    }
                }
                .padding(20)
            }
            .background(Teinte.fond.ignoresSafeArea())
            .navigationTitle(profil.nom.isEmpty ? "Nouvel enfant" : profil.nom)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        if profil.nom.trimmingCharacters(in: .whitespaces).isEmpty {
                            profil.nom = "Mon enfant"
                        }
                        etat.enregistrer(profil)
                        fermer()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { fermer() }
                }
            }
        }
    }
}

struct EtiquetteChamp: View {
    let texte: String
    init(_ texte: String) { self.texte = texte }

    var body: some View {
        Text(texte)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .kerning(1.2)
            .foregroundStyle(.tertiary)
    }
}

// MARK: - Réglages

struct ReglagesVue: View {
    @Environment(EtatApp.self) private var etat
    @State private var paywallOuvert = false
    @State private var courriel = ""
    @State private var messageCompte: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Abonnement") {
                    HStack {
                        Text(etat.abonne ? "Actif" : "Aucun abonnement")
                        Spacer()
                        Button(etat.abonne ? "Gérer" : "S’abonner") { paywallOuvert = true }
                            .tint(Teinte.betterave)
                    }
                    Button("Restaurer mes achats") {
                        Task { await etat.abonnement.restaurer() }
                    }
                }

                Section {
                    if let c = etat.abonnement.courriel {
                        HStack {
                            Text("Connecté")
                            Spacer()
                            Text(c).foregroundStyle(.secondary).font(.footnote)
                        }
                        Button("Se déconnecter", role: .destructive) {
                            Task { await etat.deconnecter() }
                        }
                    } else {
                        TextField("vous@exemple.ca", text: $courriel)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Se connecter") {
                            Task {
                                do {
                                    try await etat.connecter(courriel: courriel)
                                    messageCompte = nil
                                } catch {
                                    messageCompte = "Connexion impossible. Vérifiez l’adresse et votre connexion."
                                }
                            }
                        }
                        .disabled(!courriel.contains("@"))
                    }
                    if let m = messageCompte {
                        Text(m).font(.footnote).foregroundStyle(Teinte.canneberge)
                    }
                } header: {
                    Text("Compte")
                } footer: {
                    Text("Le compte sert à retrouver votre abonnement sur vos appareils. Les profils de vos enfants, eux, restent sur cet appareil et ne sont jamais envoyés.")
                }

                Section("Contenu") {
                    HStack {
                        Text("Dernière mise à jour")
                        Spacer()
                        Text(etat.derniereSynchro.map {
                            $0.formatted(date: .abbreviated, time: .shortened)
                        } ?? "jamais")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                    Button("Actualiser maintenant") {
                        Task { await etat.synchroniser() }
                    }
                    HStack {
                        Text("Recettes disponibles")
                        Spacer()
                        Text("\(etat.corpus.count)").foregroundStyle(.secondary).monospacedDigit()
                    }
                }

                Section {
                    Link("Conditions d’utilisation", destination: Reglages.conditions)
                    Link("Confidentialité", destination: Reglages.confidentialite)
                } footer: {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Reglages.avertissementMedical)
                        Text("Données de produits : Open Food Facts, sous licence ODbL.")
                    }
                }
            }
            .navigationTitle("Réglages")
            .sheet(isPresented: $paywallOuvert) { PaywallVue() }
        }
    }
}

// MARK: - Paywall

struct PaywallVue: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.dismiss) private var fermer

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(etat.abonne ? "Votre abonnement est actif" : "De nouvelles recettes chaque mois")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                        Text(etat.abonne
                             ? "Tous les lots sont déverrouillés. Le prochain arrive au début du mois prochain."
                             : "Chaque mois, un lot de recettes choisies là où votre profil manque de choix — pas au hasard.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    comparatif

                    if !etat.abonne {
                        if etat.abonnement.produits.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Les abonnements ne sont pas disponibles ici.")
                                    .font(.subheadline.weight(.semibold))
                                Text("C’est normal sur une version installée hors de l’App Store : l’achat intégré demande un profil signé par Apple.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(15)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Teinte.courge.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        } else {
                            ForEach(etat.abonnement.produits, id: \.id) { produit in
                                BoutonProduit(produit: produit) {
                                    if let jws = await etat.abonnement.acheter(produit) {
                                        await etat.lierAchat(jws)
                                    }
                                }
                            }
                        }
                    }

                    Button("Restaurer mes achats") {
                        Task { await etat.abonnement.restaurer() }
                    }
                    .font(.footnote)
                    .tint(Teinte.betterave)

                    if let m = etat.abonnement.message {
                        Text(m).font(.footnote).foregroundStyle(Teinte.courge)
                    }

                    Text("""
                    L’abonnement se renouvelle automatiquement à moins d’être annulé au moins 24 h avant la fin de la période. \
                    Le paiement est porté à votre compte Apple à la confirmation. Gérez ou annulez dans les réglages de votre compte Apple.
                    """)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    HStack(spacing: 18) {
                        Link("Conditions", destination: Reglages.conditions)
                        Link("Confidentialité", destination: Reglages.confidentialite)
                    }
                    .font(.caption)
                }
                .padding(20)
            }
            .background(Teinte.fond.ignoresSafeArea())
            .navigationTitle("Abonnement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { fermer() }
                }
            }
        }
        .task { await etat.abonnement.charger() }
    }

    private var comparatif: some View {
        VStack(spacing: 12) {
            BlocComparatif(titre: "Toujours gratuit", accent: Teinte.pois, lignes: [
                "Les échanges d’ingrédients pour chaque allergène",
                "Les repères d’âge et de texture",
                "Le scanner de produits",
                "Les profils de vos enfants",
                "Les recettes de départ"
            ])
            BlocComparatif(titre: "Avec l’abonnement", accent: Teinte.betterave, lignes: [
                "Un nouveau lot de recettes chaque mois",
                "Ciblé sur les profils que vous avez créés",
                "Tous les lots précédents"
            ])
        }
    }
}

struct BlocComparatif: View {
    let titre: String
    let accent: Color
    let lignes: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titre).font(.headline).foregroundStyle(accent)
            ForEach(lignes, id: \.self) { l in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                        .padding(.top, 2)
                    Text(l).font(.footnote)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct BoutonProduit: View {
    let produit: Product
    let action: () async -> Void
    @State private var enCours = false

    var body: some View {
        Button {
            Task {
                enCours = true
                await action()
                enCours = false
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(produit.displayName).font(.headline)
                    Text(produit.description).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if enCours {
                    ProgressView()
                } else {
                    Text(produit.displayPrice).font(.headline)
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .tint(Teinte.betterave)
        .disabled(enCours)
    }
}
