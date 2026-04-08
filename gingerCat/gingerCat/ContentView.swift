import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage(KimiSettingsKeys.appearanceMode) private var appearanceModeRaw = AppearanceMode.automatic.rawValue
    
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
    }
}

#Preview {
    ContentView()
        .modelContainer(for: ScanRecord.self, inMemory: true)
}
