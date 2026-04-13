import Foundation

enum AppSettingsKeys {
    static let aiSummaryEnabled = "settings.aiSummaryEnabled"
    static let haptics = "settings.haptics"
    static let hapticsIntensity = "settings.hapticsIntensity"
    static let appearanceMode = "settings.appearanceMode"
}

enum AIProvider: String, CaseIterable, Identifiable {
    case deepSeek = "deepseek"
    case kimi
    case miniMax = "minimax"
    case xiaomiMiMo = "xiaomi-mimo"
    case thirdParty = "third-party"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepSeek:
            return "DeepSeek"
        case .kimi:
            return "Kimi"
        case .miniMax:
            return "MiniMax"
        case .xiaomiMiMo:
            return "XiaoMi MiMo"
        case .thirdParty:
            return "OpenAI"
        }
    }

    var detailText: String {
        switch self {
        case .deepSeek:
            return String(localized: "深度求索")
        case .kimi:
            return String(localized: "Moonshot AI")
        case .miniMax:
            return String(localized: "MiniMax")
        case .xiaomiMiMo:
            return String(localized: "XiaoMi MiMo")
        case .thirdParty:
            return String(localized: "OpenAI")
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .deepSeek:
            return "https://api.deepseek.com"
        case .kimi:
            return "https://api.moonshot.cn/v1"
        case .miniMax:
            return "https://api.minimaxi.com/v1"
        case .xiaomiMiMo:
            return "https://api.xiaomimimo.com/v1"
        case .thirdParty:
            return "https://api.openai.com/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .deepSeek:
            return "deepseek-chat"
        case .kimi:
            return "kimi-k2.5"
        case .miniMax:
            return "MiniMax-M2.7"
        case .xiaomiMiMo:
            return "mimo-v2-pro"
        case .thirdParty:
            return "gpt-5.4"
        }
    }

    var recommendedModels: [String] {
        switch self {
        case .deepSeek:
            return ["deepseek-chat", "deepseek-reasoner"]
        case .kimi:
            return ["kimi-k2.5"]
        case .miniMax:
            return [
                "MiniMax-M2.7",
                "MiniMax-M2.7-highspeed",
                "MiniMax-M2.5",
                "MiniMax-M2.5-highspeed"
            ]
        case .xiaomiMiMo:
            return ["mimo-v2-pro", "mimo-v2-omni"]
        case .thirdParty:
            return ["gpt-5.4", "gpt-5.4-mini", "gpt-4.1"]
        }
    }

    var supportsJSONOutput: Bool {
        switch self {
        case .deepSeek, .kimi, .thirdParty:
            return true
        case .miniMax, .xiaomiMiMo:
            return false
        }
    }

    func allowsTemperature(for model: String) -> Bool {
        switch self {
        case .deepSeek:
            return model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "deepseek-reasoner"
        case .kimi:
            return true
        case .miniMax:
            return true
        case .xiaomiMiMo:
            return true
        case .thirdParty:
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
        case .deepSeek, .kimi, .miniMax, .thirdParty:
            return "max_tokens"
        }
    }

    var baseURLPlaceholder: String {
        let trimmed = defaultBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "请填写 Base URL") : trimmed
    }

    var modelPlaceholder: String {
        let trimmed = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "请填写模型名称") : trimmed
    }
}

enum AIProviderSettingsKeys {
    static let selectedProvider = "settings.ai.selectedProvider"

    static func baseURL(for provider: AIProvider) -> String {
        switch provider {
        case .deepSeek:
            return "settings.deepseek.baseURL"
        case .kimi:
            return "settings.kimi.baseURL"
        case .miniMax:
            return "settings.minimax.baseURL"
        case .xiaomiMiMo:
            return "settings.xiaomimimo.baseURL"
        case .thirdParty:
            return "settings.thirdparty.baseURL"
        }
    }

    static func model(for provider: AIProvider) -> String {
        switch provider {
        case .deepSeek:
            return "settings.deepseek.model"
        case .kimi:
            return "settings.kimi.model"
        case .miniMax:
            return "settings.minimax.model"
        case .xiaomiMiMo:
            return "settings.xiaomimimo.model"
        case .thirdParty:
            return "settings.thirdparty.model"
        }
    }

    static func apiKey(for provider: AIProvider) -> String {
        switch provider {
        case .deepSeek:
            return "settings.deepseek.apiKey"
        case .kimi:
            return "settings.kimi.apiKey"
        case .miniMax:
            return "settings.minimax.apiKey"
        case .xiaomiMiMo:
            return "settings.xiaomimimo.apiKey"
        case .thirdParty:
            return "settings.thirdparty.apiKey"
        }
    }

    static func maxTokens(for provider: AIProvider) -> String {
        switch provider {
        case .deepSeek:
            return "settings.deepseek.maxTokens"
        case .kimi:
            return "settings.kimi.maxTokens"
        case .miniMax:
            return "settings.minimax.maxTokens"
        case .xiaomiMiMo:
            return "settings.xiaomimimo.maxTokens"
        case .thirdParty:
            return "settings.thirdparty.maxTokens"
        }
    }

    static func temperature(for provider: AIProvider) -> String {
        switch provider {
        case .deepSeek:
            return "settings.deepseek.temperature"
        case .kimi:
            return "settings.kimi.temperature"
        case .miniMax:
            return "settings.minimax.temperature"
        case .xiaomiMiMo:
            return "settings.xiaomimimo.temperature"
        case .thirdParty:
            return "settings.thirdparty.temperature"
        }
    }

    static func topP(for provider: AIProvider) -> String {
        switch provider {
        case .deepSeek:
            return "settings.deepseek.topP"
        case .kimi:
            return "settings.kimi.topP"
        case .miniMax:
            return "settings.minimax.topP"
        case .xiaomiMiMo:
            return "settings.xiaomimimo.topP"
        case .thirdParty:
            return "settings.thirdparty.topP"
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
    static let hapticsIntensity = AppSettingsKeys.hapticsIntensity
    static let appearanceMode = AppSettingsKeys.appearanceMode
}

enum HapticFeedbackIntensity: String, CaseIterable {
    case weak
    case medium
    case strong

    var displayName: String {
        switch self {
        case .weak:
            return String(localized: "弱")
        case .medium:
            return String(localized: "中")
        case .strong:
            return String(localized: "强")
        }
    }
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

    var summaryModelDisplayName: String {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedModel.isEmpty == false else {
            return provider.displayName
        }
        return "\(provider.displayName) · \(trimmedModel)"
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
