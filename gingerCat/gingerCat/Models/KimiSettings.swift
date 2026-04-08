import Foundation

enum KimiSettingsKeys {
    static let baseURL = "settings.kimi.baseURL"
    static let model = "settings.kimi.model"
    static let apiKey = "settings.kimi.apiKey"
    static let maxTokens = "settings.kimi.maxTokens"
    static let temperature = "settings.kimi.temperature"
    static let topP = "settings.kimi.topP"
    static let aiSummaryEnabled = "settings.aiSummaryEnabled"
    static let haptics = "settings.haptics"
    static let appearanceMode = "settings.appearanceMode"
}

enum AppearanceMode: String, CaseIterable {
    case automatic = "automatic"
    case light = "light"
    case dark = "dark"
    
    var displayName: String {
        switch self {
        case .automatic:
            return String(localized: "自动")
        case .light:
            return String(localized: "浅色")
        case .dark:
            return String(localized: "深色")
        }
    }
    
    var iconName: String {
        switch self {
        case .automatic:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max"
        case .dark:
            return "moon"
        }
    }
}

struct KimiRuntimeConfig {
    static let defaultBaseURL = "https://api.moonshot.cn/v1"
    static let defaultModel = "kimi-k2.5"

    let baseURL: String
    let model: String
    let apiKey: String
    let maxTokens: Int?
    let temperature: Double?
    let topP: Double?

    var canRequestSummary: Bool {
        apiKey.isEmpty == false && model.isEmpty == false && chatCompletionsURL != nil
    }

    var chatCompletionsURL: URL? {
        var normalized = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { return nil }

        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }

        if normalized.hasSuffix("/chat/completions") == false {
            normalized += "/chat/completions"
        }

        return URL(string: normalized)
    }
}
