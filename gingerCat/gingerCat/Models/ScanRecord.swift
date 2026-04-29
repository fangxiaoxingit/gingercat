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
            return lhs.codeValue < rhs.codeValue
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
    case coffee = "咖啡"
    case beverage = "饮品"
    case express = "快递"
    case other = "其他"

    var displayName: String { rawValue }

    var fallbackItemName: String {
        switch self {
        case .coffee:
            return String(appLocalized: "咖啡")
        case .beverage:
            return String(appLocalized: "饮品")
        case .express:
            return String(appLocalized: "快递")
        case .other:
            return String(appLocalized: "其他")
        }
    }

    var systemImageName: String {
        switch self {
        case .coffee:
            return "cup.and.saucer.fill"
        case .beverage:
            return "takeoutbag.and.cup.and.straw.fill"
        case .express:
            return "truck.box.fill"
        case .other:
            return "shippingbox.fill"
        }
    }
}

struct ScanPickupCode: Codable, Hashable {
    var brandName: String
    var itemName: String
    var codeValue: String
    var codeLabel: String
    var category: ScanPickupCategory
    var pickupDate: String?
    var pickupTime: String?
    var source: String?
    var priority: Int?

    init(
        brandName: String?,
        itemName: String? = nil,
        codeValue: String,
        codeLabel: String,
        category: ScanPickupCategory,
        pickupDate: String? = nil,
        pickupTime: String? = nil,
        source: String? = nil,
        priority: Int? = nil
    ) {
        let normalizedBrand = brandName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedItem = itemName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedCode = codeValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedLabel = codeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDate = pickupDate?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTime = pickupTime?.trimmingCharacters(in: .whitespacesAndNewlines)

        let resolvedBrand = normalizedBrand.isEmpty ? String(appLocalized: "其他") : normalizedBrand
        let resolvedItem: String
        if normalizedItem.isEmpty == false {
            resolvedItem = normalizedItem
        } else if normalizedBrand.isEmpty == false {
            resolvedItem = normalizedBrand
        } else {
            resolvedItem = category.fallbackItemName
        }

        self.brandName = resolvedBrand
        self.itemName = resolvedItem
        self.codeValue = normalizedCode
        self.codeLabel = normalizedLabel == String(appLocalized: "取餐码")
            ? String(appLocalized: "取餐码")
            : String(appLocalized: "取件码")
        self.category = category
        self.pickupDate = normalizedDate?.isEmpty == true ? nil : normalizedDate
        self.pickupTime = normalizedTime?.isEmpty == true ? nil : normalizedTime
        self.source = source?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.priority = priority
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let brandName = try container.decodeIfPresent(String.self, forKey: .brandName)
        let itemName = try container.decodeIfPresent(String.self, forKey: .itemName)
        let codeValue = try container.decode(String.self, forKey: .codeValue)
        let codeLabel = try container.decodeIfPresent(String.self, forKey: .codeLabel) ?? String(appLocalized: "取件码")
        let category = try container.decodeIfPresent(ScanPickupCategory.self, forKey: .category) ?? .other
        let pickupDate = try container.decodeIfPresent(String.self, forKey: .pickupDate)
        let pickupTime = try container.decodeIfPresent(String.self, forKey: .pickupTime)
        let source = try container.decodeIfPresent(String.self, forKey: .source)
        let priority = try container.decodeIfPresent(Int.self, forKey: .priority)

        self.init(
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
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(brandName, forKey: .brandName)
        try container.encode(itemName, forKey: .itemName)
        try container.encode(codeValue, forKey: .codeValue)
        try container.encode(codeLabel, forKey: .codeLabel)
        try container.encode(category, forKey: .category)
        try container.encodeIfPresent(pickupDate, forKey: .pickupDate)
        try container.encodeIfPresent(pickupTime, forKey: .pickupTime)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(priority, forKey: .priority)
    }

    private enum CodingKeys: String, CodingKey {
        case brandName
        case itemName
        case codeValue
        case codeLabel
        case category
        case pickupDate
        case pickupTime
        case source
        case priority
    }

    var resolvedBrandName: String {
        let normalized = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? String(appLocalized: "其他") : normalized
    }

    var resolvedDisplayName: String {
        resolvedBrandName
    }

    var resolvedItemName: String {
        let normalized = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty == false {
            return normalized
        }
        return resolvedBrandName
    }

    var summaryText: String {
        "\(resolvedBrandName) \(codeLabel) \(codeValue)"
    }

    var dateTimeText: String? {
        if let pickupDate, let pickupTime {
            return "\(pickupDate) \(pickupTime)"
        }
        if let pickupDate {
            return pickupDate
        }
        if let pickupTime {
            return pickupTime
        }
        return nil
    }
}
