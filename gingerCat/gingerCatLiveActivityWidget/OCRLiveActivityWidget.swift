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
                    if context.state.isPickupPriority == false {
                        expandedLeadingView(for: context)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isPickupPriority == false {
                        expandedTrailingView(for: context)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isPickupPriority {
                        expandedPickupBottomView(for: context)
                    } else {
                        expandedBottomView(for: context)
                    }
                }
            } compactLeading: {
                Image(systemName: iconName(for: context.state))
                    .foregroundStyle(.white)
            } compactTrailing: {
                Text(compactTrailingText(for: context.state))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: iconName(for: context.state))
                    .foregroundStyle(.white)
            }
            .keylineTint(.white)
        }
    }

    private func recordURL(for recordID: String) -> URL? {
        URL(string: "gingercat://record/\(recordID)")
    }

    @ViewBuilder
    private func lockScreenView(
        for context: ActivityViewContext<OCRLiveActivityAttributes>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(context.state.title)
                .font(.headline)
                .lineLimit(1)
                .foregroundStyle(.white)

            if context.state.isPickupPriority {
                Text(resolvedPickupCodeLine(for: context.state))
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .foregroundStyle(.white)

                Text(resolvedPickupItemLine(for: context.state))
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(Color.white.opacity(0.92))

                HStack(spacing: 8) {
                    Text(context.state.pickupCategory ?? String(localized: "其他"))
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.78))
                    if let pickupDateTime = pickupDateTimeText(for: context.state) {
                        Text(pickupDateTime)
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.72))
                    }
                }

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

                Text(context.state.dateText)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.72))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func compactTrailingText(for state: OCRLiveActivityAttributes.ContentState) -> String {
        if state.isPickupPriority {
            return state.pickupCategory ?? String(localized: "其他")
        }
        return String(state.title.prefix(4))
    }

    @ViewBuilder
    private func expandedLeadingView(
        for context: ActivityViewContext<OCRLiveActivityAttributes>
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: iconName(for: context.state))
                .foregroundStyle(.white)
            Text(context.state.isPickupPriority ? String(localized: "取件提醒") : String(localized: "识别完成"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private func expandedPickupBottomView(
        for context: ActivityViewContext<OCRLiveActivityAttributes>
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: iconName(for: context.state))
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 6) {
                Text(resolvedPickupCodeLine(for: context.state))
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.white)

                Text(resolvedPickupItemLine(for: context.state))
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(Color.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func expandedTrailingView(
        for context: ActivityViewContext<OCRLiveActivityAttributes>
    ) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            if context.state.isPickupPriority {
                Text(context.state.pickupCategory ?? String(localized: "其他"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                if context.state.pickupExtraCount > 0 {
                    Text(String(localized: "+\(context.state.pickupExtraCount)"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
            } else {
                Text(context.state.dateText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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

            Text(context.state.summary)
                .font(.subheadline)
                .lineLimit(2)
                .foregroundStyle(.white.opacity(0.92))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func iconName(for state: OCRLiveActivityAttributes.ContentState) -> String {
        guard state.isPickupPriority else {
            return "sparkles.rectangle.stack"
        }
        switch state.pickupCategory {
        case "咖啡":
            return "cup.and.saucer.fill"
        case "饮品":
            return "takeoutbag.and.cup.and.straw.fill"
        case "快递":
            return "truck.box.fill"
        default:
            return "shippingbox.fill"
        }
    }

    private func pickupDateTimeText(for state: OCRLiveActivityAttributes.ContentState) -> String? {
        if let pickupDate = state.pickupDate, let pickupTime = state.pickupTime {
            return "\(pickupDate) \(pickupTime)"
        }
        if let pickupDate = state.pickupDate {
            return pickupDate
        }
        if let pickupTime = state.pickupTime {
            return pickupTime
        }
        return nil
    }

    private func resolvedPickupCodeLine(for state: OCRLiveActivityAttributes.ContentState) -> String {
        let label = state.pickupCodeLabel ?? String(localized: "取件码")
        let value = state.pickupCodeValue ?? String(localized: "--")
        return "\(label) \(value)"
    }

    private func resolvedPickupItemLine(for state: OCRLiveActivityAttributes.ContentState) -> String {
        if let item = state.pickupItemName?.trimmingCharacters(in: .whitespacesAndNewlines),
           item.isEmpty == false {
            return item
        }
        if let brand = state.pickupBrandName?.trimmingCharacters(in: .whitespacesAndNewlines),
           brand.isEmpty == false {
            return brand
        }
        if let category = state.pickupCategory?.trimmingCharacters(in: .whitespacesAndNewlines),
           category.isEmpty == false {
            return category
        }
        return String(localized: "其他")
    }
}
