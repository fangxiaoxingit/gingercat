import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

private struct BackgroundOCRPipelineResult {
    let recognizedText: String
    let summary: String
    let intent: ScanIntent
    let eventTitle: String?
    let eventDate: Date?
    let eventTime: String?
    let eventKeywords: [String]
    let eventDescription: String?
    let needTodo: Bool
    let isOCRCompleted: Bool
    let usedAISummary: Bool
    let lineBoxes: [OCRLineBox]
    let aiFallbackMessage: String?
    let didAISummaryRequestFail: Bool
    let summaryModelName: String?
    let todoEvents: [ScanTodoEvent]
    let pickupCodes: [ScanPickupCode]
}

@MainActor
enum BackgroundImageImportPipeline {
    // 捷径后台执行时也走同一条 OCR/AI 规则，保证和首页手动导入的字段语义一致。
    static func importImage(
        imageData: Data,
        source: String = "Shortcuts",
        defaults: UserDefaults = .standard
    ) async throws -> ScanRecord {
        let modelContext = try buildModelContext()
        let record = ScanRecord(
            imageData: imageData,
            source: source,
            recognizedText: "",
            summary: String(appLocalized: "正在识别内容..."),
            intent: .summary,
            note: "",
            isOCRCompleted: false,
            usedAISummary: false
        )
        modelContext.insert(record)
        try? modelContext.save()

        let runtimeConfig = AIProviderConfigStore.selectedRuntimeConfig(defaults: defaults)
        let aiSummaryEnabled = defaults.bool(forKey: AppSettingsKeys.aiSummaryEnabled)
        let autoAddTodoAfterAISummary = boolValue(
            forKey: AppSettingsKeys.autoAddTodoAfterAISummary,
            defaults: defaults,
            defaultValue: true
        )
        let result = await runRecognitionPipeline(
            imageData: imageData,
            source: source,
            aiSummaryEnabled: aiSummaryEnabled,
            config: runtimeConfig
        )

        applyRecognitionResult(result, to: record, modelContext: modelContext)
        let autoAddResult = await autoAddTodoIfNeeded(
            for: record,
            result: result,
            enabled: autoAddTodoAfterAISummary
        )
        if autoAddResult.addedCount > 0 {
            try? modelContext.save()
        }
        await refreshDueReminderNotifications(
            modelContext: modelContext,
            defaults: defaults
        )
        if result.isOCRCompleted {
            if result.didAISummaryRequestFail, result.intent != .pickup {
                await OCRCompletionNotifier.notifyAISummaryFailure(record: record)
            } else {
                // 捷径后台解析完成后也触发同一套系统提醒，保证无论入口都能收到一致的完成反馈。
                await OCRCompletionNotifier.notify(
                    record: record,
                    autoAddedTodoCount: autoAddResult.addedCount
                )
            }
        }
        return record
    }

    private static func buildModelContext() throws -> ModelContext {
        let schema = Schema([ScanRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private static func boolValue(
        forKey key: String,
        defaults: UserDefaults,
        defaultValue: Bool
    ) -> Bool {
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }

    private static func refreshDueReminderNotifications(
        modelContext: ModelContext,
        defaults: UserDefaults
    ) async {
        let descriptor = FetchDescriptor<ScanRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let allRecords = (try? modelContext.fetch(descriptor)) ?? []
        await TodoDueNotificationScheduler.refresh(
            for: allRecords,
            defaults: defaults
        )
    }

    private static func autoAddTodoIfNeeded(
        for record: ScanRecord,
        result: BackgroundOCRPipelineResult,
        enabled: Bool
    ) async -> TodoAutoAddService.Result {
        guard result.intent != .pickup else {
            return .init(addedCount: 0)
        }
        guard result.usedAISummary else {
            return .init(addedCount: 0)
        }
        guard result.didAISummaryRequestFail == false else {
            return .init(addedCount: 0)
        }
        return await TodoAutoAddService.autoAddIfNeeded(for: record, enabled: enabled)
    }

    private static func runRecognitionPipeline(
        imageData: Data,
        source: String,
        aiSummaryEnabled: Bool,
        config: AIProviderRuntimeConfig
    ) async -> BackgroundOCRPipelineResult {
        #if canImport(UIKit)
        guard let image = UIImage(data: imageData) else {
            return BackgroundOCRPipelineResult(
                recognizedText: "",
                summary: String(appLocalized: "当前图片格式暂不支持，请重试。"),
                intent: .summary,
                eventTitle: nil,
                eventDate: nil,
                eventTime: nil,
                eventKeywords: [],
                eventDescription: nil,
                needTodo: false,
                isOCRCompleted: false,
                usedAISummary: false,
                lineBoxes: [],
                aiFallbackMessage: nil,
                didAISummaryRequestFail: false,
                summaryModelName: nil,
                todoEvents: [],
                pickupCodes: []
            )
        }
        #else
        return BackgroundOCRPipelineResult(
            recognizedText: "",
            summary: String(appLocalized: "当前平台暂不支持 OCR。"),
            intent: .summary,
            eventTitle: nil,
            eventDate: nil,
            eventTime: nil,
            eventKeywords: [],
            eventDescription: nil,
            needTodo: false,
            isOCRCompleted: false,
            usedAISummary: false,
            lineBoxes: [],
            aiFallbackMessage: nil,
            didAISummaryRequestFail: false,
            summaryModelName: nil,
            todoEvents: [],
            pickupCodes: []
        )
        #endif

        do {
            let recognition = try await VisionOCRService.recognize(from: image)
            let payload = InsightPayloadBuilder.build(
                source: source,
                recognizedText: recognition.text,
                imageData: imageData
            )

            // AI 开启且配置完整时执行结构化提取；否则回落到 OCR 原文。
            if aiSummaryEnabled, config.canRequestSummary {
                do {
                    let aiInsight = try await AIProviderService.analyzeOCR(
                        rawText: payload.rawText,
                        config: config
                    )
                    return buildPipelineResultFromAI(
                        recognizedText: payload.rawText,
                        ocrFallbackText: payload.summary,
                        insight: aiInsight,
                        lineBoxes: recognition.lineBoxes,
                        summaryModelName: config.summaryModelDisplayName
                    )
                } catch {
                    return buildPipelineResultFromOCR(
                        payload,
                        lineBoxes: recognition.lineBoxes,
                        aiFallbackMessage: String(
                            localized: "AI 摘要请求失败，当前仅保留 OCR 文本。\(error.localizedDescription)"
                        ),
                        didAISummaryRequestFail: true
                    )
                }
            } else if aiSummaryEnabled {
                return buildPipelineResultFromOCR(
                    payload,
                    lineBoxes: recognition.lineBoxes,
                    aiFallbackMessage: String(appLocalized: "AI 摘要已开启，但 Kimi 配置不完整，当前仅保留 OCR 文本。")
                )
            }

            return buildPipelineResultFromOCR(payload, lineBoxes: recognition.lineBoxes)
        } catch VisionOCRServiceError.noRecognizedText {
            return BackgroundOCRPipelineResult(
                recognizedText: "",
                summary: String(appLocalized: "未识别到可用文字，请拍清晰一些或更换图片。"),
                intent: .summary,
                eventTitle: nil,
                eventDate: nil,
                eventTime: nil,
                eventKeywords: [],
                eventDescription: nil,
                needTodo: false,
                isOCRCompleted: false,
                usedAISummary: false,
                lineBoxes: [],
                aiFallbackMessage: nil,
                didAISummaryRequestFail: false,
                summaryModelName: nil,
                todoEvents: [],
                pickupCodes: []
            )
        } catch VisionOCRServiceError.invalidImage {
            return BackgroundOCRPipelineResult(
                recognizedText: "",
                summary: String(appLocalized: "当前图片格式暂不支持，请重试。"),
                intent: .summary,
                eventTitle: nil,
                eventDate: nil,
                eventTime: nil,
                eventKeywords: [],
                eventDescription: nil,
                needTodo: false,
                isOCRCompleted: false,
                usedAISummary: false,
                lineBoxes: [],
                aiFallbackMessage: nil,
                didAISummaryRequestFail: false,
                summaryModelName: nil,
                todoEvents: [],
                pickupCodes: []
            )
        } catch {
            return BackgroundOCRPipelineResult(
                recognizedText: "",
                summary: String(appLocalized: "OCR 识别失败，请稍后再试。"),
                intent: .summary,
                eventTitle: nil,
                eventDate: nil,
                eventTime: nil,
                eventKeywords: [],
                eventDescription: nil,
                needTodo: false,
                isOCRCompleted: false,
                usedAISummary: false,
                lineBoxes: [],
                aiFallbackMessage: nil,
                didAISummaryRequestFail: false,
                summaryModelName: nil,
                todoEvents: [],
                pickupCodes: []
            )
        }
    }

    private static func applyRecognitionResult(
        _ result: BackgroundOCRPipelineResult,
        to record: ScanRecord,
        modelContext: ModelContext
    ) {
        record.recognizedText = result.recognizedText
        record.summary = result.summary
        record.intent = result.intent.rawValue
        record.eventTitle = result.eventTitle
        record.eventDate = result.eventDate
        record.eventTime = result.eventTime
        record.eventKeywordsText = result.eventKeywords.joined(separator: ",")
        record.eventDescription = result.eventDescription
        record.needTodo = result.needTodo
        record.todoEvents = result.todoEvents
        record.pickupCodes = result.pickupCodes
        if result.todoEvents.isEmpty == false {
            let validKeys = Set(result.todoEvents.map(\.key))
            let retainedKeys = record.addedTodoEventKeys.intersection(validKeys)
            record.addedTodoEventKeys = retainedKeys
            record.hasAddedTodoReminder = retainedKeys.isEmpty == false
        } else {
            record.addedTodoEventKeys = []
            record.hasAddedTodoReminder = false
        }
        record.isOCRCompleted = result.isOCRCompleted
        record.usedAISummary = result.usedAISummary
        record.summaryUpdatedAt = result.isOCRCompleted ? .now : record.summaryUpdatedAt
        record.summaryModelName = result.isOCRCompleted
            ? (result.usedAISummary ? result.summaryModelName : String(appLocalized: "本地摘要"))
            : record.summaryModelName
        record.ocrLineBoxes = result.lineBoxes
        try? modelContext.save()
    }

    private static func buildPipelineResultFromAI(
        recognizedText: String,
        ocrFallbackText: String,
        insight: AIOCRInsight,
        lineBoxes: [OCRLineBox],
        summaryModelName: String
    ) -> BackgroundOCRPipelineResult {
        let pickupCodes = buildPickupCodes(from: insight, rawText: recognizedText)
        if let primaryPickupCode = pickupCodes.first {
            let summary = primaryPickupCode.summaryText
            return BackgroundOCRPipelineResult(
                recognizedText: recognizedText,
                summary: summary,
                intent: .pickup,
                eventTitle: summary,
                eventDate: nil,
                eventTime: nil,
                eventKeywords: [primaryPickupCode.category.displayName],
                eventDescription: pickupDescriptionText(for: pickupCodes),
                needTodo: false,
                isOCRCompleted: true,
                usedAISummary: true,
                lineBoxes: lineBoxes,
                aiFallbackMessage: nil,
                didAISummaryRequestFail: false,
                summaryModelName: summaryModelName,
                todoEvents: [],
                pickupCodes: pickupCodes
            )
        }

        let resolvedSummary = insight.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ocrFallbackText
            : insight.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let todoEvents = buildTodoEvents(from: insight)
        let primaryTodoEvent = todoEvents.first(where: { $0.needTodo }) ?? todoEvents.first
        let resolvedTitle = primaryTodoEvent?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? insight.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDescription = primaryTodoEvent?.description?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? insight.description?.trimmingCharacters(in: .whitespacesAndNewlines)

        let normalizedKeywords = Array(
            (primaryTodoEvent?.keywords ?? insight.keywords)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
                .prefix(3)
        )
        let normalizedTimeValue = primaryTodoEvent?.time ?? normalizedTime(insight.time)
        let resolvedEventTime = normalizedTimeValue ?? "00:00"
        let date = primaryTodoEvent?.date ?? parsedEventDate(date: insight.date, time: resolvedEventTime)
        let hasScheduleDate = date != nil
        let todo = primaryTodoEvent?.needTodo ?? insight.needTodo
        let descriptionText = (resolvedDescription?.isEmpty == false) ? resolvedDescription : resolvedSummary

        return BackgroundOCRPipelineResult(
            recognizedText: recognizedText,
            summary: resolvedSummary,
            intent: hasScheduleDate ? .schedule : .summary,
            eventTitle: resolvedTitle,
            eventDate: date,
            eventTime: normalizedTimeValue,
            eventKeywords: normalizedKeywords,
            eventDescription: descriptionText,
            needTodo: todo,
            isOCRCompleted: true,
            usedAISummary: true,
            lineBoxes: lineBoxes,
            aiFallbackMessage: nil,
            didAISummaryRequestFail: false,
            summaryModelName: summaryModelName,
            todoEvents: todoEvents,
            pickupCodes: []
        )
    }

    private static func buildPipelineResultFromOCR(
        _ payload: InsightPayload,
        lineBoxes: [OCRLineBox],
        aiFallbackMessage: String? = nil,
        didAISummaryRequestFail: Bool = false,
        summaryModelName: String? = nil
    ) -> BackgroundOCRPipelineResult {
        let resolvedText = payload.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let pickupCodes = PickupCodeExtractor.extract(from: resolvedText)
        if let primaryPickupCode = pickupCodes.first {
            let summary = primaryPickupCode.summaryText
            return BackgroundOCRPipelineResult(
                recognizedText: resolvedText,
                summary: summary,
                intent: .pickup,
                eventTitle: summary,
                eventDate: nil,
                eventTime: nil,
                eventKeywords: [primaryPickupCode.category.displayName],
                eventDescription: pickupDescriptionText(for: pickupCodes),
                needTodo: false,
                isOCRCompleted: true,
                usedAISummary: false,
                lineBoxes: lineBoxes,
                aiFallbackMessage: aiFallbackMessage,
                didAISummaryRequestFail: didAISummaryRequestFail,
                summaryModelName: summaryModelName,
                todoEvents: [],
                pickupCodes: pickupCodes
            )
        }

        let eventDescription = resolvedText.isEmpty ? nil : resolvedText

        return BackgroundOCRPipelineResult(
            recognizedText: resolvedText,
            summary: resolvedText,
            intent: .summary,
            eventTitle: nil,
            eventDate: nil,
            eventTime: nil,
            eventKeywords: [],
            eventDescription: eventDescription,
            needTodo: false,
            isOCRCompleted: true,
            usedAISummary: false,
            lineBoxes: lineBoxes,
            aiFallbackMessage: aiFallbackMessage,
            didAISummaryRequestFail: didAISummaryRequestFail,
            summaryModelName: summaryModelName,
            todoEvents: [],
            pickupCodes: []
        )
    }

    private static func buildTodoEvents(from insight: AIOCRInsight) -> [ScanTodoEvent] {
        insight.events.compactMap { event in
            let normalizedTimeValue = normalizedTime(event.time) ?? "00:00"
            guard let date = parsedEventDate(date: event.date, time: normalizedTimeValue) else {
                return nil
            }
            let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = event.description?.trimmingCharacters(in: .whitespacesAndNewlines)
            let keywords = Array(
                event.keywords
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.isEmpty == false }
                    .prefix(3)
            )
            return ScanTodoEvent(
                title: title,
                date: date,
                time: normalizedTimeValue,
                keywords: keywords,
                description: description,
                needTodo: event.needTodo
            )
        }
        .sorted { lhs, rhs in
            lhs.date < rhs.date
        }
    }

    private static func buildPickupCodes(from insight: AIOCRInsight, rawText: String) -> [ScanPickupCode] {
        var normalized: [ScanPickupCode] = insight.pickupItems.compactMap { item in
            ScanPickupCode(
                brandName: item.brandName,
                itemName: item.itemName,
                codeValue: item.codeValue,
                codeLabel: item.codeLabel,
                category: item.category,
                pickupDate: item.pickupDate,
                pickupTime: item.pickupTime,
                source: "ai",
                priority: item.priority
            )
        }.filter { $0.codeValue.isEmpty == false }

        if normalized.isEmpty {
            normalized = PickupCodeExtractor.extract(from: rawText)
        }
        return normalized.sorted { lhs, rhs in
            let leftPriority = lhs.priority ?? Int.max
            let rightPriority = rhs.priority ?? Int.max
            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }
            return lhs.codeValue < rhs.codeValue
        }
    }

    private static func pickupDescriptionText(for pickupCodes: [ScanPickupCode]) -> String {
        pickupCodes.map { pickup in
            let dateTime = pickup.dateTimeText ?? String(appLocalized: "未知时间")
            return "\(pickup.summaryText)（\(pickup.category.displayName)，\(dateTime)）"
        }.joined(separator: "；")
    }

    private static func parsedEventDate(date: String?, time: String) -> Date? {
        guard let date else { return nil }
        let dateText = date.trimmingCharacters(in: .whitespacesAndNewlines)
        guard dateText.isEmpty == false else { return nil }
        return eventDateFormatter.date(from: "\(dateText) \(time)")
    }

    private static func normalizedTime(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return trimmed
    }

    private static var eventDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }
}
