import Foundation

enum KimiAIServiceError: LocalizedError {
    case invalidConfiguration
    case invalidResponse
    case emptySummary
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return String(localized: "Kimi 配置不完整，请检查 Base URL / Model / API Key。")
        case .invalidResponse:
            return String(localized: "Kimi 返回内容无法解析，请稍后重试。")
        case .emptySummary:
            return String(localized: "Kimi 未返回可用摘要，请稍后重试。")
        case .requestFailed(let message):
            return message
        }
    }
}

enum KimiAIService {
    static func summarize(
        rawText: String,
        mode: InsightMode,
        events: [InsightEvent],
        config: KimiRuntimeConfig
    ) async throws -> String {
        guard config.canRequestSummary, let url = config.chatCompletionsURL else {
            throw KimiAIServiceError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        request.httpBody = try JSONSerialization.data(
            withJSONObject: requestBody(rawText: rawText, mode: mode, events: events, config: config),
            options: []
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw KimiAIServiceError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let errorMessage = extractErrorMessage(from: data)
            throw KimiAIServiceError.requestFailed(errorMessage ?? String(localized: "Kimi 请求失败，状态码 \(httpResponse.statusCode)。"))
        }

        let decoded = try JSONDecoder().decode(KimiChatCompletionResponse.self, from: data)
        let summary = decoded.choices.first?.message.textValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard summary.isEmpty == false else {
            throw KimiAIServiceError.emptySummary
        }

        return summary
    }

    private static func requestBody(
        rawText: String,
        mode: InsightMode,
        events: [InsightEvent],
        config: KimiRuntimeConfig
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "model": config.model,
            "messages": [
                [
                    "role": "system",
                    "content": """
                    你是 OCR 内容整理助手。请用简体中文输出一段 1-2 句话的摘要，尽量不超过 90 字，语气客观清晰。
                    如果文本包含时间与事件，请点出关键信息和提醒建议；如果是普通文本，请总结核心内容。
                    不要使用 Markdown，不要输出项目符号。
                    """
                ],
                [
                    "role": "user",
                    "content": userPrompt(rawText: rawText, mode: mode, events: events)
                ]
            ],
            "stream": false
        ]

        if let maxTokens = config.maxTokens {
            payload["max_tokens"] = maxTokens
        }
        if let temperature = config.temperature {
            payload["temperature"] = temperature
        }
        if let topP = config.topP {
            payload["top_p"] = topP
        }

        return payload
    }

    private static func userPrompt(rawText: String, mode: InsightMode, events: [InsightEvent]) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        let eventsText: String
        if events.isEmpty {
            eventsText = "无"
        } else {
            eventsText = events
                .map { event in
                    "\(event.title) @ \(formatter.string(from: event.date))"
                }
                .joined(separator: "\n")
        }

        return """
        解析模式：\(mode.rawValue)
        识别文本：
        \(rawText)

        已抽取事件：
        \(eventsText)
        """
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        guard let decoded = try? JSONDecoder().decode(KimiAPIErrorResponse.self, from: data) else {
            return nil
        }
        return decoded.error.message
    }
}

private struct KimiChatCompletionResponse: Decodable {
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

private struct KimiAPIErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}
