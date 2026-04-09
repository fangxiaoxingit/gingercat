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
        let event = decoded.events.first(where: { $0.needTodo == true }) ?? decoded.events.first
        let cleanedKeywords = Array(
            (event?.keywords ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
                .prefix(3)
        )
        let cleanedDescription = cleanedOptional(event?.description)
        let cleanedTitle = cleanedOptional(event?.title)
        let cleanedDate = cleanedOptional(event?.date)
        let cleanedTime = cleanedOptional(event?.time)
        let summary = cleanedDescription ?? cleanedTitle ?? ""

        return AIOCRInsight(
            summary: summary,
            date: cleanedDate,
            time: cleanedTime,
            title: cleanedTitle,
            keywords: cleanedKeywords,
            description: cleanedDescription,
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
        从文本中提取未来时间相关事件，只输出标准JSON，无多余文字。

        规则：
        1. 时间判断以模型服务器当前真实时间为准，识别晚于当前时间的未来事件，忽略已过期时间。
        2. date 格式：YYYY-MM-DD，无则为 null。
        3. time 格式：HH:MM。若有日期但无具体时间，默认填 "00:00"。
        4. title：简洁事件标题，**必须包含日期或时间信息**。
        5. keywords：字符串数组，至少1个、最多3个关键词。
        6. description：客观完整描述事件，不脑补、不编造。
        7. needTodo：布尔值。
           - 有明确未来日期 → true
           - 无日期 / 日期已过 / 仅介绍 → false

        输出结构：
        {
          "events": [
            {
              "date": "YYYY-MM-DD" | null,
              "time": "HH:MM",
              "title": "标题（含日期）",
              "keywords": ["关键词1","关键词2"],
              "description": "详情",
              "needTodo": true | false
            }
          ]
        }

        无事件返回 {"events":[]}

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
    let events: [AIOCREventPayload]
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
