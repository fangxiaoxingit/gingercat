import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        HomeScannerView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: ScanRecord.self, inMemory: true)
}
