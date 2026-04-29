import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
import ImageIO
#endif

struct ArchiveView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \ScanRecord.createdAt, order: .reverse) private var records: [ScanRecord]

    @AppStorage(KimiSettingsKeys.haptics) private var hapticsEnabled = true
    @AppStorage(KimiSettingsKeys.hapticsIntensity) private var hapticsIntensityRaw = HapticFeedbackIntensity.medium.rawValue

    @State private var searchText = ""
    @State private var selectedRecord: ScanRecord?
    @State private var selectedFilter: ArchiveRecordFilter = .all

    private var hapticsIntensity: HapticFeedbackIntensity {
        HapticFeedbackIntensity(rawValue: hapticsIntensityRaw) ?? .medium
    }

    var body: some View {
        ZStack {
            LiquidBackground()

            if filteredRecords.isEmpty {
                emptyStateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.horizontal, 24)
            } else {
                listContainer
            }
        }
        .navigationTitle(String(appLocalized: "历史记录"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(String(appLocalized: "筛选条件"), selection: $selectedFilter) {
                        ForEach(ArchiveRecordFilter.allCases, id: \.self) { option in
                            Text(option.title)
                                .tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel(String(appLocalized: "更多操作"))
            }
        }
        .searchable(text: $searchText, prompt: String(appLocalized: "搜索识别内容、摘要或备注"))
        .navigationDestination(item: $selectedRecord) { record in
            ArchiveDetailView(record: record)
        }
    }

    private var listContainer: some View {
        List {
            ForEach(filteredRecords) { record in
                Button {
                    triggerHaptic()
                    selectedRecord = record
                } label: {
                    ArchiveRowContent(record: record)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(rowCardBackgroundColor)
                                .shadow(color: rowCardShadowColor, radius: 12, x: 0, y: 6)
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        delete(record)
                    } label: {
                        Label(String(appLocalized: "删除"), systemImage: "trash")
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            HStack {
                Spacer(minLength: 0)
                Text(String(appLocalized: "没有更多记录"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func triggerHaptic() {
        HapticFeedbackService.impact(enabled: hapticsEnabled, intensity: hapticsIntensity)
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            String(appLocalized: "暂无记录"),
            systemImage: "tray",
            description: Text(String(appLocalized: "可通过主页扫描创建记录，或调整搜索关键词。"))
        )
    }

    private var filteredRecords: [ScanRecord] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if keyword.isEmpty == false {
            return records.filter { matchesSearch($0, keyword: keyword) }
        }

        let now = Date()
        let calendar = Calendar.current
        return records.filter { record in
            switch selectedFilter {
            case .all:
                return true
            case .notAdded:
                return isTodoRecord(record) && hasAddedReminder(record) == false
            case .added:
                return isTodoRecord(record) && hasAddedReminder(record)
            case .expired:
                return isExpiredTodoRecord(record, now: now, calendar: calendar)
            case .notExpired:
                return isNotExpiredTodoRecord(record, now: now, calendar: calendar)
            case .recent7Days:
                guard let startDate = calendar.date(byAdding: .day, value: -7, to: now) else {
                    return true
                }
                return record.createdAt >= startDate
            case .recentMonth:
                guard let startDate = calendar.date(byAdding: .month, value: -1, to: now) else {
                    return true
                }
                return record.createdAt >= startDate
            }
        }
    }

    private func matchesSearch(_ record: ScanRecord, keyword: String) -> Bool {
        record.summary.localizedCaseInsensitiveContains(keyword) ||
        (record.eventDescription ?? "").localizedCaseInsensitiveContains(keyword) ||
        (record.eventTitle ?? "").localizedCaseInsensitiveContains(keyword) ||
        record.eventKeywordsText.localizedCaseInsensitiveContains(keyword) ||
        record.pickupCodes.contains(where: { pickup in
            pickup.codeValue.localizedCaseInsensitiveContains(keyword) ||
            pickup.resolvedBrandName.localizedCaseInsensitiveContains(keyword) ||
            pickup.resolvedItemName.localizedCaseInsensitiveContains(keyword) ||
            pickup.category.displayName.localizedCaseInsensitiveContains(keyword)
        }) ||
        record.note.localizedCaseInsensitiveContains(keyword)
    }

    private func isTodoRecord(_ record: ScanRecord) -> Bool {
        if record.todoEvents.contains(where: { $0.needTodo }) {
            return true
        }
        return record.needTodo || record.resolvedIntent == .schedule
    }

    private func hasAddedReminder(_ record: ScanRecord) -> Bool {
        if record.addedTodoEventKeys.isEmpty == false {
            return true
        }
        return record.hasAddedTodoReminder
    }

    private func isExpiredTodoRecord(_ record: ScanRecord, now: Date, calendar: Calendar) -> Bool {
        guard isTodoRecord(record) else { return false }
        let dueDates = todoDueDates(for: record)
        guard dueDates.isEmpty == false else { return false }
        let todayStart = calendar.startOfDay(for: now)
        return dueDates.allSatisfy { $0 < todayStart }
    }

    private func isNotExpiredTodoRecord(_ record: ScanRecord, now: Date, calendar: Calendar) -> Bool {
        guard isTodoRecord(record) else { return false }
        let dueDates = todoDueDates(for: record)
        guard dueDates.isEmpty == false else { return false }
        let todayStart = calendar.startOfDay(for: now)
        return dueDates.contains { $0 >= todayStart }
    }

    private func todoDueDates(for record: ScanRecord) -> [Date] {
        let eventDates = record.todoEvents
            .filter(\.needTodo)
            .map(\.date)

        if eventDates.isEmpty == false {
            return eventDates.sorted()
        }

        if record.needTodo || record.resolvedIntent == .schedule,
           let eventDate = record.eventDate {
            return [eventDate]
        }

        return []
    }

    private func delete(_ record: ScanRecord) {
        withAnimation {
            modelContext.delete(record)
            try? modelContext.save()
        }
    }

    private var rowCardBackgroundColor: Color {
        colorScheme == .dark
            ? Color(uiColor: .secondarySystemBackground)
            : .white
    }

    private var rowCardShadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.22)
            : Color.black.opacity(0.08)
    }
}

private enum ArchiveRecordFilter: CaseIterable {
    case all
    case notAdded
    case added
    case notExpired
    case expired
    case recent7Days
    case recentMonth

    var title: String {
        switch self {
        case .all:
            return String(appLocalized: "全部记录")
        case .notAdded:
            return String(appLocalized: "未添加")
        case .added:
            return String(appLocalized: "已添加")
        case .notExpired:
            return String(appLocalized: "未过期")
        case .expired:
            return String(appLocalized: "已过期")
        case .recent7Days:
            return String(appLocalized: "最近 7 天")
        case .recentMonth:
            return String(appLocalized: "最近一个月")
        }
    }
}

private struct ArchiveRowContent: View {
    let record: ScanRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RecordThumbnailView(cacheKey: record.id, imageData: record.imageData, side: 76)

            VStack(alignment: .leading, spacing: 8) {
                Text(summaryText)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .truncationMode(.tail)

                VStack(alignment: .leading, spacing: 6) {
                    metaInfoLine

                    if record.eventKeywords.isEmpty == false {
                        keywordTags
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var summaryText: String {
        if let primaryPickupCode = record.primaryPickupCode {
            return primaryPickupCode.summaryText
        }

        let title = (record.eventTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty == false {
            return title
        }

        let todoTitle = record.todoEvents
            .sorted { lhs, rhs in
                lhs.date < rhs.date
            }
            .compactMap { event -> String? in
                let trimmed = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .first
        if let todoTitle {
            return todoTitle
        }

        let summary = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? String(appLocalized: "正在识别内容...") : summary
    }

    private var metaInfoLine: some View {
        HStack(spacing: 8) {
            if isPickupRecord {
                Text(AppDateTimeFormatter.string(from: displayedDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(appLocalized: "取件 \(record.pickupCodes.count) 条"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primary)
            } else if isTodoRecord {
                Text(String(appLocalized: "待办时间：\(AppDateTimeFormatter.string(from: displayedDate))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let todoStatusText {
                    Text(todoStatusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(hasAddedTodoReminder ? AppTheme.primary : AppTheme.primaryDark)
                }
            } else {
                Text(AppDateTimeFormatter.string(from: displayedDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isTodoRecord: Bool {
        if record.todoEvents.contains(where: { $0.needTodo }) {
            return true
        }
        return record.needTodo
    }

    private var isPickupRecord: Bool {
        record.pickupCodes.isEmpty == false
    }

    private var hasAddedTodoReminder: Bool {
        if record.addedTodoEventKeys.isEmpty == false {
            return true
        }
        return record.hasAddedTodoReminder
    }

    private var todoStatusText: String? {
        guard isTodoRecord else { return nil }
        return hasAddedTodoReminder
            ? String(appLocalized: "已添加")
            : String(appLocalized: "未添加")
    }

    private var displayedDate: Date {
        if let todoDate = firstTodoDate {
            return todoDate
        }
        return record.eventDate ?? record.createdAt
    }

    private var firstTodoDate: Date? {
        let sortedTodoDates = record.todoEvents
            .filter(\.needTodo)
            .map(\.date)
            .sorted()
        if sortedTodoDates.isEmpty == false {
            let now = Date()
            return sortedTodoDates.first(where: { $0 > now }) ?? sortedTodoDates.first
        }
        if record.needTodo {
            return record.eventDate
        }
        return nil
    }

    private var keywordTags: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(record.eventKeywords.prefix(6)), id: \.self) { keyword in
                    Text(keyword)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppTheme.primary.opacity(0.12), in: Capsule())
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct RecordThumbnailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    let cacheKey: UUID
    let imageData: Data?
    let side: CGFloat
    @State private var resolvedImage: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(uiColor: .tertiarySystemBackground))
            .overlay {
                if let image = resolvedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholderIcon
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onAppear {
                loadImageIfNeeded()
            }
            .onChange(of: cacheKey) { _, _ in
                resolvedImage = nil
                loadImageIfNeeded()
        }
    }

    // 历史记录中的文字条目没有缩略图时，用文档图标与图片条目区分开。
    @ViewBuilder
    private var placeholderIcon: some View {
        if imageData == nil {
            Image(systemName: "append.page")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(AppTheme.primary.opacity(colorScheme == .dark ? 0.92 : 0.78))
        } else {
            Image(systemName: "photo")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private func loadImageIfNeeded() {
        #if canImport(UIKit)
        guard resolvedImage == nil, let imageData else { return }

        let cacheToken = cacheKey.uuidString as NSString
        if let cachedImage = ArchiveThumbnailCache.storage.object(forKey: cacheToken) {
            resolvedImage = cachedImage
            return
        }

        let maxPixel = Int(max(side * max(displayScale, 1), side))
        let decodedImage = decodeThumbnail(from: imageData, maxPixelSize: maxPixel)
        resolvedImage = decodedImage
        if let decodedImage {
            ArchiveThumbnailCache.storage.setObject(decodedImage, forKey: cacheToken)
        }
        #endif
    }
}

#if canImport(UIKit)
private enum ArchiveThumbnailCache {
    static let storage: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        return cache
    }()
}

private func decodeThumbnail(from data: Data, maxPixelSize: Int) -> UIImage? {
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        kCGImageSourceShouldCacheImmediately: true
    ]
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        return UIImage(data: data)
    }
    return UIImage(cgImage: cgImage)
}
#endif

#Preview {
    NavigationStack {
        ArchiveView()
            .modelContainer(for: ScanRecord.self, inMemory: true)
    }
}
