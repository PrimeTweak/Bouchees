//  EtatApp.swift
//
//  L'état central. Une seule source de vérité pour les profils, le corpus et
//  les résultats adaptés — les vues ne calculent rien, elles affichent.

import Foundation
import Observation

@MainActor
@Observable
final class EtatApp {

    // MARK: - État exposé

    var profils: [Profil] = []
    var identifiantActif: String?
    var modeFamille = false

    private(set) var corpus: [Recette] = []
    private(set) var adaptees: [RecetteAdaptee] = []
    private(set) var lots: [Lot] = []

    private(set) var chargement = true
    private(set) var horsLigne = false
    private(set) var erreurCritique: String?
    private(set) var messageSynchro: String?
    private(set) var derniereSynchro: Date?

    var abonne = false

    // MARK: - Dépendances

    private var moteur: MoteurJS?
    private let local = DepotLocal()
    private let serveur = DepotServeur()
    let abonnement = Abonnement()

    // MARK: - Profil courant

    var profilActif: Profil {
        if modeFamille && profils.count > 1 { return Profil.famille(profils) }
        return profils.first { $0.id == identifiantActif } ?? profils.first ?? .defaut
    }

    var aBesoinAccueil: Bool { profils.isEmpty }

    // MARK: - Démarrage

    func demarrer() async {
        chargement = true
        defer { chargement = false }

        profils = local.lireProfils()
        identifiantActif = profils.first?.id

        do {
            let m = try MoteurJS()
            try m.chargerDonnees(
                ingredients: try Ressources.data("ingredients", "json"),
                substitutions: try Ressources.data("substitutions", "json"),
                base: try Ressources.data("base", "json"))
            moteur = m
        } catch {
            // Sans moteur, l'app ne peut rien affirmer. On le dit franchement
            // plutôt que d'afficher des recettes non vérifiées.
            erreurCritique = error.localizedDescription
            return
        }

        chargerCorpusLocal()
        recalculer()
        await synchroniser()
    }

    /// Corpus téléchargé s'il existe, sinon les lots embarqués dans l'app.
    private func chargerCorpusLocal() {
        if let sauvegarde = local.lireCorpus(), !sauvegarde.isEmpty {
            corpus = sauvegarde
        } else {
            var embarquees: [Recette] = []
            for url in Ressources.lotsEmbarques() {
                if let d = try? Data(contentsOf: url),
                   let r = try? JSONDecoder().decode([Recette].self, from: d) {
                    embarquees.append(contentsOf: r)
                }
            }
            corpus = embarquees.sorted { $0.nom < $1.nom }
        }
        if let l = local.lireLots() { lots = l }
    }

    // MARK: - Synchronisation

    func synchroniser() async {
        guard erreurCritique == nil else { return }
        let jeton = abonnement.jetonServeur
        do {
            let manif = try await serveur.manifeste(jeton: jeton)
            lots = manif.lots
            local.ecrireLots(manif.lots)
            if let a = manif.abonne { abonne = a }

            let rep = try await serveur.recettes(jeton: jeton)
            if !rep.recettes.isEmpty {
                corpus = rep.recettes
                local.ecrireCorpus(rep.recettes)
            }
            horsLigne = false
            messageSynchro = nil
            derniereSynchro = Date()
            recalculer()
        } catch {
            horsLigne = true
            messageSynchro = corpus.isEmpty
                ? "Aucune connexion et rien en mémoire. Connectez-vous une fois pour télécharger les recettes."
                : "Hors ligne — vos recettes téléchargées restent accessibles."
        }
    }

    // MARK: - Adaptation

    func recalculer() {
        guard let moteur, moteur.pret, !corpus.isEmpty else {
            adaptees = []
            return
        }
        do {
            adaptees = try moteur.adapter(corpus, pour: profilActif)
        } catch {
            adaptees = []
            messageSynchro = "Le moteur n’a pas pu adapter les recettes : \(error.localizedDescription)"
        }
    }

    /// Paire recette + résultat, dans l'ordre du corpus.
    var paires: [(recette: Recette, resultat: RecetteAdaptee)] {
        let parId = Dictionary(uniqueKeysWithValues: adaptees.map { ($0.id, $0) })
        return corpus.compactMap { r in
            guard let res = parId[r.id] else { return nil }
            return (r, res)
        }
    }

    func resultat(pour id: String) -> RecetteAdaptee? {
        adaptees.first { $0.id == id }
    }

    func recette(pour id: String) -> Recette? {
        corpus.first { $0.id == id }
    }

    // MARK: - Profils

    func enregistrer(_ profil: Profil) {
        if let i = profils.firstIndex(where: { $0.id == profil.id }) {
            profils[i] = profil
        } else {
            profils.append(profil)
            identifiantActif = profil.id
        }
        local.ecrireProfils(profils)
        recalculer()
    }

    func supprimer(_ profil: Profil) {
        profils.removeAll { $0.id == profil.id }
        if identifiantActif == profil.id { identifiantActif = profils.first?.id }
        if profils.count < 2 { modeFamille = false }
        local.ecrireProfils(profils)
        recalculer()
    }

    func choisir(_ id: String) {
        identifiantActif = id
        modeFamille = false
        recalculer()
    }

    func basculerFamille() {
        modeFamille.toggle()
        recalculer()
    }

    // MARK: - Références

    var allergenesConnus: [Allergene] { moteur?.base?.allergenes ?? [] }

    func nomAllergene(_ id: String) -> String { moteur?.nomAllergene(id) ?? id }

    func nomsAllergenes(_ ids: [String]) -> [String] { moteur?.nomsAllergenes(ids) ?? ids }

    func definition(_ id: String) -> DefinitionIngredient? { moteur?.catalogue[id] }

    func stade(pour ageMois: Int) -> Stade? { try? moteur?.stade(pour: ageMois) }

    // MARK: - Scanner

    func evaluerEtiquette(_ texte: String) throws -> VerdictProduit {
        guard let moteur else { throw ErreurMoteur.exception("moteur indisponible") }
        return try moteur.evaluerEtiquette(texte, evites: profilActif.allergenes)
    }

    func consulterProduit(code: String) async throws -> Produit {
        try await serveur.produit(code: code, jeton: abonnement.jetonServeur)
    }

    // MARK: - Compte

    func connecter(courriel: String) async throws {
        let r = try await serveur.connexion(courriel: courriel)
        abonnement.definirJeton(r.jeton, courriel: r.courriel)
        abonne = r.abonne ?? false
        await abonnement.verifierDroits()
        await synchroniser()
    }

    func lierAchat(_ jws: String) async {
        guard let jeton = abonnement.jetonServeur else { return }
        if let r = try? await serveur.lierTransaction(jws, jeton: jeton), let a = r.abonne {
            abonne = a
            await synchroniser()
        }
    }

    func deconnecter() async {
        abonnement.oublierJeton()
        abonne = false
        await synchroniser()
    }

    // MARK: - Lots

    var lotsVerrouilles: [Lot] { lots.filter { !$0.deverrouille } }

    var lotLePlusRecentDeverrouille: Lot? {
        lots.filter(\.deverrouille).sorted { $0.id < $1.id }.last
    }
}

// MARK: - Formatage partagé

enum Formats {
    /// « lait, œufs et arachides » plutôt que « lait, œufs, arachides ».
    static func liste(_ elements: [String]) -> String {
        guard elements.count > 1 else { return elements.first ?? "" }
        return elements.dropLast().joined(separator: ", ") + " et " + (elements.last ?? "")
    }

    static func age(_ mois: Int) -> String {
        if mois < 24 { return "\(mois) mois" }
        let ans = mois / 12
        let reste = mois % 12
        return reste == 0 ? "\(ans) ans" : "\(ans) ans \(reste) mois"
    }
}
