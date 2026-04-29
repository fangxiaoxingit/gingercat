import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query(sort: \ScanRecord.createdAt, order: .reverse) private var records: [ScanRecord]
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppSettingsKeys.aiSummaryEnabled) private var aiSummaryEnabled = false
    @AppStorage(AppSettingsKeys.autoAddTodoAfterAISummary) private var autoAddTodoAfterAISummary = true
    @AppStorage(AppSettingsKeys.todoDueReminderEnabled) private var todoDueReminderEnabled = true
    @AppStorage(AppSettingsKeys.todoDueReminderTime) private var todoDueReminderTimeRaw = "08:00"
    @AppStorage(AppSettingsKeys.haptics) private var hapticsEnabled = true
    @AppStorage(AppSettingsKeys.hapticsIntensity) private var hapticsIntensityRaw = HapticFeedbackIntensity.medium.rawValue
    @AppStorage(AppSettingsKeys.appearanceMode) private var appearanceModeRaw = AppearanceMode.automatic.rawValue
    @AppStorage(AppSettingsKeys.language) private var languageRaw = AppLanguage.automatic.rawValue
    @AppStorage(AIProviderSettingsKeys.selectedProvider) private var selectedProviderRaw = AIProvider.kimi.rawValue
    @State private var dueReminderRefreshTask: Task<Void, Never>?
    @State private var isProviderListExpanded = true

    private var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceModeRaw) ?? .automatic }
        set { appearanceModeRaw = newValue.rawValue }
    }

    private var appLanguage: AppLanguage {
        get { AppLanguage(rawValue: languageRaw) ?? .automatic }
        set { languageRaw = newValue.rawValue }
    }

    private var hapticsIntensity: HapticFeedbackIntensity {
        get { HapticFeedbackIntensity(rawValue: hapticsIntensityRaw) ?? .medium }
        set { hapticsIntensityRaw = newValue.rawValue }
    }

    private var selectedProvider: AIProvider {
        AIProvider(rawValue: selectedProviderRaw) ?? .kimi
    }

    private var dueReminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                DueReminderTimeParser.date(from: todoDueReminderTimeRaw)
                    ?? DueReminderTimeParser.defaultDate
            },
            set: { newValue in
                todoDueReminderTimeRaw = DueReminderTimeParser.string(from: newValue)
            }
        )
    }

    private var todoDueReminderSyncSignatures: [TodoDueReminderSyncSignature] {
        records.map { record in
            TodoDueReminderSyncSignature(
                id: record.id,
                createdAt: record.createdAt,
                eventDate: record.eventDate,
                intent: record.resolvedIntent.rawValue,
                needTodo: record.needTodo,
                eventTitle: record.eventTitle ?? "",
                eventDescription: record.eventDescription ?? "",
                todoEventsJSON: record.todoEventsJSON
            )
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackground()

                ScrollView {
                    if #available(iOS 26, *) {
                        GlassEffectContainer(spacing: 14) {
                            settingsSections
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                    } else {
                        settingsSections
                            .padding(.horizontal, 16)
                            .padding(.vertical, 20)
                    }
                }
            }
            .navigationTitle(String(appLocalized: "设置"))
            .onAppear {
                scheduleDueReminderRefresh()
            }
            .onChange(of: todoDueReminderEnabled) { _, _ in
                scheduleDueReminderRefresh()
            }
            .onChange(of: todoDueReminderTimeRaw) { _, _ in
                scheduleDueReminderRefresh()
            }
            .onChange(of: todoDueReminderSyncSignatures) { _, _ in
                scheduleDueReminderRefresh()
            }
            .onDisappear {
                dueReminderRefreshTask?.cancel()
                dueReminderRefreshTask = nil
            }
        }
    }

    private var settingsSections: some View {
        VStack(alignment: .leading, spacing: 14) {
            appHeaderSection
            usageGuideEntrySection
            aiSwitchSection
            appSettingsSection
        }
    }

    private var appHeaderSection: some View {
        GlassCard(cornerRadius: 22) {
            HStack(spacing: 14) {
                Image("BrandLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.36), lineWidth: 0.8)
                    )
                    .shadow(
                        color: AppTheme.primary.opacity(colorScheme == .dark ? 0.24 : 0.12),
                        radius: 14,
                        x: 0,
                        y: 8
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text("大橘小事")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(String(appLocalized: "截图识别、待办整理、取件提醒"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var usageGuideEntrySection: some View {
        NavigationLink {
            AppUsageGuideView()
        } label: {
            GlassCard(cornerRadius: 20) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppTheme.primary.opacity(colorScheme == .dark ? 0.18 : 0.12))
                            .frame(width: 48, height: 48)

                        Image(systemName: "book.pages")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.primary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(appLocalized: "使用说明"))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(String(appLocalized: "查看功能特性、使用路径与隐私说明"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var aiSwitchSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(String(appLocalized: "AI 总结"), systemImage: "sparkles")
                    .font(.headline)
                Toggle(String(appLocalized: "启用 AI 总结"), isOn: $aiSummaryEnabled)
                Text(String(appLocalized: "默认关闭。开启后会在 OCR 结果基础上调用模型生成摘要。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if aiSummaryEnabled {
                    Divider()
                        .padding(.top, 2)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isProviderListExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Text(String(appLocalized: "模型列表"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Spacer(minLength: 0)

                            Image(systemName: isProviderListExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    VStack(spacing: 0) {
                        ForEach(Array(visibleProviders.enumerated()), id: \.element.id) { index, provider in
                            providerRow(provider)

                            if index < visibleProviders.count - 1 {
                                Divider()
                                    .padding(.leading, 52)
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: isProviderListExpanded)
                }
            }
        }
    }

    private var visibleProviders: [AIProvider] {
        if isProviderListExpanded {
            return AIProvider.allCases
        }
        return [selectedProvider]
    }

    private func providerRow(_ provider: AIProvider) -> some View {
        let config = AIProviderConfigStore.runtimeConfig(for: provider)

        return HStack(spacing: 0) {
            Button {
                selectedProviderRaw = provider.rawValue
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selectedProvider == provider ? "checkmark.circle.fill" : "circle")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(selectedProvider == provider ? AppTheme.primary : .secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(provider.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(provider.detailText)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(String(appLocalized: "当前模型：\(config.model)"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .padding(.trailing, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 30)
                .padding(.trailing, 6)

            NavigationLink {
                AIProviderConfigView(
                    provider: provider,
                    selectedProviderRaw: $selectedProviderRaw
                )
            } label: {
                HStack(spacing: 6) {
                    Text(String(appLocalized: "配置"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 52)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var appSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(appLocalized: "APP 设置"))
                .font(.headline)
                .foregroundStyle(.primary)

            GlassCard(cornerRadius: 18) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "bell.badge")
                            .font(.body)
                            .foregroundStyle(AppTheme.primary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(appLocalized: "到期提醒"))
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Text(String(appLocalized: "当天有待办时，在设定时间推送系统通知"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        Toggle("", isOn: $todoDueReminderEnabled)
                            .labelsHidden()
                    }
                    .padding(.vertical, 20)

                    if todoDueReminderEnabled {
                        Divider()
                            .padding(.leading, 36)

                        HStack(spacing: 12) {
                            Image(systemName: "clock")
                                .font(.body)
                                .foregroundStyle(AppTheme.primary)
                                .frame(width: 24)

                            Text(String(appLocalized: "提醒时间"))
                                .font(.subheadline)
                                .foregroundStyle(.primary)

                            Spacer(minLength: 0)

                            DatePicker(
                                "",
                                selection: dueReminderTimeBinding,
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                        }
                        .padding(.vertical, 20)
                    }

                    Divider()
                        .padding(.leading, 36)

                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.arrow.trianglehead.clockwise")
                            .font(.body)
                            .foregroundStyle(AppTheme.primary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(appLocalized: "自动添加待办"))
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Text(String(appLocalized: "AI 摘要成功后自动加入系统提醒事项"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        Toggle("", isOn: $autoAddTodoAfterAISummary)
                            .labelsHidden()
                    }
                    .padding(.vertical, 20)

                    Divider()
                        .padding(.leading, 36)

                    NavigationLink {
                        AppearanceModeSelectionView(selectedMode: $appearanceModeRaw)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: appearanceMode.iconName)
                                .font(.body)
                                .foregroundStyle(AppTheme.primary)
                                .frame(width: 24)

                            Text(String(appLocalized: "外观"))
                                .font(.subheadline)
                                .foregroundStyle(.primary)

                            Spacer(minLength: 0)

                            Text(appearanceMode.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 20)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .padding(.leading, 36)

                    NavigationLink {
                        AppLanguageSelectionView(selectedLanguage: $languageRaw)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: appLanguage.iconName)
                                .font(.body)
                                .foregroundStyle(AppTheme.primary)
                                .frame(width: 24)

                            Text(String(appLocalized: "语言"))
                                .font(.subheadline)
                                .foregroundStyle(.primary)

                            Spacer(minLength: 0)

                            Text(appLanguage.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 20)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .padding(.leading, 36)

                    HStack(spacing: 12) {
                        Image(systemName: "hand.tap")
                            .font(.body)
                            .foregroundStyle(AppTheme.primary)
                            .frame(width: 24)

                        Text(String(appLocalized: "触感反馈"))
                            .font(.subheadline)
                            .foregroundStyle(.primary)

                        Spacer(minLength: 0)

                        Toggle("", isOn: $hapticsEnabled)
                            .labelsHidden()
                    }
                    .padding(.vertical, 20)

                    if hapticsEnabled {
                        Divider()
                            .padding(.leading, 36)

                        NavigationLink {
                            HapticIntensitySelectionView(selectedIntensity: $hapticsIntensityRaw)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "waveform.path")
                                    .font(.body)
                                    .foregroundStyle(AppTheme.primary)
                                    .frame(width: 24)

                                Text(String(appLocalized: "震动力度"))
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)

                                Spacer(minLength: 0)

                                Text(hapticsIntensity.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 20)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func scheduleDueReminderRefresh() {
        dueReminderRefreshTask?.cancel()
        dueReminderRefreshTask = Task { @MainActor in
            await TodoDueNotificationScheduler.refresh(for: records)
            dueReminderRefreshTask = nil
        }
    }
}

private struct TodoDueReminderSyncSignature: Equatable {
    let id: UUID
    let createdAt: Date
    let eventDate: Date?
    let intent: String
    let needTodo: Bool
    let eventTitle: String
    let eventDescription: String
    let todoEventsJSON: String
}

private enum DueReminderTimeParser {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let defaultRawValue = "08:00"

    static var defaultDate: Date {
        date(from: defaultRawValue) ?? .now
    }

    static func date(from rawValue: String) -> Date? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return formatter.date(from: trimmed)
    }

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}

private struct AIProviderConfigView: View {
    let provider: AIProvider
    @Binding var selectedProviderRaw: String
    @Environment(\.scenePhase) private var scenePhase

    @State private var baseURL = ""
    @State private var modelID = ""
    @State private var apiKey = ""
    @State private var maxTokens = ""
    @State private var temperature = ""
    @State private var topP = ""
    @State private var isTestingConfig = false
    @State private var testResult: AIProviderConfigTestResult?
    @State private var lastTestStatus: AIProviderConfigTestStatus?
    @State private var isAdvancedParametersExpanded = false
    @State private var isRequestLogsVisible = false
    @State private var requestLogs: [AIProviderRequestLogEntry] = []
    @State private var selectedRequestLog: AIProviderRequestLogEntry?
    @State private var isResetConfirmationPresented = false

    var body: some View {
        ZStack {
            LiquidBackground()

            ScrollView {
                if #available(iOS 26, *) {
                    GlassEffectContainer(spacing: 14) {
                        configSections
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                } else {
                    configSections
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                }
            }
        }
        .navigationTitle(provider.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $testResult) { result in
            Alert(
                title: Text(result.title),
                message: Text(result.message),
                dismissButton: .default(Text(String(appLocalized: "知道了")))
            )
        }
        .sheet(item: $selectedRequestLog) { record in
            AIProviderRequestLogDetailView(record: record)
                .presentationDetents([.large])
        }
        .task {
            loadStoredConfig()
            loadTestStatus()
            loadRequestLogs()
        }
        .onDisappear {
            persistCurrentConfig()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            loadTestStatus()
            loadRequestLogs()
        }
    }

    private var configSections: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    providerHeader

                    settingTextField(
                        title: String(appLocalized: "Base URL"),
                        placeholder: provider.baseURLPlaceholder,
                        text: binding(for: .baseURL)
                    )
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)

                    modelFieldSection

                    settingSecureField(
                        title: String(appLocalized: "API Key"),
                        placeholder: String(appLocalized: "API Key（由用户自行填写）"),
                        text: binding(for: .apiKey)
                    )
                    .textInputAutocapitalization(.never)

                    Divider()

                    optionalParametersSection

                    Divider()

                    HStack(spacing: 10) {
                        Button {
                            isResetConfirmationPresented = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.body.weight(.semibold))

                                Text(String(appLocalized: "重置"))
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .foregroundStyle(.primary)
                            .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isTestingConfig)
                        .alert(String(appLocalized: "确认重置配置"), isPresented: $isResetConfirmationPresented) {
                            Button(String(appLocalized: "取消"), role: .cancel) {}
                            Button(String(appLocalized: "确认重置"), role: .destructive) {
                                resetCurrentConfig()
                            }
                        } message: {
                            Text(String(appLocalized: "将恢复默认 Base URL 和模型，并清除 API Key 以及已填写的可选参数。"))
                        }

                        Button {
                            selectedProviderRaw = provider.rawValue
                            Task {
                                await testCurrentConfig()
                            }
                        } label: {
                            HStack(spacing: 10) {
                                if isTestingConfig {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "network")
                                        .font(.body.weight(.semibold))
                                }

                                Text(isTestingConfig ? String(appLocalized: "测试中...") : String(appLocalized: "测试配置"))
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isTestingConfig)
                    }

                    if let lastTestStatus {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: lastTestStatus.isSuccess ? "checkmark.seal.fill" : "xmark.seal.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(lastTestStatus.isSuccess ? .green : .red)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(String(appLocalized: "上次测试时间"))：\(requestLogTimestamp(for: lastTestStatus.lastTestAt))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)

                                Text("\(String(appLocalized: "测试结果"))：\(lastTestStatus.isSuccess ? String(appLocalized: "成功") : String(appLocalized: "失败"))")
                                    .font(.footnote)
                                    .foregroundStyle(lastTestStatus.isSuccess ? .green : .red)
                            }
                        }
                    }

                    Text(String(appLocalized: "点击后会发送一条测试提示词，验证当前模型和参数是否可用。"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if isRequestLogsVisible {
                requestLogsSection
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
                            removal: .opacity
                        )
                    )
            }
        }
    }

    private var providerHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(provider.displayName)
                    .font(.headline)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: toggleRequestLogsVisibility)
                Spacer(minLength: 0)
                Image(systemName: selectedProviderRaw == provider.rawValue ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedProviderRaw == provider.rawValue ? AppTheme.primary : .secondary)
            }

            Text(provider.detailText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var optionalParametersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: toggleAdvancedParameters) {
                HStack(spacing: 10) {
                    Text(String(appLocalized: "模型参数（可选）"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isAdvancedParametersExpanded ? 180 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isAdvancedParametersExpanded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isAdvancedParametersExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    settingTextField(
                        title: String(appLocalized: "max_tokens"),
                        placeholder: String(appLocalized: "请输入（可选）"),
                        text: binding(for: .maxTokens)
                    )
                    .keyboardType(.numberPad)

                    settingTextField(
                        title: String(appLocalized: "temperature"),
                        placeholder: provider.allowsTemperature(for: modelID) ? String(appLocalized: "请输入（可选）") : String(appLocalized: "当前模型通常忽略该参数"),
                        text: binding(for: .temperature)
                    )
                    .keyboardType(.decimalPad)

                    settingTextField(
                        title: String(appLocalized: "top_p"),
                        placeholder: provider.allowsTopP(for: modelID) ? String(appLocalized: "请输入（可选）") : String(appLocalized: "当前模型通常忽略该参数"),
                        text: binding(for: .topP)
                    )
                    .keyboardType(.decimalPad)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .transition(.opacity)
            }
        }
    }
    private var modelFieldSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            settingTextField(
                title: String(appLocalized: "Model"),
                placeholder: provider.modelPlaceholder,
                text: binding(for: .modelID)
            )
            .textInputAutocapitalization(.never)

            if provider.recommendedModels.isEmpty == false {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(provider.recommendedModels, id: \.self) { model in
                            Button {
                                modelID = model
                                persistCurrentConfig()
                            } label: {
                                Text(model)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        (modelID == model ? AppTheme.primary.opacity(0.18) : Color(uiColor: .tertiarySystemBackground)),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(modelID == model ? AppTheme.primary : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func testCurrentConfig() async {
        guard isTestingConfig == false else { return }

        persistCurrentConfig()
        selectedProviderRaw = provider.rawValue
        let config = runtimeConfig
        guard config.canRequestSummary else {
            presentTestFailure(
                String(appLocalized: "请先填写完整的 Base URL、Model 和 API Key。"),
                config: config
            )
            return
        }

        isTestingConfig = true
        defer {
            isTestingConfig = false
            loadRequestLogs()
        }

        do {
            let reply = try await AIProviderService.sendTestPrompt(
                String(appLocalized: "请用 30 个字介绍你是来自哪家公司的什么模型，不得返回其他内容"),
                config: config
            )
            persistTestStatus(isSuccess: true)
            testResult = AIProviderConfigTestResult(
                title: String(appLocalized: "测试成功"),
                message: reply
            )
        } catch let error as AIProviderServiceError {
            presentTestFailure(error.localizedDescription, config: config)
        } catch {
            presentTestFailure(error.localizedDescription, config: config)
        }
    }

    private func loadStoredConfig() {
        let config = AIProviderConfigStore.runtimeConfig(for: provider)
        baseURL = config.baseURL
        modelID = config.model
        apiKey = config.apiKey
        maxTokens = config.maxTokens.map { String($0) } ?? ""
        temperature = config.temperature.map { String($0) } ?? ""
        topP = config.topP.map { String($0) } ?? ""
    }

    private func loadRequestLogs() {
        requestLogs = AIProviderRequestLogStore.logs(for: provider)
    }

    private func loadTestStatus() {
        lastTestStatus = AIProviderConfigTestStatusStore.status(for: provider)
    }

    private func persistCurrentConfig() {
        AIProviderConfigStore.persist(runtimeConfig)
    }

    private func resetCurrentConfig() {
        baseURL = provider.defaultBaseURL
        modelID = provider.defaultModel
        apiKey = ""
        maxTokens = ""
        temperature = ""
        topP = ""
        persistCurrentConfig()
        loadTestStatus()
        loadRequestLogs()
    }

    private var runtimeConfig: AIProviderRuntimeConfig {
        AIProviderRuntimeConfig(
            provider: provider,
            baseURL: sanitized(baseURL, fallback: provider.defaultBaseURL),
            model: sanitized(modelID, fallback: provider.defaultModel),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            maxTokens: parseInt(maxTokens),
            temperature: parseDouble(temperature),
            topP: parseDouble(topP)
        )
    }

    private func binding(for field: ConfigField) -> Binding<String> {
        Binding(
            get: {
                switch field {
                case .baseURL:
                    return baseURL
                case .modelID:
                    return modelID
                case .apiKey:
                    return apiKey
                case .maxTokens:
                    return maxTokens
                case .temperature:
                    return temperature
                case .topP:
                    return topP
                }
            },
            set: { newValue in
                switch field {
                case .baseURL:
                    baseURL = newValue
                case .modelID:
                    modelID = newValue
                case .apiKey:
                    apiKey = newValue
                case .maxTokens:
                    maxTokens = newValue
                case .temperature:
                    temperature = newValue
                case .topP:
                    topP = newValue
                }
                persistCurrentConfig()
            }
        )
    }

    private func settingTextField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .padding(10)
                .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func settingSecureField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField(placeholder, text: text)
                .padding(10)
                .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var requestLogsSection: some View {
        RequestLogsSectionView(
            requestLogs: requestLogs,
            onSelectLog: { selectedRequestLog = $0 },
            onClearLogs: clearRequestLogs,
            timestampText: requestLogTimestamp(for:),
            subtitleText: requestLogSubtitle(for:)
        )
    }

    private func presentTestFailure(_ message: String, config: AIProviderRuntimeConfig) {
        persistTestStatus(isSuccess: false)
        let resolvedBaseURL = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        testResult = AIProviderConfigTestResult(
            title: String(appLocalized: "测试失败"),
            message: """
            提供商：\(config.provider.displayName)
            错误信息：\(message)

            Base URL：\(resolvedBaseURL.isEmpty ? String(appLocalized: "未填写") : resolvedBaseURL)
            Model：\(resolvedModel.isEmpty ? String(appLocalized: "未填写") : resolvedModel)
            """
        )
    }

    private func requestLogTimestamp(for date: Date) -> String {
        RequestLogDateFormatter.timestamp.string(from: date)
    }

    private func requestLogSubtitle(for record: AIProviderRequestLogEntry) -> String {
        if let totalTokensText = record.totalTokensText {
            return "\(record.operation.displayName) · \(record.model) · \(totalTokensText)"
        }
        return "\(record.operation.displayName) · \(record.model)"
    }

    private func persistTestStatus(isSuccess: Bool) {
        let status = AIProviderConfigTestStatus(lastTestAt: .now, isSuccess: isSuccess)
        AIProviderConfigTestStatusStore.persist(status, for: provider)
        lastTestStatus = status
    }

    private func clearRequestLogs() {
        AIProviderRequestLogStore.clear(provider: provider)
        loadRequestLogs()
    }

    private func toggleAdvancedParameters() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isAdvancedParametersExpanded.toggle()
        }
    }

    private func toggleRequestLogsVisibility() {
        withAnimation(.easeInOut(duration: 0.22)) {
            isRequestLogsVisible.toggle()
        }
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

private enum ConfigField {
    case baseURL
    case modelID
    case apiKey
    case maxTokens
    case temperature
    case topP
}

private struct AIProviderConfigTestResult: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct RequestLogsSectionView: View {
    let requestLogs: [AIProviderRequestLogEntry]
    let onSelectLog: (AIProviderRequestLogEntry) -> Void
    let onClearLogs: () -> Void
    let timestampText: (Date) -> String
    let subtitleText: (AIProviderRequestLogEntry) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RequestLogsHeaderView(
                isClearEnabled: requestLogs.isEmpty == false,
                onClearLogs: onClearLogs
            )

            GlassCard(cornerRadius: 18) {
                if requestLogs.isEmpty {
                    RequestLogsEmptyStateView()
                } else {
                    RequestLogsListView(
                        requestLogs: requestLogs,
                        onSelectLog: onSelectLog,
                        timestampText: timestampText,
                        subtitleText: subtitleText
                    )
                }
            }
        }
    }
}

private struct RequestLogsHeaderView: View {
    let isClearEnabled: Bool
    let onClearLogs: () -> Void

    @State private var isClearConfirmationPresented = false

    var body: some View {
        HStack {
            Text(String(appLocalized: "请求记录（本地）"))
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            if isClearEnabled {
                Button(action: presentClearConfirmation) {
                    Label(String(appLocalized: "清空"), systemImage: "trash")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.red)
                .padding(.trailing, 20)
                .alert(String(appLocalized: "确认清空请求记录？"), isPresented: $isClearConfirmationPresented) {
                    Button(String(appLocalized: "取消"), role: .cancel) {}
                    Button(String(appLocalized: "清空"), role: .destructive, action: onClearLogs)
                } message: {
                    Text(String(appLocalized: "清空后无法恢复。"))
                }
            }
        }
    }

    private func presentClearConfirmation() {
        guard isClearEnabled else { return }
        isClearConfirmationPresented = true
    }
}

private struct RequestLogsEmptyStateView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(appLocalized: "还没有请求记录"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(String(appLocalized: "点击上方“测试配置”，或在首页触发 AI 摘要后，这里会展示每次请求的时间、结果和调试详情。"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RequestLogsListView: View {
    let requestLogs: [AIProviderRequestLogEntry]
    let onSelectLog: (AIProviderRequestLogEntry) -> Void
    let timestampText: (Date) -> String
    let subtitleText: (AIProviderRequestLogEntry) -> String

    var body: some View {
        VStack(spacing: 0) {
            ForEach(requestLogs.indices, id: \.self) { index in
                let record = requestLogs[index]
                Button {
                    onSelectLog(record)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: record.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(record.isSuccess ? .green : .red)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(timestampText(record.createdAt))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text(subtitleText(record))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < requestLogs.count - 1 {
                    Divider()
                        .padding(.leading, 36)
                }
            }
        }
    }
}

private struct AIProviderRequestLogDetailView: View {
    let record: AIProviderRequestLogEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(String(appLocalized: "请求详情"))
                                    .font(.headline)

                                detailRow(
                                    title: String(appLocalized: "请求时间"),
                                    value: RequestLogDateFormatter.timestamp.string(from: record.createdAt)
                                )
                                detailRow(
                                    title: String(appLocalized: "请求类型"),
                                    value: record.operation.displayName
                                )
                                detailRow(
                                    title: String(appLocalized: "模型"),
                                    value: record.model
                                )
                                if let totalTokensText = record.totalTokensText {
                                    detailRow(
                                        title: String(appLocalized: "Token 消耗"),
                                        value: totalTokensText
                                    )
                                }
                                detailRow(
                                    title: String(appLocalized: "请求地址"),
                                    value: record.endpoint
                                )
                                detailRow(
                                    title: String(appLocalized: "请求状态"),
                                    value: record.isSuccess ? String(appLocalized: "成功") : String(appLocalized: "失败"),
                                    valueColor: record.isSuccess ? .green : .red
                                )

                                if let statusCode = record.statusCode {
                                    detailRow(
                                        title: String(appLocalized: "状态码"),
                                        value: String(statusCode)
                                    )
                                }

                                if let errorMessage = record.errorMessage, errorMessage.isEmpty == false {
                                    detailRow(
                                        title: String(appLocalized: "错误信息"),
                                        value: errorMessage,
                                        valueColor: .red
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity)

                        DebugCodeSection(
                            title: String(appLocalized: "发起参数"),
                            code: record.requestPayload
                        )

                        DebugCodeSection(
                            title: String(appLocalized: "接受参数"),
                            code: record.responsePayload
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle(String(appLocalized: "请求详情"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(appLocalized: "关闭")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func detailRow(title: String, value: String, valueColor: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(valueColor)
                .textSelection(.enabled)
        }
    }
}

private struct DebugCodeSection: View {
    let title: String
    let code: String

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)

                ScrollView(.horizontal, showsIndicators: true) {
                    Text(code.isEmpty ? String(appLocalized: "暂无内容") : code)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
}

private enum RequestLogDateFormatter {
    static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

private struct AppearanceModeSelectionView: View {
    @Binding var selectedMode: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LiquidBackground()

            ScrollView {
                GlassCard(cornerRadius: 18) {
                    VStack(spacing: 0) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Button {
                                selectedMode = mode.rawValue
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: mode.iconName)
                                        .font(.body)
                                        .foregroundStyle(AppTheme.primary)
                                        .frame(width: 24)

                                    Text(mode.displayName)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)

                                    Spacer(minLength: 0)

                                    if selectedMode == mode.rawValue {
                                        Image(systemName: "checkmark")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(AppTheme.primary)
                                    }
                                }
                                .frame(minHeight: 30)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if mode != AppearanceMode.allCases.last {
                                Divider()
                                    .padding(.leading, 36)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle(String(appLocalized: "外观"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AppLanguageSelectionView: View {
    @Binding var selectedLanguage: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LiquidBackground()

            ScrollView {
                GlassCard(cornerRadius: 18) {
                    VStack(spacing: 0) {
                        ForEach(AppLanguage.allCases, id: \.self) { language in
                            Button {
                                selectedLanguage = language.rawValue
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: language.iconName)
                                        .font(.body)
                                        .foregroundStyle(AppTheme.primary)
                                        .frame(width: 24)

                                    Text(language.displayName)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)

                                    Spacer(minLength: 0)

                                    if selectedLanguage == language.rawValue {
                                        Image(systemName: "checkmark")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(AppTheme.primary)
                                    }
                                }
                                .frame(minHeight: 30)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if language != AppLanguage.allCases.last {
                                Divider()
                                    .padding(.leading, 36)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle(String(appLocalized: "语言"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AppUsageGuideView: View {
    private let sections: [AppUsageGuideSection] = [
        AppUsageGuideSection(
            iconName: "square.and.pencil",
            title: String(appLocalized: "多入口导入"),
            points: [
                String(appLocalized: "支持文字、相册、拍照导入。"),
                String(appLocalized: "支持系统分享扩展与快捷指令。")
            ]
        ),
        AppUsageGuideSection(
            iconName: "text.viewfinder",
            title: String(appLocalized: "OCR 与 AI 整理"),
            points: [
                String(appLocalized: "先用本地 OCR 提取文本。"),
                String(appLocalized: "启用 AI 后生成摘要与待办信息。")
            ]
        ),
        AppUsageGuideSection(
            iconName: "checklist",
            title: String(appLocalized: "待办与提醒"),
            points: [
                String(appLocalized: "识别到时间后可加入系统提醒事项。"),
                String(appLocalized: "支持自动添加和当天到期通知。")
            ]
        ),
        AppUsageGuideSection(
            iconName: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            title: String(appLocalized: "历史记录与分享"),
            points: [
                String(appLocalized: "识别结果会保存到本地历史。"),
                String(appLocalized: "支持搜索、备注、重识别和分享卡片。")
            ]
        ),
        AppUsageGuideSection(
            iconName: "lock.shield",
            title: String(appLocalized: "隐私与数据"),
            points: [
                String(appLocalized: "OCR 与记录默认保存在设备上。"),
                String(appLocalized: "启用 AI 时，仅识别文本会发送到模型服务。")
            ]
        )
    ]

    var body: some View {
        ZStack {
            LiquidBackground()

            ScrollView {
                guideSectionsContent
            }
        }
        .navigationTitle(String(appLocalized: "使用说明"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var guideSectionsContent: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 14) {
                guideSectionsStack
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        } else {
            guideSectionsStack
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
        }
    }

    private var guideSectionsStack: some View {
        VStack(alignment: .leading, spacing: 14) {
            AppUsageGuideCard(cornerRadius: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(appLocalized: "大橘小事如何工作"))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(String(appLocalized: "这一页集中说明应用的核心功能、常见使用路径和数据处理方式。"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ForEach(sections) { section in
                AppUsageGuideCard(cornerRadius: 22) {
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AppTheme.primary.opacity(0.12))
                                .frame(width: 46, height: 46)

                            Image(systemName: section.iconName)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(AppTheme.primary)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(section.points.enumerated()), id: \.offset) { index, point in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("\(index + 1).")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(AppTheme.primary)
                                            .frame(width: 16, alignment: .leading)

                                        Text(point)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AppUsageGuideSection: Identifiable {
    let id = UUID()
    let iconName: String
    let title: String
    let points: [String]
}

private struct AppUsageGuideCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let content: Content

    init(cornerRadius: CGFloat, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(.clear)
                    .glassEffect(
                        .regular.tint(colorScheme == .dark ? .white.opacity(0.04) : .white.opacity(0.22)),
                        in: .rect(cornerRadius: cornerRadius)
                    )
            } else {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(colorScheme == .dark ? Color(uiColor: .secondarySystemBackground) : .white)
                    )
                    .shadow(
                        color: colorScheme == .dark ? .black.opacity(0.22) : .black.opacity(0.08),
                        radius: colorScheme == .dark ? 14 : 12,
                        x: 0,
                        y: colorScheme == .dark ? 8 : 6
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HapticIntensitySelectionView: View {
    @Binding var selectedIntensity: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LiquidBackground()

            ScrollView {
                GlassCard(cornerRadius: 18) {
                    VStack(spacing: 0) {
                        ForEach(HapticFeedbackIntensity.allCases, id: \.self) { intensity in
                            Button {
                                selectedIntensity = intensity.rawValue
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: intensityIconName(for: intensity))
                                        .font(.body)
                                        .foregroundStyle(AppTheme.primary)
                                        .frame(width: 24)

                                    Text(intensity.displayName)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)

                                    Spacer(minLength: 0)

                                    if selectedIntensity == intensity.rawValue {
                                        Image(systemName: "checkmark")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(AppTheme.primary)
                                    }
                                }
                                .frame(minHeight: 30)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if intensity != HapticFeedbackIntensity.allCases.last {
                                Divider()
                                    .padding(.leading, 36)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle(String(appLocalized: "震动力度"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // 用不同波形图标帮助用户快速区分不同力度层级。
    private func intensityIconName(for intensity: HapticFeedbackIntensity) -> String {
        switch intensity {
        case .weak:
            return "waveform.path"
        case .medium:
            return "waveform.path.badge.plus"
        case .strong:
            return "waveform"
        }
    }
}

#Preview {
    SettingsView()
}
