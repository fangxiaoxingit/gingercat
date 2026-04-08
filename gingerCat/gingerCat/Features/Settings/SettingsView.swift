import SwiftUI

struct SettingsView: View {
    @AppStorage(KimiSettingsKeys.aiSummaryEnabled) private var aiSummaryEnabled = false
    @AppStorage(KimiSettingsKeys.haptics) private var hapticsEnabled = true

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

            behaviorSection
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
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var behaviorSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(String(localized: "体验"), systemImage: "hand.tap")
                    .font(.headline)
                Toggle(String(localized: "触感反馈"), isOn: $hapticsEnabled)
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
            }
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
}

#Preview {
    SettingsView()
}
