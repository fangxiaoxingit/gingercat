import SwiftUI

struct SettingsView: View {
    @AppStorage(KimiSettingsKeys.aiSummaryEnabled) private var aiSummaryEnabled = false
    @AppStorage(KimiSettingsKeys.haptics) private var hapticsEnabled = true
    @AppStorage(KimiSettingsKeys.appearanceMode) private var appearanceModeRaw = AppearanceMode.automatic.rawValue
    
    private var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceModeRaw) ?? .automatic }
        set { appearanceModeRaw = newValue.rawValue }
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
                    NavigationLink {
                        KimiModelConfigView()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "cpu")
                                .font(.body)
                                .foregroundStyle(AppTheme.primary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Kimi")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(String(localized: "OpenAI 兼容接口"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var appSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "APP 设置"))
                .font(.headline)
                .foregroundStyle(.primary)
            
            GlassCard(cornerRadius: 18) {
                VStack(spacing: 0) {
                    // 外观设置
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
                    
                    // 触感反馈
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

private struct KimiModelConfigView: View {
    @AppStorage(KimiSettingsKeys.baseURL) private var baseURL = KimiRuntimeConfig.defaultBaseURL
    @AppStorage(KimiSettingsKeys.model) private var modelID = KimiRuntimeConfig.defaultModel
    @AppStorage(KimiSettingsKeys.apiKey) private var apiKey = ""
    @AppStorage(KimiSettingsKeys.maxTokens) private var maxTokens = ""
    @AppStorage(KimiSettingsKeys.temperature) private var temperature = ""
    @AppStorage(KimiSettingsKeys.topP) private var topP = ""
    @State private var isTestingConfig = false
    @State private var testResult: KimiConfigTestResult?

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
        .navigationTitle("Kimi")
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $testResult) { result in
            Alert(
                title: Text(result.title),
                message: Text(result.message),
                dismissButton: .default(Text(String(localized: "知道了")))
            )
        }
    }

    private var configSections: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                settingTextField(title: String(localized: "Base URL"), placeholder: "https://api.moonshot.cn/v1", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)

                settingTextField(title: String(localized: "Model"), placeholder: "kimi-k2.5", text: $modelID)
                    .textInputAutocapitalization(.never)

                SecureField(String(localized: "API Key（由用户自行填写）"), text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .padding(10)
                    .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Divider()

                Text(String(localized: "模型参数（可选）"))
                    .font(.subheadline.weight(.semibold))

                settingTextField(title: String(localized: "max_tokens"), placeholder: String(localized: "留空使用服务端默认"), text: $maxTokens)
                    .keyboardType(.numberPad)

                settingTextField(title: String(localized: "temperature"), placeholder: String(localized: "留空使用服务端默认"), text: $temperature)
                    .keyboardType(.decimalPad)

                settingTextField(title: String(localized: "top_p"), placeholder: String(localized: "留空使用服务端默认"), text: $topP)
                    .keyboardType(.decimalPad)

                Divider()

                Button {
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

    @MainActor
    private func testCurrentConfig() async {
        guard isTestingConfig == false else { return }

        let config = runtimeConfig
        guard config.canRequestSummary else {
            testResult = KimiConfigTestResult(
                title: String(localized: "测试失败"),
                message: String(localized: "请先填写完整的 Base URL、Model 和 API Key。")
            )
            return
        }

        isTestingConfig = true
        defer { isTestingConfig = false }

        do {
            let reply = try await KimiAIService.sendTestPrompt(
                String(localized: "请用 30 个字介绍你是什么模型，目前的参数是什么，来自哪家公司"),
                config: config
            )
            testResult = KimiConfigTestResult(
                title: String(localized: "测试成功"),
                message: reply
            )
        } catch let error as KimiAIServiceError {
            testResult = KimiConfigTestResult(
                title: String(localized: "测试失败"),
                message: error.localizedDescription
            )
        } catch {
            testResult = KimiConfigTestResult(
                title: String(localized: "测试失败"),
                message: error.localizedDescription
            )
        }
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

    private var runtimeConfig: KimiRuntimeConfig {
        KimiRuntimeConfig(
            baseURL: sanitized(baseURL, fallback: KimiRuntimeConfig.defaultBaseURL),
            model: sanitized(modelID, fallback: KimiRuntimeConfig.defaultModel),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            maxTokens: parseInt(maxTokens),
            temperature: parseDouble(temperature),
            topP: parseDouble(topP)
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

private struct KimiConfigTestResult: Identifiable {
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
