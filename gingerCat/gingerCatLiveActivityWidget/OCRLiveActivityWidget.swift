import ActivityKit
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 16.1, *)
struct OCRLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OCRLiveActivityAttributes.self) { context in
            lockScreenView(for: context)
                .activityBackgroundTint(Color.black.opacity(0.82))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(recordURL(for: context.attributes.recordID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.state.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(context.state.summary)
                            .font(.subheadline)
                            .lineLimit(2)
                        Text(context.state.dateText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                }
            } compactLeading: {
                Image(systemName: "sparkles.rectangle.stack")
                    .foregroundStyle(.white)
            } compactTrailing: {
                Text(String(context.state.title.prefix(4)))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: "sparkles")
                    .foregroundStyle(.white)
            }
            .widgetURL(recordURL(for: context.attributes.recordID))
            .keylineTint(.white)
        }
    }

    // 灵动岛与锁屏展示保持同一份文案结构，用户点击后统一回到对应记录详情。
    @ViewBuilder
    private func lockScreenView(
        for context: ActivityViewContext<OCRLiveActivityAttributes>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(context.state.title)
                .font(.headline)
                .lineLimit(1)
                .foregroundStyle(.white)

            Text(context.state.summary)
                .font(.subheadline)
                .lineLimit(2)
                .foregroundStyle(Color.white.opacity(0.92))

            Text(context.state.dateText)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func recordURL(for recordID: String) -> URL? {
        URL(string: "gingercat://record/\(recordID)")
    }
}
