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
    let events: [AIOCREventInsight]
    let pickupItems: [AIOCRPickupInsight]
}

struct AIOCREventInsight: Hashable {
    let date: String?
    let time: String?
    let title: String?
    let keywords: [String]
    let description: String?
    let needTodo: Bool
}

struct AIOCRPickupInsight: Hashable {
    let brandName: String
    let itemName: String
    let codeValue: String
    let codeLabel: String
    let category: ScanPickupCategory
    let pickupDate: String?
    let pickupTime: String?
    let priority: Int?
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
            operation: .configTest,
            requestLogDisplayText: prompt
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
        let normalizedRawText: String = {
            let normalized = normalizedOCRTextForAI(rawText)
            if normalized.isEmpty {
                return rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return normalized
        }()
        let nowContext = currentDateContext()
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
                        "content": userPrompt(rawText: normalizedRawText, currentDateContext: nowContext)
                    ]
                ],
                config: config,
                responseFormat: config.provider.supportsJSONOutput ? ["type": "json_object"] : nil,
                operation: .ocrAnalysis,
                requestLogDisplayText: normalizedRawText
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
        operation: AIProviderRequestOperation,
        requestLogDisplayText: String
    ) async throws -> String {
        let payload = requestBody(messages: messages, config: config, responseFormat: responseFormat)
        let requestData = try JSONSerialization.data(withJSONObject: payload, options: [])
        let requestPayload = truncatedLogPayload(requestLogDisplayText.trimmingCharacters(in: .whitespacesAndNewlines))

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
                errorMessage: error.localizedDescription,
                totalTokens: nil
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
                responsePayload: content,
                errorMessage: nil,
                totalTokens: decoded.usage?.totalTokens
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
                errorMessage: error.localizedDescription,
                totalTokens: nil
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
                errorMessage: error.localizedDescription,
                totalTokens: nil
            )
            throw error
        }
    }

    private static func decodeInsight(from content: String, provider: AIProvider) throws -> AIOCRInsight {
        guard let jsonData = normalizedJSONData(from: content) else {
            throw AIProviderServiceError.invalidResponse(provider)
        }

        let decoded = try JSONDecoder().decode(AIOCRInsightResponse.self, from: jsonData)
        let normalizedEvents = (decoded.events ?? []).map { event in
            AIOCREventInsight(
                date: cleanedOptional(event.date),
                time: cleanedOptional(event.time),
                title: cleanedOptional(event.title),
                keywords: Array(
                    (event.keywords ?? [])
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { $0.isEmpty == false }
                        .prefix(3)
                ),
                description: cleanedOptional(event.description),
                needTodo: event.needTodo ?? false
            )
        }.filter { event in
            event.date != nil ||
            event.title != nil ||
            event.description != nil ||
            event.needTodo ||
            event.keywords.isEmpty == false
        }
        let event = normalizedEvents.first(where: { $0.needTodo }) ?? normalizedEvents.first
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
            needTodo: event?.needTodo ?? false,
            events: normalizedEvents,
            pickupItems: normalizedPickupItems(from: decoded.pickupItems)
        )
    }

    private static func normalizedPickupItems(from payloads: [AIOCRPickupPayload]?) -> [AIOCRPickupInsight] {
        guard let payloads else { return [] }

        var seenCodes: Set<String> = []
        let items = payloads.compactMap { payload -> AIOCRPickupInsight? in
            let codeValue = payload.codeValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard codeValue.isEmpty == false else { return nil }
            guard seenCodes.insert(codeValue).inserted else { return nil }

            let category = PickupCodeExtractor.normalizedCategory(from: payload.category)
            let brandName = cleanedOptional(payload.brandName) ?? String(localized: "其他")
            let itemName = cleanedOptional(payload.itemName) ?? brandName
            let codeLabel = PickupCodeExtractor.normalizedCodeLabel(from: payload.codeLabel)
            let pickupDate = PickupCodeExtractor.normalizedPickupDate(from: payload.pickupDate)
            let pickupTime = PickupCodeExtractor.normalizedPickupTime(from: payload.pickupTime)

            return AIOCRPickupInsight(
                brandName: brandName,
                itemName: itemName,
                codeValue: codeValue,
                codeLabel: codeLabel,
                category: category,
                pickupDate: pickupDate,
                pickupTime: pickupTime,
                priority: payload.priority
            )
        }

        return items.sorted { lhs, rhs in
            let leftPriority = lhs.priority ?? Int.max
            let rightPriority = rhs.priority ?? Int.max
            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }
            return lhs.codeValue < rhs.codeValue
        }
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

    private static func userPrompt(rawText: String, currentDateContext: String) -> String {
            """
            你需要先理解 OCR 文本，再输出摘要、事件信息和取件信息。只输出标准 JSON，无多余文字。
            当前时间基准（必须严格使用，禁止自行假设）：
            - \(currentDateContext)

            核心规则（严格执行，优先级从高到低）：
            1. 【年份推断逻辑】
               - 若文本中明确标注完整年份（如2025、2026、2027），以文本标注为准，禁止篡改。
               - 若文本仅标注月日（如4月21日、6.13），以“当前时间基准”的年份补全年份，禁止硬编码固定年份。
               - 若文本出现两位年份（如26-4-11、26/4/11），按 20YY 解析为四位年份（26 -> 2026）。
               - 若文本无任何日期信息，不补全年份，date 字段填 null。
            2. 【时间判断逻辑】
               - 仅识别晚于“当前时间基准”的未来事件，忽略已过期时间。
               - 若补全年份后日期已过期，自动忽略该事件，不纳入 events 数组。
            3. 【摘要生成规则】
               - 无论文本是否包含未来事件，必须生成 `summary`，严格控制在50字以内，精准概括图片核心内容。
               - 商品、通知、聊天、说明、文章、海报等非日程内容，也必须正常生成 summary。
            4. 【标题规则】
               - 主标题 title：提炼图片核心主题，无明确主标题时可填 null，主要信息在前，时间在后表述。
               - 事件标题 event.title：若识别到未来事件，**必须包含完整日期/时间信息**，禁止无时间的事件标题，事件标题在前，时间在后表述。
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
            9. 【取件识别规则】pickupItems 数组：
               - 识别快递取件码、外卖/餐饮取餐码、茶饮取单号、咖啡取单号、门店提货码等。
               - 每条 pickupItem 必须包含：brandName、itemName、codeValue、codeLabel、category。pickupDate/pickupTime 没有可填 null。
               - category 只允许中文：咖啡 / 饮品 / 快递 / 其他。
               - brandName 没有时填“其他”。
               - itemName 为商品/包裹名称（如“生椰拿铁”“顺丰快递”），缺失时可回填 brandName，禁止留空。
               - codeLabel 只允许：取件码 / 取餐码。
               - 严禁把物流运单号、手机号误判为取件码；只有明确“取件/取货/取餐/叫号/核销码”等语义才输出。

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
              ],
              "pickupItems": [
                {
                  "brandName": "品牌或门店名，没有时填“其他”",
                  "itemName": "商品/包裹名称，缺失时回填 brandName",
                  "codeValue": "取件码或取餐码值",
                  "codeLabel": "取件码|取餐码",
                  "category": "咖啡|饮品|快递|其他",
                  "pickupDate": "YYYY-MM-DD | null",
                  "pickupTime": "HH:MM | null",
                  "priority": 0
                }
              ]
            }

            特殊情况处理：
            - 没有未来事件时，events 返回 []，但 summary / title / keywords / description 仍需正常生成。
            - 没有取件信息时，pickupItems 返回 []。
            - 文本为商品广告/通知/聊天/说明类，优先生成 summary 和 description，events 若无明确日程则为空数组。
            - 若OCR文本存在识别错误，以可理解的语义为准进行合理修正，禁止输出乱码或无意义内容。
            - 输出前必须自检：将 events 中每一条 date+time 转成完整时间，若不晚于“当前时间基准”，就从 events 删除。

            文本内容：
            \(rawText)
            """
        }

    private static let promptDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static func currentDateContext() -> String {
        let now = Date()
        let timeZone = TimeZone.current
        let offsetSeconds = timeZone.secondsFromGMT(for: now)
        let sign = offsetSeconds >= 0 ? "+" : "-"
        let absoluteSeconds = abs(offsetSeconds)
        let hours = absoluteSeconds / 3600
        let minutes = (absoluteSeconds % 3600) / 60
        let offsetText = String(format: "%@%02d:%02d", sign, hours, minutes)
        return "\(promptDateFormatter.string(from: now)) \(offsetText) (\(timeZone.identifier))"
    }

    private static func normalizedOCRTextForAI(_ text: String) -> String {
        let normalizedLineBreaks = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let mergedLines = normalizedLineBreaks
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
        let collapsedSpaces = mergedLines.replacingOccurrences(
            of: #"[ \t]{2,}"#,
            with: " ",
            options: .regularExpression
        )
        return collapsedSpaces.trimmingCharacters(in: .whitespacesAndNewlines)
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
        errorMessage: String?,
        totalTokens: Int?
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
                errorMessage: errorMessage,
                totalTokens: totalTokens
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

enum PickupCodeExtractor {
    static func extract(from rawText: String, source: String = "regex") -> [ScanPickupCode] {
        let lines = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        guard lines.isEmpty == false else { return [] }
        let fullText = lines.joined(separator: "\n")
        let matches = regexMatches(in: fullText)
        guard matches.isEmpty == false else { return [] }

        var dedupedCodes: Set<String> = []
        var results: [ScanPickupCode] = []

        for (index, match) in matches.enumerated() {
            let codeValue = match.code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard codeValue.isEmpty == false else { continue }
            guard dedupedCodes.insert(codeValue).inserted else { continue }

            let brandName = resolvedMerchantName(lines: lines, context: match.context) ?? String(localized: "其他")
            let category = normalizedCategory(
                from: [match.context, brandName]
                    .compactMap { $0 }
                    .joined(separator: " ")
            )
            let itemName = resolvedItemName(
                lines: lines,
                context: match.context,
                brandName: brandName,
                category: category
            )
            let codeLabel = normalizedCodeLabel(from: match.context)
            let pickupDate = normalizedPickupDate(from: extractDate(from: match.context) ?? extractDate(from: fullText))
            let pickupTime = normalizedPickupTime(from: extractTime(from: match.context) ?? extractTime(from: fullText))
            let priority = prioritizedValue(category: category, index: index)

            results.append(
                ScanPickupCode(
                    brandName: brandName,
                    itemName: itemName,
                    codeValue: codeValue,
                    codeLabel: codeLabel,
                    category: category,
                    pickupDate: pickupDate,
                    pickupTime: pickupTime,
                    source: source,
                    priority: priority
                )
            )
        }

        return results.sorted { lhs, rhs in
            let leftPriority = lhs.priority ?? Int.max
            let rightPriority = rhs.priority ?? Int.max
            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }
            return lhs.codeValue < rhs.codeValue
        }
    }

    static func normalizedCategory(from rawValue: String?) -> ScanPickupCategory {
        let normalized = (rawValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized.contains("咖啡") ||
            normalized.contains("coffee") ||
            normalized.contains("瑞幸") ||
            normalized.contains("星巴克") ||
            normalized.contains("manner") ||
            normalized.contains("库迪") ||
            normalized.contains("幸运咖") {
            return .coffee
        }
        if normalized.contains("饮品") ||
            normalized.contains("beverage") ||
            normalized.contains("茶饮") ||
            normalized.contains("奶茶") ||
            normalized.contains("喜茶") ||
            normalized.contains("奈雪") ||
            normalized.contains("霸王茶姬") ||
            normalized.contains("茶百道") ||
            normalized.contains("蜜雪") {
            return .beverage
        }
        if normalized.contains("快递") ||
            normalized.contains("express") ||
            normalized.contains("快递") ||
            normalized.contains("驿站") ||
            normalized.contains("丰巢") ||
            normalized.contains("菜鸟") {
            return .express
        }
        return .other
    }

    static func normalizedCodeLabel(from rawValue: String?) -> String {
        let normalized = (rawValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized.contains("取餐码") || normalized.contains("取单号") || normalized.contains("叫号") {
            return String(localized: "取餐码")
        }
        return String(localized: "取件码")
    }

    static func normalizedPickupDate(from rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return normalized
    }

    static func normalizedPickupTime(from rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return normalized
    }

    private static func prioritizedValue(category: ScanPickupCategory, index: Int) -> Int {
        let categoryPriority: Int
        switch category {
        case .coffee:
            categoryPriority = 0
        case .beverage:
            categoryPriority = 1
        case .express:
            categoryPriority = 2
        case .other:
            categoryPriority = 3
        }
        return categoryPriority * 100 + index
    }

    private static func resolvedMerchantName(lines: [String], context: String) -> String? {
        let contextLower = context.lowercased()
        let preferredKeywords = [
            "快递", "驿站", "超市", "门店", "咖啡", "茶", "餐", "瑞幸", "星巴克", "喜茶",
            "奈雪", "霸王茶姬", "茶百道", "蜜雪", "顺丰", "京东", "中通", "圆通", "申通", "韵达"
        ]

        if let directLine = lines.first(where: { line in
            let lowered = line.lowercased()
            guard lowered.contains(contextLower) else { return false }
            return preferredKeywords.contains { lowered.contains($0) }
        }) {
            let normalized = normalizedMerchantName(from: directLine)
            if normalized.isEmpty == false { return normalized }
        }

        if let nearby = lines.first(where: { line in
            let lowered = line.lowercased()
            let isCodeLine = lowered.contains("取件码") ||
                lowered.contains("取货码") ||
                lowered.contains("取餐码") ||
                lowered.contains("取单号")
            guard isCodeLine == false else { return false }
            return preferredKeywords.contains { lowered.contains($0) }
        }) {
            let normalized = normalizedMerchantName(from: nearby)
            if normalized.isEmpty == false { return normalized }
        }

        return nil
    }

    private static func normalizedMerchantName(from text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: #"(取件码|取货码|取餐码|取单号|订单号|叫号|核销码)[:：]?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[A-Za-z0-9][A-Za-z0-9\-_]{1,}"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(24))
    }

    private static func resolvedItemName(
        lines: [String],
        context: String,
        brandName: String,
        category: ScanPickupCategory
    ) -> String {
        let contextItem = normalizedItemName(from: context)
        if contextItem.isEmpty == false {
            return contextItem
        }

        let preferredKeywords = [
            "拿铁", "美式", "咖啡", "饮品", "奶茶", "茶", "包裹", "快递", "外卖", "顺丰", "京东", "中通", "圆通", "申通", "韵达"
        ]
        if let nearbyLine = lines.first(where: { line in
            let lowered = line.lowercased()
            let isCodeLine = lowered.contains("取件码") ||
                lowered.contains("取货码") ||
                lowered.contains("取餐码") ||
                lowered.contains("取单号")
            guard isCodeLine == false else { return false }
            return preferredKeywords.contains { lowered.contains($0) }
        }) {
            let candidate = normalizedItemName(from: nearbyLine)
            if candidate.isEmpty == false {
                return candidate
            }
        }

        let normalizedBrand = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedBrand.isEmpty == false {
            return normalizedBrand
        }
        return category.fallbackItemName
    }

    private static func normalizedItemName(from text: String) -> String {
        let cleaned = text
            .replacingOccurrences(
                of: #"(取件码|取货码|取餐码|取单号|订单号|叫号|核销码)\s*[:：#]?\s*[A-Za-z0-9\-_]+"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(下单时间|订单编号|支付方式|实付|原价|优惠券|制作完成|可自取|状态|时间|金额)[:：]?"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(24))
    }

    private static func regexMatches(in text: String) -> [(code: String, context: String)] {
        let pattern = #"(?:取件码|取货码|提货码|取餐码|取单号|订单号|叫号|核销码)\s*[:：#]?\s*([A-Za-z0-9]{2,}(?:[-_][A-Za-z0-9]{1,}){0,4})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, options: [], range: fullRange).compactMap { match in
            guard match.numberOfRanges >= 2,
                  let codeRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            let code = String(text[codeRange])
            let matchRange = match.range(at: 0)
            let lineStart = nsText.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: matchRange.location)).location
            let contextStart = (lineStart == NSNotFound) ? 0 : lineStart + 1
            let searchEndStart = matchRange.location + matchRange.length
            let afterRangeLength = max(nsText.length - searchEndStart, 0)
            let lineEndSearch = NSRange(location: searchEndStart, length: afterRangeLength)
            let lineEndMatch = nsText.range(of: "\n", options: [], range: lineEndSearch)
            let contextEnd = (lineEndMatch.location == NSNotFound) ? nsText.length : lineEndMatch.location
            let context = nsText.substring(with: NSRange(location: contextStart, length: max(contextEnd - contextStart, 0)))
            return (code: code, context: context)
        }
    }

    private static func extractDate(from text: String) -> String? {
        let pattern = #"(20\d{2})[.\-/年](\d{1,2})[.\-/月](\d{1,2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: fullRange),
              match.numberOfRanges >= 4 else {
            return nil
        }
        let year = nsText.substring(with: match.range(at: 1))
        let month = nsText.substring(with: match.range(at: 2))
        let day = nsText.substring(with: match.range(at: 3))
        let monthValue = String(format: "%02d", Int(month) ?? 0)
        let dayValue = String(format: "%02d", Int(day) ?? 0)
        return "\(year)-\(monthValue)-\(dayValue)"
    }

    private static func extractTime(from text: String) -> String? {
        let pattern = #"([01]?\d|2[0-3])[:：]([0-5]\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: fullRange),
              match.numberOfRanges >= 3 else {
            return nil
        }
        let hour = nsText.substring(with: match.range(at: 1))
        let minute = nsText.substring(with: match.range(at: 2))
        return String(format: "%02d:%02d", Int(hour) ?? 0, Int(minute) ?? 0)
    }
}

private struct AIOCRInsightResponse: Decodable {
    let summary: String?
    let title: String?
    let keywords: [String]?
    let description: String?
    let events: [AIOCREventPayload]?
    let pickupItems: [AIOCRPickupPayload]?
}

private struct AIOCREventPayload: Decodable {
    let date: String?
    let time: String?
    let title: String?
    let keywords: [String]?
    let description: String?
    let needTodo: Bool?
}

private struct AIOCRPickupPayload: Decodable {
    let brandName: String?
    let itemName: String?
    let codeValue: String
    let codeLabel: String?
    let category: String?
    let pickupDate: String?
    let pickupTime: String?
    let priority: Int?
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

    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }

    let choices: [Choice]
    let usage: Usage?
}

private struct APIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String?
    }

    let error: APIError?
    let message: String?
}
