import Foundation
import SwiftData

enum ScanIntent: String, CaseIterable, Codable {
    case schedule
    case summary
}

@Model
final class ScanRecord {
    var id: UUID
    var createdAt: Date
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

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
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
        hasAddedTodoReminder: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
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

    static func previewData() -> [ScanRecord] {
        [
            ScanRecord(
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
