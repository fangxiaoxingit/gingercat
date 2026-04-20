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
                DynamicIslandExpandedRegion(.leading) {
                    expandedLeadingView(for: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    expandedTrailingView(for: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expandedBottomView(for: context)
                }
            } compactLeading: {
                Image(systemName: "sparkles.rectangle.stack")
                    .foregroundStyle(.white)
            } compactTrailing: {
                Text(compactTrailingText(for: context.state))
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

            if context.state.isPickupPriority, let pickupText = context.state.pickupText {
                Text(pickupText)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                if context.state.pickupExtraCount > 0 {
                    Text(String(localized: "另有 \(context.state.pickupExtraCount) 个取件码"))
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.72))
                }
            } else {
                Text(context.state.summary)
                    .font(.subheadline)
                    .lineLimit(2)
                    .foregroundStyle(Color.white.opacity(0.92))
            }

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

    private func compactTrailingText(for state: OCRLiveActivityAttributes.ContentState) -> String {
        if state.isPickupPriority, let pickupText = state.pickupText {
            let segments = pickupText.split(separator: " ")
            if let last = segments.last {
                return String(last.prefix(4))
            }
        }
        return String(state.title.prefix(4))
    }

    @ViewBuilder
    private func expandedLeadingView(
        for context: ActivityViewContext<OCRLiveActivityAttributes>
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: context.state.isPickupPriority ? "shippingbox.fill" : "sparkles")
                .foregroundStyle(.white)
            Text(context.state.isPickupPriority ? String(localized: "取件提醒") : String(localized: "识别完成"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private func expandedTrailingView(
        for context: ActivityViewContext<OCRLiveActivityAttributes>
    ) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(context.state.dateText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if context.state.isPickupPriority, context.state.pickupExtraCount > 0 {
                Text(String(localized: "+\(context.state.pickupExtraCount)"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder
    private func expandedBottomView(
        for context: ActivityViewContext<OCRLiveActivityAttributes>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(context.state.title)
                .font(.headline)
                .lineLimit(1)
                .foregroundStyle(.white)

            if context.state.isPickupPriority, let pickupText = context.state.pickupText {
                Text(pickupText)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                if context.state.pickupExtraCount > 0 {
                    Text(String(localized: "另有 \(context.state.pickupExtraCount) 个取件码"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text(context.state.summary)
                    .font(.subheadline)
                    .lineLimit(2)
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
