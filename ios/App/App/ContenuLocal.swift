//  ContenuLocal.swift — hors ligne et profils (bloc H)
//
//  Le hors ligne n'est pas un extra : c'est le cas d'usage. Un parent vérifie
//  une recette dans l'allée d'épicerie au sous-sol, sans signal. Une fois le
//  contenu téléchargé, tout fonctionne — moteur, substitutions, illustrations.
//
//  Les profils vivent côté natif, pas dans le stockage web : ils survivent à
//  un vidage de cache et se sauvegardent avec l'appareil.

import Foundation

struct Profil: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var nom: String
    var ageMois: Int
    var allergenes: [String]
}

@MainActor
final class ContenuLocal: ObservableObject {
    @Published var profils: [Profil] = []
    @Published var profilActifId: String?
    @Published private(set) var lots: [String] = []

    private let fm = FileManager.default

    var dossierBase: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Bouchees", isDirectory: true)
    }
    var dossierWeb: URL { dossierBase.appendingPathComponent("web", isDirectory: true) }
    private var fichierProfils: URL { dossierBase.appendingPathComponent("profils.json") }
    private var fichierContenu: URL { dossierBase.appendingPathComponent("contenu.json") }

    var aDuContenuLocal: Bool { fm.fileExists(atPath: fichierContenu.path) }

    var profilActif: Profil {
        profils.first { $0.id == profilActifId } ?? profils.first
            ?? Profil(nom: "Mon enfant", ageMois: 9, allergenes: [])
    }

    init() {
        try? fm.createDirectory(at: dossierWeb, withIntermediateDirectories: true)
        chargerProfils()
        installerWebSiBesoin()
    }

    // MARK: - Profils

    func chargerProfils() {
        guard let d = try? Data(contentsOf: fichierProfils),
              let p = try? JSONDecoder().decode([Profil].self, from: d) else { return }
        profils = p
        profilActifId = p.first?.id
    }

    func sauverProfils() {
        guard let d = try? JSONEncoder().encode(profils) else { return }
        try? d.write(to: fichierProfils, options: .atomic)
        // Exclu de la sauvegarde iCloud : données d'un enfant, gardées locales.
        var url = fichierProfils
        var v = URLResourceValues(); v.isExcludedFromBackup = false
        try? url.setResourceValues(v)
    }

    // MARK: - Contenu web embarqué

    /// La coquille embarque une copie du moteur et des lots gratuits : la
    /// première ouverture fonctionne sans réseau, avant toute connexion.
    private func installerWebSiBesoin() {
        let index = dossierWeb.appendingPathComponent("index.html")
        guard !fm.fileExists(atPath: index.path),
              let source = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web") else { return }
        let dossierSource = source.deletingLastPathComponent()
        if let items = try? fm.contentsOfDirectory(at: dossierSource, includingPropertiesForKeys: nil) {
            for f in items {
                try? fm.copyItem(at: f, to: dossierWeb.appendingPathComponent(f.lastPathComponent))
            }
        }
    }

    // MARK: - Synchronisation

    /// Récupère le manifeste puis les lots autorisés. Le serveur ne renvoie que
    /// ce à quoi le compte a droit — le client ne filtre rien.
    func rafraichir(jeton: String?) async throws {
        var req = URLRequest(url: Reglages.baseServeur.appendingPathComponent("api/recettes"))
        req.timeoutInterval = 15
        if let j = jeton { req.setValue("Bearer \(j)", forHTTPHeaderField: "Authorization") }
        let (data, rep) = try await URLSession.shared.data(for: req)
        guard let http = rep as? HTTPURLResponse, http.statusCode == 200 else { throw ErreurContenu.reseau }
        try data.write(to: fichierContenu, options: .atomic)

        var reqS = URLRequest(url: Reglages.baseServeur.appendingPathComponent("api/securite"))
        reqS.timeoutInterval = 15
        let (secu, repS) = try await URLSession.shared.data(for: reqS)
        guard let httpS = repS as? HTTPURLResponse, httpS.statusCode == 200 else { throw ErreurContenu.reseau }
        try secu.write(to: dossierBase.appendingPathComponent("securite.json"), options: .atomic)

        if let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let l = o["lots"] as? [String] { lots = l }
    }

    enum ErreurContenu: Error { case reseau }
}

enum Reglages {
    /// À remplacer par l'adresse de ton service déployé.
    static let baseServeur = URL(string: ProcessInfo.processInfo.environment["BOUCHEES_SERVEUR"]
                                 ?? "https://bouchees.onrender.com")!
    static let conditions = URL(string: "https://bouchees.example/conditions")!
    static let confidentialite = URL(string: "https://bouchees.example/confidentialite")!
}
