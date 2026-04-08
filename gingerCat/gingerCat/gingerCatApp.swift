import SwiftUI
import SwiftData
import UserNotifications
import Combine
#if canImport(UIKit)
import UIKit
#endif

@main
struct gingerCatApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppNotificationDelegate.self) private var appNotificationDelegate
    #endif

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
        }
        .modelContainer(sharedModelContainer)
    }
}

@MainActor
final class RecordNavigationCenter: ObservableObject {
    static let shared = RecordNavigationCenter()

    @Published var pendingRecordID: UUID?

    private init() {}

    func openRecordDetail(recordID: UUID) {
        pendingRecordID = recordID
    }

    func consumePendingRecordID() {
        pendingRecordID = nil
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
        guard let rawID = response.notification.request.content.userInfo["recordID"] as? String,
              let recordID = UUID(uuidString: rawID) else {
            return
        }

        await MainActor.run {
            RecordNavigationCenter.shared.openRecordDetail(recordID: recordID)
        }
    }
}
#endif
