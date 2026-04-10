import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage(KimiSettingsKeys.appearanceMode) private var appearanceModeRaw = AppearanceMode.automatic.rawValue
    @EnvironmentObject private var externalImportCenter: ExternalImportCenter
    
    private var colorScheme: ColorScheme? {
        switch AppearanceMode(rawValue: appearanceModeRaw) ?? .automatic {
        case .automatic:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
    
    var body: some View {
        HomeScannerView()
            .preferredColorScheme(colorScheme)
            .onOpenURL { url in
                // 深链优先处理记录跳转，其次再处理导入唤醒，避免通知点击被导入分支吞掉。
                if let recordID = AppDeepLink.recordID(from: url) {
                    RecordNavigationCenter.shared.openRecordDetail(recordID: recordID)
                    return
                }
                if AppDeepLink.isImportImageURL(url) {
                    externalImportCenter.refreshPendingImport()
                }
            }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: ScanRecord.self, inMemory: true)
        .environmentObject(
            ExternalImportCenter(
                store: ExternalImageImportStore(
                    baseDirectoryProvider: {
                        FileManager.default.temporaryDirectory
                            .appending(path: "PreviewIncomingImports", directoryHint: .isDirectory)
                    }
                )
            )
        )
}
