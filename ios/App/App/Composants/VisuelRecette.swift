//  VisuelRecette.swift
//
//  LA RÈGLE, ET ELLE NE SE NÉGOCIE PAS
//
//  Une photo montre le plat D'ORIGINE. Si la recette a été adaptée — le
//  fromage remplacé, l'œuf retiré — la photo montre autre chose que ce qu'on
//  demande de cuisiner. Dans une app d'allergies, c'est le pire endroit
//  possible pour un décalage.
//
//  Donc : photo seulement quand la recette est servie TELLE QUELLE. Dès qu'il
//  y a un échange, l'illustration reprend la place — elle, est dérivée des
//  ingrédients réels après adaptation, et ne peut pas mentir.
//
//  Le mélange devient une grammaire plutôt qu'une incohérence : photo = rien
//  touché, dessin = on a adapté.

import SwiftUI
import UIKit

struct VisuelRecette: View {
    let recette: Recette
    let resultat: RecetteAdaptee

    @State private var photo: UIImage?
    @State private var echec = false

    private var photoPertinente: Bool {
        recette.image != nil && resultat.statut == .telleQuelle && !echec
    }

    var body: some View {
        ZStack {
            if let photo, photoPertinente {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                PlatVue(resultat: resultat, categorie: recette.categorie)
            }
        }
        .task(id: recette.id) { await charger() }
        .animation(.easeInOut(duration: 0.2), value: photo != nil)
    }

    private func charger() async {
        guard photoPertinente, photo == nil, let fichier = recette.image else { return }
        if let img = await CachePhotos.partage.image(fichier) {
            photo = img
        } else {
            // Pas de photo disponible : l'illustration reste, et c'est correct.
            echec = true
        }
    }
}

/// Cache disque des photos. Elles arrivent du serveur, pas du bundle : les
/// lots tournent chaque semaine, embarquer les images ferait grossir l'app
/// sans fin et pour rien.
actor CachePhotos {
    static let partage = CachePhotos()

    private let fm = FileManager.default
    private var enMemoire: [String: UIImage] = [:]

    private var dossier: URL {
        let d = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("photos", isDirectory: true)
        if !fm.fileExists(atPath: d.path) {
            try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
        return d
    }

    private func cheminLocal(_ fichier: String) -> URL {
        // Le nom du fichier peut contenir un sous-dossier : on l'aplatit pour
        // ne jamais écrire hors du dossier de cache.
        let sur = fichier.replacingOccurrences(of: "/", with: "_")
        return dossier.appendingPathComponent(sur)
    }

    func image(_ fichier: String) async -> UIImage? {
        if let deja = enMemoire[fichier] { return deja }

        let local = cheminLocal(fichier)
        if let d = try? Data(contentsOf: local), let img = UIImage(data: d) {
            enMemoire[fichier] = img
            return img
        }

        guard let url = URL(string: fichier, relativeTo: Reglages.baseServeur) else { return nil }
        var requete = URLRequest(url: url)
        requete.timeoutInterval = 20
        guard let (data, reponse) = try? await URLSession.shared.data(for: requete),
              let http = reponse as? HTTPURLResponse, http.statusCode == 200,
              let img = UIImage(data: data) else { return nil }

        try? data.write(to: local, options: .atomic)
        enMemoire[fichier] = img
        return img
    }

    /// Les lots tournent : les photos des semaines sorties de la fenêtre
    /// n'ont plus à occuper le disque.
    func nettoyer(garder fichiers: Set<String>) {
        let gardes = Set(fichiers.map { $0.replacingOccurrences(of: "/", with: "_") })
        guard let items = try? fm.contentsOfDirectory(at: dossier, includingPropertiesForKeys: nil) else { return }
        for f in items where !gardes.contains(f.lastPathComponent) {
            try? fm.removeItem(at: f)
        }
        enMemoire = enMemoire.filter { fichiers.contains($0.key) }
    }
}

// MARK: - Contrôle de note

/// Cinq étoiles. Toucher la même étoile deux fois retire la note — un parent
/// doit pouvoir se rétracter, pas seulement corriger.
struct EtoilesNote: View {
    let note: Int?
    var taille: CGFloat = 26
    let surChangement: (Int?) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { i in
                Button {
                    surChangement(note == i ? nil : i)
                } label: {
                    Image(systemName: (note ?? 0) >= i ? "star.fill" : "star")
                        .font(.system(size: taille))
                        .foregroundStyle((note ?? 0) >= i ? Teinte.courge : Color.secondary.opacity(0.4))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(i) étoile\(i > 1 ? "s" : "")")
                .accessibilityAddTraits(note == i ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(note == nil ? "Pas encore noté" : "Noté \(note!) sur 5")
    }
}

/// L'agrégat public, affiché à côté du titre.
struct BadgeNote: View {
    let votes: Int
    let moyenne: Double?
    var compact = false

    var body: some View {
        if votes > 0, let m = moyenne {
            HStack(spacing: 3) {
                Image(systemName: "star.fill").font(.system(size: compact ? 9 : 11))
                Text(String(format: "%.1f", m).replacingOccurrences(of: ".", with: ","))
                    .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                if !compact {
                    Text("(\(votes))").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(Teinte.courge)
            .accessibilityLabel("Noté \(String(format: "%.1f", m)) sur 5 par \(votes) personne\(votes > 1 ? "s" : "")")
        }
    }
}
