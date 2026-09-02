//  Sequence.swift
//  Each device derives its own day sequence from a seed: a meal and a snack
//  per day, drawn from the pool, with a rotation gap before a recipe returns.

import Foundation

/// What one day of the sequence holds.
struct DayPick: Codable, Equatable, Sendable {
    var meal: String?
    var snack: String?
}

struct RecipeSequence {
    let seed: UInt64
    /// Day zero: the Monday of the week the app was first opened.
    let epoch: Date
    /// A recipe does not return before this many weeks.
    let rotationWeeks: Int
    /// The first two weeks draw from the free recipes only.
    static let freeDays = 14

    /// The day index of a calendar date, negative before the epoch.
    func dayIndex(of date: Date, calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: epoch), b = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// The meal and the snack for one day. `history` holds the days already
    /// shown, frozen; `pool` is the catalogue. Deterministic for a seed.
    func pick(day: Int, pool: [Recipe], history: [Int: DayPick]) -> DayPick {
        if let fixed = history[day] { return fixed }
        let free = day < Self.freeDays
        let meals = pool.filter { $0.isMeal && (!free || $0.free == true) }
        let snacks = pool.filter { $0.isSnack && (!free || $0.free == true) }
        return DayPick(meal: choose(day: day, from: meals, history: history, isMeal: true),
                       snack: choose(day: day, from: snacks, history: history, isMeal: false))
    }

    /// The days from `from` to `to` inclusive, walking forward so each day
    /// sees the ones before it.
    func picks(from: Int, to: Int, pool: [Recipe], history: [Int: DayPick]) -> [Int: DayPick] {
        var seen = history
        var out: [Int: DayPick] = [:]
        let start = min(from, (history.keys.min() ?? from))
        for d in start...max(to, start) {
            let p = pick(day: d, pool: pool, history: seen)
            seen[d] = p
            if d >= from { out[d] = p }
        }
        return out
    }

    private func choose(day: Int, from candidates: [Recipe], history: [Int: DayPick], isMeal: Bool) -> String? {
        guard !candidates.isEmpty else { return nil }
        let gap = rotationWeeks * 7
        var lastUsed: [String: Int] = [:]
        for (d, p) in history where d < day {
            if let id = isMeal ? p.meal : p.snack, lastUsed[id] ?? Int.min < d { lastUsed[id] = d }
        }
        /* Everything outside the rotation gap, picked by hash. When the pool
         * is too small to honour the gap, the least recently used wins, so a
         * recipe waits the whole pool before returning. */
        let rested = candidates.filter { (lastUsed[$0.id] ?? Int.min) <= day - gap }
        let field: [Recipe]
        if rested.isEmpty {
            let oldest = candidates.map { lastUsed[$0.id] ?? Int.min }.min() ?? Int.min
            field = candidates.filter { (lastUsed[$0.id] ?? Int.min) == oldest }
        } else {
            field = rested
        }
        return field.min { score(day: day, id: $0.id) < score(day: day, id: $1.id) }?.id
    }

    /// A stable 64-bit mix of the seed, the day and the recipe id.
    private func score(day: Int, id: String) -> UInt64 {
        var h = seed ^ 0x9E3779B97F4A7C15
        h = mix(h, UInt64(bitPattern: Int64(day)))
        for b in id.utf8 { h = mix(h, UInt64(b)) }
        return h
    }

    private func mix(_ h: UInt64, _ v: UInt64) -> UInt64 {
        var x = (h ^ v) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 31)) &* 0x94D049BB133111EB
        return x ^ (x >> 29)
    }
}
