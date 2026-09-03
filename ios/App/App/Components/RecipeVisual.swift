// In an allergy app, that is the worst possible place for a mismatch. So: a
// photo only when the recipe is served AS IS.

import SwiftUI
import UIKit

struct RecipeVisual: View {
    let recipe: Recipe
    let result: AdaptedRecipe
    /// Off in the hero, where the drawing sits on its own field.
    var drawingBackground = true

    /// Whether the origin warning is spelled out: true only on the recipe
    /// page, where the photo runs 430pt and the parent is about to cook from
    /// it.
    var showsOriginLabel = false

    /// True in a list row, where the 480px twin is enough.
    var compact = false

    @State private var photo: UIImage?
    @State private var echec = false

    /* The rule existed for a real reason — the photo is of the ORIGINAL dish,
     * and showing a milk-and-egg muffin on a page whose whole point is that
     * both were replaced would be a lie in the place it matters most. */
    private var photoPertinente: Bool {
        recipe.image != nil && !echec
    }

    /// True when the picture is of the dish BEFORE the swaps.
    /// What the load depends on: the file, or the id when there is none.
    private var photoKey: String {
        if let t = recipe.thumb { return t }
        if let i = recipe.image { return i }
        return recipe.id
    }

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
                    /* Bottom trailing, level with the title: the top corner
                     * sits under the status bar and had to be pulled into
                     * view, and the gradient down here carries the text. */
                    .overlay(alignment: .bottomTrailing) { originWarning }
            } else {
                DishArtwork(showsBackground: drawingBackground,
                            result: result, category: recipe.category)
            }
        }
        /* Keyed on the photo: a card arrives without one and gains one at the
         * next sync. Keyed on the id, the view never looked again. */
        .task(id: photoKey) { await load() }
        .animation(.soft(0.2), value: photo != nil)
    }

    /// The photo shows the dish before the swaps. Said on the hero, where a
    /// parent looks at it; a thumbnail is too small for a second mark.
    @ViewBuilder
    private var originWarning: some View {
        if photoDuPlatOriginal && showsOriginLabel {
            /* A pale photo swallowed white text on a shadow alone. A dark
             * field, barely there, holds it at any exposure. */
            Text("original recipe")
                .scaledFont(Type.micro)
                .foregroundStyle(.white.opacity(0.95))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.38), in: Capsule())
                .padding(.trailing, 15)
                /* Level with the verdict pill sitting just below the photo. */
                .padding(.bottom, 13)
        }
    }

    private func load() async {
        /* No `photo == nil` guard: the task runs again when the file name
         * changes, and the old picture has to give way to the new one. */
        guard photoPertinente, let full = recipe.image else { return }
        echec = false
        /* Under 160pt the list only needs the 480px twin; 3 MB for a 60pt
         * thumbnail is what made the first sync cost 45 MB on cellular. */
        let file = (compact && recipe.thumb != nil) ? recipe.thumb! : full
        if let img = await PhotoCache.partage.image(file) {
            photo = img
        } else {
            // No photo available: the drawing stands in, and that is correct.
            echec = true
        }
    }
}

/// Disk cache for photos. They come from the server, never the bundle:
/// batches rotate weekly and embedding images would grow the app for nothing.
actor PhotoCache {
    static let partage = PhotoCache()

    private let fm = FileManager.default
    /* Nscache, not a dictionary: nSCache hands memory back under pressure,
     * which is the whole reason it exists. */
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
        if let existing = enMemoire.object(forKey: file as NSString) { return existing }

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
        /* Emptying it is correct here: this runs when batches rotate, and
         * whatever is still needed is one disk read away. */
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
                        .scaledFont(size)
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
                Image(systemName: "star.fill").scaledFont(compact ? Type.micro : Type.label)
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
