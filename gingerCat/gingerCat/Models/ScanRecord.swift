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
    var note: String

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
        note: String = ""
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
        self.note = note
    }

    var resolvedIntent: ScanIntent {
        ScanIntent(rawValue: intent) ?? .summary
    }
}

extension ScanRecord {
    static func previewData() -> [ScanRecord] {
        [
            ScanRecord(
                source: "Photo",
                recognizedText: "4月10日 19:30 产品评审会，线上会议室 A",
                summary: "识别到一次产品评审会议，建议提前 30 分钟提醒。",
                intent: .schedule,
                eventTitle: "产品评审会",
                eventDate: Calendar.current.date(byAdding: .day, value: 2, to: .now)
            ),
            ScanRecord(
                source: "Camera",
                recognizedText: "会议纪要：重点优化首页转化路径与埋点完整性。",
                summary: "这张图主要是会议纪要，不包含明确时间信息。",
                intent: .summary,
                note: "后续整理成迭代任务"
            )
        ]
    }
}
