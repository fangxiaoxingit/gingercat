import SwiftUI
import WidgetKit
#if canImport(UIKit)
import UIKit
#endif

private enum TodoWidgetSharedConfig {
    static let appGroupIdentifier = "group.com.siyufang.LivePhotoMakerUniversal.gingerCat"
    static let snapshotKey = "widget.todo.snapshot.v1"
    static let latestTodoWidgetKind = "gingercat.todo.latest.small"
    static let recentTodoWidgetKind = "gingercat.todo.recent.medium"

    static let themeColor = Color(
        uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 83.0 / 255.0, green: 183.0 / 255.0, blue: 98.0 / 255.0, alpha: 1.0)
                : UIColor(red: 52.0 / 255.0, green: 103.0 / 255.0, blue: 57.0 / 255.0, alpha: 1.0)
        }
    )
}

private struct TodoWidgetSnapshotPayload: Codable {
    let updatedAt: Date
    let items: [TodoWidgetSnapshotItemPayload]

    static let empty = TodoWidgetSnapshotPayload(updatedAt: .distantPast, items: [])
}

private struct TodoWidgetSnapshotItemPayload: Codable, Hashable, Identifiable {
    let id: String
    let recordID: UUID
    let title: String
    let dueDate: Date
    let usesImageBackground: Bool
    let backgroundImageDataBase64: String?
}

private struct TodoWidgetsEntry: TimelineEntry {
    let date: Date
    let payload: TodoWidgetSnapshotPayload
}

private struct TodoWidgetsProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoWidgetsEntry {
        TodoWidgetsEntry(
            date: .now,
            payload: TodoWidgetSnapshotPayload(
                updatedAt: .now,
                items: [
                    TodoWidgetSnapshotItemPayload(
                        id: "placeholder",
                        recordID: UUID(),
                        title: String(localized: "准备上线海报"),
                        dueDate: Calendar.current.date(byAdding: .hour, value: 2, to: .now) ?? .now,
                        usesImageBackground: false,
                        backgroundImageDataBase64: nil
                    )
                ]
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TodoWidgetsEntry) -> Void) {
        completion(TodoWidgetsEntry(date: .now, payload: loadPayload()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoWidgetsEntry>) -> Void) {
        let entry = TodoWidgetsEntry(date: .now, payload: loadPayload())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 20, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func loadPayload() -> TodoWidgetSnapshotPayload {
        guard let defaults = UserDefaults(suiteName: TodoWidgetSharedConfig.appGroupIdentifier),
              let data = defaults.data(forKey: TodoWidgetSharedConfig.snapshotKey),
              let payload = try? JSONDecoder().decode(TodoWidgetSnapshotPayload.self, from: data) else {
            return .empty
        }
        return payload
    }
}

struct LatestTodoSquareWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodoWidgetSharedConfig.latestTodoWidgetKind, provider: TodoWidgetsProvider()) { entry in
            LatestTodoSquareWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "最近待办"))
        .description(String(localized: "显示最近一个待办和日期。"))
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

private struct LatestTodoSquareWidgetView: View {
    let entry: TodoWidgetsEntry
    @Environment(\.colorScheme) private var colorScheme

    private var latestItem: TodoWidgetSnapshotItemPayload? {
        entry.payload.items.first
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                topImageArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                bottomInfoStrip
                    .frame(
                        maxWidth: .infinity,
                        minHeight: min(bottomPanelHeight, geometry.size.height),
                        maxHeight: min(bottomPanelHeight, geometry.size.height),
                        alignment: .topLeading
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
        .widgetURL(latestItem.flatMap(recordURL(for:)))
    }

    private var topImageArea: some View {
        squareBackground
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }

    private var bottomInfoStrip: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let latestItem {
                Text(latestItem.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TodoWidgetSharedConfig.themeColor)
                    .lineLimit(2)
                Text(widgetDateText(for: latestItem.dueDate))
                    .font(.caption2)
                    .foregroundStyle(Color.black.opacity(0.62))
                    .lineLimit(1)
            } else {
                Text(String(localized: "暂无待办"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TodoWidgetSharedConfig.themeColor)
                    .lineLimit(1)
                Text(String(localized: "等待新提醒"))
                    .font(.caption2)
                    .foregroundStyle(Color.black.opacity(0.62))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Color.white.opacity(colorScheme == .dark ? 0.20 : 0.36))
            }
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
        )
    }

    @ViewBuilder
    private var squareBackground: some View {
        if let image = latestBackgroundImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        TodoWidgetSharedConfig.themeColor.opacity(0.95),
                        TodoWidgetSharedConfig.themeColor.opacity(0.72)
                    ]
                    : [
                        TodoWidgetSharedConfig.themeColor.opacity(0.94),
                        TodoWidgetSharedConfig.themeColor.opacity(0.76)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func recordURL(for item: TodoWidgetSnapshotItemPayload) -> URL? {
        URL(string: "gingercat://record/\(item.recordID.uuidString)")
    }

    private var latestBackgroundImage: UIImage? {
        guard let latestItem,
              latestItem.usesImageBackground,
              let base64 = latestItem.backgroundImageDataBase64,
              let data = Data(base64Encoded: base64) else {
            return nil
        }
        return UIImage(data: data)
    }

    private var bottomPanelHeight: CGFloat {
        62
    }
}

struct RecentTodosMediumWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodoWidgetSharedConfig.recentTodoWidgetKind, provider: TodoWidgetsProvider()) { entry in
            RecentTodosMediumWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "待办列表"))
        .description(String(localized: "显示最近三个待办标题。"))
        .supportedFamilies([.systemMedium])
    }
}

private struct RecentTodosMediumWidgetView: View {
    let entry: TodoWidgetsEntry
    @Environment(\.colorScheme) private var colorScheme

    private var topItems: [TodoWidgetSnapshotItemPayload] {
        Array(entry.payload.items.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "最近待办"))
                .font(.headline.weight(.bold))
                .foregroundStyle(TodoWidgetSharedConfig.themeColor)
                .padding(.top, 4)

            if topItems.isEmpty {
                Text(String(localized: "暂无待办事项"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(topItems) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(TodoWidgetSharedConfig.themeColor)
                                .lineLimit(1)
                            Text(widgetDateText(for: item.dueDate))
                                .font(.caption2)
                                .foregroundStyle(dateSecondaryColor)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            Color(uiColor: colorScheme == .dark ? .secondarySystemBackground : .white)
        }
        .widgetURL(topItems.first.flatMap(recordURL(for:)))
    }

    private func recordURL(for item: TodoWidgetSnapshotItemPayload) -> URL? {
        URL(string: "gingercat://record/\(item.recordID.uuidString)")
    }

    private var dateSecondaryColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.58) : Color.gray.opacity(0.82)
    }
}

private func widgetDateText(for date: Date) -> String {
    TodoWidgetDateFormatter.shared.string(from: date)
}

private enum TodoWidgetDateFormatter {
    static let shared: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
