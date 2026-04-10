import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettingsKeys.aiSummaryEnabled) private var aiSummaryEnabled = false
    @AppStorage(AppSettingsKeys.haptics) private var hapticsEnabled = true
    @AppStorage(AppSettingsKeys.hapticsIntensity) private var hapticsIntensityRaw = HapticFeedbackIntensity.medium.rawValue
    @AppStorage(AppSettingsKeys.appearanceMode) private var appearanceModeRaw = AppearanceMode.automatic.rawValue
    @AppStorage(AIProviderSettingsKeys.selectedProvider) private var selectedProviderRaw = AIProvider.kimi.rawValue

    private var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceModeRaw) ?? .automatic }
        set { appearanceModeRaw = newValue.rawValue }
    }

    private var hapticsIntensity: HapticFeedbackIntensity {
        get { HapticFeedbackIntensity(rawValue: hapticsIntensityRaw) ?? .medium }
        set { hapticsIntensityRaw = newValue.rawValue }
    }

    private var selectedProvider: AIProvider {
        AIProvider(rawValue: selectedProviderRaw) ?? .kimi
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
            .navigationTitle(String(localized: "设置"))
        }
    }

    private var settingsSections: some View {
        VStack(alignment: .leading, spacing: 14) {
            aiSwitchSection

            if aiSummaryEnabled {
                modelListSection
            }

            appSettingsSection
        }
    }

    private var aiSwitchSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(String(localized: "AI 总结"), systemImage: "sparkles")
                    .font(.headline)
                Toggle(String(localized: "启用 AI 总结"), isOn: $aiSummaryEnabled)
                Text(String(localized: "默认关闭。开启后会在 OCR 结果基础上调用模型生成摘要。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var modelListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "模型列表"))
                .font(.headline)
                .foregroundStyle(.primary)

            GlassCard(cornerRadius: 18) {
                VStack(spacing: 0) {
                    ForEach(Array(AIProvider.allCases.enumerated()), id: \.element.id) { index, provider in
                        providerRow(provider)

                        if index < AIProvider.allCases.count - 1 {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
            }
        }
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

                        Text(String(localized: "当前模型：\(config.model)"))
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
                    Text(String(localized: "配置"))
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
            Text(String(localized: "APP 设置"))
                .font(.headline)
                .foregroundStyle(.primary)

            GlassCard(cornerRadius: 18) {
                VStack(spacing: 0) {
                    NavigationLink {
                        AppearanceModeSelectionView(selectedMode: $appearanceModeRaw)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: appearanceMode.iconName)
                                .font(.body)
                                .foregroundStyle(AppTheme.primary)
                                .frame(width: 24)

                            Text(String(localized: "外观"))
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

                    HStack(spacing: 12) {
                        Image(systemName: "hand.tap")
                            .font(.body)
                            .foregroundStyle(AppTheme.primary)
                            .frame(width: 24)

                        Text(String(localized: "触感反馈"))
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

                                Text(String(localized: "震动力度"))
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
                dismissButton: .default(Text(String(localized: "知道了")))
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
                        title: String(localized: "Base URL"),
                        placeholder: provider.defaultBaseURL,
                        text: binding(for: .baseURL)
                    )
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)

                    modelFieldSection

                    SecureField(String(localized: "API Key（由用户自行填写）"), text: binding(for: .apiKey))
                        .textInputAutocapitalization(.never)
                        .padding(10)
                        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Divider()

                    optionalParametersSection

                    Divider()

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

                            Text(isTestingConfig ? String(localized: "测试中...") : String(localized: "测试配置"))
                                .font(.subheadline.weight(.semibold))

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isTestingConfig)

                    if let lastTestStatus {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: lastTestStatus.isSuccess ? "checkmark.seal.fill" : "xmark.seal.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(lastTestStatus.isSuccess ? .green : .red)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(String(localized: "上次测试时间"))：\(requestLogTimestamp(for: lastTestStatus.lastTestAt))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)

                                Text("\(String(localized: "测试结果"))：\(lastTestStatus.isSuccess ? String(localized: "成功") : String(localized: "失败"))")
                                    .font(.footnote)
                                    .foregroundStyle(lastTestStatus.isSuccess ? .green : .red)
                            }
                        }
                    }

                    Text(String(localized: "点击后会发送一条测试提示词，验证当前模型和参数是否可用。"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if isRequestLogsVisible {
                requestLogsSection
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isRequestLogsVisible)
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

            if let providerGuidanceText {
                Text(providerGuidanceText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var optionalParametersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: toggleAdvancedParameters) {
                HStack(spacing: 10) {
                    Text(String(localized: "模型参数（可选）"))
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
                        title: String(localized: "max_tokens"),
                        placeholder: String(localized: "留空使用服务端默认"),
                        text: binding(for: .maxTokens)
                    )
                    .keyboardType(.numberPad)

                    settingTextField(
                        title: String(localized: "temperature"),
                        placeholder: provider.allowsTemperature(for: modelID) ? String(localized: "留空使用服务端默认") : String(localized: "当前模型通常忽略该参数"),
                        text: binding(for: .temperature)
                    )
                    .keyboardType(.decimalPad)

                    settingTextField(
                        title: String(localized: "top_p"),
                        placeholder: provider.allowsTopP(for: modelID) ? String(localized: "留空使用服务端默认") : String(localized: "当前模型通常忽略该参数"),
                        text: binding(for: .topP)
                    )
                    .keyboardType(.decimalPad)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .transition(.opacity)
            }
        }
    }

    private var providerGuidanceText: String? {
        switch provider {
        case .doubao:
            return String(localized: "官方 OpenAI 兼容接入地址为 https://ark.cn-beijing.volces.com/api/v3，当前先支持 doubao-seed-2-0-lite-260215、doubao-seed-2-0-mini-260215、doubao-seed-2-0-pro-260215。")
        case .deepSeek:
            return String(localized: "推荐模型：deepseek-chat、deepseek-reasoner。若使用 deepseek-reasoner，temperature 与 top_p 往往会被忽略。")
        case .miniMax:
            return String(localized: "推荐使用 OpenAI 兼容接口。默认地址为 https://api.minimaxi.com/v1，推荐模型可按场景选择标准版或 highspeed 版本。")
        case .xiaomiMiMo:
            return String(localized: "官方 OpenAI 兼容地址为 https://api.xiaomimimo.com/v1，常用模型为 mimo-v2-pro；多模态场景可尝试 mimo-v2-omni。")
        case .kimi:
            return nil
        }
    }

    private var modelFieldSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            settingTextField(
                title: String(localized: "Model"),
                placeholder: provider.defaultModel,
                text: binding(for: .modelID)
            )
            .textInputAutocapitalization(.never)

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

    @MainActor
    private func testCurrentConfig() async {
        guard isTestingConfig == false else { return }

        persistCurrentConfig()
        selectedProviderRaw = provider.rawValue
        let config = runtimeConfig
        guard config.canRequestSummary else {
            presentTestFailure(
                String(localized: "请先填写完整的 Base URL、Model 和 API Key。"),
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
                String(localized: "请用 30 个字介绍你是什么模型，目前的参数是什么，来自哪家公司"),
                config: config
            )
            persistTestStatus(isSuccess: true)
            testResult = AIProviderConfigTestResult(
                title: String(localized: "测试成功"),
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
            title: String(localized: "测试失败"),
            message: """
            提供商：\(config.provider.displayName)
            错误信息：\(message)

            Base URL：\(resolvedBaseURL.isEmpty ? String(localized: "未填写") : resolvedBaseURL)
            Model：\(resolvedModel.isEmpty ? String(localized: "未填写") : resolvedModel)
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
        withAnimation {
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
            Text(String(localized: "请求记录"))
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            if isClearEnabled {
                Button(action: presentClearConfirmation) {
                    Label(String(localized: "清空"), systemImage: "trash")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.red)
                .padding(.trailing, 20)
                .alert(String(localized: "确认清空请求记录？"), isPresented: $isClearConfirmationPresented) {
                    Button(String(localized: "取消"), role: .cancel) {}
                    Button(String(localized: "清空"), role: .destructive, action: onClearLogs)
                } message: {
                    Text(String(localized: "清空后无法恢复。"))
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
            Text(String(localized: "还没有请求记录"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(String(localized: "点击上方“测试配置”，或在首页触发 AI 摘要后，这里会展示每次请求的时间、结果和调试详情。"))
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
                                Text(String(localized: "请求详情"))
                                    .font(.headline)

                                detailRow(
                                    title: String(localized: "请求时间"),
                                    value: RequestLogDateFormatter.timestamp.string(from: record.createdAt)
                                )
                                detailRow(
                                    title: String(localized: "请求类型"),
                                    value: record.operation.displayName
                                )
                                detailRow(
                                    title: String(localized: "模型"),
                                    value: record.model
                                )
                                if let totalTokensText = record.totalTokensText {
                                    detailRow(
                                        title: String(localized: "Token 消耗"),
                                        value: totalTokensText
                                    )
                                }
                                detailRow(
                                    title: String(localized: "请求地址"),
                                    value: record.endpoint
                                )
                                detailRow(
                                    title: String(localized: "请求状态"),
                                    value: record.isSuccess ? String(localized: "成功") : String(localized: "失败"),
                                    valueColor: record.isSuccess ? .green : .red
                                )

                                if let statusCode = record.statusCode {
                                    detailRow(
                                        title: String(localized: "状态码"),
                                        value: String(statusCode)
                                    )
                                }

                                if let errorMessage = record.errorMessage, errorMessage.isEmpty == false {
                                    detailRow(
                                        title: String(localized: "错误信息"),
                                        value: errorMessage,
                                        valueColor: .red
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity)

                        DebugCodeSection(
                            title: String(localized: "发起参数"),
                            code: record.requestPayload
                        )

                        DebugCodeSection(
                            title: String(localized: "接受参数"),
                            code: record.responsePayload
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle(String(localized: "请求详情"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "关闭")) {
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
                    Text(code.isEmpty ? String(localized: "暂无内容") : code)
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
        .navigationTitle(String(localized: "外观"))
        .navigationBarTitleDisplayMode(.inline)
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
        .navigationTitle(String(localized: "震动力度"))
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
