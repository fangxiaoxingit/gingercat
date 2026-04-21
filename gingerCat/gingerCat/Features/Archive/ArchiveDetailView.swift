import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
import ImageIO
#endif
#if canImport(Photos)
import Photos
#endif

struct ArchiveDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(AppSettingsKeys.haptics) private var hapticsEnabled = true
    @AppStorage(AppSettingsKeys.autoAddTodoAfterAISummary) private var autoAddTodoAfterAISummary = true
    @AppStorage(AppSettingsKeys.hapticsIntensity) private var hapticsIntensityRaw = HapticFeedbackIntensity.medium.rawValue

    @Bindable var record: ScanRecord
    @State private var isImagePreviewPresented = false
    @State private var isSavingReminder = false
    @State private var isRunningLocalOCR = false
    @State private var isRunningAISummary = false
    @State private var reminderFeedback: ReminderFeedback?
    @State private var isReminderEditorPresented = false
    @State private var reminderDraft = ReminderDraft.empty
    @State private var isDeleteConfirmationPresented = false
    @State private var showRepeatTodoHintInEditor = false
    @State private var selectedReminderEventKey: String?
    @State private var toastMessage: String?
    @State private var toastDismissTask: Task<Void, Never>?
    @State private var isShareCardComposerPresented = false

    private var hapticsIntensity: HapticFeedbackIntensity {
        HapticFeedbackIntensity(rawValue: hapticsIntensityRaw) ?? .medium
    }

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

            toastLayer
        }
        .navigationTitle(String(localized: "记录详情"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        presentReminderEditor()
                    } label: {
                        Label(
                            String(localized: "加入待办提醒"),
                            systemImage: "checklist"
                        )
                    }

                    Divider()

                    Button {
                        showGenerationToast()
                        Task {
                            await runAISummary()
                        }
                    } label: {
                        Label(
                            isRunningAISummary ? String(localized: "AI摘要总结处理中...") : String(localized: "AI 摘要总结"),
                            systemImage: "sparkles"
                        )
                    }
                    .disabled(isRunningLocalOCR || isRunningAISummary)

                    Button {
                        showGenerationToast()
                        Task {
                            await runLocalOCR()
                        }
                    } label: {
                        Label(
                            isRunningLocalOCR ? String(localized: "文字提取处理中...") : String(localized: "本地提取文字"),
                            systemImage: "text.viewfinder"
                        )
                    }
                    .disabled(isRunningLocalOCR || isRunningAISummary)

                    Divider()

                    Button {
                        isShareCardComposerPresented = true
                    } label: {
                        Label(
                            String(localized: "卡片分享"),
                            systemImage: "square.and.arrow.up.on.square"
                        )
                    }

                    Divider()

                    Button(role: .destructive) {
                        isDeleteConfirmationPresented = true
                    } label: {
                        Label(String(localized: "删除记录"), systemImage: "trash")
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
        .fullScreenCover(isPresented: $isShareCardComposerPresented) {
            ArchiveShareCardComposerView(
                record: record,
                isPresented: $isShareCardComposerPresented
            )
        }
        .sheet(isPresented: $isReminderEditorPresented) {
            ReminderDraftEditorView(
                draft: $reminderDraft,
                isSaving: isSavingReminder,
                showRepeatHint: showRepeatTodoHintInEditor,
                onCancel: {
                    isReminderEditorPresented = false
                    showRepeatTodoHintInEditor = false
                    selectedReminderEventKey = nil
                },
                onSave: {
                    Task {
                        await saveReminderDraft()
                    }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .alert(String(localized: "确认删除这条记录？"), isPresented: $isDeleteConfirmationPresented) {
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "删除"), role: .destructive) {
                deleteRecord()
            }
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
        .onDisappear {
            toastDismissTask?.cancel()
            toastDismissTask = nil
        }
    }

    private var detailSections: some View {
        VStack(alignment: .leading, spacing: 14) {
            imageHeroSection
            mergedRecordCard
            noteCard
        }
    }

    @ViewBuilder
    private var toastLayer: some View {
        VStack {
            if let toastMessage {
                Text(toastMessage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .animation(.easeInOut(duration: 0.22), value: toastMessage != nil)
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
                            .glassBadgeStyle()
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
                            if record.imageData == nil {
                                Image(systemName: "append.page")
                                    .font(.system(size: 44, weight: .medium))
                                    .foregroundStyle(AppTheme.primary.opacity(colorScheme == .dark ? 0.92 : 0.78))
                                Text(String(localized: "文字记录"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                Image(systemName: "photo")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text(String(localized: "暂无图片"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 120, maxHeight: 120)
            }
        }
    }

    private var mergedRecordCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if shouldShowSummaryOverviewCard {
                summaryOverviewCard
            }

            ForEach(Array(recordInfoModules.enumerated()), id: \.element.id) { index, module in
                recordInfoModuleCard(module: module, index: index)
            }
        }
    }

    private var summaryOverviewCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Label(String(localized: "总体摘要"), systemImage: "doc.text.magnifyingglass")
                        .font(.headline)

                    Spacer(minLength: 0)

                    Text(String(localized: "待办 \(pendingTodoCount)/\(reminderModuleCount)"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                }

                Divider()

                Text(summaryOverviewText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    private func recordInfoModuleCard(module: RecordInfoModule, index: Int) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Label(moduleTitle(for: module, at: index), systemImage: "text.quote")
                        .font(.headline)

                    Spacer(minLength: 0)

                    if shouldShowInlineAddTodoButton(for: module) {
                        Button {
                            presentReminderEditor(for: module)
                        } label: {
                            Label(String(localized: "加入待办"), systemImage: "checklist")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                        .tint(AppTheme.primary)
                    } else if isReminderAdded(for: module) {
                        Label(String(localized: "已添加"), systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.primary)
                    }
                }

                Divider()

                detailField(
                    title: String(localized: "标题"),
                    content: module.title
                )

                detailField(
                    title: String(localized: "详细内容"),
                    content: module.detail
                )

                detailField(
                    title: String(localized: "关键词"),
                    content: module.keywordsText
                )

                if module.kind != .pickup {
                    detailField(
                        title: String(localized: "待办提醒时间"),
                        content: module.dueDateText
                    )
                }

                Divider()

                recordMetaFootnote
            }
        }
    }

    private var recordMetaFootnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "创建时间：\(AppDateTimeFormatter.string(from: record.createdAt))"))
            Text(String(localized: "摘要更新时间：\(summaryUpdatedTimeText)"))
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            if let selectedReminderEventKey {
                var addedKeys = record.addedTodoEventKeys
                addedKeys.insert(selectedReminderEventKey)
                record.addedTodoEventKeys = addedKeys
                record.hasAddedTodoReminder = addedKeys.isEmpty == false
            } else {
                record.hasAddedTodoReminder = true
            }
            try? modelContext.save()
            isReminderEditorPresented = false
            showRepeatTodoHintInEditor = false
            selectedReminderEventKey = nil
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
        HapticFeedbackService.impact(enabled: hapticsEnabled, intensity: hapticsIntensity)
    }

    @MainActor
    private func showGenerationToast() {
        showToast(String(localized: "正在生成，请稍候查看结果。"), duration: 2_800_000_000)
    }

    @MainActor
    private func showToast(_ message: String, duration: UInt64) {
        toastDismissTask?.cancel()
        toastMessage = message
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: duration)
            guard Task.isCancelled == false else { return }
            await MainActor.run {
                withAnimation {
                    toastMessage = nil
                }
            }
        }
    }

    private func presentReminderEditor(for module: RecordInfoModule? = nil) {
        let resolvedModule = module ?? firstCandidateModuleForReminder
        selectedReminderEventKey = resolvedModule?.reminderKey
        showRepeatTodoHintInEditor = resolvedModule.map(isReminderAdded(for:)) ?? record.hasAddedTodoReminder
        openReminderEditor(for: resolvedModule)
    }

    private func openReminderEditor(for module: RecordInfoModule?) {
        reminderDraft = ReminderDraft(record: record, module: module)
        isReminderEditorPresented = true
    }

    @MainActor
    private func runLocalOCR() async {
        guard isRunningLocalOCR == false else { return }
        guard let image = resolvedImage else {
            reminderFeedback = ReminderFeedback(
                title: String(localized: "文字提取失败"),
                message: String(localized: "当前记录没有可用图片，无法执行文字提取。")
            )
            return
        }

        isRunningLocalOCR = true
        defer { isRunningLocalOCR = false }

        do {
            let recognition = try await VisionOCRService.recognize(from: image)
            applyLocalOCRResult(recognition)
            reminderFeedback = ReminderFeedback(
                title: String(localized: "文字提取完成"),
                message: String(localized: "已更新识别文本，当前未生成本地摘要。")
            )
        } catch VisionOCRServiceError.noRecognizedText {
            reminderFeedback = ReminderFeedback(
                title: String(localized: "文字提取失败"),
                message: String(localized: "未识别到可用文字，请更换更清晰的图片。")
            )
        } catch {
            reminderFeedback = ReminderFeedback(
                title: String(localized: "文字提取失败"),
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
                ocrFallbackText: payload.summary,
                insight: insight,
                lineBoxes: recognition.lineBoxes
            )
            let autoAddResult = await TodoAutoAddService.autoAddIfNeeded(
                for: record,
                enabled: autoAddTodoAfterAISummary
            )
            if autoAddResult.addedCount > 0 {
                try? modelContext.save()
            }
            let successMessage = autoAddResult.addedCount > 0
                ? String(localized: "已更新标题、详细内容、关键词和日期时间，并自动加入 \(autoAddResult.addedCount) 条待办。")
                : String(localized: "已更新标题、详细内容、关键词和日期时间。")
            reminderFeedback = ReminderFeedback(
                title: String(localized: "AI摘要完成"),
                message: successMessage
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
        let pickupCodes = PickupCodeExtractor.extract(from: payload.rawText)
        let primaryPickupCode = pickupCodes.first

        // 手动本地提取只更新 OCR 原文，避免重新生成本地摘要或本地事件结构。
        record.recognizedText = recognition.text
        record.ocrLineBoxes = recognition.lineBoxes
        record.summary = primaryPickupCode?.summaryText ?? payload.summary
        record.intent = primaryPickupCode == nil ? ScanIntent.summary.rawValue : ScanIntent.pickup.rawValue
        record.eventTitle = primaryPickupCode?.summaryText
        record.eventDate = nil
        record.eventTime = nil
        record.eventKeywordsText = primaryPickupCode.map { $0.category.displayName } ?? ""
        record.eventDescription = pickupCodes.isEmpty
            ? (payload.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : payload.rawText)
            : pickupDescriptionText(for: pickupCodes)
        record.needTodo = false
        record.todoEvents = []
        record.pickupCodes = pickupCodes
        record.addedTodoEventKeys = []
        record.hasAddedTodoReminder = false
        record.isOCRCompleted = true
        record.usedAISummary = false
        record.summaryUpdatedAt = .now
        record.summaryModelName = String(localized: "本地摘要")
        try? modelContext.save()
    }

    private func applyAIResult(
        recognizedText: String,
        ocrFallbackText: String,
        insight: AIOCRInsight,
        lineBoxes: [OCRLineBox]
    ) {
        let pickupCodes = buildPickupCodes(from: insight, rawText: recognizedText)
        if let primaryPickupCode = pickupCodes.first {
            record.recognizedText = recognizedText
            record.ocrLineBoxes = lineBoxes
            record.summary = primaryPickupCode.summaryText
            record.intent = ScanIntent.pickup.rawValue
            record.eventTitle = primaryPickupCode.summaryText
            record.eventDate = nil
            record.eventTime = nil
            record.eventKeywordsText = primaryPickupCode.category.displayName
            record.eventDescription = pickupDescriptionText(for: pickupCodes)
            record.needTodo = false
            record.todoEvents = []
            record.pickupCodes = pickupCodes
            record.addedTodoEventKeys = []
            record.hasAddedTodoReminder = false
            record.isOCRCompleted = true
            record.usedAISummary = true
            record.summaryUpdatedAt = .now
            record.summaryModelName = AIProviderConfigStore.selectedRuntimeConfig().summaryModelDisplayName
            try? modelContext.save()
            return
        }

        // AI 未返回摘要时回落到 OCR 原文，确保这里不会重新启用本地摘要。
        let resolvedSummary = insight.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ocrFallbackText
            : insight.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let todoEvents = buildTodoEvents(from: insight)
        let primaryTodoEvent = todoEvents.first(where: { $0.needTodo }) ?? todoEvents.first
        let resolvedTitle = primaryTodoEvent?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? insight.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDescription = primaryTodoEvent?.description?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? insight.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedKeywords = Array(
            (primaryTodoEvent?.keywords ?? insight.keywords)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
                .prefix(3)
        )
        let normalizedTimeValue = primaryTodoEvent?.time ?? normalizedTime(insight.time)
        let resolvedEventTime = normalizedTimeValue ?? "00:00"
        let date = primaryTodoEvent?.date ?? parsedEventDate(date: insight.date, time: resolvedEventTime)
        let hasScheduleDate = date != nil
        let needTodo = primaryTodoEvent?.needTodo ?? insight.needTodo
        let descriptionText = (resolvedDescription?.isEmpty == false) ? resolvedDescription : resolvedSummary

        record.recognizedText = recognizedText
        record.ocrLineBoxes = lineBoxes
        record.summary = resolvedSummary
        record.intent = (hasScheduleDate ? ScanIntent.schedule : ScanIntent.summary).rawValue
        record.eventTitle = resolvedTitle
        record.eventDate = date
        record.eventTime = normalizedTimeValue
        record.eventKeywordsText = normalizedKeywords.joined(separator: ",")
        record.eventDescription = descriptionText
        record.needTodo = needTodo
        record.todoEvents = todoEvents
        record.pickupCodes = []
        if todoEvents.isEmpty {
            record.addedTodoEventKeys = []
            record.hasAddedTodoReminder = false
        } else {
            let validKeys = Set(todoEvents.map(\.key))
            let retainedKeys = record.addedTodoEventKeys.intersection(validKeys)
            record.addedTodoEventKeys = retainedKeys
            record.hasAddedTodoReminder = retainedKeys.isEmpty == false
        }
        record.isOCRCompleted = true
        record.usedAISummary = true
        record.summaryUpdatedAt = .now
        record.summaryModelName = AIProviderConfigStore.selectedRuntimeConfig().summaryModelDisplayName
        try? modelContext.save()
    }

    private func buildTodoEvents(from insight: AIOCRInsight) -> [ScanTodoEvent] {
        insight.events.compactMap { event in
            let normalizedTimeValue = normalizedTime(event.time) ?? "00:00"
            guard let date = parsedEventDate(date: event.date, time: normalizedTimeValue) else {
                return nil
            }
            let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = event.description?.trimmingCharacters(in: .whitespacesAndNewlines)
            let keywords = Array(
                event.keywords
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.isEmpty == false }
                    .prefix(3)
            )
            return ScanTodoEvent(
                title: title,
                date: date,
                time: normalizedTimeValue,
                keywords: keywords,
                description: description,
                needTodo: event.needTodo
            )
        }
        .sorted { lhs, rhs in
            lhs.date < rhs.date
        }
    }

    private func buildPickupCodes(from insight: AIOCRInsight, rawText: String) -> [ScanPickupCode] {
        var normalized: [ScanPickupCode] = insight.pickupItems.compactMap { item in
            ScanPickupCode(
                brandName: item.brandName,
                itemName: item.itemName,
                codeValue: item.codeValue,
                codeLabel: item.codeLabel,
                category: item.category,
                pickupDate: item.pickupDate,
                pickupTime: item.pickupTime,
                source: "ai",
                priority: item.priority
            )
        }.filter { $0.codeValue.isEmpty == false }

        if normalized.isEmpty {
            normalized = PickupCodeExtractor.extract(from: rawText)
        }
        return normalized.sorted { lhs, rhs in
            let leftPriority = lhs.priority ?? Int.max
            let rightPriority = rhs.priority ?? Int.max
            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }
            return lhs.codeValue < rhs.codeValue
        }
    }

    private func pickupDescriptionText(for pickupCodes: [ScanPickupCode]) -> String {
        pickupCodes.map { pickup in
            let dateTime = pickup.dateTimeText ?? String(localized: "未知时间")
            return "\(pickup.summaryText)（\(pickup.category.displayName)，\(dateTime)）"
        }.joined(separator: "；")
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

    private var recordInfoModules: [RecordInfoModule] {
        let normalizedSummary = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let summaryFallback = normalizedSummary.isEmpty ? String(localized: "无") : normalizedSummary
        let summaryTitleFallback = normalizedSummary.isEmpty ? String(localized: "无") : String(normalizedSummary.prefix(40))
        if record.pickupCodes.isEmpty == false {
            let primary = record.primaryPickupCode
            let detailText = record.pickupCodes.map { pickup in
                let dateTime = pickup.dateTimeText ?? String(localized: "未知时间")
                return "品牌：\(pickup.resolvedBrandName)\n码值：\(pickup.codeLabel) \(pickup.codeValue)\n商品名称：\(pickup.resolvedItemName)\n商品类型：\(pickup.category.displayName)\n时间：\(dateTime)"
            }.joined(separator: "\n")
            return [
                RecordInfoModule(
                    id: "pickup-\(record.id.uuidString)",
                    reminderKey: nil,
                    title: primary?.summaryText ?? summaryTitleFallback,
                    detail: detailText.isEmpty ? summaryFallback : detailText,
                    keywords: Array(Set(record.pickupCodes.map { $0.category.displayName })).sorted(),
                    dueDate: nil,
                    isTodoCandidate: false,
                    kind: .pickup
                )
            ]
        }

        let todoEvents = record.todoEvents.filter(\.needTodo).sorted { lhs, rhs in
            lhs.date < rhs.date
        }

        if todoEvents.isEmpty == false {
            return todoEvents.enumerated().map { index, event in
                let title = (event.title ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let detail = (event.description ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return RecordInfoModule(
                    id: "todo-\(index)-\(event.key)",
                    reminderKey: event.key,
                    title: title.isEmpty ? summaryTitleFallback : title,
                    detail: detail.isEmpty ? summaryFallback : detail,
                    keywords: event.keywords,
                    dueDate: event.date,
                    isTodoCandidate: true,
                    kind: .event
                )
            }
        }

        let legacyReminderKey: String? = {
            guard record.needTodo, let eventDate = record.eventDate else { return nil }
            return ScanRecord.todoEventKey(
                date: eventDate,
                title: record.eventTitle,
                description: record.eventDescription
            )
        }()

        return [
            RecordInfoModule(
                id: "legacy-\(record.id.uuidString)",
                reminderKey: legacyReminderKey,
                title: resolvedTitle,
                detail: resolvedDetailText,
                keywords: record.eventKeywords,
                dueDate: record.eventDate,
                isTodoCandidate: record.needTodo,
                kind: .record
            )
        ]
    }

    private var reminderModules: [RecordInfoModule] {
        recordInfoModules.filter { $0.isTodoCandidate && $0.reminderKey != nil }
    }

    private var shouldShowSummaryOverviewCard: Bool {
        reminderModuleCount > 1
    }

    private var reminderModuleCount: Int {
        reminderModules.count
    }

    private var pendingTodoCount: Int {
        reminderModules.filter { shouldShowInlineAddTodoButton(for: $0) }.count
    }

    private var summaryOverviewText: String {
        let text = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? resolvedDetailText : text
    }

    private var firstCandidateModuleForReminder: RecordInfoModule? {
        reminderModules.first { shouldShowInlineAddTodoButton(for: $0) }
            ?? reminderModules.first
            ?? recordInfoModules.first
    }

    private func moduleTitle(for module: RecordInfoModule, at index: Int) -> String {
        if module.kind == .pickup {
            return String(localized: "取件信息")
        }
        if recordInfoModules.count > 1 {
            return String(localized: "记录信息 \(index + 1)")
        }
        return String(localized: "记录信息")
    }

    private var summaryUpdatedTimeText: String {
        guard let updatedAt = record.summaryUpdatedAt ?? (record.isOCRCompleted ? record.createdAt : nil) else {
            return String(localized: "无")
        }
        let sourceName = (record.summaryModelName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let timestamp = AppDateTimeFormatter.string(from: updatedAt)
        guard sourceName.isEmpty == false else {
            return timestamp
        }
        return "\(sourceName) · \(timestamp)"
    }

    private func isReminderAdded(for module: RecordInfoModule) -> Bool {
        if let key = module.reminderKey {
            if record.addedTodoEventKeys.contains(key) {
                return true
            }
            if reminderModules.count == 1,
               record.addedTodoEventKeys.isEmpty,
               record.hasAddedTodoReminder {
                return true
            }
            return false
        }
        return record.hasAddedTodoReminder
    }

    private func shouldShowInlineAddTodoButton(for module: RecordInfoModule) -> Bool {
        guard module.isTodoCandidate else {
            return false
        }
        guard isReminderAdded(for: module) == false else {
            return false
        }
        guard let dueDate = module.dueDate else {
            return false
        }
        return dueDate > .now
    }

    private func detailField(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(content)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

}

private struct ArchiveShareCardComposerView: View {
    @Environment(\.colorScheme) private var colorScheme

    let record: ScanRecord
    @Binding var isPresented: Bool

    @State private var shareImage: ShareableImage?
    @State private var feedback: ShareCardFeedback?
    @State private var isSavingImage = false
    @State private var selectedCardColor: ShareCardColor = ShareCardColorDataSource.defaultColor

    private let cardColors: [ShareCardColor] = ShareCardColorDataSource.allColors

    var body: some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { proxy in
                let cardWidth = min(proxy.size.width * 0.9, 390)
                let cardHeight = cardWidth * 4 / 3

                ArchiveShareCardCanvasView(
                    appName: appDisplayName,
                    title: shareTitle,
                    content: shareContent,
                    backgroundColor: selectedCardColor.color
                )
                .frame(width: cardWidth, height: cardHeight)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2 - 10)
                .environment(\.colorScheme, .light)
            }
            .ignoresSafeArea()

            // 顶部标题和关闭按钮
            VStack(spacing: 0) {
                titleBar
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 16)

            // 底部颜色选择器和按钮组
            VStack(spacing: 16) {
                colorPickerBar
                bottomActionBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 26)
        }
        .sheet(item: $shareImage) { shareableImage in
            ActivityShareSheet(activityItems: [shareableImage.image])
        }
        .alert(item: $feedback) { feedback in
            Alert(
                title: Text(feedback.title),
                message: Text(feedback.message),
                dismissButton: .default(Text(String(localized: "知道了")))
            )
        }
    }

    private var titleBar: some View {
        HStack {
            // 左侧占位，保持居中
            Spacer()
                .frame(width: 44)

            Spacer()

            // 中间标题
            Text(String(localized: "分享预览"))
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer()

            // 右侧关闭按钮
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .glassCloseButtonStyle()
        }
        .padding(.horizontal, 18)
    }

    private var colorPickerBar: some View {
        HStack(spacing: 12) {
            ForEach(cardColors, id: \.self) { color in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedCardColor = color
                    }
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: selectedCardColor == color ? 36 : 30,
                               height: selectedCardColor == color ? 36 : 30)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.5), lineWidth: selectedCardColor == color ? 2 : 0)
                        )
                        .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassContainerStyle()
    }

    private var bottomActionBar: some View {
        // 中间按钮组：下载 | 分享
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                // 下载按钮
                Button {
                    Task {
                        await saveCardImageToPhotos()
                    }
                } label: {
                    if isSavingImage {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.primary)
                            .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
                .disabled(isSavingImage)
                .frame(width: 62, height: 50)

                // 分隔线
                Divider()
                    .frame(width: 1, height: 26)

                // 分享按钮
                Button {
                    shareCardImage()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 62, height: 50)
                }
                .disabled(isSavingImage)
            }
            .padding(.horizontal, 10)
        }
        .glassContainerStyle()
    }

    private var appDisplayName: String {
        if let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return displayName
        }
        if let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
           appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return appName
        }
        return String(localized: "大橘小事")
    }

    private var shareTitle: String {
        let eventTitle = (record.eventTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if eventTitle.isEmpty == false {
            return eventTitle
        }

        let summary = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if summary.isEmpty == false {
            return String(summary.prefix(32))
        }

        return String(localized: "识别记录")
    }

    private var shareContent: String {
        let description = (record.eventDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if description.isEmpty == false, description != shareTitle {
            return description
        }

        let summary = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if summary.isEmpty == false {
            return summary
        }

        let recognizedText = record.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if recognizedText.isEmpty == false {
            return recognizedText
        }

        return String(localized: "暂无详细内容")
    }

    private func shareCardImage() {
        guard let image = renderedCardImage() else {
            feedback = ShareCardFeedback(
                title: String(localized: "分享失败"),
                message: String(localized: "卡片渲染失败，请稍后重试。")
            )
            return
        }
        shareImage = ShareableImage(image: image)
    }

    private func saveCardImageToPhotos() async {
        guard isSavingImage == false else { return }
        isSavingImage = true
        defer { isSavingImage = false }

        guard let image = renderedCardImage() else {
            feedback = ShareCardFeedback(
                title: String(localized: "保存失败"),
                message: String(localized: "卡片渲染失败，请稍后重试。")
            )
            return
        }

        do {
            try await ShareCardPhotoLibrarySaver.save(image: image)
            feedback = ShareCardFeedback(
                title: String(localized: "保存成功"),
                message: String(localized: "卡片已保存到系统相册。")
            )
        } catch {
            feedback = ShareCardFeedback(
                title: String(localized: "保存失败"),
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    private func renderedCardImage() -> UIImage? {
        let renderView = ArchiveShareCardCanvasView(
            appName: appDisplayName,
            title: shareTitle,
            content: shareContent,
            backgroundColor: selectedCardColor.color
        )
        .frame(width: 1080, height: 1440)
        // 固定使用浅色模式，确保生成的图片外观一致
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: renderView)
        renderer.scale = 1
        return renderer.uiImage
    }
}

private struct ArchiveShareCardCanvasView: View {
    let appName: String
    let title: String
    let content: String
    let backgroundColor: Color

    var body: some View {
        GeometryReader { proxy in
            let widthScale = max(proxy.size.width / 390, 0.85)
            let topPadding = 20 * widthScale
            let horizontalPadding = 30 * widthScale
            let appNameSize = 20 * widthScale
            let titleSize = 30 * widthScale
            let contentSize = 16 * widthScale

            ZStack {
                // 使用选中的背景色
                backgroundColor

                VStack(alignment: .leading, spacing: 0) {
                    Text(appName)
                        .font(.system(size: appNameSize, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))

                    Spacer(minLength: 20 * widthScale)

                    Text(title)
                        .font(.system(size: titleSize, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(4)
                        .minimumScaleFactor(0.68)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 20 * widthScale)

                    Text(content)
                        .font(.system(size: contentSize, weight: .regular))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineSpacing(4 * widthScale)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(6)
                        .minimumScaleFactor(0.74)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(.top, topPadding)
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 48 * widthScale)
            }
        }
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct ShareCardFeedback: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct ShareableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private enum ShareCardPhotoLibrarySaver {
    static func save(image: UIImage) async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let resolvedStatus: PHAuthorizationStatus

        switch status {
        case .authorized, .limited:
            resolvedStatus = status
        case .notDetermined:
            resolvedStatus = await requestPhotoAuthorization()
        case .restricted, .denied:
            throw ShareCardSaveError.permissionDenied
        @unknown default:
            throw ShareCardSaveError.permissionDenied
        }

        guard resolvedStatus == .authorized || resolvedStatus == .limited else {
            throw ShareCardSaveError.permissionDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }, completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: ShareCardSaveError.saveFailed)
                }
            })
        }
    }

    private static func requestPhotoAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}

private enum ShareCardSaveError: LocalizedError {
    case permissionDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return String(localized: "没有相册写入权限，请在系统设置中允许后重试。")
        case .saveFailed:
            return String(localized: "保存到相册失败，请稍后重试。")
        }
    }
}

// MARK: - Share Card Color

/// 分享卡片颜色数据源
/// 集中管理所有可选颜色，方便后期添加或修改
enum ShareCardColorDataSource {
    /// 森林绿 - 默认颜色
    static let forestGreen = ShareCardColor(
        id: "forestGreen",
        hex: "#346739",
        displayName: "森林绿"
    )

    /// 海洋蓝
    static let oceanBlue = ShareCardColor(
        id: "oceanBlue",
        hex: "#344CB7",
        displayName: "海洋蓝"
    )

    /// 珊瑚红
    static let coralRed = ShareCardColor(
        id: "coralRed",
        hex: "#A31D1D",
        displayName: "珊瑚红"
    )

    /// 日落橙
    static let sunsetOrange = ShareCardColor(
        id: "sunsetOrange",
        hex: "#dc5400",
        displayName: "日落橙"
    )

    /// 深紫
    static let deepPurple = ShareCardColor(
        id: "deepPurple",
        hex: "#4b18ab",
        displayName: "深紫"
    )

    /// 黄色
    static let mintGreen = ShareCardColor(
        id: "mintGreen",
        hex: "#e3b32f",
        displayName: "薄荷绿"
    )

    /// 石板灰
    static let slateGray = ShareCardColor(
        id: "slateGray",
        hex: "#29292f",
        displayName: "石板灰"
    )

    /// 所有颜色数组
    static var allColors: [ShareCardColor] {
        [
            forestGreen,
            oceanBlue,
            coralRed,
            sunsetOrange,
            deepPurple,
            mintGreen,
            slateGray
        ]
    }

    /// 默认颜色
    static var defaultColor: ShareCardColor {
        forestGreen
    }

    /// 根据 ID 查找颜色
    static func color(withId id: String) -> ShareCardColor? {
        allColors.first { $0.id == id }
    }
}

/// 分享卡片颜色模型
struct ShareCardColor: Identifiable, Equatable, Hashable {
    let id: String
    let hex: String
    let displayName: String

    var color: Color {
        Color(hex: hex)
    }
}

#Preview {
    NavigationStack {
        ArchiveDetailView(record: ScanRecord.previewData()[0])
    }
}

// MARK: - Liquid Glass Extensions

private extension View {
    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(iOS 26, *) {
            self
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            self
                .background(
                    Color.primary.opacity(0.1),
                    in: Capsule()
                )
        }
    }

    @ViewBuilder
    func glassContainerStyle() -> some View {
        if #available(iOS 26, *) {
            self
                .glassEffect(.regular, in: .capsule)
        } else {
            self
                .background(
                    Color.primary.opacity(0.1),
                    in: Capsule()
                )
        }
    }

    @ViewBuilder
    func glassBadgeStyle() -> some View {
        if #available(iOS 26, *) {
            self
                .glassEffect(.regular, in: .capsule)
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    @ViewBuilder
    func glassCloseButtonStyle() -> some View {
        if #available(iOS 26, *) {
            self
                .glassEffect(.regular.interactive(), in: .circle)
        } else {
            self
                .background(
                    Color.white.opacity(0.2),
                    in: Circle()
                )
        }
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

            VStack {
                HStack {
                    Spacer()
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                    }
                    .glassCloseButtonStyle()
                    .padding(.top, 16)
                    .padding(.trailing, 16)
                }
                Spacer()
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

private struct RecordInfoModule: Identifiable, Hashable {
    let id: String
    let reminderKey: String?
    let title: String
    let detail: String
    let keywords: [String]
    let dueDate: Date?
    let isTodoCandidate: Bool
    let kind: RecordInfoModuleKind

    var keywordsText: String {
        keywords.isEmpty
            ? String(localized: "无")
            : keywords.joined(separator: " / ")
    }

    var dueDateText: String {
        guard let dueDate else {
            return String(localized: "无")
        }
        return AppDateTimeFormatter.string(from: dueDate)
    }
}

private enum RecordInfoModuleKind: String, Hashable {
    case pickup
    case event
    case record
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

    init(record: ScanRecord, module: RecordInfoModule?) {
        let resolvedTitle: String
        if let moduleTitle = module?.title.trimmingCharacters(in: .whitespacesAndNewlines), moduleTitle.isEmpty == false {
            resolvedTitle = moduleTitle
        } else if let eventTitle = record.eventTitle?.trimmingCharacters(in: .whitespacesAndNewlines), eventTitle.isEmpty == false {
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
        if let moduleDescription = module?.detail.trimmingCharacters(in: .whitespacesAndNewlines), moduleDescription.isEmpty == false {
            noteLines.append(String(localized: "事件描述：\(moduleDescription)"))
        } else if let description = record.eventDescription?.trimmingCharacters(in: .whitespacesAndNewlines), description.isEmpty == false {
            noteLines.append(String(localized: "事件描述：\(description)"))
        } else {
            let label = record.usedAISummary ? String(localized: "摘要") : String(localized: "识别内容")
            noteLines.append("\(label)：\(record.summary)")
        }
        let keywords = module?.keywords ?? record.eventKeywords
        if keywords.isEmpty == false {
            noteLines.append(String(localized: "关键词：\(keywords.joined(separator: "、"))"))
        }

        self.title = resolvedTitle
        self.notes = noteLines.joined(separator: "\n")
        self.dueDate = module?.dueDate ?? record.eventDate ?? Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        self.hasDueDate = (module?.dueDate ?? record.eventDate) != nil
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
                        Text(String(localized: "该记录已添加过待办提醒，继续添加会创建重复待办。"))
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .multilineTextAlignment(.center)
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
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                    }
                }
            }
            .environment(\.locale, Locale(identifier: "zh_CN"))
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
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primary)
                    .disabled(isSaving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
