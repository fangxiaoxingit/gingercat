import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(UIKit)
import UIKit
#endif

struct TodoWidgetSnapshotPayload: Codable {
    let updatedAt: Date
    let items: [TodoWidgetSnapshotItemPayload]

    static let empty = TodoWidgetSnapshotPayload(updatedAt: .distantPast, items: [])
}

struct TodoWidgetSnapshotItemPayload: Codable, Hashable, Identifiable {
    let id: String
    let recordID: UUID
    let title: String
    let dueDate: Date
    let usesImageBackground: Bool
    let backgroundImageDataBase64: String?
}

enum TodoWidgetSnapshotSync {
    static let appGroupIdentifier = ExternalImageImportStore.sharedAppGroupIdentifier
    static let snapshotKey = "widget.todo.snapshot.v1"
    static let latestTodoWidgetKind = "gingercat.todo.latest.small"
    static let recentTodoWidgetKind = "gingercat.todo.recent.medium"

    private static let maxStoredItems = 10

    static func sync(records: [ScanRecord], now: Date = .now) {
        let snapshot = TodoWidgetSnapshotPayload(
            updatedAt: now,
            items: buildSnapshotItems(from: records, now: now)
        )

        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = try? JSONEncoder().encode(snapshot) else {
            return
        }

        defaults.set(data, forKey: snapshotKey)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: latestTodoWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: recentTodoWidgetKind)
        #endif
    }

    private struct TodoCandidate {
        let id: String
        let record: ScanRecord
        let title: String
        let dueDate: Date
    }

    private static func buildSnapshotItems(
        from records: [ScanRecord],
        now: Date
    ) -> [TodoWidgetSnapshotItemPayload] {
        let candidates = buildCandidates(from: records, now: now)
            .sorted { lhs, rhs in
                if lhs.dueDate == rhs.dueDate {
                    return lhs.record.createdAt < rhs.record.createdAt
                }
                return lhs.dueDate < rhs.dueDate
            }

        return Array(candidates.prefix(maxStoredItems).enumerated()).map { index, candidate in
            let imageBase64: String?
            if index == 0,
               let rawImageData = candidate.record.imageData,
               let processedImageData = makeWidgetBackgroundImageData(from: rawImageData) {
                imageBase64 = processedImageData.base64EncodedString()
            } else {
                imageBase64 = nil
            }

            return TodoWidgetSnapshotItemPayload(
                id: candidate.id,
                recordID: candidate.record.id,
                title: candidate.title,
                dueDate: candidate.dueDate,
                usesImageBackground: imageBase64 != nil,
                backgroundImageDataBase64: imageBase64
            )
        }
    }

    private static func buildCandidates(from records: [ScanRecord], now: Date) -> [TodoCandidate] {
        var candidates: [TodoCandidate] = []

        for record in records {
            let todoEvents = record.todoEvents.filter(\.needTodo)

            if todoEvents.isEmpty == false {
                let eventCandidates = todoEvents.compactMap { event -> TodoCandidate? in
                    guard event.date > now else { return nil }
                    return TodoCandidate(
                        id: "\(record.id.uuidString)-\(event.key)",
                        record: record,
                        title: resolvedTitle(for: record, event: event),
                        dueDate: event.date
                    )
                }
                candidates.append(contentsOf: eventCandidates)
                continue
            }

            let isTodoRecord = record.needTodo || record.resolvedIntent == .schedule
            guard isTodoRecord,
                  let dueDate = record.eventDate,
                  dueDate > now else {
                continue
            }

            candidates.append(
                TodoCandidate(
                    id: "\(record.id.uuidString)-fallback",
                    record: record,
                    title: resolvedTitle(for: record, event: nil),
                    dueDate: dueDate
                )
            )
        }

        return candidates
    }

    private static func resolvedTitle(for record: ScanRecord, event: ScanTodoEvent?) -> String {
        if let value = trimmedNonEmpty(event?.title) {
            return value
        }
        if let value = trimmedNonEmpty(record.eventTitle) {
            return value
        }
        if let value = trimmedNonEmpty(event?.description) {
            return value
        }
        if let value = trimmedNonEmpty(record.eventDescription) {
            return value
        }
        if let value = trimmedNonEmpty(record.summary) {
            return String(value.prefix(50))
        }
        if let value = trimmedNonEmpty(record.recognizedText) {
            return String(value.prefix(50))
        }
        return String(localized: "待办事项")
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    #if canImport(UIKit)
    private static func makeWidgetBackgroundImageData(from rawImageData: Data) -> Data? {
        guard let image = UIImage(data: rawImageData),
              image.size.width > 0,
              image.size.height > 0 else {
            return nil
        }

        let targetSize = CGSize(width: 420, height: 420)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        let rendered = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            let horizontalScale = targetSize.width / image.size.width
            let verticalScale = targetSize.height / image.size.height
            let scale = max(horizontalScale, verticalScale)
            let drawSize = CGSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )
            let drawOrigin = CGPoint(
                x: (targetSize.width - drawSize.width) / 2,
                y: (targetSize.height - drawSize.height) / 2
            )
            image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }

        return rendered.jpegData(compressionQuality: 0.62)
    }
    #else
    private static func makeWidgetBackgroundImageData(from rawImageData: Data) -> Data? {
        rawImageData
    }
    #endif
}
