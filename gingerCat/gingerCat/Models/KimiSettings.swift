import Foundation

enum AppSettingsKeys {
    static let aiSummaryEnabled = "settings.aiSummaryEnabled"
    static let haptics = "settings.haptics"
    static let appearanceMode = "settings.appearanceMode"
}

enum AIProvider: String, CaseIterable, Identifiable {
    case kimi
    case deepSeek = "deepseek"
    case miniMax = "minimax"
    case xiaomiMiMo = "xiaomi-mimo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .kimi:
            return "Kimi"
        case .deepSeek:
            return "DeepSeek"
        case .miniMax:
            return "MiniMax"
        case .xiaomiMiMo:
            return "Xiaomi MiMo"
        }
    }

    var detailText: String {
        switch self {
        case .kimi:
            return String(localized: "Moonshot AI · OpenAI 兼容接口")
        case .deepSeek:
            return String(localized: "深度求索 · OpenAI 兼容接口")
        case .miniMax:
            return String(localized: "MiniMax · OpenAI 兼容接口")
        case .xiaomiMiMo:
            return String(localized: "小米 MiMo · OpenAI 兼容接口")
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .kimi:
            return "https://api.moonshot.cn/v1"
        case .deepSeek:
            return "https://api.deepseek.com"
        case .miniMax:
            return "https://api.minimaxi.com/v1"
        case .xiaomiMiMo:
            return "https://api.xiaomimimo.com/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .kimi:
            return "kimi-k2.5"
        case .deepSeek:
            return "deepseek-chat"
        case .miniMax:
            return "MiniMax-M2.7"
        case .xiaomiMiMo:
            return "mimo-v2-pro"
        }
    }

    var recommendedModels: [String] {
        switch self {
        case .kimi:
            return ["kimi-k2.5"]
        case .deepSeek:
            return ["deepseek-chat", "deepseek-reasoner"]
        case .miniMax:
            return [
                "MiniMax-M2.7",
                "MiniMax-M2.7-highspeed",
                "MiniMax-M2.5",
                "MiniMax-M2.5-highspeed"
            ]
        case .xiaomiMiMo:
            return ["mimo-v2-pro", "mimo-v2-omni"]
        }
    }

    var supportsJSONOutput: Bool {
        switch self {
        case .kimi, .deepSeek:
            return true
        case .miniMax, .xiaomiMiMo:
            return false
        }
    }

    func allowsTemperature(for model: String) -> Bool {
        switch self {
        case .kimi:
            return true
        case .deepSeek:
            return model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "deepseek-reasoner"
        case .miniMax:
            return true
        case .xiaomiMiMo:
            return true
        }
    }

    func allowsTopP(for model: String) -> Bool {
        allowsTemperature(for: model)
    }

    var maxTokensParameterName: String {
        switch self {
        case .xiaomiMiMo:
            return "max_completion_tokens"
        case .kimi, .deepSeek, .miniMax:
            return "max_tokens"
        }
    }
}

enum AIProviderSettingsKeys {
    static let selectedProvider = "settings.ai.selectedProvider"

    static func baseURL(for provider: AIProvider) -> String {
        switch provider {
        case .kimi:
            return "settings.kimi.baseURL"
        case .deepSeek:
            return "settings.deepseek.baseURL"
        case .miniMax:
            return "settings.minimax.baseURL"
        case .xiaomiMiMo:
            return "settings.xiaomimimo.baseURL"
        }
    }

    static func model(for provider: AIProvider) -> String {
        switch provider {
        case .kimi:
            return "settings.kimi.model"
        case .deepSeek:
            return "settings.deepseek.model"
        case .miniMax:
            return "settings.minimax.model"
        case .xiaomiMiMo:
            return "settings.xiaomimimo.model"
        }
    }

    static func apiKey(for provider: AIProvider) -> String {
        switch provider {
        case .kimi:
            return "settings.kimi.apiKey"
        case .deepSeek:
            return "settings.deepseek.apiKey"
        case .miniMax:
            return "settings.minimax.apiKey"
        case .xiaomiMiMo:
            return "settings.xiaomimimo.apiKey"
        }
    }

    static func maxTokens(for provider: AIProvider) -> String {
        switch provider {
        case .kimi:
            return "settings.kimi.maxTokens"
        case .deepSeek:
            return "settings.deepseek.maxTokens"
        case .miniMax:
            return "settings.minimax.maxTokens"
        case .xiaomiMiMo:
            return "settings.xiaomimimo.maxTokens"
        }
    }

    static func temperature(for provider: AIProvider) -> String {
        switch provider {
        case .kimi:
            return "settings.kimi.temperature"
        case .deepSeek:
            return "settings.deepseek.temperature"
        case .miniMax:
            return "settings.minimax.temperature"
        case .xiaomiMiMo:
            return "settings.xiaomimimo.temperature"
        }
    }

    static func topP(for provider: AIProvider) -> String {
        switch provider {
        case .kimi:
            return "settings.kimi.topP"
        case .deepSeek:
            return "settings.deepseek.topP"
        case .miniMax:
            return "settings.minimax.topP"
        case .xiaomiMiMo:
            return "settings.xiaomimimo.topP"
        }
    }
}

enum KimiSettingsKeys {
    static let baseURL = AIProviderSettingsKeys.baseURL(for: .kimi)
    static let model = AIProviderSettingsKeys.model(for: .kimi)
    static let apiKey = AIProviderSettingsKeys.apiKey(for: .kimi)
    static let maxTokens = AIProviderSettingsKeys.maxTokens(for: .kimi)
    static let temperature = AIProviderSettingsKeys.temperature(for: .kimi)
    static let topP = AIProviderSettingsKeys.topP(for: .kimi)
    static let aiSummaryEnabled = AppSettingsKeys.aiSummaryEnabled
    static let haptics = AppSettingsKeys.haptics
    static let appearanceMode = AppSettingsKeys.appearanceMode
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

struct AIProviderRuntimeConfig {
    let provider: AIProvider
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

enum AIProviderConfigStore {
    static func selectedProvider(defaults: UserDefaults = .standard) -> AIProvider {
        guard let rawValue = defaults.string(forKey: AIProviderSettingsKeys.selectedProvider),
              let provider = AIProvider(rawValue: rawValue) else {
            return .kimi
        }
        return provider
    }

    static func runtimeConfig(
        for provider: AIProvider,
        defaults: UserDefaults = .standard
    ) -> AIProviderRuntimeConfig {
        AIProviderRuntimeConfig(
            provider: provider,
            baseURL: sanitized(
                defaults.string(forKey: AIProviderSettingsKeys.baseURL(for: provider)),
                fallback: provider.defaultBaseURL
            ),
            model: sanitized(
                defaults.string(forKey: AIProviderSettingsKeys.model(for: provider)),
                fallback: provider.defaultModel
            ),
            apiKey: defaults.string(forKey: AIProviderSettingsKeys.apiKey(for: provider))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            maxTokens: parseInt(defaults.string(forKey: AIProviderSettingsKeys.maxTokens(for: provider))),
            temperature: parseDouble(defaults.string(forKey: AIProviderSettingsKeys.temperature(for: provider))),
            topP: parseDouble(defaults.string(forKey: AIProviderSettingsKeys.topP(for: provider)))
        )
    }

    static func selectedRuntimeConfig(defaults: UserDefaults = .standard) -> AIProviderRuntimeConfig {
        runtimeConfig(for: selectedProvider(defaults: defaults), defaults: defaults)
    }

    static func persist(
        _ config: AIProviderRuntimeConfig,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(config.baseURL, forKey: AIProviderSettingsKeys.baseURL(for: config.provider))
        defaults.set(config.model, forKey: AIProviderSettingsKeys.model(for: config.provider))
        defaults.set(config.apiKey, forKey: AIProviderSettingsKeys.apiKey(for: config.provider))
        defaults.set(config.maxTokens.map { String($0) }, forKey: AIProviderSettingsKeys.maxTokens(for: config.provider))
        defaults.set(config.temperature.map { String($0) }, forKey: AIProviderSettingsKeys.temperature(for: config.provider))
        defaults.set(config.topP.map { String($0) }, forKey: AIProviderSettingsKeys.topP(for: config.provider))
    }

    private static func sanitized(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func parseInt(_ value: String?) -> Int? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty == false else { return nil }
        return Int(trimmed)
    }

    private static func parseDouble(_ value: String?) -> Double? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty == false else { return nil }
        return Double(trimmed)
    }
}
