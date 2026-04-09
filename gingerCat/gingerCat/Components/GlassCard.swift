import SwiftUI

struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private let content: Content
    private let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = 22, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(colorScheme == .dark ? Color(uiColor: .secondarySystemBackground) : .white)
            }
            // 模块之间改用阴影分层，避免统一灰边框让卡片显得生硬。
            .shadow(
                color: colorScheme == .dark ? .black.opacity(0.22) : .black.opacity(0.08),
                radius: colorScheme == .dark ? 14 : 12,
                x: 0,
                y: colorScheme == .dark ? 8 : 6
            )
    }
}

#Preview {
    ZStack {
        LiquidBackground()
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Glass Card")
                    .font(.headline)
                Text("Liquid material preview")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
