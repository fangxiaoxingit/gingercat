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
    @Query(sort: \ScanRecord.createdAt, order: .reverse) private var records: [ScanRecord]

    @AppStorage(KimiSettingsKeys.baseURL) private var kimiBaseURL = KimiRuntimeConfig.defaultBaseURL
    @AppStorage(KimiSettingsKeys.model) private var kimiModel = KimiRuntimeConfig.defaultModel
    @AppStorage(KimiSettingsKeys.apiKey) private var kimiAPIKey = ""
    @AppStorage(KimiSettingsKeys.maxTokens) private var kimiMaxTokens = ""
    @AppStorage(KimiSettingsKeys.temperature) private var kimiTemperature = ""
    @AppStorage(KimiSettingsKeys.topP) private var kimiTopP = ""
    @AppStorage(KimiSettingsKeys.aiSummaryEnabled) private var aiSummaryEnabled = false
    @AppStorage(KimiSettingsKeys.haptics) private var hapticsEnabled = true

    @State private var activeInsight: InsightPayload?

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false

    @State private var isCameraPresented = false
    @State private var capturedCameraImage: UIImage?

    @State private var isProcessingOCR = false
    @State private var processingMessage = String(localized: "正在执行 OCR 识别...")
    @State private var activeAlert: HomeAlert?

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
                .allowsHitTesting(isProcessingOCR == false)

                floatingAddButtonLayer

                if isProcessingOCR {
                    processingOverlay
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $activeInsight) { payload in
                InsightDrawerView(payload: payload) { record in
                    withAnimation {
                        modelContext.insert(record)
                    }
                    playSuccessHaptic()
                }
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
                    await processSelectedImage(newImage, source: "Camera")
                    capturedCameraImage = nil
                }
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
        ZStack {
            Color(uiColor: colorScheme == .dark ? .black : .systemGray6)
            .ignoresSafeArea()

            DotGridBackground(dotColor: colorScheme == .dark ? .white.opacity(0.18) : .black.opacity(0.16))
                .ignoresSafeArea()
        }
    }

    private var homeWireframeLayout: some View {
        Group {
            if #available(iOS 26.0, *) {
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
            topHeader
            recentRecordsSection
            pendingTodosSection
        }
    }

    private var topHeader: some View {
        HStack {
            Text(String(localized: "首页"))
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            NavigationLink {
                SettingsView()
            } label: {
                Circle()
                    .fill(moduleBackgroundColor)
                    .frame(width: 54, height: 54)
                    .overlay {
                        Circle()
                            .stroke(cardBorderColor, lineWidth: 1)
                    }
                    .overlay {
                        Image(systemName: "gearshape")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .homeInteractiveGlass(cornerRadius: 27, tint: accentGlassTint)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
    }

    private var recentRecordsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(String(localized: "最近记录"))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                NavigationLink {
                    ArchiveView()
                } label: {
                    Circle()
                        .fill(moduleBackgroundColor)
                        .frame(width: 48, height: 48)
                        .overlay {
                            Circle()
                                .stroke(cardBorderColor, lineWidth: 1)
                        }
                        .overlay {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        .homeInteractiveGlass(cornerRadius: 24, tint: accentGlassTint)
                }
                .buttonStyle(.plain)
            }

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(moduleBackgroundColor.opacity(0.92))
                .frame(height: 320)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(cardBorderColor, lineWidth: 1)
                }
                .homeRegularGlass(cornerRadius: 16, tint: cardGlassTint)
                .overlay {
                    HomeRecordCollage(records: Array(records.prefix(3)))
                        .padding(22)
                }
        }
    }

    private var pendingTodosSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "最近待办事项"))
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(moduleBackgroundColor.opacity(0.92))
                .frame(minHeight: 280)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(cardBorderColor, lineWidth: 1)
                }
                .homeRegularGlass(cornerRadius: 16, tint: cardGlassTint)
                .overlay(alignment: .topLeading) {
                    if pendingTodos.isEmpty {
                        Text(String(localized: "暂无待办，点击右下角 + 开始识别"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(20)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(pendingTodos.enumerated()), id: \.element.id) { index, item in
                                NavigationLink {
                                    ArchiveDetailView(record: item.record)
                                } label: {
                                    pendingTodoRow(item)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 14)
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
        .allowsHitTesting(isProcessingOCR == false)
    }

    private func pendingTodoRow(_ item: PendingTodoItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(moduleBackgroundColor)
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.26 : 0.75), lineWidth: 1)
                }
                .homeRegularGlass(cornerRadius: 17, tint: accentGlassTint)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(item.timeText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var quickAddButton: some View {
        Circle()
            .fill(moduleBackgroundColor)
            .frame(width: 84, height: 84)
            .overlay {
                Circle()
                    .stroke(cardBorderColor, lineWidth: 1)
            }
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.primary)
            }
            .homeInteractiveGlass(cornerRadius: 42, tint: accentGlassTint)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.12), radius: 12, x: 0, y: 6)
            .onTapGesture {
                guard isProcessingOCR == false else { return }
                isPhotoPickerPresented = true
            }
            .onLongPressGesture(minimumDuration: 0.6) {
                guard isProcessingOCR == false else { return }
                Task {
                    await startCameraFlow()
                }
            }
            .accessibilityLabel(String(localized: "添加识别"))
            .accessibilityHint(String(localized: "点击选图，长按拍照"))
    }

    private var moduleBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : .white
    }

    private var cardGlassTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.03)
    }

    private var accentGlassTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.20) : Color.black.opacity(0.05)
    }

    private var cardBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.28) : Color.black.opacity(0.18)
    }

    private var pendingTodos: [PendingTodoItem] {
        let scheduleCandidates = records
            .filter { $0.resolvedIntent == .schedule }
            .sorted { lhs, rhs in
                (lhs.eventDate ?? lhs.createdAt) < (rhs.eventDate ?? rhs.createdAt)
            }
        let candidates = scheduleCandidates.isEmpty ? records : scheduleCandidates

        return Array(candidates.prefix(3)).map { record in
            let title = record.eventTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedTitle = (title?.isEmpty == false) ? title! : record.summary
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

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            GlassCard {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text(processingMessage)
                        .font(.subheadline)
                }
            }
            .padding(.horizontal, 32)
        }
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
            await processSelectedImage(image, source: "Photo")
        } catch {
            activeAlert = HomeAlert(message: String(localized: "读取照片失败，请稍后重试。"))
        }
    }

    @MainActor
    private func processSelectedImage(_ image: UIImage, source: String) async {
        playSoftHaptic()
        processingMessage = String(localized: "正在执行 OCR 识别...")
        isProcessingOCR = true
        defer {
            isProcessingOCR = false
        }

        do {
            let recognizedText = try await VisionOCRService.recognizeText(from: image)
            let imageData = image.jpegData(compressionQuality: 0.86) ?? image.pngData()
            let localPayload = InsightPayloadBuilder.build(
                source: source,
                recognizedText: recognizedText,
                imageData: imageData
            )
            processingMessage = aiSummaryEnabled ? String(localized: "正在生成 AI 摘要...") : String(localized: "正在整理结果...")
            activeInsight = await applyAISummaryIfNeeded(for: localPayload)
        } catch VisionOCRServiceError.noRecognizedText {
            activeAlert = HomeAlert(message: String(localized: "未识别到可用文字，请拍清晰一些或更换图片。"))
        } catch VisionOCRServiceError.invalidImage {
            activeAlert = HomeAlert(message: String(localized: "当前图片格式暂不支持，请重试。"))
        } catch {
            activeAlert = HomeAlert(message: String(localized: "OCR 识别失败，请稍后再试。"))
        }
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

    @MainActor
    private func applyAISummaryIfNeeded(for payload: InsightPayload) async -> InsightPayload {
        guard aiSummaryEnabled else {
            return payload
        }

        let config = kimiConfig
        guard config.canRequestSummary else {
            activeAlert = HomeAlert(message: String(localized: "已开启 AI 总结，但 Kimi 配置不完整，已回退到本地摘要。"))
            return payload
        }

        do {
            let aiSummary = try await KimiAIService.summarize(
                rawText: payload.rawText,
                mode: payload.mode,
                events: payload.events,
                config: config
            )

            return InsightPayload(
                imageData: payload.imageData,
                source: payload.source,
                rawText: payload.rawText,
                summary: aiSummary,
                summarySource: .ai,
                mode: payload.mode,
                events: payload.events
            )
        } catch {
            activeAlert = HomeAlert(message: String(localized: "AI 总结失败，已回退到本地摘要。"))
            return payload
        }
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

private struct DotGridBackground: View {
    let dotColor: Color

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let step: CGFloat = 38
                let diameter: CGFloat = 3
                for x in stride(from: CGFloat(8), through: size.width + step, by: step) {
                    for y in stride(from: CGFloat(8), through: size.height + step, by: step) {
                        let dot = CGRect(x: x, y: y, width: diameter, height: diameter)
                        context.fill(Path(ellipseIn: dot), with: .color(dotColor))
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
    }
}

private struct HomeRecordCollage: View {
    let records: [ScanRecord]
    @State private var animateCards = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                HomeCollageCard(
                    record: records.indices.contains(index) ? records[index] : nil,
                    angle: angles[index % angles.count],
                    offset: offsets[index % offsets.count],
                    isFront: index == topRecordIndex
                )
                .opacity(animateCards ? 1 : 0)
                .scaleEffect(animateCards ? 1 : 0.92)
                .offset(y: animateCards ? 0 : 14)
                .animation(
                    .spring(response: 0.42, dampingFraction: 0.82).delay(Double(index) * 0.08),
                    value: animateCards
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            animateCards = true
        }
    }

    private var angles: [Double] {
        [-14, -2, 14]
    }

    private var offsets: [CGSize] {
        [
            CGSize(width: -78, height: -4),
            CGSize(width: 0, height: 16),
            CGSize(width: 78, height: -4)
        ]
    }

    private var topRecordIndex: Int {
        if records.isEmpty {
            return 2
        }
        return min(records.count - 1, 2)
    }
}

private struct HomeCollageCard: View {
    let record: ScanRecord?
    let angle: Double
    let offset: CGSize
    let isFront: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.42))
            .overlay {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    Text(String(localized: "图片"))
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isFront ? AppTheme.primary.opacity(0.45) : Color.white.opacity(0.74),
                        lineWidth: isFront ? 2.5 : 1
                    )
            }
            .homeRegularGlass(cornerRadius: 16, tint: AppTheme.primary.opacity(0.12))
            .frame(width: 185, height: 185)
            .rotationEffect(.degrees(angle))
            .offset(offset)
            .shadow(color: isFront ? AppTheme.primary.opacity(0.12) : .clear, radius: 6, x: 0, y: 2)
    }

    private var image: UIImage? {
        #if canImport(UIKit)
        guard let record, let imageData = record.imageData else { return nil }
        return UIImage(data: imageData)
        #else
        return nil
        #endif
    }
}

private extension View {
    @ViewBuilder
    func homeRegularGlass(cornerRadius: CGFloat, tint: Color) -> some View {
        if #available(iOS 26.0, *) {
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
