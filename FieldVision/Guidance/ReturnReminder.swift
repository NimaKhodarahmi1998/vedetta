import UserNotifications

/// Asks the walker to come back after leaving the app by mistake: a notification, read aloud by VoiceOver
/// and, with Announce Notifications on, by Siri, with a button that goes straight back to guiding.
final class ReturnReminder: NSObject, UNUserNotificationCenterDelegate {
    nonisolated private static let categoryIdentifier = "fieldvision.return"
    nonisolated private static let resumeIdentifier = "fieldvision.return.resume"
    nonisolated private static let notificationIdentifier = "fieldvision.left"

    var onResume: (() -> Void)?

    private let center = UNUserNotificationCenter.current()

    init(language: Language) {
        super.init()
        center.delegate = self
        let resume = UNNotificationAction(
            identifier: Self.resumeIdentifier,
            title: InterfaceText.backToGuidance(in: language),
            options: [.foreground]
        )
        let notNow = UNNotificationAction(identifier: "fieldvision.return.dismiss", title: InterfaceText.notNow(in: language))
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.categoryIdentifier, actions: [resume, notNow], intentIdentifiers: [])])
    }

    func requestPermission() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func post(in language: Language) {
        let content = UNMutableNotificationContent()
        content.title = InterfaceText.leftAppTitle(in: language)
        content.body = InterfaceText.leftAppBody(in: language)
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        center.add(UNNotificationRequest(identifier: Self.notificationIdentifier, content: content, trigger: nil))
    }

    func clear() {
        center.removeDeliveredNotifications(withIdentifiers: [Self.notificationIdentifier])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        guard action == Self.resumeIdentifier || action == UNNotificationDefaultActionIdentifier else { return }
        await resume()
    }

    private func resume() {
        onResume?()
    }
}
