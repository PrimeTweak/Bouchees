//  RecipeVisual.swift
//
//  THE RULE, AND IT IS NOT NEGOTIABLE
//
//  A photo shows the ORIGINAL dish. If the recipe was adapted — the cheese
//  swapped, the egg removed — the photo shows something other than what we are
//  asking the parent to cook. In an allergy app, that is the worst possible
//  place for a mismatch.
//
//  So: a photo only when the recipe is served AS IS. The moment a swap
//  happens, the drawing takes over — it is derived from the real ingredients
//  after adaptation, so it cannot lie.
//
//  The mix becomes a grammar rather than an inconsistency: photo means nothing
//  was changed, drawing means we adapted.

import SwiftUI
import UIKit

struct RecipeVisual: View {
    let recipe: Recipe
    let result: AdaptedRecipe

    @State private var photo: UIImage?
    @State private var echec = false

    private var photoPertinente: Bool {
        recipe.image != nil && result.status == .telleQuelle && !echec
    }

    var body: some View {
        ZStack {
            if let photo, photoPertinente {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                DishArtwork(result: result, category: recipe.category)
            }
        }
        .task(id: recipe.id) { await load() }
        .animation(.easeInOut(duration: 0.2), value: photo != nil)
    }

    private func load() async {
        guard photoPertinente, photo == nil, let file = recipe.image else { return }
        if let img = await PhotoCache.partage.image(file) {
            photo = img
        } else {
            // Pas de photo disponible : l'illustration others, et c'est correct.
            echec = true
        }
    }
}

/// Cache disque des photos. Elles arrivent du serveur, pas du bundle : les
/// batches tournent chaque semaine, embarquer les images ferait grossir l'app
/// sans fin et pour rien.
actor PhotoCache {
    static let partage = PhotoCache()

    private let fm = FileManager.default
    private var enMemoire: [String: UIImage] = [:]

    private var folder: URL {
        let d = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("photos", isDirectory: true)
        if !fm.fileExists(atPath: d.path) {
            try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
        return d
    }

    private func cheminLocal(_ file: String) -> URL {
        // Le name du file peut contenir un sous-folder : on l'aplatit pour
        // ne jamais écrire hors du folder de cache.
        let sur = file.replacingOccurrences(of: "/", with: "_")
        return folder.appendingPathComponent(sur)
    }

    func image(_ file: String) async -> UIImage? {
        if let deja = enMemoire[file] { return deja }

        let local = cheminLocal(file)
        if let d = try? Data(contentsOf: local), let img = UIImage(data: d) {
            enMemoire[file] = img
            return img
        }

        guard let url = URL(string: file, relativeTo: Settings.serverBase) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let img = UIImage(data: data) else { return nil }

        try? data.write(to: local, options: .atomic)
        enMemoire[file] = img
        return img
    }

    /// Les batches tournent : les photos des semaines sorties de la fenêtre
    /// n'ont plus à occuper le disque.
    func nettoyer(garder fichiers: Set<String>) {
        let gardes = Set(fichiers.map { $0.replacingOccurrences(of: "/", with: "_") })
        guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for f in items where !gardes.contains(f.lastPathComponent) {
            try? fm.removeItem(at: f)
        }
        enMemoire = enMemoire.filter { fichiers.contains($0.key) }
    }
}

// MARK: - Contrôle de note

/// Cinq étoiles. Toucher la même étoile deux fois retire la note — un parent
/// doit pouvoir se rétracter, pas seulement corriger.
struct StarRating: View {
    let note: Int?
    var size: CGFloat = 26
    let onChange: (Int?) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { i in
                Button {
                    onChange(note == i ? nil : i)
                } label: {
                    Image(systemName: (note ?? 0) >= i ? "star.fill" : "star")
                        .font(.system(size: size))
                        .foregroundStyle((note ?? 0) >= i ? Tint.courge : Color.secondary.opacity(0.4))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(i) étoile\(i > 1 ? "s" : "")")
                .accessibilityAddTraits(note == i ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(note == nil ? "Not rated yet" : "Noté \(note!) sur 5")
    }
}

/// L'agrégat public, affiché à côté du title.
struct RatingBadge: View {
    let votes: Int
    let average: Double?
    var compact = false

    var body: some View {
        if votes > 0, let m = average {
            HStack(spacing: 3) {
                Image(systemName: "star.fill").font(.system(size: compact ? 9 : 11))
                Text(String(format: "%.1f", m).replacingOccurrences(of: ".", with: ","))
                    .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                if !compact {
                    Text("(\(votes))").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(Tint.courge)
            .accessibilityLabel("Noté \(String(format: "%.1f", m)) sur 5 par \(votes) personne\(votes > 1 ? "s" : "")")
        }
    }
}
