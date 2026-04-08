import Foundation

struct InsightEvent: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let date: Date
}

enum InsightMode: String {
    case schedule
    case summary

    var intent: ScanIntent {
        switch self {
        case .schedule: return .schedule
        case .summary: return .summary
        }
    }
}

enum InsightSummarySource: String {
    case local
    case ai
}

struct InsightPayload: Identifiable {
    let id = UUID()
    let imageData: Data?
    let source: String
    let rawText: String
    let summary: String
    let summarySource: InsightSummarySource
    let mode: InsightMode
    let events: [InsightEvent]
}
