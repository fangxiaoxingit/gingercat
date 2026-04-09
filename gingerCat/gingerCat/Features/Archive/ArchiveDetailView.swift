import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
import ImageIO
#endif

struct ArchiveDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppSettingsKeys.haptics) private var hapticsEnabled = true

    @Bindable var record: ScanRecord
    @State private var isImagePreviewPresented = false
    @State private var isSavingReminder = false
    @State private var isRunningLocalOCR = false
    @State private var isRunningAISummary = false
    @State private var reminderFeedback: ReminderFeedback?
    @State private var isReminderEditorPresented = false
    @State private var reminderDraft = ReminderDraft.empty
    @State private var isDeleteConfirmationPresented = false
    @State private var isRepeatTodoConfirmationPresented = false
    @State private var showRepeatTodoHintInEditor = false

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
                    if record.isOCRCompleted == false {
                        Button {
                            Task {
                                await runLocalOCR()
                            }
                        } label: {
                            Label(
                                isRunningLocalOCR ? String(localized: "本地OCR处理中...") : String(localized: "本地OCR"),
                                systemImage: "text.viewfinder"
                            )
                        }
                        .disabled(isRunningLocalOCR || isRunningAISummary)
                    }

                    if record.usedAISummary == false {
                        Button {
                            Task {
                                await runAISummary()
                            }
                        } label: {
                            Label(
                                isRunningAISummary ? String(localized: "AI摘要处理中...") : String(localized: "AI 摘要"),
                                systemImage: "sparkles"
                            )
                        }
                        .disabled(isRunningLocalOCR || isRunningAISummary)
                    }

                    Button {
                        presentReminderEditor()
                    } label: {
                        Label(
                            record.hasAddedTodoReminder ? String(localized: "再次加入待办事项") : String(localized: "加入待办事项"),
                            systemImage: "checklist"
                        )
                    }

                    Button(role: .destructive) {
                        isDeleteConfirmationPresented = true
                    } label: {
                        Label(String(localized: "删除"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
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
                showRepeatHint: showRepeatTodoHintInEditor,
                onCancel: {
                    isReminderEditorPresented = false
                    showRepeatTodoHintInEditor = false
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
        .confirmationDialog(
            String(localized: "这条记录已添加过待办事项"),
            isPresented: $isRepeatTodoConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(String(localized: "继续添加"), role: .destructive) {
                showRepeatTodoHintInEditor = true
                reminderDraft = ReminderDraft(record: record)
                isReminderEditorPresented = true
            }
            Button(String(localized: "取消"), role: .cancel) {}
        } message: {
            Text(String(localized: "继续添加会生成重复待办，请确认后再操作。"))
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
            if record.hasAddedTodoReminder {
                repeatTodoReminderBanner
            }
            mergedRecordCard
            noteCard
        }
    }

    private var imageHeroSection: some View {
        Group {
            if let image = resolvedImage {
                Button {
                    triggerHaptic()
                    isImagePreviewPresented = true
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))

                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 120)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)

                        Label(String(localized: "查看大图"), systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(12)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 120)
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
                    .frame(minHeight: 120, maxHeight: 120)
            }
        }
    }

    private var repeatTodoReminderBanner: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(String(localized: "这条记录已添加过待办事项，再次添加前请确认是否需要重复创建。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var mergedRecordCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(String(localized: "记录信息"), systemImage: "text.quote")
                    .font(.headline)

                Divider()

                LabeledContent(String(localized: "标题"), value: resolvedTitle)
                LabeledContent(String(localized: "详细内容"), value: resolvedDetailText)
                LabeledContent(String(localized: "关键词"), value: resolvedKeywords)
                LabeledContent(String(localized: "日期时间"), value: AppDateTimeFormatter.string(from: record.eventDate ?? record.createdAt))
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
        if let image = UIImage(data: data) {
            return image
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
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
            record.hasAddedTodoReminder = true
            try? modelContext.save()
            isReminderEditorPresented = false
            showRepeatTodoHintInEditor = false
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

    private func triggerHaptic() {
        guard hapticsEnabled else { return }
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred()
        #endif
    }

    private func presentReminderEditor() {
        if record.hasAddedTodoReminder {
            isRepeatTodoConfirmationPresented = true
            return
        }

        showRepeatTodoHintInEditor = false
        reminderDraft = ReminderDraft(record: record)
        isReminderEditorPresented = true
    }

    @MainActor
    private func runLocalOCR() async {
        guard isRunningLocalOCR == false else { return }
        guard let image = resolvedImage else {
            reminderFeedback = ReminderFeedback(
                title: String(localized: "本地OCR失败"),
                message: String(localized: "当前记录没有可用图片，无法执行本地OCR。")
            )
            return
        }

        isRunningLocalOCR = true
        defer { isRunningLocalOCR = false }

        do {
            let recognition = try await VisionOCRService.recognize(from: image)
            applyLocalOCRResult(recognition)
            reminderFeedback = ReminderFeedback(
                title: String(localized: "本地OCR完成"),
                message: String(localized: "已更新标题、详细内容、关键词和日期时间。")
            )
        } catch VisionOCRServiceError.noRecognizedText {
            reminderFeedback = ReminderFeedback(
                title: String(localized: "本地OCR失败"),
                message: String(localized: "未识别到可用文字，请更换更清晰的图片。")
            )
        } catch {
            reminderFeedback = ReminderFeedback(
                title: String(localized: "本地OCR失败"),
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    private func runAISummary() async {
        guard isRunningAISummary == false else { return }

        let config = AIProviderConfigStore.selectedRuntimeConfig()
        guard config.canRequestSummary else {
            reminderFeedback = ReminderFeedback(
                title: String(localized: "AI摘要失败"),
                message: String(localized: "\(config.provider.displayName) 配置不完整，请先到设置中补全 Base URL、Model 与 API Key。")
            )
            return
        }

        isRunningAISummary = true
        defer { isRunningAISummary = false }

        do {
            let recognition = try await ensureRecognitionForAI()
            let payload = InsightPayloadBuilder.build(
                source: record.source,
                recognizedText: recognition.text,
                imageData: record.imageData
            )
            let insight = try await AIProviderService.analyzeOCR(
                rawText: payload.rawText,
                config: config
            )
            applyAIResult(
                recognizedText: payload.rawText,
                localFallbackSummary: payload.summary,
                insight: insight,
                lineBoxes: recognition.lineBoxes
            )
            reminderFeedback = ReminderFeedback(
                title: String(localized: "AI摘要完成"),
                message: String(localized: "已更新标题、详细内容、关键词和日期时间。")
            )
        } catch let error as AIProviderServiceError {
            reminderFeedback = ReminderFeedback(
                title: String(localized: "AI摘要失败"),
                message: error.localizedDescription
            )
        } catch VisionOCRServiceError.noRecognizedText {
            reminderFeedback = ReminderFeedback(
                title: String(localized: "AI摘要失败"),
                message: String(localized: "执行AI摘要前未识别到可用文字，请先确保图片内容清晰。")
            )
        } catch {
            reminderFeedback = ReminderFeedback(
                title: String(localized: "AI摘要失败"),
                message: error.localizedDescription
            )
        }
    }

    private func applyLocalOCRResult(_ recognition: OCRRecognitionResult) {
        let payload = InsightPayloadBuilder.build(
            source: record.source,
            recognizedText: recognition.text,
            imageData: record.imageData
        )
        let event = payload.events.first
        let eventDate = event?.date
        let needTodo = (eventDate ?? .distantPast) > .now

        record.recognizedText = recognition.text
        record.ocrLineBoxes = recognition.lineBoxes
        record.summary = payload.summary
        record.intent = (needTodo ? ScanIntent.schedule : ScanIntent.summary).rawValue
        record.eventTitle = event?.title
        record.eventDate = eventDate
        record.eventTime = eventDate.map { pendingTimeFormatter.string(from: $0) }
        record.eventKeywordsText = ""
        record.eventDescription = payload.summary
        record.needTodo = needTodo
        record.isOCRCompleted = true
        record.usedAISummary = false
        try? modelContext.save()
    }

    private func applyAIResult(
        recognizedText: String,
        localFallbackSummary: String,
        insight: AIOCRInsight,
        lineBoxes: [OCRLineBox]
    ) {
        let resolvedSummary = insight.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? localFallbackSummary
            : insight.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = insight.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDescription = insight.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedKeywords = Array(
            insight.keywords
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
                .prefix(3)
        )
        let normalizedTimeValue = normalizedTime(insight.time)
        let resolvedEventTime = normalizedTimeValue ?? "00:00"
        let date = parsedEventDate(date: insight.date, time: resolvedEventTime)
        let needTodo = insight.needTodo && date != nil
        let descriptionText = (resolvedDescription?.isEmpty == false) ? resolvedDescription : resolvedSummary

        record.recognizedText = recognizedText
        record.ocrLineBoxes = lineBoxes
        record.summary = resolvedSummary
        record.intent = (needTodo ? ScanIntent.schedule : ScanIntent.summary).rawValue
        record.eventTitle = resolvedTitle
        record.eventDate = date
        record.eventTime = normalizedTimeValue
        record.eventKeywordsText = normalizedKeywords.joined(separator: ",")
        record.eventDescription = descriptionText
        record.needTodo = needTodo
        record.isOCRCompleted = true
        record.usedAISummary = true
        try? modelContext.save()
    }

    private func ensureRecognitionForAI() async throws -> OCRRecognitionResult {
        let existingText = record.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if existingText.isEmpty == false {
            return OCRRecognitionResult(text: existingText, lineBoxes: record.ocrLineBoxes)
        }

        guard let image = resolvedImage else {
            throw VisionOCRServiceError.invalidImage
        }
        return try await VisionOCRService.recognize(from: image)
    }

    private func parsedEventDate(date: String?, time: String) -> Date? {
        guard let date else { return nil }
        let dateText = date.trimmingCharacters(in: .whitespacesAndNewlines)
        guard dateText.isEmpty == false else { return nil }
        return eventDateFormatter.date(from: "\(dateText) \(time)")
    }

    private func normalizedTime(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return trimmed
    }

    private var eventDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }

    private var pendingTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    private var resolvedTitle: String {
        let title = (record.eventTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty == false {
            return title
        }
        let summary = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? String(localized: "无") : String(summary.prefix(40))
    }

    private var resolvedDetailText: String {
        let description = (record.eventDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if description.isEmpty == false {
            return description
        }
        let summary = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? String(localized: "无") : summary
    }

    private var resolvedKeywords: String {
        let keywords = record.eventKeywords
        return keywords.isEmpty ? String(localized: "无") : keywords.joined(separator: " / ")
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
    @State private var baseScale: CGFloat = 1
    @State private var gestureScale: CGFloat = 1
    @State private var baseOffset: CGSize = .zero
    @State private var gestureOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            GeometryReader { proxy in
                let displayScale = clampedScale(baseScale * gestureScale)
                let candidateOffset = CGSize(
                    width: baseOffset.width + gestureOffset.width,
                    height: baseOffset.height + gestureOffset.height
                )
                let displayOffset = clampedOffset(candidateOffset, scale: displayScale, in: proxy.size)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 40)
                    .scaleEffect(displayScale)
                    .offset(displayOffset)
                    .gesture(
                        SimultaneousGesture(
                            magnificationGesture(containerSize: proxy.size),
                            dragGesture(containerSize: proxy.size)
                        )
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                            if displayScale > 1.01 {
                                resetTransform()
                            } else {
                                baseScale = 2
                                baseOffset = .zero
                            }
                        }
                    }
                    .onTapGesture {
                        if displayScale <= 1.01 {
                            isPresented = false
                        }
                    }
                    .contentShape(Rectangle())
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

    private func magnificationGesture(containerSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                gestureScale = value
            }
            .onEnded { value in
                baseScale = clampedScale(baseScale * value)
                gestureScale = 1

                let currentOffset = CGSize(
                    width: baseOffset.width + gestureOffset.width,
                    height: baseOffset.height + gestureOffset.height
                )
                baseOffset = clampedOffset(currentOffset, scale: baseScale, in: containerSize)
                gestureOffset = .zero
            }
    }

    private func dragGesture(containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard clampedScale(baseScale * gestureScale) > 1.01 else {
                    gestureOffset = .zero
                    return
                }
                gestureOffset = value.translation
            }
            .onEnded { value in
                guard clampedScale(baseScale * gestureScale) > 1.01 else {
                    resetTransform()
                    return
                }

                let currentOffset = CGSize(
                    width: baseOffset.width + value.translation.width,
                    height: baseOffset.height + value.translation.height
                )
                baseOffset = clampedOffset(currentOffset, scale: baseScale, in: containerSize)
                gestureOffset = .zero
            }
    }

    private func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, 1), 4)
    }

    private func clampedOffset(_ offset: CGSize, scale: CGFloat, in size: CGSize) -> CGSize {
        let maxX = max((size.width * (scale - 1)) / 2, 0)
        let maxY = max((size.height * (scale - 1)) / 2, 0)

        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    private func resetTransform() {
        baseScale = 1
        gestureScale = 1
        baseOffset = .zero
        gestureOffset = .zero
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
            let fallback = (record.eventDescription ?? record.summary).trimmingCharacters(in: .whitespacesAndNewlines)
            resolvedTitle = fallback.isEmpty ? String(localized: "识别记录提醒") : String(fallback.prefix(40))
        }

        var noteLines: [String] = []
        let note = record.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if note.isEmpty == false {
            noteLines.append(note)
        }
        if let description = record.eventDescription?.trimmingCharacters(in: .whitespacesAndNewlines), description.isEmpty == false {
            noteLines.append(String(localized: "事件描述：\(description)"))
        } else {
            noteLines.append(String(localized: "摘要：\(record.summary)"))
        }
        if record.eventKeywords.isEmpty == false {
            noteLines.append(String(localized: "关键词：\(record.eventKeywords.joined(separator: "、"))"))
        }

        self.title = resolvedTitle
        self.notes = noteLines.joined(separator: "\n")
        self.dueDate = record.eventDate ?? Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        self.hasDueDate = record.needTodo && record.eventDate != nil
    }
}

private struct ReminderDraftEditorView: View {
    @Binding var draft: ReminderDraft
    let isSaving: Bool
    let showRepeatHint: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                if showRepeatHint {
                    Section {
                        Text(String(localized: "这条记录已经添加过待办事项，请再次确认是否需要重复创建。"))
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

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
