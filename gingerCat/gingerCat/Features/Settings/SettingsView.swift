import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettingsKeys.aiSummaryEnabled) private var aiSummaryEnabled = false
    @AppStorage(AppSettingsKeys.haptics) private var hapticsEnabled = true
    @AppStorage(AppSettingsKeys.appearanceMode) private var appearanceModeRaw = AppearanceMode.automatic.rawValue
    @AppStorage(AIProviderSettingsKeys.selectedProvider) private var selectedProviderRaw = AIProvider.kimi.rawValue

    private var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceModeRaw) ?? .automatic }
        set { appearanceModeRaw = newValue.rawValue }
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
                        .padding(.vertical, 12)
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
                    .padding(.vertical, 12)
                }
            }
        }
    }
}

private struct AIProviderConfigView: View {
    let provider: AIProvider
    @Binding var selectedProviderRaw: String

    @State private var baseURL = ""
    @State private var modelID = ""
    @State private var apiKey = ""
    @State private var maxTokens = ""
    @State private var temperature = ""
    @State private var topP = ""
    @State private var isTestingConfig = false
    @State private var testResult: AIProviderConfigTestResult?

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
        .task {
            loadStoredConfig()
        }
        .onDisappear {
            persistCurrentConfig()
        }
    }

    private var configSections: some View {
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

                Text(String(localized: "模型参数（可选）"))
                    .font(.subheadline.weight(.semibold))

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

                Text(String(localized: "点击后会发送一条测试提示词，验证当前模型和参数是否可用。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var providerHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(provider.displayName)
                    .font(.headline)
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

    private var providerGuidanceText: String? {
        switch provider {
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
        defer { isTestingConfig = false }

        do {
            let reply = try await AIProviderService.sendTestPrompt(
                String(localized: "请用 30 个字介绍你是什么模型，目前的参数是什么，来自哪家公司"),
                config: config
            )
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

    private func presentTestFailure(_ message: String, config: AIProviderRuntimeConfig) {
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
                                .padding(.vertical, 12)
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

#Preview {
    SettingsView()
}
