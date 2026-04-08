import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

struct ArchiveView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScanRecord.createdAt, order: .reverse) private var records: [ScanRecord]

    @AppStorage(KimiSettingsKeys.haptics) private var hapticsEnabled = true

    @State private var searchText = ""
    @State private var selectedRecord: ScanRecord?

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
        .navigationTitle(String(localized: "历史记录"))
        .searchable(text: $searchText, prompt: String(localized: "搜索摘要或备注"))
        .navigationDestination(item: $selectedRecord) { record in
            ArchiveDetailView(record: record)
        }
    }

    private var listContainer: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(filteredRecords) { record in
                    SwipeableRow(
                        record: record,
                        onSelect: {
                            triggerHaptic()
                            selectedRecord = record
                        },
                        onDelete: {
                            delete(record)
                        }
                    )
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func triggerHaptic() {
        guard hapticsEnabled else { return }
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred()
        #endif
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            String(localized: "暂无记录"),
            systemImage: "tray",
            description: Text(String(localized: "可通过主页扫描创建记录，或调整搜索关键词。"))
        )
    }

    private var filteredRecords: [ScanRecord] {
        guard searchText.isEmpty == false else {
            return records
        }

        return records.filter { record in
            record.summary.localizedCaseInsensitiveContains(searchText) ||
            record.note.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func delete(_ record: ScanRecord) {
        withAnimation {
            modelContext.delete(record)
        }
    }
}

private struct SwipeableRow: View {
    let record: ScanRecord
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var isSwiped: Bool = false

    private let buttonWidth: CGFloat = 80

    var body: some View {
        ZStack {
            // 背景删除按钮
            HStack {
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: buttonWidth)
                        .frame(maxHeight: .infinity)
                        .background(Color.red)
                }
                .buttonStyle(.plain)
            }

            // 前景内容
            Button(action: onSelect) {
                ArchiveRowContent(record: record)
            }
            .buttonStyle(.plain)
            .background(.white)
            .offset(x: offset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onChanged { value in
                        // 只响应水平滑动
                        if abs(value.translation.width) > abs(value.translation.height) {
                            let translation = value.translation.width
                            if translation < 0 {
                                // 向左滑动，限制最大滑动距离
                                offset = max(translation, -buttonWidth)
                            } else if isSwiped {
                                // 向右滑动恢复
                                offset = min(translation - buttonWidth, 0)
                            }
                        }
                    }
                    .onEnded { value in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            let translation = value.translation.width
                            let velocity = value.predictedEndLocation.x - value.location.x

                            // 根据滑动距离或速度决定是否打开/关闭
                            if translation < -buttonWidth / 2 || velocity < -200 {
                                offset = -buttonWidth
                                isSwiped = true
                            } else {
                                offset = 0
                                isSwiped = false
                            }
                        }
                    }
            )
        }
    }
}

private struct ArchiveRowContent: View {
    let record: ScanRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RecordThumbnailView(imageData: record.imageData, side: 76)

            VStack(alignment: .leading, spacing: 8) {
                Text(summaryText)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .truncationMode(.tail)

                VStack(alignment: .leading, spacing: 6) {
                    Text(record.createdAt, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        statusTag(
                            record.resolvedIntent == .schedule ? String(localized: "日程") : String(localized: "总结"),
                            background: AppTheme.primary.opacity(0.16),
                            foreground: AppTheme.primary
                        )
                        statusTag(
                            record.isOCRCompleted ? String(localized: "已 OCR") : String(localized: "待 OCR"),
                            background: record.isOCRCompleted ? Color.green.opacity(0.16) : Color.orange.opacity(0.18),
                            foreground: record.isOCRCompleted ? .green : .orange
                        )
                        statusTag(
                            record.usedAISummary ? String(localized: "AI 摘要") : String(localized: "本地摘要"),
                            background: record.usedAISummary ? Color.blue.opacity(0.16) : Color.gray.opacity(0.18),
                            foreground: record.usedAISummary ? .blue : .secondary
                        )
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
        let trimmed = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "正在识别内容...") : trimmed
    }

    private func statusTag(_ text: String, background: Color, foreground: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background, in: Capsule())
    }
}

private struct RecordThumbnailView: View {
    let imageData: Data?
    let side: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(uiColor: .tertiarySystemBackground))
            .overlay {
                if let image = resolvedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var resolvedImage: UIImage? {
        #if canImport(UIKit)
        guard let imageData else { return nil }
        return UIImage(data: imageData)
        #else
        return nil
        #endif
    }
}

#Preview {
    NavigationStack {
        ArchiveView()
            .modelContainer(for: ScanRecord.self, inMemory: true)
    }
}
