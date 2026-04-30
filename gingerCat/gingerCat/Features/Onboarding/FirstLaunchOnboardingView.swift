import SwiftUI

struct FirstLaunchOnboardingView: View {
    @Binding var isPresented: Bool

    @State private var currentPage = 0

    private var sections: [AppUsageGuideSectionContent] {
        AppUsageGuideContent.sections()
    }

    var body: some View {
        ZStack {
            LiquidBackground()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 6)
                    .padding(.horizontal, 18)

                TabView(selection: $currentPage) {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        page(section: section, index: index)
                            .tag(index)
                            .padding(.horizontal, 28)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                bottomBar
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
            }
        }
        .interactiveDismissDisabled(true)
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button(String(appLocalized: "跳过")) {
                completeOnboarding()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .frame(height: 44)
    }

    private func page(section: AppUsageGuideSectionContent, index: Int) -> some View {
        let pageText = String(
            format: String(appLocalized: "第 %d/%d 页"),
            index + 1,
            sections.count
        )

        return VStack(spacing: 20) {
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(AppTheme.primary.opacity(0.12))
                    .frame(width: 136, height: 136)

                Image(systemName: section.iconName)
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
            }

            Text(section.title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(section.points.joined(separator: "  "))
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(pageText)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Button {
                if currentPage == sections.count - 1 {
                    completeOnboarding()
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentPage = min(currentPage + 1, sections.count - 1)
                    }
                }
            } label: {
                Text(currentPage == sections.count - 1 ? String(appLocalized: "开始使用") : String(appLocalized: "下一步"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Text(String(appLocalized: "左右滑动切换"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func completeOnboarding() {
        isPresented = false
    }
}

#Preview {
    FirstLaunchOnboardingView(isPresented: .constant(true))
}
