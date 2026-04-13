import Foundation
import EventKit

enum ReminderServiceError: LocalizedError {
    case permissionDenied
    case noCalendarAvailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return String(localized: "未获得提醒事项权限，请在系统设置中允许访问后重试。")
        case .noCalendarAvailable:
            return String(localized: "未找到可用提醒列表，请先在系统提醒事项中创建列表。")
        }
    }
}

@MainActor
final class ReminderService {
    static let shared = ReminderService()

    private let eventStore = EKEventStore()

    private init() {}

    func addReminder(for record: ScanRecord) async throws {
        try await addReminder(
            title: reminderTitle(for: record, event: nil),
            notes: reminderNotes(for: record, event: nil),
            dueDate: record.eventDate
        )
    }

    func addReminder(for record: ScanRecord, event: ScanTodoEvent) async throws {
        try await addReminder(
            title: reminderTitle(for: record, event: event),
            notes: reminderNotes(for: record, event: event),
            dueDate: event.date
        )
    }

    func addReminder(title: String, notes: String, dueDate: Date?) async throws {
        let granted = try await requestAccessIfNeeded()
        guard granted else {
            throw ReminderServiceError.permissionDenied
        }

        let reminder = EKReminder(eventStore: eventStore)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.title = trimmedTitle.isEmpty ? String(localized: "识别记录提醒") : trimmedTitle

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNotes.isEmpty == false {
            reminder.notes = trimmedNotes
        }

        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }

        guard let calendar = eventStore.defaultCalendarForNewReminders() ?? eventStore.calendars(for: .reminder).first else {
            throw ReminderServiceError.noCalendarAvailable
        }
        reminder.calendar = calendar

        try eventStore.save(reminder, commit: true)
    }

    private func requestAccessIfNeeded() async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .authorized, .fullAccess:
            return true
        case .denied, .restricted:
            return false
        case .writeOnly:
            return true
        case .notDetermined:
            return try await eventStore.requestFullAccessToReminders()
        @unknown default:
            return false
        }
    }

    private func reminderTitle(for record: ScanRecord, event: ScanTodoEvent?) -> String {
        if let eventTitle = event?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           eventTitle.isEmpty == false {
            return eventTitle
        }

        if let eventDescription = event?.description?.trimmingCharacters(in: .whitespacesAndNewlines),
           eventDescription.isEmpty == false {
            return String(eventDescription.prefix(40))
        }

        if let eventTitle = record.eventTitle?.trimmingCharacters(in: .whitespacesAndNewlines), eventTitle.isEmpty == false {
            return eventTitle
        }

        let description = (record.eventDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if description.isEmpty == false {
            return String(description.prefix(40))
        }

        let summary = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if summary.isEmpty == false {
            return String(summary.prefix(40))
        }

        return String(localized: "识别记录提醒")
    }

    private func reminderNotes(for record: ScanRecord, event: ScanTodoEvent?) -> String {
        var lines: [String] = []
        lines.append("来源：\(record.source)")

        let eventDescription = event?.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let eventDescription, eventDescription.isEmpty == false {
            lines.append("事件描述：\(eventDescription)")
        } else if let description = record.eventDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           description.isEmpty == false {
            lines.append("事件描述：\(description)")
        } else {
            // 未启用 AI 摘要时，这里保存的是 OCR 原文，因此文案需要与真实来源保持一致。
            let label = record.usedAISummary ? "摘要" : "识别内容"
            lines.append("\(label)：\(record.summary)")
        }

        let eventKeywords = event?.keywords ?? []
        if eventKeywords.isEmpty == false {
            lines.append("关键词：\(eventKeywords.joined(separator: "、"))")
        } else if record.eventKeywords.isEmpty == false {
            lines.append("关键词：\(record.eventKeywords.joined(separator: "、"))")
        }

        if let event {
            lines.append("待办时间：\(AppDateTimeFormatter.string(from: event.date))")
        }

        let rawText = record.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawText.isEmpty == false {
            lines.append("识别结果：")
            lines.append(rawText)
        }

        let note = record.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if note.isEmpty == false {
            lines.append("备注：\(note)")
        }

        return lines.joined(separator: "\n")
    }
}
