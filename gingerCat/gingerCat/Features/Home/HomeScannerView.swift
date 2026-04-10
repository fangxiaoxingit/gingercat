import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

struct HomeScannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var externalImportCenter: ExternalImportCenter
    @Query(sort: \ScanRecord.createdAt, order: .reverse) private var records: [ScanRecord]

    @AppStorage(AppSettingsKeys.aiSummaryEnabled) private var aiSummaryEnabled = false
    @AppStorage(AppSettingsKeys.haptics) private var hapticsEnabled = true
    @AppStorage(AppSettingsKeys.hapticsIntensity) private var hapticsIntensityRaw = HapticFeedbackIntensity.medium.rawValue

    private var hapticsIntensity: HapticFeedbackIntensity {
        HapticFeedbackIntensity(rawValue: hapticsIntensityRaw) ?? .medium
    }

    private func triggerHaptic() {
        HapticFeedbackService.impact(enabled: hapticsEnabled, intensity: hapticsIntensity)
    }

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false

    @State private var isCameraPresented = false
    @State private var capturedCameraImage: UIImage?

    @State private var activeAlert: HomeAlert?
    @State private var toastMessage: String?
    @State private var toastDismissTask: Task<Void, Never>?
    @State private var isAddMenuExpanded = false
    @State private var pendingAddConfirmation: PendingAddConfirmation?
    @State private var pendingTextInput = ""
    @State private var isSettingsPresented = false
    @State private var isArchivePresented = false
    @State private var selectedRecordRoute: RecordDetailRoute?
    @State private var quickAddAnimationTask: Task<Void, Never>?
    @ObservedObject private var recordNavigationCenter = RecordNavigationCenter.shared
    @GestureState private var isQuickAddPressed = false
    @State private var pendingNotificationPresentationTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                homeBackground

                ScrollView(showsIndicators: false) {
                    homeWireframeLayout
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                        .padding(.bottom, 140)
                }

                if isAddMenuExpanded {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            collapseAddMenu()
                        }
                }

                floatingAddButtonLayer
                toastLayer
            }
            .navigationTitle(String(localized: "首页"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSettingsPresented = true
                    } label: {
                        settingsToolbarButton
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationDestination(isPresented: $isSettingsPresented) {
                SettingsView()
            }
            .navigationDestination(isPresented: $isArchivePresented) {
                ArchiveView()
            }
            .navigationDestination(item: $selectedRecordRoute) { route in
                RecordDetailDestinationView(recordID: route.recordID)
            }
            .photosPicker(
                isPresented: $isPhotoPickerPresented,
                selection: $selectedPhotoItem,
                matching: .images,
                preferredItemEncoding: .automatic
            )
            .fullScreenCover(isPresented: $isCameraPresented) {
                CameraCaptureView(capturedImage: $capturedCameraImage)
                    .ignoresSafeArea()
            }
            .sheet(item: $pendingAddConfirmation) { pending in
                PendingAddConfirmationSheet(
                    pending: pending,
                    text: $pendingTextInput,
                    aiSummaryEnabled: aiSummaryEnabled,
                    config: AIProviderConfigStore.selectedRuntimeConfig(),
                    onCancel: {
                        pendingAddConfirmation = nil
                        pendingTextInput = ""
                    },
                    onConfirm: {
                        let source = pending.source
                        switch pending.kind {
                        case .image:
                            guard let image = pending.image else {
                                pendingAddConfirmation = nil
                                return
                            }
                            pendingAddConfirmation = nil
                            Task {
                                await enqueueImageForRecognition(image, source: source)
                            }
                        case .text:
                            let text = pendingTextInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            pendingAddConfirmation = nil
                            pendingTextInput = ""
                            Task {
                                await enqueueTextForRecognition(text, source: source)
                            }
                        }
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    await handlePhotoSelection(newItem)
                }
            }
            .onChange(of: capturedCameraImage) { _, newImage in
                guard let newImage else { return }
                presentPendingAddConfirmation(for: newImage, source: "Camera")
                capturedCameraImage = nil
            }
            .onAppear {
                openPendingNotificationRecordIfNeeded()
                consumePendingExternalImportIfNeeded()
                consumeLatestExternalImportErrorIfNeeded()
            }
            .onReceive(recordNavigationCenter.$pendingRecordID) { _ in
                openPendingNotificationRecordIfNeeded()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                openPendingNotificationRecordIfNeeded()
            }
            .onChange(of: externalImportCenter.pendingImport?.id) { _, _ in
                consumePendingExternalImportIfNeeded()
            }
            .onChange(of: externalImportCenter.latestErrorMessage) { _, _ in
                consumeLatestExternalImportErrorIfNeeded()
            }
            .alert(item: $activeAlert) { alert in
                Alert(
                    title: Text(String(localized: "提示")),
                    message: Text(alert.message),
                    dismissButton: .default(Text(String(localized: "知道了")))
                )
            }
            .onDisappear {
                quickAddAnimationTask?.cancel()
                quickAddAnimationTask = nil
                toastDismissTask?.cancel()
                toastDismissTask = nil
                pendingNotificationPresentationTask?.cancel()
                pendingNotificationPresentationTask = nil
            }
        }
    }

    private var homeBackground: some View {
        // 首页容器需要比模块卡片更浅一层，避免白色卡片与页面底色混在一起。
        Color(
            uiColor: colorScheme == .dark
                ? .systemBackground
                : .systemGroupedBackground
        )
            .ignoresSafeArea()
    }

    private var homeWireframeLayout: some View {
        Group {
            if #available(iOS 26.0, *), colorScheme == .light {
                GlassEffectContainer(spacing: 24) {
                    homeWireframeContent
                }
            } else {
                homeWireframeContent
            }
        }
    }

    private var homeWireframeContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            recentRecordsSection
            pendingTodosSection
        }
    }

    private var settingsToolbarButton: some View {
        Image(systemName: "gearshape")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.primary)
    }

    private var recentRecordsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(String(localized: "最近记录"))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Button {
                    triggerHaptic()
                    isArchivePresented = true
                } label: {
                    Image(systemName: "clock")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
            }

            if records.isEmpty {
                homeSectionCard(height: 240) {
                    homeEmptyState(
                        systemImage: "photo.on.rectangle.angled",
                        title: String(localized: "暂无记录"),
                        message: String(localized: "扫描图片后，最近三条记录会展示在这里。")
                    )
                    .padding(20)
                }
            } else {
                homeSectionCard(height: 240) {
                    HomeRecordCollage(records: Array(records.prefix(3))) { record in
                        triggerHaptic()
                        presentRecordDetail(record.id, source: .manual)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private var pendingTodosSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "最近待办"))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)
                
                Text(String(localized: "识别出时间或事件后，这里会自动显示最近待办"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if pendingTodos.isEmpty {
                homeSectionCard(height: 240) {
                    homeEmptyState(
                        systemImage: "checklist",
                        title: String(localized: "暂无待办"),
                        message: String(localized: "识别出时间或事件后，这里会自动出现最近待办。")
                    )
                    .padding(20)
                }
            } else {
                homeSectionCard(minHeight: 240, alignment: .topLeading) {
                    VStack(spacing: 0) {
                        ForEach(Array(pendingTodos.enumerated()), id: \.element.id) { index, item in
                            Button {
                                triggerHaptic()
                                presentRecordDetail(item.record.id, source: .manual)
                            } label: {
                                pendingTodoRow(item)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if index < pendingTodos.count - 1 {
                                Divider()
                                    .padding(.leading, 56)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func homeSectionCard<Content: View>(
        height: CGFloat? = nil,
        minHeight: CGFloat? = nil,
        alignment: Alignment = .center,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(moduleBackgroundColor)

            content()
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: minHeight)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(
            color: colorScheme == .dark ? Color.black.opacity(0.22) : Color.black.opacity(0.08),
            radius: colorScheme == .dark ? 14 : 12,
            x: 0,
            y: colorScheme == .dark ? 8 : 6
        )
    }

    private func homeEmptyState(systemImage: String, title: String, message: String) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppTheme.primary.opacity(colorScheme == .dark ? 0.32 : 0.14))
                    .frame(width: 56, height: 56)

                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(colorScheme == .dark ? .white : AppTheme.primary)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.footnote)
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.82) : .secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var floatingAddButtonLayer: some View {
        VStack {
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                addMenuCluster
            }
        }
        .padding(.trailing, 24)
        .padding(.bottom, 24)
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

    private func pendingTodoRow(_ item: PendingTodoItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.primary)
                .frame(width: 22, height: 22)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.primary)
                    .lineLimit(2)

                Text(item.timeText)
                    .font(.subheadline)
                    .foregroundStyle(pendingTodoSecondaryTextColor)
            }

            Spacer(minLength: 0)
        }
    }

    private var addMenuCluster: some View {
        ZStack(alignment: .bottomTrailing) {
            addMenuActionButtonsLayout
                .frame(width: quickAddClusterSize, height: quickAddClusterSize, alignment: .bottomTrailing)
                .allowsHitTesting(isAddMenuExpanded)
                .zIndex(1)

            quickAddButton
                .zIndex(10)
        }
        .frame(width: quickAddClusterSize, height: quickAddClusterSize, alignment: .bottomTrailing)
    }

    private var addMenuActionButtonsLayout: some View {
        ZStack {
            ForEach(QuickAddAction.allCases) { action in
                AddMenuActionButton(
                    systemImage: action.systemImage,
                    tint: AppTheme.primary
                ) {
                    handleQuickAddAction(action)
                }
                .offset(isAddMenuExpanded ? action.offset : .zero)
                .scaleEffect(isAddMenuExpanded ? 1 : 0.01, anchor: .center)
                .allowsHitTesting(isAddMenuExpanded)
                .animation(quickAddAnimation(for: action), value: isAddMenuExpanded)
                .zIndex(Double(action.animationIndex))
            }
        }
        .frame(width: 1, height: 1)
        .position(x: quickAddAnchorPosition.x, y: quickAddAnchorPosition.y)
    }

    private var quickAddButton: some View {
        Button {
            toggleAddMenu()
        } label: {
            Circle()
                .fill(AppTheme.primary)
                .frame(width: 66, height: 66)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                }
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(isAddMenuExpanded ? 45 : 0))
                        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isAddMenuExpanded)
                }
        }
        .buttonStyle(.plain)
        .homeRegularGlass(cornerRadius: 33, tint: AppTheme.primary.opacity(0.24))
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.16), radius: 8, x: 0, y: 4)
        .scaleEffect(isQuickAddPressed ? 0.93 : 1.0)
        .brightness(isQuickAddPressed ? -0.05 : 0)
        .animation(.spring(response: 0.2, dampingFraction: 0.78), value: isQuickAddPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isQuickAddPressed) { _, state, _ in
                        state = true
                    }
            )
        .contentShape(Circle())
        .accessibilityLabel(String(localized: "添加识别"))
        .accessibilityHint(
            isAddMenuExpanded
                ? String(localized: "点击关闭添加菜单")
                : String(localized: "点击展开文字、相册和拍照入口")
        )
    }

    private var moduleBackgroundColor: Color {
        colorScheme == .dark ? Color(uiColor: .secondarySystemBackground) : .white
    }

    private var accentGlassTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.24) : Color.black.opacity(0.05)
    }

    private var pendingTodoSecondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.58)
    }

    private var pendingTodos: [PendingTodoItem] {
        let todoRecords = records
            .filter { record in
                record.needTodo ||
                (record.resolvedIntent == .schedule && (record.eventDate ?? .distantPast) > .now)
            }
            .sorted { lhs, rhs in
                (lhs.eventDate ?? lhs.createdAt) < (rhs.eventDate ?? rhs.createdAt)
            }
        
        return Array(todoRecords.prefix(3)).map { record in
            let title = record.eventTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = record.eventDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedTitle: String
            if let title, title.isEmpty == false {
                resolvedTitle = title
            } else if let description, description.isEmpty == false {
                resolvedTitle = description
            } else if summary.isEmpty == false {
                resolvedTitle = summary
            } else {
                resolvedTitle = String(localized: "未命名待办")
            }

            return PendingTodoItem(
                id: record.id,
                title: resolvedTitle,
                timeText: pendingTimeText(for: record),
                record: record
            )
        }
    }

    private func pendingTimeText(for record: ScanRecord) -> String {
        if let eventDate = record.eventDate {
            return AppDateTimeFormatter.string(from: eventDate)
        }
        return AppDateTimeFormatter.string(from: record.createdAt)
    }

    @MainActor
    private func handlePhotoSelection(_ item: PhotosPickerItem) async {
        defer {
            selectedPhotoItem = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                activeAlert = HomeAlert(message: String(localized: "图片加载失败，请换一张图片重试。"))
                return
            }
            presentPendingAddConfirmation(for: image, source: "Photo")
        } catch {
            activeAlert = HomeAlert(message: String(localized: "读取照片失败，请稍后重试。"))
        }
    }

    @MainActor
    private func presentPendingAddConfirmation(
        for image: UIImage,
        source: String,
        titleOverride: String? = nil
    ) {
        let title: String
        if let titleOverride {
            title = titleOverride
        } else if source == "Camera" {
            title = String(localized: "确认添加拍照图片")
        } else if source == "Share" {
            title = String(localized: "确认添加共享图片")
        } else {
            title = String(localized: "确认添加相册图片")
        }

        pendingAddConfirmation = PendingAddConfirmation(
            kind: .image,
            image: image,
            source: source,
            title: title
        )
    }

    // 外部导入先在首页统一转成现有确认或自动解析动作，保证分享扩展、捷径、相册三条路径产出的记录结构一致。
    @MainActor
    private func consumePendingExternalImportIfNeeded() {
        guard let pendingImport = externalImportCenter.pendingImport else { return }
        externalImportCenter.clearPendingImport()

        // 外部入口已经完成 OCR 时，这里直接落库成已完成记录，避免再次弹确认或重复解析。
        if let recognizedText = pendingImport.recognizedText {
            insertPreParsedExternalRecord(
                recognizedText: recognizedText,
                imageData: pendingImport.imageData,
                source: pendingImport.source
            )
            return
        }

        guard let imageData = pendingImport.imageData,
              let image = UIImage(data: imageData) else {
            activeAlert = HomeAlert(message: String(localized: "共享图片读取失败，请重新分享一次。"))
            return
        }

        if pendingImport.autoProcess {
            Task {
                await enqueueImageForRecognition(image, source: pendingImport.source)
            }
            return
        }

        presentPendingAddConfirmation(
            for: image,
            source: pendingImport.source,
            titleOverride: String(localized: "确认添加共享图片")
        )
    }

    @MainActor
    private func insertPreParsedExternalRecord(
        recognizedText: String,
        imageData: Data?,
        source: String
    ) {
        let cleanedText = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanedText.isEmpty == false else {
            activeAlert = HomeAlert(message: String(localized: "共享图片没有识别到可用文字。"))
            return
        }

        let record = ScanRecord(
            summaryUpdatedAt: .now,
            summaryModelName: String(localized: "本地摘要"),
            imageData: imageData,
            source: source,
            recognizedText: cleanedText,
            summary: cleanedText,
            intent: .summary,
            note: "",
            isOCRCompleted: true,
            usedAISummary: false
        )
        modelContext.insert(record)
        try? modelContext.save()
        showToast(String(localized: "图片已自动解析并加入记录。"), duration: 2_600_000_000)
    }

    @MainActor
    private func consumeLatestExternalImportErrorIfNeeded() {
        guard let latestErrorMessage = externalImportCenter.latestErrorMessage else { return }
        externalImportCenter.clearLatestErrorMessage()
        activeAlert = HomeAlert(message: latestErrorMessage)
    }

    // 文字入口不经过 OCR，直接把用户输入按现有数据结构落库，并在 AI 开启时补充摘要。
    @MainActor
    private func enqueueTextForRecognition(_ text: String, source: String) async {
        let sanitizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sanitizedText.isEmpty == false else {
            activeAlert = HomeAlert(message: String(localized: "请输入需要记录的文字内容。"))
            return
        }

        let record = ScanRecord(
            imageData: nil,
            source: source,
            recognizedText: "",
            summary: String(localized: "正在处理文字..."),
            intent: .summary,
            note: "",
            isOCRCompleted: false,
            usedAISummary: false
        )
        modelContext.insert(record)
        try? modelContext.save()

        playSoftHaptic()
        showEnqueueToast()
        let recordID = record.id
        let runtimeConfig = AIProviderConfigStore.selectedRuntimeConfig()
        let useAI = aiSummaryEnabled

        Task {
            let result = await runTextRecognitionPipeline(
                text: sanitizedText,
                source: source,
                aiSummaryEnabled: useAI,
                config: runtimeConfig
            )
            await MainActor.run {
                applyRecognitionResult(result, to: recordID)
            }
        }
    }

    @MainActor
    private func enqueueImageForRecognition(_ image: UIImage, source: String) async {
        guard let imageData = image.jpegData(compressionQuality: 0.86) ?? image.pngData() else {
            activeAlert = HomeAlert(message: String(localized: "当前图片格式暂不支持，请重试。"))
            return
        }

        let record = ScanRecord(
            imageData: imageData,
            source: source,
            recognizedText: "",
            summary: String(localized: "正在识别内容..."),
            intent: .summary,
            note: "",
            isOCRCompleted: false,
            usedAISummary: false
        )
        modelContext.insert(record)
        try? modelContext.save()

        playSoftHaptic()
        showEnqueueToast()
        let recordID = record.id
        let runtimeConfig = AIProviderConfigStore.selectedRuntimeConfig()
        let useAI = aiSummaryEnabled

        Task {
            let result = await runRecognitionPipeline(
                imageData: imageData,
                source: source,
                aiSummaryEnabled: useAI,
                config: runtimeConfig
            )
            await MainActor.run {
                applyRecognitionResult(result, to: recordID)
            }
        }
    }

    // 文字录入与图片识别共用同一份 AI 结构化链路，确保首页三种入口的落库结构一致。
    private func runTextRecognitionPipeline(
        text: String,
        source: String,
        aiSummaryEnabled: Bool,
        config: AIProviderRuntimeConfig
    ) async -> OCRPipelineResult {
        let payload = InsightPayloadBuilder.build(
            source: source,
            recognizedText: text,
            imageData: nil
        )

        if aiSummaryEnabled, config.canRequestSummary {
            do {
                let aiInsight = try await AIProviderService.analyzeOCR(
                    rawText: payload.rawText,
                    config: config
                )
                return buildPipelineResultFromAI(
                    recognizedText: payload.rawText,
                    ocrFallbackText: payload.summary,
                    insight: aiInsight,
                    lineBoxes: [],
                    summaryModelName: config.summaryModelDisplayName
                )
            } catch {
                return buildPipelineResultFromOCR(
                    payload,
                    lineBoxes: [],
                    aiFallbackMessage: String(
                        localized: "AI 摘要请求失败，当前仅保留输入文字。\(error.localizedDescription)"
                    ),
                    didAISummaryRequestFail: true
                )
            }
        } else if aiSummaryEnabled {
            return buildPipelineResultFromOCR(
                payload,
                lineBoxes: [],
                aiFallbackMessage: String(localized: "AI 摘要已开启，但 Kimi 配置不完整，当前仅保留输入文字。")
            )
        }

        return buildPipelineResultFromOCR(payload, lineBoxes: [])
    }

    private func runRecognitionPipeline(
        imageData: Data,
        source: String,
        aiSummaryEnabled: Bool,
        config: AIProviderRuntimeConfig
    ) async -> OCRPipelineResult {
        #if canImport(UIKit)
        guard let image = UIImage(data: imageData) else {
            return OCRPipelineResult(
                recognizedText: "",
                summary: String(localized: "当前图片格式暂不支持，请重试。"),
                intent: .summary,
                eventTitle: nil,
                eventDate: nil,
                eventTime: nil,
                eventKeywords: [],
                eventDescription: nil,
                needTodo: false,
                isOCRCompleted: false,
                usedAISummary: false,
                lineBoxes: [],
                aiFallbackMessage: nil,
                didAISummaryRequestFail: false,
                summaryModelName: nil
            )
        }
        #else
        return OCRPipelineResult(
            recognizedText: "",
            summary: String(localized: "当前平台暂不支持 OCR。"),
            intent: .summary,
            eventTitle: nil,
            eventDate: nil,
            eventTime: nil,
            eventKeywords: [],
            eventDescription: nil,
            needTodo: false,
            isOCRCompleted: false,
            usedAISummary: false,
            lineBoxes: [],
            aiFallbackMessage: nil,
            didAISummaryRequestFail: false,
            summaryModelName: nil
        )
        #endif

        do {
            let recognition = try await VisionOCRService.recognize(from: image)
            let payload = InsightPayloadBuilder.build(
                source: source,
                recognizedText: recognition.text,
                imageData: imageData
            )

            // 只有 AI 开启且配置完整时才做摘要与结构化提取，其他情况只保留 OCR 原文。
            if aiSummaryEnabled, config.canRequestSummary {
                do {
                    let aiInsight = try await AIProviderService.analyzeOCR(
                        rawText: payload.rawText,
                        config: config
                    )
                    return buildPipelineResultFromAI(
                        recognizedText: payload.rawText,
                        ocrFallbackText: payload.summary,
                        insight: aiInsight,
                        lineBoxes: recognition.lineBoxes,
                        summaryModelName: config.summaryModelDisplayName
                    )
                } catch {
                    return buildPipelineResultFromOCR(
                        payload,
                        lineBoxes: recognition.lineBoxes,
                        aiFallbackMessage: String(
                            localized: "AI 摘要请求失败，当前仅保留 OCR 文本。\(error.localizedDescription)"
                        ),
                        didAISummaryRequestFail: true
                    )
                }
            } else if aiSummaryEnabled {
                return buildPipelineResultFromOCR(
                    payload,
                    lineBoxes: recognition.lineBoxes,
                    aiFallbackMessage: String(localized: "AI 摘要已开启，但 Kimi 配置不完整，当前仅保留 OCR 文本。")
                )
            }

            return buildPipelineResultFromOCR(payload, lineBoxes: recognition.lineBoxes)
        } catch VisionOCRServiceError.noRecognizedText {
            return OCRPipelineResult(
                recognizedText: "",
                summary: String(localized: "未识别到可用文字，请拍清晰一些或更换图片。"),
                intent: .summary,
                eventTitle: nil,
                eventDate: nil,
                eventTime: nil,
                eventKeywords: [],
                eventDescription: nil,
                needTodo: false,
                isOCRCompleted: false,
                usedAISummary: false,
                lineBoxes: [],
                aiFallbackMessage: nil,
                didAISummaryRequestFail: false,
                summaryModelName: nil
            )
        } catch VisionOCRServiceError.invalidImage {
            return OCRPipelineResult(
                recognizedText: "",
                summary: String(localized: "当前图片格式暂不支持，请重试。"),
                intent: .summary,
                eventTitle: nil,
                eventDate: nil,
                eventTime: nil,
                eventKeywords: [],
                eventDescription: nil,
                needTodo: false,
                isOCRCompleted: false,
                usedAISummary: false,
                lineBoxes: [],
                aiFallbackMessage: nil,
                didAISummaryRequestFail: false,
                summaryModelName: nil
            )
        } catch {
            return OCRPipelineResult(
                recognizedText: "",
                summary: String(localized: "OCR 识别失败，请稍后再试。"),
                intent: .summary,
                eventTitle: nil,
                eventDate: nil,
                eventTime: nil,
                eventKeywords: [],
                eventDescription: nil,
                needTodo: false,
                isOCRCompleted: false,
                usedAISummary: false,
                lineBoxes: [],
                aiFallbackMessage: nil,
                didAISummaryRequestFail: false,
                summaryModelName: nil
            )
        }
    }

    @MainActor
    private func applyRecognitionResult(_ result: OCRPipelineResult, to recordID: UUID) {
        guard let record = records.first(where: { $0.id == recordID }) else { return }

        record.recognizedText = result.recognizedText
        record.summary = result.summary
        record.intent = result.intent.rawValue
        record.eventTitle = result.eventTitle
        record.eventDate = result.eventDate
        record.eventTime = result.eventTime
        record.eventKeywordsText = result.eventKeywords.joined(separator: ",")
        record.eventDescription = result.eventDescription
        record.needTodo = result.needTodo
        record.isOCRCompleted = result.isOCRCompleted
        record.usedAISummary = result.usedAISummary
        record.summaryUpdatedAt = result.isOCRCompleted ? .now : record.summaryUpdatedAt
        record.summaryModelName = result.isOCRCompleted
            ? (result.usedAISummary ? result.summaryModelName : String(localized: "本地摘要"))
            : record.summaryModelName
        record.ocrLineBoxes = result.lineBoxes
        try? modelContext.save()

        if let aiFallbackMessage = result.aiFallbackMessage {
            showToast(aiFallbackMessage, duration: 4_000_000_000)
        }

        if result.isOCRCompleted {
            playSuccessHaptic()
            Task {
                if result.didAISummaryRequestFail {
                    await OCRCompletionNotifier.notifyAISummaryFailure(record: record)
                } else {
                    await OCRCompletionNotifier.notify(record: record)
                }
            }
        } else {
            activeAlert = HomeAlert(message: result.summary)
        }
    }

    @MainActor
    private func openPendingNotificationRecordIfNeeded() {
        guard scenePhase == .active else { return }
        guard let recordID = recordNavigationCenter.pendingRecordIDFromMemoryOrStore() else { return }
        presentRecordDetail(recordID, source: .notification)
    }

    @MainActor
    private func presentRecordDetail(_ recordID: UUID, source: RecordDetailOpenSource) {
        pendingNotificationPresentationTask?.cancel()
        pendingNotificationPresentationTask = nil

        switch source {
        case .manual:
            recordNavigationCenter.consumePendingRecordID()
            selectedRecordRoute = RecordDetailRoute(recordID: recordID)
        case .notification:
            pendingNotificationPresentationTask = Task { @MainActor in
                defer {
                    pendingNotificationPresentationTask = nil
                }

                try? await Task.sleep(for: .milliseconds(120))
                guard Task.isCancelled == false else { return }
                guard selectedRecordRoute == nil else { return }

                selectedRecordRoute = RecordDetailRoute(recordID: recordID)
                recordNavigationCenter.consumePendingRecordID()
            }
        }
    }

    private enum RecordDetailOpenSource {
        case manual
        case notification
    }

    @MainActor
    private func startCameraFlow() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            activeAlert = HomeAlert(message: String(localized: "当前设备不支持相机。"))
            return
        }

        let granted = await requestCameraPermissionIfNeeded()
        guard granted else {
            activeAlert = HomeAlert(message: String(localized: "未获得相机权限，请在系统设置中开启相机访问。"))
            return
        }

        isCameraPresented = true
    }

    private func requestCameraPermissionIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func playSoftHaptic() {
        HapticFeedbackService.impact(enabled: hapticsEnabled, intensity: hapticsIntensity)
    }

    private func playSuccessHaptic() {
        HapticFeedbackService.success(enabled: hapticsEnabled)
    }

    @MainActor
    private func toggleAddMenu() {
        triggerHaptic()
        if isAddMenuExpanded {
            collapseAddMenu()
        } else {
            expandAddMenu()
        }
    }

    @MainActor
    private func collapseAddMenu() {
        guard isAddMenuExpanded else { return }
        quickAddAnimationTask?.cancel()
        quickAddAnimationTask = nil
        isAddMenuExpanded = false
    }

    // 菜单点击后先收起圆环，再分发到具体入口，避免出现弹窗时菜单还停留在页面上。
    @MainActor
    private func handleQuickAddAction(_ action: QuickAddAction) {
        guard isAddMenuExpanded else { return }
        quickAddAnimationTask?.cancel()
        isAddMenuExpanded = false
        quickAddAnimationTask = Task { @MainActor in
            try? await Task.sleep(for: quickAddCollapseDuration)
            guard Task.isCancelled == false else { return }
            quickAddAnimationTask = nil
            triggerHaptic()

            switch action {
            case .text:
                pendingTextInput = ""
                pendingAddConfirmation = PendingAddConfirmation(
                    kind: .text,
                    image: nil,
                    source: "Text",
                    title: String(localized: "确认添加文字")
                )
            case .photo:
                isPhotoPickerPresented = true
            case .camera:
                Task {
                    await startCameraFlow()
                }
            }
        }
    }

    @MainActor
    private func expandAddMenu() {
        quickAddAnimationTask?.cancel()
        quickAddAnimationTask = nil
        isAddMenuExpanded = true
    }

    private func quickAddAnimation(for action: QuickAddAction) -> Animation {
        let expandDelay = Double(action.animationIndex) * 0.055
        let collapseDelay = Double(QuickAddAction.allCases.count - 1 - action.animationIndex) * 0.055
        return .spring(
            response: isAddMenuExpanded ? 0.28 : 0.22,
            dampingFraction: isAddMenuExpanded ? 0.82 : 0.88
        )
        .delay(isAddMenuExpanded ? expandDelay : collapseDelay)
    }

    private var quickAddCollapseDuration: Duration {
        let lastActionDelay = Double(max(QuickAddAction.allCases.count - 1, 0)) * 0.055
        let totalSeconds = lastActionDelay + 0.22
        return .milliseconds(Int((totalSeconds * 1000).rounded(.up)))
    }

    private var quickAddAnchorPosition: CGPoint {
        CGPoint(
            x: quickAddClusterSize - (quickAddPrimaryButtonSize / 2),
            y: quickAddClusterSize - (quickAddPrimaryButtonSize / 2)
        )
    }

    private var quickAddClusterSize: CGFloat { 220 }

    private var quickAddPrimaryButtonSize: CGFloat { 66 }

    private func buildPipelineResultFromAI(
        recognizedText: String,
        ocrFallbackText: String,
        insight: AIOCRInsight,
        lineBoxes: [OCRLineBox],
        summaryModelName: String
    ) -> OCRPipelineResult {
        // AI 未返回摘要时，直接回落到 OCR 原文，避免恢复已删除的本地摘要逻辑。
        let resolvedSummary = insight.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ocrFallbackText
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
        let hasScheduleDate = date != nil
        let todo = insight.needTodo
        let descriptionText = (resolvedDescription?.isEmpty == false) ? resolvedDescription : resolvedSummary

        return OCRPipelineResult(
            recognizedText: recognizedText,
            summary: resolvedSummary,
            intent: hasScheduleDate ? .schedule : .summary,
            eventTitle: resolvedTitle,
            eventDate: date,
            eventTime: normalizedTimeValue,
            eventKeywords: normalizedKeywords,
            eventDescription: descriptionText,
            needTodo: todo,
            isOCRCompleted: true,
            usedAISummary: true,
            lineBoxes: lineBoxes,
            aiFallbackMessage: nil,
            didAISummaryRequestFail: false,
            summaryModelName: summaryModelName
        )
    }

    private func buildPipelineResultFromOCR(
        _ payload: InsightPayload,
        lineBoxes: [OCRLineBox],
        aiFallbackMessage: String? = nil,
        didAISummaryRequestFail: Bool = false,
        summaryModelName: String? = nil
    ) -> OCRPipelineResult {
        let resolvedText = payload.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let eventDescription = resolvedText.isEmpty ? nil : resolvedText

        // 本地分支只同步 OCR 文本，事件结构化信息统一留给 AI 摘要阶段生成。
        return OCRPipelineResult(
            recognizedText: resolvedText,
            summary: resolvedText,
            intent: .summary,
            eventTitle: nil,
            eventDate: nil,
            eventTime: nil,
            eventKeywords: [],
            eventDescription: eventDescription,
            needTodo: false,
            isOCRCompleted: true,
            usedAISummary: false,
            lineBoxes: lineBoxes,
            aiFallbackMessage: aiFallbackMessage,
            didAISummaryRequestFail: didAISummaryRequestFail,
            summaryModelName: summaryModelName
        )
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

    @MainActor
    private func showEnqueueToast() {
        showToast(
            String(localized: "已加入记录，请稍候查看结果。"),
            duration: 2_800_000_000
        )
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
}

private struct PendingTodoItem: Identifiable {
    let id: UUID
    let title: String
    let timeText: String
    let record: ScanRecord
}

private struct PendingAddConfirmation: Identifiable {
    let kind: PendingAddConfirmationKind
    let id = UUID()
    let image: UIImage?
    let source: String
    let title: String
}

private enum PendingAddConfirmationKind: Equatable {
    case image
    case text
}

private struct HomeAlert: Identifiable {
    let id = UUID()
    let message: String
}

private struct OCRPipelineResult {
    let recognizedText: String
    let summary: String
    let intent: ScanIntent
    let eventTitle: String?
    let eventDate: Date?
    let eventTime: String?
    let eventKeywords: [String]
    let eventDescription: String?
    let needTodo: Bool
    let isOCRCompleted: Bool
    let usedAISummary: Bool
    let lineBoxes: [OCRLineBox]
    let aiFallbackMessage: String?
    let didAISummaryRequestFail: Bool
    let summaryModelName: String?
}

private struct PendingAddConfirmationSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    let pending: PendingAddConfirmation
    @Binding var text: String
    let aiSummaryEnabled: Bool
    let config: AIProviderRuntimeConfig
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @FocusState private var isTextEditorFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        contentCard

                        VStack(spacing: 6) {
                            Text(aiSummaryStatusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(modelInfoText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 24)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(pending.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color(uiColor: .systemBackground), for: .navigationBar)
            .onAppear {
                guard pending.kind == .text else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isTextEditorFocused = true
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 12) {
                Button(String(localized: "取消")) {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                Button(String(localized: "确认添加")) {
                    onConfirm()
                }
                .buttonStyle(.plain)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(AppTheme.primary, in: Capsule())
                .controlSize(.large)
                .disabled(confirmDisabled)
                .opacity(confirmDisabled ? 0.5 : 1)
            }
            .padding(.top, 12)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .background(Color(uiColor: .systemBackground))
        }
    }

    @ViewBuilder
    private var contentCard: some View {
        switch pending.kind {
        case .image:
            imagePreviewCard
        case .text:
            textInputCard
        }
    }

    private var imagePreviewCard: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color(uiColor: .secondarySystemBackground))
            .frame(maxWidth: .infinity, minHeight: 320, maxHeight: 460)
            .overlay {
                if let image = pending.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(18)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            }
            .padding(.horizontal, 20)
    }

    private var textInputCard: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color(uiColor: .secondarySystemBackground))
            .frame(maxWidth: .infinity, minHeight: 260)
            .overlay(alignment: .topLeading) {
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .foregroundStyle(colorScheme == .dark ? .white : .primary)
                    .focused($isTextEditorFocused)
                    .padding(16)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            }
            .padding(.horizontal, 20)
    }

    private var aiSummaryStatusText: String {
        aiSummaryEnabled
            ? String(localized: "AI 摘要：已开启")
            : String(localized: "AI 摘要：未开启")
    }

    private var modelInfoText: String {
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.isEmpty {
            return String(localized: "当前模型：\(config.provider.displayName)")
        }
        return String(localized: "当前模型：\(config.provider.displayName) · \(model)")
    }

    private var confirmDisabled: Bool {
        pending.kind == .text && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private enum QuickAddAction: CaseIterable, Identifiable {
    case text
    case photo
    case camera

    var id: Self { self }

    var animationIndex: Int {
        switch self {
        case .text:
            return 0
        case .photo:
            return 1
        case .camera:
            return 2
        }
    }

    var systemImage: String {
        switch self {
        case .text:
            return "square.and.pencil"
        case .photo:
            return "photo.on.rectangle.angled"
        case .camera:
            return "camera"
        }
    }

    // 通过固定角度把三个入口沿半圆展开，保持右下角按钮的空间关系稳定。
    var offset: CGSize {
        let radius: CGFloat = 96
        let angle: Double

        switch self {
        case .text:
            angle = 180
        case .photo:
            angle = 135
        case .camera:
            angle = 90
        }

        let radians = angle * .pi / 180
        return CGSize(
            width: cos(radians) * radius,
            height: -sin(radians) * radius
        )
    }
}

private struct AddMenuActionButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if #available(iOS 26.0, *) {
                    Circle()
                        .fill(Color.clear)
                } else {
                    Circle()
                        .fill(buttonFillColor)
                }

                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            .frame(width: 56, height: 56)
        }
        .buttonStyle(.plain)
        .modifier(AddMenuActionGlassModifier(tint: tint, colorScheme: colorScheme))
        .padding(6)
        .contentShape(Circle())
        .accessibilityLabel(accessibilityTitle)
    }

    private var iconColor: Color {
        colorScheme == .dark ? .white : tint
    }

    private var buttonFillColor: Color {
        colorScheme == .dark ? Color(uiColor: .secondarySystemBackground) : .white
    }

    private var accessibilityTitle: String {
        switch systemImage {
        case "square.and.pencil":
            return String(localized: "添加文字")
        case "photo.on.rectangle.angled":
            return String(localized: "添加相册图片")
        case "camera":
            return String(localized: "添加拍照图片")
        default:
            return systemImage
        }
    }
}

private struct AddMenuActionGlassModifier: ViewModifier {
    let tint: Color
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(glassTint).interactive(),
                    in: .circle
                )
                .shadow(color: shadowColor, radius: 8, x: 0, y: 4)
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: shadowColor, radius: 8, x: 0, y: 4)
        }
    }

    private var glassTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : tint.opacity(0.12)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.24) : Color.black.opacity(0.12)
    }
}

private struct HomeRecordCollage: View {
    let records: [ScanRecord]
    let onSelectRecord: (ScanRecord) -> Void
    @State private var animateCards = false

    var body: some View {
        ZStack {
            ForEach(Array(records.prefix(3).enumerated()), id: \.element.id) { index, record in
                collageCard(for: record, at: index)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear {
            playEntryAnimation()
        }
        .onChange(of: recordIDs) { _, _ in
            playEntryAnimation()
        }
    }

    private func collageCard(for record: ScanRecord, at index: Int) -> some View {
        let angle = angles[index % angles.count]
        let offset = offsets[index % offsets.count]
        let isFront = index == records.prefix(3).count - 1
        let targetAngle = animateCards ? angle : 0
        let targetOffsetX = animateCards ? offset.width : 0
        let targetOffsetY = animateCards ? offset.height : 0
        let targetScale = animateCards ? 1.0 : 0.64
        let targetOpacity = animateCards ? 1.0 : 0.0

        return Button {
            onSelectRecord(record)
        } label: {
            HomeCollageCard(
                record: record,
                angle: angle,
                offset: offset,
                isFront: isFront
            )
        }
        .buttonStyle(HomeCollageButtonStyle())
        .rotationEffect(.degrees(targetAngle))
        .offset(x: targetOffsetX, y: targetOffsetY)
        .scaleEffect(targetScale)
        .opacity(targetOpacity)
        .zIndex(Double(index))
        .animation(
            .spring(response: 0.50, dampingFraction: 0.78).delay(Double(index) * 0.10),
            value: animateCards
        )
    }

    private var angles: [Double] {
        [-10, 0, 10]
    }

    private var offsets: [CGSize] {
        [
            CGSize(width: -78, height: -4),
            CGSize(width: 0, height: 14),
            CGSize(width: 78, height: -4)
        ]
    }

    private var recordIDs: [UUID] {
        records.prefix(3).map(\.id)
    }

    private func playEntryAnimation() {
        animateCards = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            animateCards = true
        }
    }
}

private struct HomeCollageCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let record: ScanRecord
    let angle: Double
    let offset: CGSize
    let isFront: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(baseCardFill)

            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipped()
            } else {
                placeholderContent
            }
        }
        .frame(width: 120, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: shadowColor, radius: 8, x: 0, y: 3)
    }

    private var image: UIImage? {
        #if canImport(UIKit)
        guard let imageData = record.imageData else { return nil }
        return UIImage(data: imageData)
        #else
        return nil
        #endif
    }

    // 纯文字记录没有图片资源时，用统一文档图标占位，避免误导成图片丢失。
    @ViewBuilder
    private var placeholderContent: some View {
        if record.imageData == nil {
            Image(systemName: "append.page")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(AppTheme.primary.opacity(colorScheme == .dark ? 0.92 : 0.78))
        } else {
            Text(String(localized: "图片"))
                .font(.title2)
                .foregroundStyle(.primary.opacity(0.7))
        }
    }

    private var baseCardFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.72)
    }

    private var shadowColor: Color {
        if colorScheme == .dark {
            return Color.black.opacity(isFront ? 0.32 : 0.22)
        } else {
            return Color.black.opacity(isFront ? 0.12 : 0.08)
        }
    }
}

private struct HomeCollageButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.04 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

private struct RecordDetailRoute: Hashable, Identifiable {
    let recordID: UUID

    var id: UUID { recordID }
}

private struct RecordDetailDestinationView: View {
    @Environment(\.modelContext) private var modelContext

    let recordID: UUID

    @State private var record: ScanRecord?
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let record {
                ArchiveDetailView(record: record)
            } else {
                ContentUnavailableView(
                    String(localized: "正在打开记录"),
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(String(localized: "正在定位这条识别记录，请稍候。"))
                )
            }
        }
        .task(id: recordID) {
            await loadRecord()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    @MainActor
    private func loadRecord() async {
        loadTask?.cancel()
        record = nil

        loadTask = Task { @MainActor in
            for _ in 0..<15 {
                guard Task.isCancelled == false else { return }

                if let fetchedRecord = fetchRecord() {
                    record = fetchedRecord
                    return
                }

                try? await Task.sleep(for: .milliseconds(160))
            }
        }

        await loadTask?.value
    }

    @MainActor
    private func fetchRecord() -> ScanRecord? {
        var descriptor = FetchDescriptor<ScanRecord>(
            predicate: #Predicate { record in
                record.id == recordID
            }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}

private extension View {
    @ViewBuilder
    func homeRegularGlass(cornerRadius: CGFloat, tint: Color, enabled: Bool = true) -> some View {
        if #available(iOS 26.0, *), enabled {
            self.glassEffect(
                .regular.tint(tint),
                in: .rect(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            self
        }
    }

    @ViewBuilder
    func homeInteractiveGlass(cornerRadius: CGFloat, tint: Color) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(
                .regular.tint(tint).interactive(),
                in: .rect(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            self
        }
    }
}

#Preview {
    HomeScannerView()
        .modelContainer(for: ScanRecord.self, inMemory: true)
}
