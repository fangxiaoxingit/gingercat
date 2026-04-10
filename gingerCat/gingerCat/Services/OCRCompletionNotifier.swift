import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif
#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
enum OCRCompletionNotifier {
    static func notify(record: ScanRecord) async {
        #if canImport(UIKit)
        // 只在用户不在前台时发送系统级提醒，避免和当前页面的即时反馈重复。
        guard UIApplication.shared.applicationState != .active else { return }
        #endif

        let title = completionTitle(for: record)
        let summary = completionSummary(for: record)
        let dateText = completionDateText(for: record)

        if await OCRDynamicIslandService.showIfAvailable(
            recordID: record.id,
            title: title,
            summary: summary,
            dateText: dateText
        ) {
            return
        }

        await OCRLocalNotificationService.notify(
            recordID: record.id,
            title: title,
            summary: summary,
            dateText: dateText
        )
    }

    static func notifyAISummaryFailure(record: ScanRecord) async {
        #if canImport(UIKit)
        guard UIApplication.shared.applicationState != .active else { return }
        #endif

        let title = completionTitle(for: record)
        let dateText = completionDateText(for: record)

        await OCRLocalNotificationService.notifyAISummaryFailure(
            recordID: record.id,
            title: title,
            dateText: dateText
        )
    }

    static func completionTitle(for record: ScanRecord) -> String {
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
}

private enum OCRLocalNotificationService {
    static func notify(
        recordID: UUID,
        title: String,
        summary: String,
        dateText: String
    ) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "识别完成")
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

private enum OCRDynamicIslandService {
    static func showIfAvailable(
        recordID: UUID,
        title: String,
        summary: String,
        dateText: String
    ) async -> Bool {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            // 先保证系统允许 Live Activities，再按设备能力决定是否尝试灵动岛展示。
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                return false
            }
            guard DynamicIslandCapability.isSupported else { return false }

            let attributes = OCRLiveActivityAttributes(recordID: recordID.uuidString)
            let state = OCRLiveActivityAttributes.ContentState(
                title: title,
                summary: summary,
                dateText: dateText
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
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    await activity.end(content, dismissalPolicy: .default)
                }
                return true
            } catch {
                return false
            }
        }
        #endif
        return false
    }
}

private enum DynamicIslandCapability {
    static var isSupported: Bool {
        #if canImport(UIKit)
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }

        // 运行时优先用安全区高度判断灵动岛能力，避免新机型因硬编码列表缺失被误判成不支持。
        if let topInset = topSafeAreaInset {
            return topInset >= 51
        }

        // 没有可用窗口时回退到机型表，仍保持老机型稳定回落通知。
        if let hardwareIdentifier = HardwareIdentifier.current,
           dynamicIslandIdentifiers.contains(hardwareIdentifier) {
            return true
        }
        #endif
        return false
    }

    // 覆盖已发布的灵动岛机型；未知机型默认回落系统通知，避免误判导致提醒丢失。
    private static let dynamicIslandIdentifiers: Set<String> = [
        "iPhone15,2", "iPhone15,3",
        "iPhone15,4", "iPhone15,5",
        "iPhone16,1", "iPhone16,2",
        "iPhone17,1", "iPhone17,2", "iPhone17,3", "iPhone17,4"
    ]

    #if canImport(UIKit)
    private static var topSafeAreaInset: CGFloat? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let candidateWindows = scenes.flatMap(\.windows)
        if let keyWindow = candidateWindows.first(where: \.isKeyWindow) {
            return keyWindow.safeAreaInsets.top
        }
        return candidateWindows.first?.safeAreaInsets.top
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
