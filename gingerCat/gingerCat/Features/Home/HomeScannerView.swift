import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

struct HomeScannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \ScanRecord.createdAt, order: .reverse) private var records: [ScanRecord]

    @AppStorage(KimiSettingsKeys.baseURL) private var kimiBaseURL = KimiRuntimeConfig.defaultBaseURL
    @AppStorage(KimiSettingsKeys.model) private var kimiModel = KimiRuntimeConfig.defaultModel
    @AppStorage(KimiSettingsKeys.apiKey) private var kimiAPIKey = ""
    @AppStorage(KimiSettingsKeys.maxTokens) private var kimiMaxTokens = ""
    @AppStorage(KimiSettingsKeys.temperature) private var kimiTemperature = ""
    @AppStorage(KimiSettingsKeys.topP) private var kimiTopP = ""
    @AppStorage(KimiSettingsKeys.aiSummaryEnabled) private var aiSummaryEnabled = false
    @AppStorage(KimiSettingsKeys.haptics) private var hapticsEnabled = true

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false

    @State private var isCameraPresented = false
    @State private var capturedCameraImage: UIImage?

    @State private var activeAlert: HomeAlert?
    @State private var isSettingsPresented = false
    @State private var isArchivePresented = false
    @State private var selectedPendingRecord: ScanRecord?
    @ObservedObject private var recordNavigationCenter = RecordNavigationCenter.shared
    @GestureState private var isQuickAddPressed = false

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

                floatingAddButtonLayer
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
            .navigationDestination(item: $selectedPendingRecord) { record in
                ArchiveDetailView(record: record)
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
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    await handlePhotoSelection(newItem)
                }
            }
            .onChange(of: capturedCameraImage) { _, newImage in
                guard let newImage else { return }
                Task {
                    await enqueueImageForRecognition(newImage, source: "Camera")
                    capturedCameraImage = nil
                }
            }
            .onAppear {
                openPendingNotificationRecordIfNeeded()
            }
            .onChange(of: records.map(\.id)) { _, _ in
                openPendingNotificationRecordIfNeeded()
            }
            .onReceive(recordNavigationCenter.$pendingRecordID) { _ in
                openPendingNotificationRecordIfNeeded()
            }
            .alert(item: $activeAlert) { alert in
                Alert(
                    title: Text(String(localized: "提示")),
                    message: Text(alert.message),
                    dismissButton: .default(Text(String(localized: "知道了")))
                )
            }
        }
    }

    private var homeBackground: some View {
        Color(uiColor: .systemBackground)
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
                    isArchivePresented = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
            }

            if records.isEmpty {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(moduleBackgroundColor)
                    .frame(height: 240)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(cardBorderColor, lineWidth: 1)
                    }
                    .overlay {
                        homeEmptyState(
                            systemImage: "photo.on.rectangle.angled",
                            title: String(localized: "暂无记录"),
                            message: String(localized: "扫描图片后，最近三条记录会展示在这里。")
                        )
                        .padding(20)
                    }
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(moduleBackgroundColor)
                    .frame(height: 240)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(cardBorderColor, lineWidth: 1)
                    }
                    .homeRegularGlass(cornerRadius: 16, tint: cardGlassTint, enabled: colorScheme == .light)
                    .overlay {
                        HomeRecordCollage(records: Array(records.prefix(3)))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    }
            }
        }
    }

    private var pendingTodosSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "最近待办事项"))
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)

            if pendingTodos.isEmpty {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(moduleBackgroundColor)
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(cardBorderColor, lineWidth: 1)
                    }
                    .overlay {
                        homeEmptyState(
                            systemImage: "checklist",
                            title: String(localized: "暂无待办"),
                            message: String(localized: "识别出时间或事件后，这里会自动出现最近待办。")
                        )
                        .padding(20)
                    }
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(moduleBackgroundColor)
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(cardBorderColor, lineWidth: 1)
                    }
                    .overlay {
                        VStack(spacing: 0) {
                            ForEach(Array(pendingTodos.enumerated()), id: \.element.id) { index, item in
                                Button {
                                    selectedPendingRecord = item.record
                                } label: {
                                    pendingTodoRow(item)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 14)
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())

                                if index < pendingTodos.count - 1 {
                                    Divider()
                                        .padding(.leading, 56)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
            }
        }
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
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colorScheme == .dark ? Color.black.opacity(0.18) : Color.white.opacity(0.72))
        }
    }

    private var floatingAddButtonLayer: some View {
        VStack {
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                quickAddButton
            }
        }
        .padding(.trailing, 24)
        .padding(.bottom, 24)
    }

    private func pendingTodoRow(_ item: PendingTodoItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(pendingTodoPrimaryTextColor)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(pendingTodoPrimaryTextColor)
                    .lineLimit(2)

                Text(item.timeText)
                    .font(.subheadline)
                    .foregroundStyle(pendingTodoSecondaryTextColor)
            }

            Spacer(minLength: 0)
        }
    }

    private var quickAddButton: some View {
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
            }
            .homeRegularGlass(cornerRadius: 33, tint: AppTheme.primary.opacity(0.24))
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.16), radius: 8, x: 0, y: 4)
            .scaleEffect(isQuickAddPressed ? 0.93 : 1.0)
            .brightness(isQuickAddPressed ? -0.05 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.78), value: isQuickAddPressed)
            .onTapGesture {
                isPhotoPickerPresented = true
            }
            .onLongPressGesture(minimumDuration: 0.6) {
                Task {
                    await startCameraFlow()
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isQuickAddPressed) { _, state, _ in
                        state = true
                    }
            )
            .contentShape(Circle())
            .accessibilityLabel(String(localized: "添加识别"))
            .accessibilityHint(String(localized: "点击选图，长按拍照"))
    }

    private var moduleBackgroundColor: Color {
        colorScheme == .dark ? Color(uiColor: .secondarySystemBackground) : .white
    }

    private var cardGlassTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.03)
    }

    private var accentGlassTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.24) : Color.black.opacity(0.05)
    }

    private var cardBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.24) : Color.black.opacity(0.16)
    }

    private var pendingTodoPrimaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.96) : Color.black.opacity(0.86)
    }

    private var pendingTodoSecondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.58)
    }

    private var pendingTodos: [PendingTodoItem] {
        let todoRecords = records
            .filter { $0.resolvedIntent == .schedule }
            .sorted { lhs, rhs in
                (lhs.eventDate ?? lhs.createdAt) < (rhs.eventDate ?? rhs.createdAt)
            }
        
        return Array(todoRecords.prefix(3)).map { record in
            let title = record.eventTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedTitle: String
            if let title, title.isEmpty == false {
                resolvedTitle = title
            } else if summary.isEmpty == false {
                resolvedTitle = summary
            } else {
                resolvedTitle = String(localized: "未命名待办")
            }
            let date = record.eventDate ?? record.createdAt

            return PendingTodoItem(
                id: record.id,
                title: resolvedTitle,
                timeText: pendingDateFormatter.string(from: date),
                record: record
            )
        }
    }

    private var pendingDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
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
            await enqueueImageForRecognition(image, source: "Photo")
        } catch {
            activeAlert = HomeAlert(message: String(localized: "读取照片失败，请稍后重试。"))
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
        let recordID = record.id
        let runtimeConfig = kimiConfig
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

    private func runRecognitionPipeline(
        imageData: Data,
        source: String,
        aiSummaryEnabled: Bool,
        config: KimiRuntimeConfig
    ) async -> OCRPipelineResult {
        #if canImport(UIKit)
        guard let image = UIImage(data: imageData) else {
            return OCRPipelineResult(
                recognizedText: "",
                summary: String(localized: "当前图片格式暂不支持，请重试。"),
                intent: .summary,
                eventTitle: nil,
                eventDate: nil,
                isOCRCompleted: false,
                usedAISummary: false
            )
        }
        #else
        return OCRPipelineResult(
            recognizedText: "",
            summary: String(localized: "当前平台暂不支持 OCR。"),
            intent: .summary,
            eventTitle: nil,
            eventDate: nil,
            isOCRCompleted: false,
            usedAISummary: false
        )
        #endif

        do {
            let recognizedText = try await VisionOCRService.recognizeText(from: image)
            let payload = InsightPayloadBuilder.build(
                source: source,
                recognizedText: recognizedText,
                imageData: imageData
            )

            var finalSummary = payload.summary
            var usedAI = false
            if aiSummaryEnabled, config.canRequestSummary {
                if let aiSummary = try? await KimiAIService.summarize(
                    rawText: payload.rawText,
                    mode: payload.mode,
                    events: payload.events,
                    config: config
                ) {
                    finalSummary = aiSummary
                    usedAI = true
                }
            }

            return OCRPipelineResult(
                recognizedText: payload.rawText,
                summary: finalSummary,
                intent: payload.mode.intent,
                eventTitle: payload.events.first?.title,
                eventDate: payload.events.first?.date,
                isOCRCompleted: true,
                usedAISummary: usedAI
            )
        } catch VisionOCRServiceError.noRecognizedText {
            return OCRPipelineResult(
                recognizedText: "",
                summary: String(localized: "未识别到可用文字，请拍清晰一些或更换图片。"),
                intent: .summary,
                eventTitle: nil,
                eventDate: nil,
                isOCRCompleted: false,
                usedAISummary: false
            )
        } catch VisionOCRServiceError.invalidImage {
            return OCRPipelineResult(
                recognizedText: "",
                summary: String(localized: "当前图片格式暂不支持，请重试。"),
                intent: .summary,
                eventTitle: nil,
                eventDate: nil,
                isOCRCompleted: false,
                usedAISummary: false
            )
        } catch {
            return OCRPipelineResult(
                recognizedText: "",
                summary: String(localized: "OCR 识别失败，请稍后再试。"),
                intent: .summary,
                eventTitle: nil,
                eventDate: nil,
                isOCRCompleted: false,
                usedAISummary: false
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
        record.isOCRCompleted = result.isOCRCompleted
        record.usedAISummary = result.usedAISummary
        try? modelContext.save()

        if result.isOCRCompleted {
            playSuccessHaptic()
            let completionTitle = completionNotificationTitle(for: record)
            Task {
                await OCRCompletionNotificationService.notify(
                    recordID: record.id,
                    title: completionTitle
                )
            }
        } else {
            activeAlert = HomeAlert(message: result.summary)
        }
    }

    @MainActor
    private func openPendingNotificationRecordIfNeeded() {
        guard let recordID = recordNavigationCenter.pendingRecordID else { return }
        guard let record = records.first(where: { $0.id == recordID }) else { return }
        selectedPendingRecord = record
        recordNavigationCenter.consumePendingRecordID()
    }

    private func completionNotificationTitle(for record: ScanRecord) -> String {
        if let title = record.eventTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           title.isEmpty == false {
            return title
        }
        let summary = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if summary.isEmpty {
            return String(localized: "识别记录")
        }
        return String(summary.prefix(18))
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
        #if canImport(UIKit)
        guard hapticsEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred()
        #endif
    }

    private func playSuccessHaptic() {
        #if canImport(UIKit)
        guard hapticsEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }

    private var kimiConfig: KimiRuntimeConfig {
        KimiRuntimeConfig(
            baseURL: sanitized(kimiBaseURL, fallback: KimiRuntimeConfig.defaultBaseURL),
            model: sanitized(kimiModel, fallback: KimiRuntimeConfig.defaultModel),
            apiKey: kimiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines),
            maxTokens: parseInt(kimiMaxTokens),
            temperature: parseDouble(kimiTemperature),
            topP: parseDouble(kimiTopP)
        )
    }

    private func sanitized(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func parseInt(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        return Int(trimmed)
    }

    private func parseDouble(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        return Double(trimmed)
    }
}

private struct PendingTodoItem: Identifiable {
    let id: UUID
    let title: String
    let timeText: String
    let record: ScanRecord
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
    let isOCRCompleted: Bool
    let usedAISummary: Bool
}

private enum OCRCompletionNotificationService {
    static func notify(recordID: UUID, title: String) async {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = String(localized: "识别完成")
            content.body = "\(title) \(String(localized: "内容摘要已完成"))"
            content.sound = .default
            content.userInfo = ["recordID": recordID.uuidString]

            let request = UNNotificationRequest(
                identifier: "ocr.summary.\(recordID.uuidString)",
                content: content,
                trigger: nil
            )
            try await center.add(request)
        } catch {
            // Silent fail: local notification should not interrupt main OCR flow.
        }
    }
}

private struct HomeRecordCollage: View {
    let records: [ScanRecord]
    @State private var animateCards = false

    var body: some View {
        ZStack {
            ForEach(Array(records.prefix(3).enumerated()), id: \.element.id) { index, record in
                HomeCollageCard(
                    record: record,
                    angle: angles[index % angles.count],
                    offset: offsets[index % offsets.count],
                    isFront: index == records.prefix(3).count - 1
                )
                .rotationEffect(.degrees(animateCards ? angles[index % angles.count] : 0))
                .offset(
                    x: animateCards ? offsets[index % offsets.count].width : 0,
                    y: animateCards ? offsets[index % offsets.count].height : 0
                )
                .scaleEffect(animateCards ? 1 : 0.64)
                .opacity(animateCards ? 1 : 0)
                .zIndex(Double(index))
                .animation(
                    .spring(response: 0.50, dampingFraction: 0.78).delay(Double(index) * 0.10),
                    value: animateCards
                )
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

    private var angles: [Double] {
        [-13, -2, 13]
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
                Text(String(localized: "图片"))
                    .font(.title2)
                    .foregroundStyle(.primary.opacity(0.7))
            }
        }
        .frame(width: 120, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isFront ? AppTheme.primary.opacity(colorScheme == .dark ? 0.70 : 0.45) : neutralBorderColor,
                    lineWidth: isFront ? 2.5 : 1
                )
        }
        .homeRegularGlass(cornerRadius: 14, tint: glassTint, enabled: colorScheme == .light)
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

    private var baseCardFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.72)
    }

    private var neutralBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.34) : Color.black.opacity(0.18)
    }

    private var glassTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : AppTheme.primary.opacity(0.10)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.28) : AppTheme.primary.opacity(0.10)
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
