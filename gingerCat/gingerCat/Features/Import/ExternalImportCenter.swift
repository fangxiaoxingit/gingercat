import Foundation
import Combine

@MainActor
final class ExternalImportCenter: ObservableObject {
    @Published private(set) var pendingImport: QueuedExternalImageImport?
    @Published private(set) var latestErrorMessage: String?

    private let store: ExternalImageImportStore

    init(store: ExternalImageImportStore) {
        self.store = store
    }

    convenience init() {
        self.init(store: ExternalImageImportStore())
    }

    // App 每次回到前台或收到唤醒 URL 时都刷新一次共享队列，保证分享扩展与捷径都能及时落到首页。
    func refreshPendingImport() {
        do {
            guard let queuedImport = try store.consumePendingImport() else {
                return
            }

            pendingImport = queuedImport
            latestErrorMessage = nil
        } catch {
            latestErrorMessage = error.localizedDescription
        }
    }

    func clearPendingImport() {
        pendingImport = nil
    }

    func clearLatestErrorMessage() {
        latestErrorMessage = nil
    }
}
