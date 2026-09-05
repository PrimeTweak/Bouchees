//  WeeklyReminder.swift
//  One local notification a week. No server, no token, nothing sent.

import Foundation
import UserNotifications

/// Schedules the Monday-morning reminder that a new week is open.
@MainActor
enum WeeklyReminder {
    private static let identifier = "bouchees.weekly"
    private static let key = "weeklyReminder"

    /// Whether the parent has the reminder on. Off until asked.
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Asks for permission, then schedules; returns false when refused.
    static func enable(firstName: String) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let ok = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard ok else { enabled = false; return false }
        enabled = true
        await schedule(firstName: firstName)
        return true
    }

    static func disable() {
        enabled = false
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// Every Monday at 8:00 local time. Repeats until removed.
    static func schedule(firstName: String) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        let content = UNMutableNotificationContent()
        content.title = String(localized: "New week, new recipes")
        content.body = firstName.isEmpty
            ? String(localized: "7 new recipes are open this week.")
            : String(format: String(localized: "7 new recipes for %@ this week."), firstName)
        content.sound = .default
        var date = DateComponents()
        date.weekday = 2
        date.hour = 8
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }
}
