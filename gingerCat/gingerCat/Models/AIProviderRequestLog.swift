import Foundation

enum AIProviderRequestOperation: String, Codable, Hashable {
    case configTest
    case ocrAnalysis

    var displayName: String {
        switch self {
        case .configTest:
            return String(appLocalized: "配置测试")
        case .ocrAnalysis:
            return String(appLocalized: "OCR 分析")
        }
    }
}

struct AIProviderRequestLogEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let providerRawValue: String
    let operationRawValue: String
    let createdAt: Date
    let isSuccess: Bool
    let model: String
    let endpoint: String
    let statusCode: Int?
    let requestPayload: String
    let responsePayload: String
    let errorMessage: String?
    let totalTokens: Int?

    init(
        id: UUID = UUID(),
        provider: AIProvider,
        operation: AIProviderRequestOperation,
        createdAt: Date = .now,
        isSuccess: Bool,
        model: String,
        endpoint: String,
        statusCode: Int?,
        requestPayload: String,
        responsePayload: String,
        errorMessage: String?,
        totalTokens: Int? = nil
    ) {
        self.id = id
        self.providerRawValue = provider.rawValue
        self.operationRawValue = operation.rawValue
        self.createdAt = createdAt
        self.isSuccess = isSuccess
        self.model = model
        self.endpoint = endpoint
        self.statusCode = statusCode
        self.requestPayload = requestPayload
        self.responsePayload = responsePayload
        self.errorMessage = errorMessage
        self.totalTokens = totalTokens
    }

    var provider: AIProvider {
        AIProvider(rawValue: providerRawValue) ?? .kimi
    }

    var operation: AIProviderRequestOperation {
        AIProviderRequestOperation(rawValue: operationRawValue) ?? .configTest
    }

    var totalTokensText: String? {
        guard let totalTokens else { return nil }
        return String(appLocalized: "总计 \(totalTokens) tokens")
    }
}

enum AIProviderRequestLogStore {
    private static let maxRecordCount = 10

    static func logs(
        for provider: AIProvider,
        defaults: UserDefaults = .standard
    ) -> [AIProviderRequestLogEntry] {
        guard let data = defaults.data(forKey: storageKey(for: provider)),
              let decoded = try? JSONDecoder().decode([AIProviderRequestLogEntry].self, from: data) else {
            return []
        }
        let normalized = normalizedLogs(decoded)
        if normalized.count != decoded.count {
            persist(normalized, for: provider, defaults: defaults)
        }
        return normalized
    }

    static func append(
        _ entry: AIProviderRequestLogEntry,
        defaults: UserDefaults = .standard
    ) {
        var current = logs(for: entry.provider, defaults: defaults)
        current.insert(entry, at: 0)
        persist(normalizedLogs(current), for: entry.provider, defaults: defaults)
    }

    static func clear(
        provider: AIProvider,
        defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: storageKey(for: provider))
    }

    private static func storageKey(for provider: AIProvider) -> String {
        "settings.ai.requestLogs.\(provider.rawValue)"
    }

    private static func normalizedLogs(_ entries: [AIProviderRequestLogEntry]) -> [AIProviderRequestLogEntry] {
        Array(entries.sorted { $0.createdAt > $1.createdAt }.prefix(maxRecordCount))
    }

    private static func persist(
        _ entries: [AIProviderRequestLogEntry],
        for provider: AIProvider,
        defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey(for: provider))
    }
}

struct AIProviderConfigTestStatus: Codable, Hashable {
    let lastTestAt: Date
    let isSuccess: Bool
}

enum AIProviderConfigTestStatusStore {
    static func status(
        for provider: AIProvider,
        defaults: UserDefaults = .standard
    ) -> AIProviderConfigTestStatus? {
        guard let data = defaults.data(forKey: storageKey(for: provider)),
              let decoded = try? JSONDecoder().decode(AIProviderConfigTestStatus.self, from: data) else {
            return nil
        }
        return decoded
    }

    static func persist(
        _ status: AIProviderConfigTestStatus,
        for provider: AIProvider,
        defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(status) else { return }
        defaults.set(data, forKey: storageKey(for: provider))
    }

    private static func storageKey(for provider: AIProvider) -> String {
        "settings.ai.testStatus.\(provider.rawValue)"
    }
}
