import SwiftUI

struct LiquidBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if colorScheme == .dark {
                Color(uiColor: .systemBackground)
            } else {
                Color(uiColor: .systemGroupedBackground)
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    LiquidBackground()
}
