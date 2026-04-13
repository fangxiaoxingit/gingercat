import Foundation

@MainActor
enum TodoAutoAddService {
    struct Result {
        let addedCount: Int
    }

    private struct Candidate {
        let key: String?
        let event: ScanTodoEvent?
    }

    static func autoAddIfNeeded(
        for record: ScanRecord,
        enabled: Bool,
        now: Date = .now
    ) async -> Result {
        guard enabled else {
            return Result(addedCount: 0)
        }

        let candidates = reminderCandidates(for: record, now: now)
        guard candidates.isEmpty == false else {
            return Result(addedCount: 0)
        }

        var addedCount = 0
        var addedKeys = record.addedTodoEventKeys

        for candidate in candidates {
            if let key = candidate.key, addedKeys.contains(key) {
                continue
            }

            do {
                if let event = candidate.event {
                    try await ReminderService.shared.addReminder(for: record, event: event)
                } else {
                    try await ReminderService.shared.addReminder(for: record)
                }

                if let key = candidate.key {
                    addedKeys.insert(key)
                }
                addedCount += 1
            } catch {
                continue
            }
        }

        if addedCount > 0 {
            record.addedTodoEventKeys = addedKeys
            record.hasAddedTodoReminder = addedKeys.isEmpty == false
        }

        return Result(addedCount: addedCount)
    }

    private static func reminderCandidates(
        for record: ScanRecord,
        now: Date
    ) -> [Candidate] {
        let eventCandidates = record.todoEvents
            .filter { $0.needTodo && $0.date > now }
            .sorted { lhs, rhs in
                lhs.date < rhs.date
            }
            .map { event in
                Candidate(key: event.key, event: event)
            }

        if eventCandidates.isEmpty == false {
            return eventCandidates
        }

        guard record.needTodo,
              let eventDate = record.eventDate,
              eventDate > now else {
            return []
        }

        let legacyKey = ScanRecord.todoEventKey(
            date: eventDate,
            title: record.eventTitle,
            description: record.eventDescription
        )
        return [Candidate(key: legacyKey, event: nil)]
    }
}
