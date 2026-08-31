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
    /// Off in the hero, where the drawing sits on its own field.
    var drawingBackground = true

    @State private var photo: UIImage?
    @State private var echec = false

    /* THE PHOTO SHOWS WHENEVER THERE IS ONE.
     *
     * It used to require `status == .asIs`, so a photo only appeared on a
     * recipe that needed no swap. MEASURED for a child avoiding milk, egg and
     * peanut: three recipes of thirty-eight qualify. Thirty-five photos were
     * invisible by construction, whatever the pipeline produced.
     *
     * The rule existed for a real reason — the photo is of the ORIGINAL dish,
     * and showing a milk-and-egg muffin on a page whose whole point is that
     * both were replaced would be a lie in the place it matters most.
     *
     * So the photo shows, and it SAYS SO. A caption on an adapted recipe
     * names what is different. That keeps the promise and shows the food. */
    private var photoPertinente: Bool {
        recipe.image != nil && !echec
    }

    /// True when the picture is of the dish BEFORE the swaps.
    private var photoDuPlatOriginal: Bool {
        photoPertinente && result.status != .asIs
    }

    var body: some View {
        ZStack {
            if let photo, photoPertinente {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
                    /* SAY WHEN THE PICTURE IS OF THE ORIGINAL.
                     *
                     * Without this the photo would quietly claim to be the
                     * adapted dish. A parent cooking a milk-free version has
                     * to know the picture shows the version with milk. */
                    .overlay(alignment: .bottomTrailing) {
                        if photoDuPlatOriginal {
                            Text("Original recipe")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.black.opacity(0.42), in: Capsule())
                                .padding(10)
                        }
                    }
            } else {
                DishArtwork(showsBackground: drawingBackground,
                            result: result, category: recipe.category)
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
    /* NSCache, NOT A DICTIONARY.
     *
     * A dictionary grows until the app dies. Each photo is 1408x1408 — about
     * 8 MB decoded — so twenty opened recipes is 160 MB of RAM that is never
     * given back, on a device that will terminate the app before it complains.
     *
     * NSCache hands memory back under pressure, which is the whole reason it
     * exists. The limit is a ceiling, not a target. */
    private let enMemoire: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 24
        c.totalCostLimit = 80 * 1024 * 1024
        return c
    }()

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
        // never write outside the cache folder.
        let sur = file.replacingOccurrences(of: "/", with: "_")
        return folder.appendingPathComponent(sur)
    }

    func image(_ file: String) async -> UIImage? {
        if let deja = enMemoire.object(forKey: file as NSString) { return deja }

        let local = cheminLocal(file)
        if let d = try? Data(contentsOf: local), let img = UIImage(data: d) {
            enMemoire.setObject(img, forKey: file as NSString,
                                cost: d.count)
            return img
        }

        guard let url = URL(string: file, relativeTo: Settings.serverBase) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let img = UIImage(data: data) else { return nil }

        try? data.write(to: local, options: .atomic)
        enMemoire.setObject(img, forKey: file as NSString, cost: data.count)
        return img
    }

    /// Batches rotate: photos from weeks that left the window no longer need
    /// to take up disk space.
    func nettoyer(garder fichiers: Set<String>) {
        let gardes = Set(fichiers.map { $0.replacingOccurrences(of: "/", with: "_") })
        guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for f in items where !gardes.contains(f.lastPathComponent) {
            try? fm.removeItem(at: f)
        }
        /* NSCache has no enumeration — by design, since entries can vanish
         * under memory pressure at any moment. Emptying it is correct here:
         * this runs when batches rotate, and whatever is still needed is
         * one disk read away. */
        enMemoire.removeAllObjects()
    }
}

// MARK: - Rating control

/// Five stars. Tapping the same star twice removes the rating — a parent has
/// to be able to take it back, not only to correct it.
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
                        .foregroundStyle((note ?? 0) >= i ? Tone.swap : Color.secondary.opacity(0.4))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(i) star\(i > 1 ? "s" : "")")
                .accessibilityAddTraits(note == i ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(note == nil ? String(localized: "Not rated yet") : "Rated \(note!) out of 5")
    }
}

/// The public summary, shown next to the title.
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
            .foregroundStyle(Tone.swap)
            .accessibilityLabel("Rated \(String(format: "%.1f", m)) out of 5 by \(votes) \(votes > 1 ? "people" : "person")")
        }
    }
}
