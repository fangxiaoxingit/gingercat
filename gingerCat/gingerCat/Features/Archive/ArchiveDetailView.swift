import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

struct ArchiveDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var record: ScanRecord
    @State private var isImagePreviewPresented = false
    @State private var isSavingReminder = false
    @State private var reminderFeedback: ReminderFeedback?
    @State private var isReminderEditorPresented = false
    @State private var reminderDraft = ReminderDraft.empty
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        ZStack {
            LiquidBackground()

            ScrollView {
                if #available(iOS 26, *) {
                    GlassEffectContainer(spacing: 14) {
                        detailSections
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                } else {
                    detailSections
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                }
            }
        }
        .navigationTitle(String(localized: "记录详情"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        reminderDraft = ReminderDraft(record: record)
                        isReminderEditorPresented = true
                    } label: {
                        Label(String(localized: "加入待办事项"), systemImage: "checklist")
                    }

                    Button(role: .destructive) {
                        isDeleteConfirmationPresented = true
                    } label: {
                        Label(String(localized: "删除"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3.weight(.semibold))
                }
            }
        }
        .fullScreenCover(isPresented: $isImagePreviewPresented) {
            if let image = resolvedImage {
                ArchiveImagePreviewView(image: image, isPresented: $isImagePreviewPresented)
            }
        }
        .sheet(isPresented: $isReminderEditorPresented) {
            ReminderDraftEditorView(
                draft: $reminderDraft,
                isSaving: isSavingReminder,
                onCancel: {
                    isReminderEditorPresented = false
                },
                onSave: {
                    Task {
                        await saveReminderDraft()
                    }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            String(localized: "确认删除这条记录？"),
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(String(localized: "删除"), role: .destructive) {
                deleteRecord()
            }
            Button(String(localized: "取消"), role: .cancel) {}
        } message: {
            Text(String(localized: "删除后无法恢复。"))
        }
        .alert(item: $reminderFeedback) { feedback in
            Alert(
                title: Text(feedback.title),
                message: Text(feedback.message),
                dismissButton: .default(Text(String(localized: "知道了")))
            )
        }
    }

    private var detailSections: some View {
        VStack(alignment: .leading, spacing: 14) {
            imageHeroSection
            summaryCard
            recognitionCard
            noteCard
        }
    }

    private var imageHeroSection: some View {
        Group {
            if let image = resolvedImage {
                Button {
                    isImagePreviewPresented = true
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .aspectRatio(4.0 / 3.0, contentMode: .fit)
                            .clipped()

                        Label(String(localized: "查看大图"), systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(12)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemBackground))
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text(String(localized: "暂无图片"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
            }
        }
    }

    private var summaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(String(localized: "摘要信息"), systemImage: "text.quote")
                    .font(.headline)
                Text(record.summary)
                    .font(.body)
                Divider()
                LabeledContent(String(localized: "来源"), value: record.source)
                LabeledContent(String(localized: "创建时间")) {
                    Text(record.createdAt, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                }
            }
        }
    }

    private var recognitionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(String(localized: "识别结果"), systemImage: "checkmark.seal")
                    .font(.headline)

                Text(record.recognizedText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)

                Divider()

                LabeledContent(String(localized: "模式"), value: record.resolvedIntent == .schedule ? String(localized: "日程") : String(localized: "总结"))
                LabeledContent(String(localized: "事件时间")) {
                    if let eventDate = record.eventDate {
                        Text(eventDate, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                    } else {
                        Text(String(localized: "无"))
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent(String(localized: "事件标题"), value: record.eventTitle ?? String(localized: "无"))
            }
        }
    }

    private var noteCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(String(localized: "备注"), systemImage: "square.and.pencil")
                    .font(.headline)
                TextEditor(text: $record.note)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
        }
    }

    private var resolvedImage: UIImage? {
        #if canImport(UIKit)
        guard let data = record.imageData else { return nil }
        return UIImage(data: data)
        #else
        return nil
        #endif
    }

    private func saveReminderDraft() async {
        guard isSavingReminder == false else { return }
        isSavingReminder = true
        defer { isSavingReminder = false }

        do {
            try await ReminderService.shared.addReminder(
                title: reminderDraft.title,
                notes: reminderDraft.notes,
                dueDate: reminderDraft.hasDueDate ? reminderDraft.dueDate : nil
            )
            isReminderEditorPresented = false
            reminderFeedback = ReminderFeedback(
                title: String(localized: "添加成功"),
                message: String(localized: "已加入系统提醒事项，你可以前往提醒事项 App 查看。")
            )
        } catch let error as ReminderServiceError {
            reminderFeedback = ReminderFeedback(
                title: String(localized: "添加失败"),
                message: error.localizedDescription
            )
        } catch {
            reminderFeedback = ReminderFeedback(
                title: String(localized: "添加失败"),
                message: error.localizedDescription
            )
        }
    }

    private func deleteRecord() {
        modelContext.delete(record)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        ArchiveDetailView(record: ScanRecord.previewData()[0])
    }
}

private struct ArchiveImagePreviewView: View {
    let image: UIImage
    @Binding var isPresented: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(.horizontal, 16)
                .padding(.vertical, 40)
                .onTapGesture {
                    isPresented = false
                }

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(20)
            }
        }
    }
}

private struct ReminderFeedback: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct ReminderDraft {
    var title: String
    var notes: String
    var dueDate: Date
    var hasDueDate: Bool

    init(title: String, notes: String, dueDate: Date, hasDueDate: Bool) {
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.hasDueDate = hasDueDate
    }

    static let empty = ReminderDraft(
        title: "",
        notes: "",
        dueDate: .now,
        hasDueDate: true
    )

    init(record: ScanRecord) {
        let resolvedTitle: String
        if let eventTitle = record.eventTitle?.trimmingCharacters(in: .whitespacesAndNewlines), eventTitle.isEmpty == false {
            resolvedTitle = eventTitle
        } else {
            let fallback = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            resolvedTitle = fallback.isEmpty ? String(localized: "识别记录提醒") : String(fallback.prefix(40))
        }

        var noteLines: [String] = []
        let note = record.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if note.isEmpty == false {
            noteLines.append(note)
        }
        noteLines.append(String(localized: "摘要：\(record.summary)"))

        self.title = resolvedTitle
        self.notes = noteLines.joined(separator: "\n")
        self.dueDate = record.eventDate ?? Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        self.hasDueDate = true
    }
}

private struct ReminderDraftEditorView: View {
    @Binding var draft: ReminderDraft
    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "待办内容")) {
                    TextField(String(localized: "标题"), text: $draft.title)
                    TextField(String(localized: "备注"), text: $draft.notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section(String(localized: "时间")) {
                    Toggle(String(localized: "设置提醒时间"), isOn: $draft.hasDueDate)
                    if draft.hasDueDate {
                        DatePicker(
                            String(localized: "日期时间"),
                            selection: $draft.dueDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }
            }
            .navigationTitle(String(localized: "加入待办事项"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "取消")) {
                        onCancel()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSave()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(String(localized: "确认添加"))
                        }
                    }
                    .disabled(isSaving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
