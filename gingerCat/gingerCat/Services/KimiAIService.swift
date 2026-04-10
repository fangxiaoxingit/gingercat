import Foundation

enum AIProviderServiceError: LocalizedError {
    case invalidConfiguration(AIProvider)
    case invalidResponse(AIProvider)
    case timeout(AIProvider)
    case requestFailed(provider: AIProvider, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let provider):
            return String(localized: "\(provider.displayName) 配置不完整，请检查 Base URL / Model / API Key。")
        case .invalidResponse(let provider):
            return String(localized: "\(provider.displayName) 返回内容无法解析，请稍后重试。")
        case .timeout(let provider):
            return String(localized: "\(provider.displayName) 摘要请求超时，请稍后重试。")
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
            config: config,
            operation: .configTest
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
        let content = try await withTimeout(seconds: 20, provider: config.provider) {
            try await requestCompletionContent(
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
                responseFormat: config.provider.supportsJSONOutput ? ["type": "json_object"] : nil,
                operation: .ocrAnalysis
            )
        }
        return try decodeInsight(from: content, provider: config.provider)
    }

    private static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        provider: AIProvider,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                let duration = UInt64(seconds * 1_000_000_000)
                try await Task.sleep(nanoseconds: duration)
                throw AIProviderServiceError.timeout(provider)
            }

            guard let firstResult = try await group.next() else {
                group.cancelAll()
                throw AIProviderServiceError.timeout(provider)
            }

            group.cancelAll()
            return firstResult
        }
    }

    private static func requestCompletionContent(
        messages: [[String: String]],
        config: AIProviderRuntimeConfig,
        responseFormat: [String: Any]? = nil,
        operation: AIProviderRequestOperation
    ) async throws -> String {
        let payload = requestBody(messages: messages, config: config, responseFormat: responseFormat)
        let requestData = try JSONSerialization.data(withJSONObject: payload, options: [])
        let requestPayload = formattedPayload(from: requestData)

        guard config.canRequestSummary, let url = config.chatCompletionsURL else {
            let error = AIProviderServiceError.invalidConfiguration(config.provider)
            appendRequestLog(
                provider: config.provider,
                operation: operation,
                config: config,
                endpoint: config.chatCompletionsURL?.absoluteString ?? config.baseURL,
                statusCode: nil,
                isSuccess: false,
                requestPayload: requestPayload,
                responsePayload: String(localized: "配置不完整，未发起网络请求。"),
                errorMessage: error.localizedDescription
            )
            throw error
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = requestData

        var responsePayload = String(localized: "暂无返回内容")
        var statusCode: Int?

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            responsePayload = formattedPayload(from: data)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIProviderServiceError.invalidResponse(config.provider)
            }

            statusCode = httpResponse.statusCode

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

            appendRequestLog(
                provider: config.provider,
                operation: operation,
                config: config,
                endpoint: url.absoluteString,
                statusCode: statusCode,
                isSuccess: true,
                requestPayload: requestPayload,
                responsePayload: responsePayload,
                errorMessage: nil
            )
            return content
        } catch let error as AIProviderServiceError {
            appendRequestLog(
                provider: config.provider,
                operation: operation,
                config: config,
                endpoint: url.absoluteString,
                statusCode: statusCode,
                isSuccess: false,
                requestPayload: requestPayload,
                responsePayload: responsePayload,
                errorMessage: error.localizedDescription
            )
            throw error
        } catch {
            appendRequestLog(
                provider: config.provider,
                operation: operation,
                config: config,
                endpoint: url.absoluteString,
                statusCode: statusCode,
                isSuccess: false,
                requestPayload: requestPayload,
                responsePayload: responsePayload,
                errorMessage: error.localizedDescription
            )
            throw error
        }
    }

    private static func decodeInsight(from content: String, provider: AIProvider) throws -> AIOCRInsight {
        guard let jsonData = normalizedJSONData(from: content) else {
            throw AIProviderServiceError.invalidResponse(provider)
        }

        let decoded = try JSONDecoder().decode(AIOCRInsightResponse.self, from: jsonData)
        let events = decoded.events ?? []
        let event = events.first(where: { $0.needTodo == true }) ?? events.first
        // 兼容“通用摘要 + 可选事件”的新结构，同时兼容旧的仅 events 返回格式。
        let cleanedKeywords = Array(
            (event?.keywords ?? decoded.keywords ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
                .prefix(3)
        )
        let cleanedDescription = cleanedOptional(event?.description) ?? cleanedOptional(decoded.description)
        let cleanedTitle = cleanedOptional(event?.title) ?? cleanedOptional(decoded.title)
        let cleanedDate = cleanedOptional(event?.date)
        let cleanedTime = cleanedOptional(event?.time)
        let summary = cleanedOptional(decoded.summary) ?? cleanedDescription ?? cleanedTitle ?? ""

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
            你需要先理解 OCR 文本，再输出摘要和事件信息。只输出标准 JSON，无多余文字。

            核心规则（严格执行，优先级从高到低）：
            1. 【年份推断逻辑】
               - 若文本中明确标注完整年份（如2025、2026、2027），以文本标注为准，禁止篡改。
               - 若文本仅标注月日（如4月21日、6.13），**以模型服务器当前真实时间的年份为基准**，自动补全年份，禁止硬编码固定年份。
               - 若文本无任何日期信息，不补全年份，date 字段填 null。
            2. 【时间判断逻辑】
               - 以模型服务器当前真实时间为基准，仅识别晚于当前时间的未来事件，忽略已过期时间。
               - 若补全年份后日期已过期，自动忽略该事件，不纳入 events 数组。
            3. 【摘要生成规则】
               - 无论文本是否包含未来事件，必须生成 `summary`，严格控制在50字以内，精准概括图片核心内容。
               - 商品、通知、聊天、说明、文章、海报等非日程内容，也必须正常生成 summary。
            4. 【标题规则】
               - 主标题 title：提炼图片核心主题，无明确主标题时可填 null。
               - 事件标题 event.title：若识别到未来事件，**必须包含完整日期/时间信息**，禁止无时间的事件标题。
            5. 【关键词规则】
               - 全局 keywords 数组：严格限制为**至少1个、最多3个**关键词，无合适关键词时返回空数组。
               - 事件 keywords 数组：严格限制为**至少1个、最多3个**关键词，无合适关键词时返回空数组。
            6. 【描述规则】
               - description：客观完整描述图片主要内容，不脑补、不编造、不添加原文不存在的信息，可比 summary 更详细。
               - 事件 description：客观描述事件详情，严格基于原文内容，禁止延伸解读。
            7. 【时间格式规范】
               - date 格式：YYYY-MM-DD，无日期则填 null。
               - time 格式：HH:MM。若有日期但无具体时间，默认填 "00:00"。
            8. 【待办标记规则】event.needTodo 布尔值判断：
               - 有明确未来日期且未过期 → true
               - 无日期 / 日期已过 / 仅为商品介绍 / 非日程内容 → false

            输出结构（严格遵循，禁止增减字段）：
            {
              "summary": "50字以内的图片内容摘要",
              "title": "主标题或 null",
              "keywords": ["关键词1","关键词2","关键词3"],
              "description": "对图片内容的客观详细描述",
              "events": [
                {
                  "date": "YYYY-MM-DD | null",
                  "time": "HH:MM",
                  "title": "包含日期/时间的事件标题",
                  "keywords": ["关键词1","关键词2"],
                  "description": "事件详情描述",
                  "needTodo": true | false
                }
              ]
            }

            特殊情况处理：
            - 没有未来事件时，events 返回 []，但 summary / title / keywords / description 仍需正常生成。
            - 文本为商品广告/通知/聊天/说明类，优先生成 summary 和 description，events 若无明确日程则为空数组。
            - 若OCR文本存在识别错误，以可理解的语义为准进行合理修正，禁止输出乱码或无意义内容。

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

    private static func appendRequestLog(
        provider: AIProvider,
        operation: AIProviderRequestOperation,
        config: AIProviderRuntimeConfig,
        endpoint: String,
        statusCode: Int?,
        isSuccess: Bool,
        requestPayload: String,
        responsePayload: String,
        errorMessage: String?
    ) {
        AIProviderRequestLogStore.append(
            AIProviderRequestLogEntry(
                provider: provider,
                operation: operation,
                isSuccess: isSuccess,
                model: config.model,
                endpoint: endpoint,
                statusCode: statusCode,
                requestPayload: requestPayload,
                responsePayload: truncatedLogPayload(responsePayload),
                errorMessage: errorMessage
            )
        )
    }

    private static func formattedPayload(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            return truncatedLogPayload(prettyString)
        }

        let rawString = String(data: data, encoding: .utf8) ?? String(localized: "返回内容无法转为文本。")
        return truncatedLogPayload(rawString)
    }

    private static func truncatedLogPayload(_ payload: String) -> String {
        let limit = 20_000
        guard payload.count > limit else { return payload }
        let endIndex = payload.index(payload.startIndex, offsetBy: limit)
        return String(payload[..<endIndex]) + "\n\n... 已截断，原始内容过长 ..."
    }
}

private struct AIOCRInsightResponse: Decodable {
    let summary: String?
    let title: String?
    let keywords: [String]?
    let description: String?
    let events: [AIOCREventPayload]?
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
