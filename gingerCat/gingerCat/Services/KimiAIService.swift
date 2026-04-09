import Foundation

enum AIProviderServiceError: LocalizedError {
    case invalidConfiguration(AIProvider)
    case invalidResponse(AIProvider)
    case requestFailed(provider: AIProvider, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let provider):
            return String(localized: "\(provider.displayName) 配置不完整，请检查 Base URL / Model / API Key。")
        case .invalidResponse(let provider):
            return String(localized: "\(provider.displayName) 返回内容无法解析，请稍后重试。")
        case .requestFailed(_, let message):
            return message
        }
    }
}

struct AIOCRInsight: Hashable {
    let summary: String
    let date: String?
    let time: String?
    let title: String?
    let keywords: [String]
    let description: String?
    let needTodo: Bool
}

enum AIProviderService {
    static func sendTestPrompt(
        _ prompt: String,
        config: AIProviderRuntimeConfig
    ) async throws -> String {
        let content = try await requestCompletionContent(
            messages: [
                [
                    "role": "system",
                    "content": """
                    你是模型配置测试助手，请直接回答用户问题，不要输出 JSON。
                    """
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            config: config
        )
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw AIProviderServiceError.invalidResponse(config.provider)
        }
        return trimmed
    }

    static func analyzeOCR(
        rawText: String,
        config: AIProviderRuntimeConfig
    ) async throws -> AIOCRInsight {
        let content = try await requestCompletionContent(
            messages: [
                [
                    "role": "system",
                    "content": """
                    你是 OCR 信息提取助手，必须严格输出 JSON 对象，不允许输出 JSON 之外的任何字符。
                    """
                ],
                [
                    "role": "user",
                    "content": userPrompt(rawText: rawText)
                ]
            ],
            config: config,
            responseFormat: config.provider.supportsJSONOutput ? ["type": "json_object"] : nil
        )
        return try decodeInsight(from: content, provider: config.provider)
    }

    private static func requestCompletionContent(
        messages: [[String: String]],
        config: AIProviderRuntimeConfig,
        responseFormat: [String: Any]? = nil
    ) async throws -> String {
        guard config.canRequestSummary, let url = config.chatCompletionsURL else {
            throw AIProviderServiceError.invalidConfiguration(config.provider)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        request.httpBody = try JSONSerialization.data(
            withJSONObject: requestBody(messages: messages, config: config, responseFormat: responseFormat),
            options: []
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderServiceError.invalidResponse(config.provider)
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let errorMessage = extractErrorMessage(from: data)
            throw AIProviderServiceError.requestFailed(
                provider: config.provider,
                message: errorMessage ?? String(localized: "\(config.provider.displayName) 请求失败，状态码 \(httpResponse.statusCode)。")
            )
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        let content = decoded.choices.first?.message.textValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard content.isEmpty == false else {
            throw AIProviderServiceError.invalidResponse(config.provider)
        }
        return content
    }

    private static func decodeInsight(from content: String, provider: AIProvider) throws -> AIOCRInsight {
        guard let jsonData = normalizedJSONData(from: content) else {
            throw AIProviderServiceError.invalidResponse(provider)
        }

        let decoded = try JSONDecoder().decode(AIOCRInsightResponse.self, from: jsonData)
        let summary = decoded.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard summary.isEmpty == false else {
            throw AIProviderServiceError.invalidResponse(provider)
        }

        let event = decoded.event
        let cleanedKeywords = Array(
            (event?.keywords ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
                .prefix(3)
        )

        return AIOCRInsight(
            summary: summary,
            date: cleanedOptional(event?.date),
            time: cleanedOptional(event?.time),
            title: cleanedOptional(event?.title),
            keywords: cleanedKeywords,
            description: cleanedOptional(event?.description),
            needTodo: event?.needTodo ?? false
        )
    }

    private static func normalizedJSONData(from content: String) -> Data? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let directData = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: directData)) != nil {
            return directData
        }

        if let start = trimmed.range(of: "{"),
           let end = trimmed.range(of: "}", options: .backwards),
           start.lowerBound <= end.upperBound {
            let candidate = String(trimmed[start.lowerBound..<end.upperBound])
            if let candidateData = candidate.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: candidateData)) != nil {
                return candidateData
            }
        }

        return nil
    }

    private static func requestBody(
        messages: [[String: String]],
        config: AIProviderRuntimeConfig,
        responseFormat: [String: Any]? = nil
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "stream": false
        ]

        if let responseFormat {
            payload["response_format"] = responseFormat
        }
        if let maxTokens = config.maxTokens {
            payload[config.provider.maxTokensParameterName] = maxTokens
        }
        if let temperature = config.temperature, config.provider.allowsTemperature(for: config.model) {
            payload["temperature"] = temperature
        }
        if let topP = config.topP, config.provider.allowsTopP(for: config.model) {
            payload["top_p"] = topP
        }

        return payload
    }

    private static func userPrompt(rawText: String) -> String {
        """
        请从 OCR 文本中一次性提取摘要与结构化信息，只输出标准JSON，无多余文字。

        输出规则：
        1. summary：1-2句中文摘要，客观，不编造事实。
        2. event.date：YYYY-MM-DD；无明确日期填 null。
        3. event.time：HH:MM；无明确时间填 null。
        4. event.title：事件标题；无事件填 null。
        5. event.keywords：关键词数组，0-3个。
        6. event.description：详细内容；无事件填 null。
        7. event.needTodo：布尔值。有明确未来日期才为 true，否则 false。

        输出结构：
        {
          "summary": "摘要",
          "event": {
            "date": null,
            "time": null,
            "title": null,
            "keywords": ["关键词1","关键词2"],
            "description": null,
            "needTodo": false
          }
        }

        返回内容必须是合法 JSON，只能使用 JSON 支持的类型，不要输出 | null、注释、代码块标记或额外说明。
        无事件时，event 字段仍保留，除 keywords 可为空数组外其余为 null，needTodo 为 false。

        文本内容：
        \(rawText)
        """
    }

    private static func cleanedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
            if let message = decoded.error?.message, message.isEmpty == false {
                return message
            }
            if let message = decoded.message, message.isEmpty == false {
                return message
            }
        }
        return nil
    }
}

private struct AIOCRInsightResponse: Decodable {
    let summary: String
    let event: AIOCREventPayload?
}

private struct AIOCREventPayload: Decodable {
    let date: String?
    let time: String?
    let title: String?
    let keywords: [String]?
    let description: String?
    let needTodo: Bool?
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: MessageContent

        var textValue: String {
            switch content {
            case .string(let text):
                return text
            case .parts(let parts):
                return parts.compactMap(\.text).joined(separator: "\n")
            }
        }
    }

    enum MessageContent: Decodable {
        case string(String)
        case parts([MessagePart])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) {
                self = .string(value)
                return
            }
            self = .parts(try container.decode([MessagePart].self))
        }
    }

    struct MessagePart: Decodable {
        let text: String?
    }

    let choices: [Choice]
}

private struct APIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String?
    }

    let error: APIError?
    let message: String?
}
