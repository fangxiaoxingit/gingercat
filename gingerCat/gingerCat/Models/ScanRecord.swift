import Foundation
import SwiftData

enum ScanIntent: String, CaseIterable, Codable {
    case schedule
    case summary
    case pickup
}

@Model
final class ScanRecord {
    var id: UUID
    var createdAt: Date
    var summaryUpdatedAt: Date?
    var summaryModelName: String?
    var imageData: Data?
    var source: String
    var recognizedText: String
    var summary: String
    var intent: String
    var eventTitle: String?
    var eventDate: Date?
    var eventTime: String?
    var eventKeywordsText: String = ""
    var eventDescription: String?
    var needTodo: Bool = false
    var note: String
    var isOCRCompleted: Bool = false
    var usedAISummary: Bool = false
    var ocrLineBoxesJSON: String = ""
    var hasAddedTodoReminder: Bool = false
    var todoEventsJSON: String = ""
    var addedTodoEventKeysJSON: String = ""
    var pickupCodesJSON: String = ""

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        summaryUpdatedAt: Date? = nil,
        summaryModelName: String? = nil,
        imageData: Data? = nil,
        source: String,
        recognizedText: String,
        summary: String,
        intent: ScanIntent,
        eventTitle: String? = nil,
        eventDate: Date? = nil,
        eventTime: String? = nil,
        eventKeywordsText: String = "",
        eventDescription: String? = nil,
        needTodo: Bool = false,
        note: String = "",
        isOCRCompleted: Bool = false,
        usedAISummary: Bool = false,
        ocrLineBoxesJSON: String = "",
        hasAddedTodoReminder: Bool = false,
        todoEventsJSON: String = "",
        addedTodoEventKeysJSON: String = "",
        pickupCodesJSON: String = ""
    ) {
        self.id = id
        self.createdAt = createdAt
        self.summaryUpdatedAt = summaryUpdatedAt
        self.summaryModelName = summaryModelName
        self.imageData = imageData
        self.source = source
        self.recognizedText = recognizedText
        self.summary = summary
        self.intent = intent.rawValue
        self.eventTitle = eventTitle
        self.eventDate = eventDate
        self.eventTime = eventTime
        self.eventKeywordsText = eventKeywordsText
        self.eventDescription = eventDescription
        self.needTodo = needTodo
        self.note = note
        self.isOCRCompleted = isOCRCompleted
        self.usedAISummary = usedAISummary
        self.ocrLineBoxesJSON = ocrLineBoxesJSON
        self.hasAddedTodoReminder = hasAddedTodoReminder
        self.todoEventsJSON = todoEventsJSON
        self.addedTodoEventKeysJSON = addedTodoEventKeysJSON
        self.pickupCodesJSON = pickupCodesJSON
    }

    var resolvedIntent: ScanIntent {
        ScanIntent(rawValue: intent) ?? .summary
    }
}

extension ScanRecord {
    var eventKeywords: [String] {
        eventKeywordsText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    var ocrLineBoxes: [OCRLineBox] {
        get {
            guard let data = ocrLineBoxesJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([OCRLineBox].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let value = String(data: data, encoding: .utf8) else {
                ocrLineBoxesJSON = ""
                return
            }
            ocrLineBoxesJSON = value
        }
    }

    var todoEvents: [ScanTodoEvent] {
        get {
            guard let data = todoEventsJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([ScanTodoEvent].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let value = String(data: data, encoding: .utf8) else {
                todoEventsJSON = ""
                return
            }
            todoEventsJSON = value
        }
    }

    var addedTodoEventKeys: Set<String> {
        get {
            guard let data = addedTodoEventKeysJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return Set(decoded)
        }
        set {
            let values = Array(newValue)
            guard let data = try? JSONEncoder().encode(values),
                  let value = String(data: data, encoding: .utf8) else {
                addedTodoEventKeysJSON = ""
                return
            }
            addedTodoEventKeysJSON = value
        }
    }

    var pickupCodes: [ScanPickupCode] {
        get {
            guard let data = pickupCodesJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([ScanPickupCode].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let value = String(data: data, encoding: .utf8) else {
                pickupCodesJSON = ""
                return
            }
            pickupCodesJSON = value
        }
    }

    var primaryPickupCode: ScanPickupCode? {
        pickupCodes.sorted { lhs, rhs in
            let leftPriority = lhs.priority ?? Int.max
            let rightPriority = rhs.priority ?? Int.max
            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }
            return lhs.code < rhs.code
        }.first
    }

    static func todoEventKey(date: Date, title: String?, description: String?) -> String {
        let timestamp = Int(date.timeIntervalSince1970.rounded())
        let normalizedTitle = (title ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedDescription = (description ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let briefDescription = String(normalizedDescription.prefix(40))
        return "\(timestamp)|\(normalizedTitle)|\(briefDescription)"
    }

    static func previewData() -> [ScanRecord] {
        [
            ScanRecord(
                summaryUpdatedAt: .now,
                source: "Photo",
                recognizedText: "4月10日 19:30 产品评审会，线上会议室 A",
                summary: "4月10日 19:30 产品评审会，线上会议室A。",
                intent: .schedule,
                eventTitle: "4月10日 19:30 产品评审会",
                eventDate: Calendar.current.date(byAdding: .day, value: 2, to: .now),
                eventTime: "19:30",
                eventKeywordsText: "评审会,产品,会议",
                eventDescription: "4月10日 19:30 在线上会议室A进行产品评审会。",
                needTodo: true,
                isOCRCompleted: true,
                usedAISummary: true,
                hasAddedTodoReminder: true
            ),
            ScanRecord(
                summaryUpdatedAt: .now,
                source: "Camera",
                recognizedText: "会议纪要：重点优化首页转化路径与埋点完整性。",
                summary: "这张图主要是会议纪要，不包含明确时间信息。",
                intent: .summary,
                eventKeywordsText: "会议纪要",
                eventDescription: "这张图主要是会议纪要，不包含明确时间信息。",
                needTodo: false,
                note: "后续整理成迭代任务",
                isOCRCompleted: true,
                usedAISummary: false
            )
        ]
    }
}

enum AppDateTimeFormatter {
    private static let shared: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static func string(from date: Date) -> String {
        shared.string(from: date)
    }
}

struct ScanTodoEvent: Codable, Hashable {
    var title: String?
    var date: Date
    var time: String?
    var keywords: [String]
    var description: String?
    var needTodo: Bool

    var key: String {
        ScanRecord.todoEventKey(date: date, title: title, description: description)
    }
}

enum ScanPickupCategory: String, Codable, CaseIterable {
    case express
    case tea
    case coffee
    case food
    case retail
    case other

    var fallbackDisplayName: String {
        switch self {
        case .express:
            return String(localized: "快递")
        case .tea:
            return String(localized: "茶饮")
        case .coffee:
            return String(localized: "咖啡")
        case .food:
            return String(localized: "餐饮")
        case .retail:
            return String(localized: "门店")
        case .other:
            return String(localized: "其他取件")
        }
    }
}

struct ScanPickupCode: Codable, Hashable {
    var code: String
    var category: ScanPickupCategory
    var merchantName: String?
    var displayName: String
    var source: String?
    var priority: Int?

    init(
        code: String,
        category: ScanPickupCategory,
        merchantName: String?,
        displayName: String? = nil,
        source: String? = nil,
        priority: Int? = nil
    ) {
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMerchantName = merchantName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)

        self.code = normalizedCode
        self.category = category
        self.merchantName = normalizedMerchantName?.isEmpty == true ? nil : normalizedMerchantName
        self.displayName = (normalizedDisplayName?.isEmpty == false)
            ? (normalizedDisplayName ?? category.fallbackDisplayName)
            : category.fallbackDisplayName
        self.source = source?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.priority = priority
    }

    var label: String {
        String(localized: "取件码")
    }

    var resolvedDisplayName: String {
        if let merchantName = merchantName?.trimmingCharacters(in: .whitespacesAndNewlines),
           merchantName.isEmpty == false {
            return merchantName
        }
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedDisplayName.isEmpty == false {
            return normalizedDisplayName
        }
        return category.fallbackDisplayName
    }

    var summaryText: String {
        "\(resolvedDisplayName) \(label) \(code)"
    }
}
