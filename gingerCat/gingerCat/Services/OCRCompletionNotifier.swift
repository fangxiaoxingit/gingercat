import Foundation
import os
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif
#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
enum OCRCompletionNotifier {
    static func notify(record: ScanRecord, autoAddedTodoCount: Int = 0) async {
        let isPickupPriority = isPickupRecord(record)
        let primaryPickup = record.primaryPickupCode
        #if canImport(UIKit)
        // 常规识别维持“仅后台提醒”；取件优先事项前台也允许系统级提醒。
        if UIApplication.shared.applicationState == .active, isPickupPriority == false {
            return
        }
        #endif

        let title = completionTitle(for: record)
        let summary = completionSummary(for: record)
        let dateText = completionDateText(for: record)
        let pickupExtraCount = max(record.pickupCodes.count - 1, 0)

        if await OCRDynamicIslandService.showIfAvailable(
            recordID: record.id,
            title: title,
            summary: summary,
            dateText: dateText,
            isPickupPriority: isPickupPriority,
            pickupBrandName: primaryPickup?.resolvedBrandName,
            pickupItemName: primaryPickup?.resolvedItemName,
            pickupCodeLabel: primaryPickup?.codeLabel,
            pickupCodeValue: primaryPickup?.codeValue,
            pickupCategory: primaryPickup?.category.displayName,
            pickupDate: primaryPickup?.pickupDate,
            pickupTime: primaryPickup?.pickupTime,
            pickupExtraCount: pickupExtraCount
        ) {
            return
        }

        await OCRLocalNotificationService.notify(
            recordID: record.id,
            title: title,
            summary: summary,
            dateText: dateText,
            autoAddedTodoCount: autoAddedTodoCount,
            isPickupPriority: isPickupPriority
        )
    }

    static func notifyAISummaryFailure(record: ScanRecord) async {
        let title = completionTitle(for: record)
        let dateText = completionDateText(for: record)

        // AI 摘要失败需要明确反馈，前台也允许弹系统通知，避免“有时收不到失败提醒”。
        await OCRLocalNotificationService.notifyAISummaryFailure(
            recordID: record.id,
            title: title,
            dateText: dateText
        )
    }

    static func completionTitle(for record: ScanRecord) -> String {
        if let pickup = record.primaryPickupCode {
            return pickup.resolvedBrandName
        }
        if let title = record.eventTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           title.isEmpty == false {
            return title
        }
        let summary = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if summary.isEmpty {
            return String(localized: "识别记录")
        }
        return String(summary.prefix(18))
    }

    private static func completionSummary(for record: ScanRecord) -> String {
        if let pickup = record.primaryPickupCode {
            let extraCount = max(record.pickupCodes.count - 1, 0)
            if extraCount > 0 {
                return "\(pickup.summaryText)（另有\(extraCount)个）"
            }
            return pickup.summaryText
        }
        let normalized = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            return String(localized: "识别结果已生成")
        }
        return String(normalized.prefix(80))
    }

    private static func completionDateText(for record: ScanRecord) -> String {
        if let eventDate = record.eventDate {
            return AppDateTimeFormatter.string(from: eventDate)
        }
        return AppDateTimeFormatter.string(from: record.createdAt)
    }

    private static func isPickupRecord(_ record: ScanRecord) -> Bool {
        record.pickupCodes.isEmpty == false
    }
}

private enum OCRLocalNotificationService {
    static func notify(
        recordID: UUID,
        title: String,
        summary: String,
        dateText: String,
        autoAddedTodoCount: Int,
        isPickupPriority: Bool
    ) async {
        let content = UNMutableNotificationContent()
        if isPickupPriority {
            content.title = String(localized: "识别到取件信息")
        } else {
            content.title = autoAddedTodoCount > 0
                ? String(localized: "识别完成（已加入待办）")
                : String(localized: "识别完成")
        }
        content.body = "\(title)\n\(summary)\n\(dateText)"
        content.sound = .default
        content.userInfo = userInfo(for: recordID)

        await enqueue(content, identifier: "ocr.summary.\(recordID.uuidString)")
    }

    static func notifyAISummaryFailure(
        recordID: UUID,
        title: String,
        dateText: String
    ) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "AI 摘要失败")
        content.body = "\(title)\n\(String(localized: "请进入详情页重新尝试 AI 摘要。"))\n\(dateText)"
        content.sound = .default
        content.userInfo = userInfo(for: recordID)

        await enqueue(content, identifier: "ocr.ai-failure.\(recordID.uuidString)")
    }

    private static func enqueue(_ content: UNMutableNotificationContent, identifier: String) async {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return }

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil
            )
            try await center.add(request)
        } catch {
            // Silent fail: 系统通知失败不影响主链路落库。
        }
    }

    private static func userInfo(for recordID: UUID) -> [String: String] {
        [
            "recordID": recordID.uuidString,
            "recordURL": "gingercat://record/\(recordID.uuidString)"
        ]
    }
}

@MainActor
enum TodoDueNotificationScheduler {
    private static let notificationPrefix = "todo.due.daily."
    private static let defaultReminderTime = "08:00"

    static func refresh(
        for records: [ScanRecord],
        defaults: UserDefaults = .standard,
        now: Date = .now
    ) async {
        let center = UNUserNotificationCenter.current()
        let pendingIdentifiers = await pendingNotificationIdentifiers(center: center)
        let todayIdentifier = identifier(for: now)

        let reminderEnabled = boolValue(
            forKey: AppSettingsKeys.todoDueReminderEnabled,
            defaults: defaults,
            defaultValue: true
        )

        if reminderEnabled == false {
            removePendingDueNotifications(
                from: pendingIdentifiers,
                center: center
            )
            return
        }

        let candidates = dueCandidates(
            in: records,
            targetDate: now
        )

        guard candidates.isEmpty == false else {
            removePendingDueNotifications(
                from: pendingIdentifiers,
                center: center
            )
            return
        }

        let deliveredIdentifiers = await deliveredNotificationIdentifiers(center: center)
        if deliveredIdentifiers.contains(todayIdentifier) {
            return
        }

        let granted: Bool
        do {
            granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return
        }
        guard granted else { return }

        removeStalePendingDueNotifications(
            from: pendingIdentifiers,
            keeping: todayIdentifier,
            center: center
        )

        let reminderDate = dueReminderDate(
            for: now,
            rawTime: defaults.string(forKey: AppSettingsKeys.todoDueReminderTime) ?? defaultReminderTime
        )
        let trigger: UNNotificationTrigger?
        if reminderDate.timeIntervalSince(now) > 3 {
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: reminderDate
            )
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        } else {
            trigger = nil
        }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "今日待办提醒")
        content.body = dueNotificationBody(candidates: candidates)
        content.sound = .default
        content.threadIdentifier = "todo.due.daily"
        content.userInfo = userInfo(for: candidates.first?.recordID)

        let request = UNNotificationRequest(
            identifier: todayIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            if pendingIdentifiers.contains(todayIdentifier) {
                center.removePendingNotificationRequests(withIdentifiers: [todayIdentifier])
            }
            try await center.add(request)
        } catch {
            return
        }
    }

    private static func dueCandidates(
        in records: [ScanRecord],
        targetDate: Date
    ) -> [TodoDueCandidate] {
        let calendar = Calendar.current
        var candidatesByKey: [String: TodoDueCandidate] = [:]

        for record in records {
            let fallbackNeedsTodo = record.needTodo || record.resolvedIntent == .schedule

            if record.todoEvents.isEmpty == false {
                for event in record.todoEvents {
                    let shouldRemind = event.needTodo || fallbackNeedsTodo
                    guard shouldRemind else { continue }
                    guard calendar.isDate(event.date, inSameDayAs: targetDate) else { continue }

                    if candidatesByKey[event.key] == nil {
                        candidatesByKey[event.key] = TodoDueCandidate(
                            key: event.key,
                            recordID: record.id,
                            title: resolvedTitle(record: record, event: event),
                            dueDate: event.date
                        )
                    }
                }
                continue
            }

            guard fallbackNeedsTodo else { continue }
            guard let eventDate = record.eventDate else { continue }
            guard calendar.isDate(eventDate, inSameDayAs: targetDate) else { continue }

            let fallbackKey = "record.\(record.id.uuidString).\(Int(eventDate.timeIntervalSince1970))"
            if candidatesByKey[fallbackKey] == nil {
                candidatesByKey[fallbackKey] = TodoDueCandidate(
                    key: fallbackKey,
                    recordID: record.id,
                    title: resolvedTitle(record: record, event: nil),
                    dueDate: eventDate
                )
            }
        }

        return candidatesByKey.values.sorted { lhs, rhs in
            lhs.dueDate < rhs.dueDate
        }
    }

    private static func resolvedTitle(
        record: ScanRecord,
        event: ScanTodoEvent?
    ) -> String {
        let eventTitle = event?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if eventTitle.isEmpty == false {
            return eventTitle
        }

        let recordTitle = record.eventTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if recordTitle.isEmpty == false {
            return recordTitle
        }

        let eventDescription = event?.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if eventDescription.isEmpty == false {
            return String(eventDescription.prefix(24))
        }

        let recordDescription = record.eventDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if recordDescription.isEmpty == false {
            return String(recordDescription.prefix(24))
        }

        let summary = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if summary.isEmpty == false {
            return String(summary.prefix(24))
        }
        return String(localized: "待办事项")
    }

    private static func dueNotificationBody(candidates: [TodoDueCandidate]) -> String {
        guard let first = candidates.first else {
            return String(localized: "今天有待办事项需要处理。")
        }

        if candidates.count == 1 {
            return String(localized: "「\(first.title)」今天到期，记得处理。")
        }

        let preview = candidates.prefix(3).map(\.title).joined(separator: "、")
        if candidates.count > 3 {
            return String(localized: "今天有 \(candidates.count) 条待办：\(preview) 等。")
        }
        return String(localized: "今天有 \(candidates.count) 条待办：\(preview)。")
    }

    private static func dueReminderDate(
        for baseDate: Date,
        rawTime: String
    ) -> Date {
        let normalizedTime = normalizeTime(rawTime) ?? defaultReminderTime
        let parts = normalizedTime.split(separator: ":")
        let hour = Int(parts.first ?? "8") ?? 8
        let minute = Int(parts.last ?? "0") ?? 0
        var components = Calendar.current.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components) ?? baseDate
    }

    private static func normalizeTime(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return trimmed
    }

    private static func userInfo(for recordID: UUID?) -> [String: String] {
        guard let recordID else {
            return ["notificationType": "todoDueReminder"]
        }
        return [
            "notificationType": "todoDueReminder",
            "recordID": recordID.uuidString,
            "recordURL": "gingercat://record/\(recordID.uuidString)"
        ]
    }

    private static func identifier(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyyMMdd"
        return "\(notificationPrefix)\(formatter.string(from: date))"
    }

    private static func removePendingDueNotifications(
        from identifiers: Set<String>,
        center: UNUserNotificationCenter
    ) {
        let dueIDs = identifiers.filter { $0.hasPrefix(notificationPrefix) }
        guard dueIDs.isEmpty == false else { return }
        center.removePendingNotificationRequests(withIdentifiers: Array(dueIDs))
    }

    private static func removeStalePendingDueNotifications(
        from identifiers: Set<String>,
        keeping identifier: String,
        center: UNUserNotificationCenter
    ) {
        let staleIDs = identifiers.filter { $0.hasPrefix(notificationPrefix) && $0 != identifier }
        guard staleIDs.isEmpty == false else { return }
        center.removePendingNotificationRequests(withIdentifiers: Array(staleIDs))
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

    private static func pendingNotificationIdentifiers(
        center: UNUserNotificationCenter
    ) async -> Set<String> {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: Set(requests.map(\.identifier)))
            }
        }
    }

    private static func deliveredNotificationIdentifiers(
        center: UNUserNotificationCenter
    ) async -> Set<String> {
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                continuation.resume(returning: Set(notifications.map(\.request.identifier)))
            }
        }
    }
}

private struct TodoDueCandidate {
    let key: String
    let recordID: UUID
    let title: String
    let dueDate: Date
}

private enum OCRDynamicIslandService {
    private static let logSubsystem = "com.siyufang.LivePhotoMakerUniversal.gingerCat"
    private static let logger = Logger(
        subsystem: logSubsystem,
        category: "OCRDynamicIsland"
    )

    static func showIfAvailable(
        recordID: UUID,
        title: String,
        summary: String,
        dateText: String,
        isPickupPriority: Bool,
        pickupBrandName: String?,
        pickupItemName: String?,
        pickupCodeLabel: String?,
        pickupCodeValue: String?,
        pickupCategory: String?,
        pickupDate: String?,
        pickupTime: String?,
        pickupExtraCount: Int
    ) async -> Bool {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            logger.info("Attempt live activity. pickup=\(isPickupPriority, privacy: .public), record=\(recordID.uuidString, privacy: .public)")
            // 先保证系统允许 Live Activities，再按设备能力决定是否尝试灵动岛展示。
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                logger.warning("Live Activities disabled by system/user settings.")
                return false
            }
            let capability = DynamicIslandCapability.supportVerdict
            guard capability != .unsupported else {
                logger.info("Capability judged as unsupported.")
                return false
            }

            let attributes = OCRLiveActivityAttributes(recordID: recordID.uuidString)
            let state = OCRLiveActivityAttributes.ContentState(
                title: title,
                summary: summary,
                dateText: dateText,
                isPickupPriority: isPickupPriority,
                pickupBrandName: pickupBrandName,
                pickupItemName: pickupItemName,
                pickupCodeLabel: pickupCodeLabel,
                pickupCodeValue: pickupCodeValue,
                pickupCategory: pickupCategory,
                pickupDate: pickupDate,
                pickupTime: pickupTime,
                pickupExtraCount: pickupExtraCount
            )
            let content = ActivityContent(
                state: state,
                staleDate: Date().addingTimeInterval(15 * 60)
            )

            do {
                for activity in Activity<OCRLiveActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }

                let activity = try Activity<OCRLiveActivityAttributes>.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )

                Task {
                    let displayDuration: UInt64 = isPickupPriority ? 60_000_000_000 : 15_000_000_000
                    try? await Task.sleep(nanoseconds: displayDuration)
                    await activity.end(content, dismissalPolicy: .default)
                }
                DynamicIslandCapability.cacheSupportIfNeeded(true)
                return true
            } catch {
                logger.error("Activity.request failed: \(String(describing: error), privacy: .public)")
                return false
            }
        }
        #endif
        return false
    }
}

private enum DynamicIslandCapability {
    enum SupportVerdict: Equatable {
        case supported
        case unsupported
        case unknown
    }

    static var supportVerdict: SupportVerdict {
        #if canImport(UIKit)
        guard UIDevice.current.userInterfaceIdiom == .phone else { return .unsupported }

        // 运行时优先用安全区高度判断灵动岛能力，避免新机型因硬编码列表缺失被误判成不支持。
        if let topInset = topSafeAreaInset {
            if topInset >= 51 {
                cacheSupportIfNeeded(true)
                return .supported
            }
            // 某些运行时窗口状态下安全区可能不稳定，这里标记为 unknown，交给 Activity.request 最终确认。
            return .unknown
        }

        if cachedSupport == true {
            return .supported
        }

        // 没有可用窗口时回退到机型表；未知新机型返回 unknown，交给请求链路最终确认。
        if let hardwareIdentifier = HardwareIdentifier.current,
           dynamicIslandIdentifiers.contains(hardwareIdentifier) {
            cacheSupportIfNeeded(true)
            return .supported
        }

        if let hardwareIdentifier = HardwareIdentifier.current,
           isKnownNonDynamicIslandModel(hardwareIdentifier) {
            return .unsupported
        }
        #endif
        return .unknown
    }

    static func cacheSupportIfNeeded(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: cacheKey)
    }

    // 覆盖已发布的灵动岛机型；未知机型默认回落系统通知，避免误判导致提醒丢失。
    private static let dynamicIslandIdentifiers: Set<String> = [
        "iPhone15,2", "iPhone15,3",
        "iPhone15,4", "iPhone15,5",
        "iPhone16,1", "iPhone16,2",
        "iPhone17,1", "iPhone17,2", "iPhone17,3", "iPhone17,4"
    ]

    private static let cacheKey = "dynamicIsland.capability.cached"

    private static var cachedSupport: Bool? {
        guard UserDefaults.standard.object(forKey: cacheKey) != nil else {
            return nil
        }
        return UserDefaults.standard.bool(forKey: cacheKey)
    }

    private static func isKnownNonDynamicIslandModel(_ identifier: String) -> Bool {
        guard identifier.hasPrefix("iPhone"),
              let majorPart = identifier.split(separator: ",").first,
              let major = Int(majorPart.replacingOccurrences(of: "iPhone", with: "")) else {
            return false
        }
        // iPhone14 及更老机型明确无灵动岛。
        return major < 15
    }

    #if canImport(UIKit)
    private static var topSafeAreaInset: CGFloat? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
        for scene in scenes {
            if let keyWindow = scene.windows.first(where: \.isKeyWindow) {
                return keyWindow.safeAreaInsets.top
            }
        }
        return nil
    }
    #endif
}

private enum HardwareIdentifier {
    static var current: String? {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = Mirror(reflecting: systemInfo.machine)
            .children
            .compactMap { element -> UInt8? in
                guard let value = element.value as? Int8, value != 0 else { return nil }
                return UInt8(value)
            }
        let identifier = String(bytes: machine, encoding: .utf8) ?? ""
        if identifier == "x86_64" || identifier == "arm64" {
            return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]
        }
        return identifier.isEmpty ? nil : identifier
    }
}
