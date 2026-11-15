import Foundation

/// Follows the iPhone's language: Italian, or English for any other.
nonisolated enum Language: String {
    case italian = "it"
    case english = "en"

    static var current: Language {
        Locale.preferredLanguages.first?.hasPrefix("it") == true ? .italian : .english
    }

    var voiceCode: String {
        switch self {
            case .italian: "it-IT"
            case .english: "en-US"
        }
    }

    func text(_ italian: String, _ english: String) -> String {
        switch self {
            case .italian: italian
            case .english: english
        }
    }

    func number(_ value: Float, digits: Int = 1) -> String {
        let formatted = String(format: "%.\(digits)f", value)
        return self == .italian ? formatted.replacingOccurrences(of: ".", with: ",") : formatted
    }
}
