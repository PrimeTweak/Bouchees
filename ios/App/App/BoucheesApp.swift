//  BoucheesApp.swift — coquille native (bloc H)
//
//  L'architecture : le moteur de substitution est en JavaScript, déterministe
//  et testé (79 tests). On ne le réécrit PAS en Swift — deux moteurs, ce sont
//  deux vérités, et sur des allergies c'est inacceptable. Le WKWebView
//  l'héberge; tout le reste est natif.
//
//  Ce que ça donne pour la règle 4.2 : des onglets natifs, un scanner de
//  code-barres impossible en Safari, le fonctionnement hors ligne complet,
//  et StoreKit. La coquille n'enveloppe pas un site — elle donne des sens à
//  un moteur.

import SwiftUI

@main
struct BoucheesApp: App {
    @StateObject private var etat = EtatApp()

    var body: some Scene {
        WindowGroup {
            RacineVue()
                .environmentObject(etat)
                .task { await etat.demarrer() }
        }
    }
}

/// État partagé : abonnement, connectivité, profils.
@MainActor
final class EtatApp: ObservableObject {
    @Published var abonne = false
    @Published var horsLigne = false
    @Published var derniereSynchro: Date?
    @Published var messageSynchro: String?

    let abonnement = Abonnement()
    let contenu = ContenuLocal()

    func demarrer() async {
        await abonnement.charger()
        abonne = abonnement.estActif
        await synchroniser()
    }

    /// Le contenu est mis en cache sur l'appareil. Une fois téléchargé, tout
    /// fonctionne sans réseau — c'est le cas d'usage réel : l'allée d'épicerie
    /// au sous-sol, sans signal.
    func synchroniser() async {
        do {
            try await contenu.rafraichir(jeton: abonnement.jetonServeur)
            horsLigne = false
            derniereSynchro = Date()
            messageSynchro = nil
        } catch {
            horsLigne = true
            messageSynchro = contenu.aDuContenuLocal
                ? "Hors ligne — vos recettes téléchargées restent accessibles."
                : "Aucune connexion et rien en mémoire. Reconnectez-vous une fois pour télécharger."
        }
    }
}

struct RacineVue: View {
    @EnvironmentObject var etat: EtatApp
    @State private var onglet = 0

    var body: some View {
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
        .tint(Color("Betterave"))
        .overlay(alignment: .top) {
            if etat.horsLigne, let m = etat.messageSynchro {
                BandeauHorsLigne(texte: m)
            }
        }
    }
}

struct BandeauHorsLigne: View {
    let texte: String
    var body: some View {
        Text(texte)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color("Courge"))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(Color("CourgePale"))
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// L'onglet Recettes héberge le moteur. Le WKWebView charge des fichiers
/// locaux — jamais une URL distante — pour que tout marche hors ligne et
/// qu'aucun contenu arbitraire ne puisse être injecté.
struct RecettesVue: View {
    @EnvironmentObject var etat: EtatApp
    var body: some View {
        NavigationStack {
            PontMoteur(dossier: etat.contenu.dossierWeb)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Recettes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await etat.synchroniser() }
                        } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Actualiser les recettes")
                    }
                }
        }
    }
}
