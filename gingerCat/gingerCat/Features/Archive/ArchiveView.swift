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
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(rowCardBorderColor, lineWidth: 1)
                                )
                                .shadow(color: rowCardShadowColor, radius: 8, x: 0, y: 4)
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        delete(record)
                    } label: {
                        Label(String(localized: "删除"), systemImage: "trash")
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
            (record.eventDescription ?? "").localizedCaseInsensitiveContains(searchText) ||
            (record.eventTitle ?? "").localizedCaseInsensitiveContains(searchText) ||
            record.eventKeywordsText.localizedCaseInsensitiveContains(searchText) ||
            record.note.localizedCaseInsensitiveContains(searchText)
        }
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

    private var rowCardBorderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.05)
    }

    private var rowCardShadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.16)
            : Color.black.opacity(0.04)
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
                    Text(AppDateTimeFormatter.string(from: record.eventDate ?? record.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)

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
        let description = (record.eventDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if description.isEmpty == false {
            return description
        }
        let summary = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? String(localized: "正在识别内容...") : summary
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
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.secondary)
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
