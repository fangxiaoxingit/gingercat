import SwiftUI
import SwiftData
import UserNotifications
import Combine
import AppIntents
#if canImport(UIKit)
import UIKit
#endif

@main
struct gingerCatApp: App {
    @Environment(\.scenePhase) private var scenePhase
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppNotificationDelegate.self) private var appNotificationDelegate
    #endif
    @StateObject private var externalImportCenter = ExternalImportCenter()

    init() {
        // 启动时刷新一次捷径参数缓存，避免新加的图片导入捷径在系统里长时间不出现。
        GingerCatShortcutsProvider.updateAppShortcutParameters()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ScanRecord.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(externalImportCenter)
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            // 分享扩展与捷径都会把图片先写进共享容器，App 回到前台时统一在这里消费即可。
            guard newPhase == .active else { return }
            PickupSchemaMigrationService.runIfNeeded(modelContainer: sharedModelContainer)
            externalImportCenter.refreshPendingImport()
        }
    }
}

@MainActor
final class RecordNavigationCenter: ObservableObject {
    static let shared = RecordNavigationCenter()

    @Published var pendingRecordID: UUID?

    private init() {}

    func openRecordDetail(recordID: UUID) {
        pendingRecordID = recordID
        NotificationRouteStore.persist(recordID: recordID)
    }

    func consumePendingRecordID() {
        pendingRecordID = nil
        NotificationRouteStore.clear()
    }

    func pendingRecordIDFromMemoryOrStore() -> UUID? {
        if let pendingRecordID {
            return pendingRecordID
        }
        if let persisted = NotificationRouteStore.peekRecordID() {
            pendingRecordID = persisted
            return persisted
        }
        return nil
    }
}

enum NotificationRouteStore {
    private static let key = "navigation.pendingRecordID"

    // 通知点击可能早于页面树就绪，先落地到本地存储，页面可见后再安全消费跳转。
    static func persist(recordID: UUID, defaults: UserDefaults = .standard) {
        defaults.set(recordID.uuidString, forKey: key)
    }

    static func peekRecordID(defaults: UserDefaults = .standard) -> UUID? {
        guard let rawValue = defaults.string(forKey: key),
              let recordID = UUID(uuidString: rawValue) else {
            return nil
        }
        return recordID
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

#if canImport(UIKit)
final class AppNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // 冷启动由通知点击进入时，先从 connection options 提前提取 recordID，避免 delegate 回调晚到导致丢跳转。
        if let notificationResponse = options.notificationResponse {
            routeToRecordIfPossible(userInfo: notificationResponse.notification.request.content.userInfo)
        }

        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.badge, .banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        routeToRecordIfPossible(userInfo: response.notification.request.content.userInfo)
    }

    private func routeToRecordIfPossible(userInfo: [AnyHashable: Any]) {
        let recordID: UUID?
        if let rawRecordURL = userInfo["recordURL"] as? String,
           let url = URL(string: rawRecordURL),
           let parsedRecordID = AppDeepLink.recordID(from: url) {
            recordID = parsedRecordID
        } else if let rawID = userInfo["recordID"] as? String,
                  let parsedRecordID = UUID(uuidString: rawID) {
            recordID = parsedRecordID
        } else {
            recordID = nil
        }

        guard let recordID else {
            return
        }

        Task { @MainActor in
            RecordNavigationCenter.shared.openRecordDetail(recordID: recordID)
        }
    }
}
#endif
