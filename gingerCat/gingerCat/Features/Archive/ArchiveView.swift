import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

struct ArchiveView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScanRecord.createdAt, order: .reverse) private var records: [ScanRecord]

    @State private var searchText = ""

    var body: some View {
        ZStack {
            LiquidBackground()

            List {
                archiveContent
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .listRowSeparator(.hidden)
            .background(Color.clear)
        }
        .navigationTitle(String(localized: "历史记录"))
        .searchable(text: $searchText, prompt: String(localized: "搜索摘要或备注"))
    }

    private var archiveContent: some View {
        Group {
            if filteredRecords.isEmpty {
                ContentUnavailableView(
                    String(localized: "暂无匹配记录"),
                    systemImage: "tray",
                    description: Text(String(localized: "可通过主页扫描创建记录，或调整搜索关键词。"))
                )
                .frame(maxWidth: .infinity, minHeight: 220)
                .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16))
                .listRowBackground(Color.clear)
            } else {
                ForEach(filteredRecords) { record in
                    NavigationLink {
                        ArchiveDetailView(record: record)
                    } label: {
                        GlassCard(cornerRadius: 18) {
                            ArchiveRow(record: record)
                                .padding(.vertical, 12)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation {
                                delete(record)
                            }
                        } label: {
                            Label(String(localized: "删除"), systemImage: "trash")
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }
        }
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

private struct ArchiveRow: View {
    let record: ScanRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RecordThumbnailView(imageData: record.imageData, side: 76)

            VStack(alignment: .leading, spacing: 8) {
                Text(record.summary)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .truncationMode(.tail)

                HStack(spacing: 8) {
                    Text(record.createdAt, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(record.resolvedIntent == .schedule ? String(localized: "日程") : String(localized: "总结"))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.primary.opacity(0.16), in: Capsule())
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
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
