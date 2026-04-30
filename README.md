# 大橘小事 / GingerCat

> 从图片、截图或文字中提取关键信息，把杂乱内容整理成摘要、待办、取件码和可追踪的本地记录。
>
> Extract useful information from images, screenshots, and text, then turn it into summaries, reminders, pickup codes, and searchable local records.

[中文](#中文) | [English](#english)

---

## 中文

### 项目简介

大橘小事是一款 SwiftUI iOS 应用，面向"截图里有重要信息但不想手动整理"的场景。它可以通过相册、相机、分享扩展、快捷指令或手动文字输入导入内容，使用 Apple Vision 做本地 OCR，并可选调用兼容 OpenAI Chat Completions 的模型服务生成结构化摘要。

官网地址：https://xiaoxinnote.com/gingercat

应用会把识别结果保存为本地历史记录，并尽可能提取：

- 普通摘要：把 OCR 原文整理成更易读的内容。
- 待办事件：识别日期、时间、标题、关键词和描述，并写入系统“提醒事项”。
- 多事件待办：同一张图里有多个时间点时，拆分为多条可添加的待办。
- 取件码：识别咖啡、饮品、快递等取件信息，并在通知中优先展示。

### 功能特性

- 图片导入：支持相册选择、相机拍摄、系统分享扩展导入图片。
- 文字导入：支持直接输入文字并走同一套摘要 / 待办提取流程。
- 本地 OCR：基于 Vision `VNRecognizeTextRequest`，当前识别语言包含简体中文和英文。
- AI 结构化分析：支持 DeepSeek、Kimi、MiniMax、OpenAI，也支持自定义 Base URL、模型 ID 和 API Key。
- AI 配置测试：可在设置页发送测试提示词，并查看最近请求日志。
- 国际化：支持自动、中文、英文三种界面语言模式，可在设置中切换。
- 历史记录：基于 SwiftData 本地存储，支持搜索、筛选、详情查看、备注、删除和重新 OCR / AI 摘要。
- 系统提醒事项：识别到有效时间后，可手动或自动加入 Apple Reminders。
- 到期通知：可配置每天提醒时间，当天有待办时推送本地通知。
- 取件优先通知：识别到取件码后，通知会优先显示取件信息。
- 桌面小组件：提供最近待办小组件和待办列表小组件。
- 快捷指令：提供“导入图片并解析” App Intent，可从 Shortcuts 自动导入图片。
- 深链跳转：支持 `gingercat://record/<UUID>` 打开指定记录。
- 分享卡片：可把记录渲染为卡片图片并保存或分享。
- 视觉风格：使用 Liquid Glass 风格背景、玻璃卡片、主题色和触感反馈。

### 技术栈

- Swift / SwiftUI
- SwiftData
- Vision OCR
- EventKit Reminders
- WidgetKit
- App Intents / Shortcuts
- Share Extension
- UserNotifications
- App Groups

### 项目结构

```text
gingerCat/
├── Config/                         # Info.plist 配置
├── gingerCat/                       # 主 App
│   ├── AppIntents/                  # 快捷指令入口
│   ├── Components/                  # 通用 UI 组件
│   ├── Features/                    # 首页、历史、导入、设置、分析抽屉
│   ├── Models/                      # SwiftData 模型、AI 配置、深链模型
│   ├── Services/                    # OCR、AI、提醒、通知、导入管线等服务
│   └── Theme/                       # 主题定义
├── gingerCatShareExtension/         # 系统分享扩展
├── gingerCatLiveActivityWidget/     # WidgetKit 小组件扩展（目录名保留）
├── gingerCatTests/                  # 单元测试
└── gingerCatUITests/                # UI 测试
```

### 运行要求

- macOS + Xcode（需支持项目中使用的 iOS SDK）
- iOS 26.4 或更高版本（项目当前部署目标）
- 一个有效的 Apple Developer Team，用于签名主 App、Share Extension、Widget Extension 和 App Group
- 可选：DeepSeek / Kimi / MiniMax / OpenAI 或兼容 OpenAI Chat Completions 的模型服务 API Key

### 本地运行

1. 克隆仓库。

```bash
git clone <your-repo-url>
cd ginger-cat
```

2. 打开 Xcode 工程。

```bash
open gingerCat/gingerCat.xcodeproj
```

3. 修改签名配置。

- 在 Xcode 中把主 App、Share Extension、Widget Extension 的 Team 改成你的 Apple Developer Team。
- 将 Bundle Identifier 改成你自己的反向域名。
- 将 App Group 从 `group.com.example.GingerCat` 改成你自己的 App Group。
- 同步修改代码中使用 App Group 的位置：`ExternalImageImportStore.sharedAppGroupIdentifier`、Share Extension 和 Widget 里的共享配置。

4. 运行 `gingerCat` scheme。

5. 如需使用 AI 摘要，在 App 内进入“设置 -> AI 总结”，选择模型提供商并填写 Base URL、Model 和 API Key。

### AI Provider 说明

当前内置 Provider：

| Provider | 默认 Base URL | 默认模型 |
| --- | --- | --- |
| DeepSeek | `https://api.deepseek.com` | `deepseek-chat` |
| Kimi | `https://api.moonshot.cn/v1` | `kimi-k2.5` |
| MiniMax | `https://api.minimaxi.com/v1` | `MiniMax-M2.7` |
| OpenAI | `https://api.openai.com/v1` | `gpt-5.4` |

请求路径会自动补齐为 `/chat/completions`。如果你使用兼容 OpenAI Chat Completions 的第三方网关，填写对应 Base URL、模型名称和 API Key 即可。

### 隐私说明

- OCR 在设备本地通过 Apple Vision 执行。
- 只有启用 AI 总结并配置 API Key 后，识别文本才会发送给所选模型服务。
- 图片和历史记录使用 SwiftData 保存在本地。
- Share Extension、Widget 和主 App 通过 App Group 共享必要的导入队列和小组件快照。
- API Key 和模型配置当前通过 `UserDefaults/AppStorage` 保存在本地。开源或上架前，建议迁移敏感凭据到 Keychain。
- 项目会请求相机、相册、提醒事项和通知权限；权限用途已在 `Info.plist` 中声明。

### 当前限制

- 日历写入仍是预留能力，当前实际集成的是系统“提醒事项”。
- 当前已支持中英文国际化与语言切换，部分长尾文案仍在持续完善中。
- App Group 和 Bundle Identifier 仍包含原作者标识，开源复用时必须替换。
- AI 输出质量依赖所选模型、Prompt 和 OCR 原文质量。

### 贡献

欢迎提交 Issue 和 Pull Request。建议在 PR 中说明：

- 变更目标和影响范围。
- 是否涉及权限、App Group、Widget 或数据模型迁移。
- 已执行的测试或手动验证步骤。

### License

当前仓库尚未包含开源许可证文件。正式开源前请添加 `LICENSE`，例如 MIT、Apache-2.0 或其他与你的分发目标匹配的许可证。

---

## English

### Overview

GingerCat is a SwiftUI iOS app for turning screenshots, photos, and plain text into organized local records. It imports content from Photos, Camera, the iOS Share Sheet, Shortcuts, or manual text input. It runs local OCR with Apple Vision and can optionally call an OpenAI Chat Completions-compatible model provider for structured summaries.

The app stores every result locally and tries to extract:

- General summaries: cleaner, readable summaries from OCR text.
- Reminder events: date, time, title, keywords, and descriptions that can be added to Apple Reminders.
- Multi-event reminders: multiple due dates from one image can become separate reminder candidates.
- Pickup codes: coffee, beverage, express delivery, and other pickup information, prioritized in notifications.

### Features

- Image import: Photos picker, camera capture, and iOS Share Extension.
- Text import: manual text input using the same analysis pipeline as OCR results.
- Local OCR: Apple Vision `VNRecognizeTextRequest`, currently configured for Simplified Chinese and English.
- AI structured analysis: built-in support for DeepSeek, Kimi, MiniMax, OpenAI, plus custom Base URL, model ID, and API key.
- AI config testing: send a test prompt from Settings and inspect recent request logs.
- Internationalization: supports Automatic, Chinese, and English UI language modes in Settings.
- Local archive: SwiftData-backed records with search, filters, detail view, notes, deletion, and rerun OCR / AI summary actions.
- Apple Reminders integration: manually or automatically add recognized events to Reminders.
- Due notifications: configurable daily local notification time for reminders due today.
- Pickup-first notifications: pickup codes are highlighted in notifications.
- Home Screen widgets: latest reminder widget and recent reminders list widget.
- Shortcuts integration: App Intent for importing and parsing an image from Shortcuts.
- Deep links: `gingercat://record/<UUID>` opens a specific record.
- Share cards: render a record into an image card for saving or sharing.
- Visual style: Liquid Glass-inspired backgrounds, glass cards, theme colors, and haptic feedback.

### Tech Stack

- Swift / SwiftUI
- SwiftData
- Vision OCR
- EventKit Reminders
- WidgetKit
- App Intents / Shortcuts
- Share Extension
- UserNotifications
- App Groups

### Project Structure

```text
gingerCat/
├── Config/                         # Info.plist files
├── gingerCat/                       # Main app target
│   ├── AppIntents/                  # Shortcuts entry points
│   ├── Components/                  # Shared UI components
│   ├── Features/                    # Home, Archive, Import, Settings, Insight UI
│   ├── Models/                      # SwiftData models, AI config, deep links
│   ├── Services/                    # OCR, AI, reminders, notifications, import pipeline
│   └── Theme/                       # Theme definitions
├── gingerCatShareExtension/         # iOS Share Extension
├── gingerCatLiveActivityWidget/     # WidgetKit extension (legacy folder name)
├── gingerCatTests/                  # Unit tests
└── gingerCatUITests/                # UI tests
```

### Requirements

- macOS + Xcode with support for the iOS SDK used by this project
- iOS 26.4 or later, based on the current deployment target
- A valid Apple Developer Team for signing the main app, Share Extension, Widget Extension, and App Group
- Optional: an API key for DeepSeek, Kimi, MiniMax, OpenAI, or another OpenAI Chat Completions-compatible provider

### Local Setup

1. Clone the repository.

```bash
git clone <your-repo-url>
cd ginger-cat
```

2. Open the Xcode project.

```bash
open gingerCat/gingerCat.xcodeproj
```

3. Update signing and identifiers.

- Change the Team for the main app, Share Extension, and Widget Extension.
- Replace the Bundle Identifiers with your own reverse-DNS identifiers.
- Replace the App Group `group.com.example.GingerCat` with your own App Group.
- Update every App Group reference in code, including `ExternalImageImportStore.sharedAppGroupIdentifier`, the Share Extension import store, and the Widget shared config.

4. Run the `gingerCat` scheme.

5. To enable AI summaries, open “Settings -> AI Summary” in the app, choose a provider, then fill in Base URL, Model, and API Key.

### AI Providers

Built-in providers:

| Provider | Default Base URL | Default Model |
| --- | --- | --- |
| DeepSeek | `https://api.deepseek.com` | `deepseek-chat` |
| Kimi | `https://api.moonshot.cn/v1` | `kimi-k2.5` |
| MiniMax | `https://api.minimaxi.com/v1` | `MiniMax-M2.7` |
| OpenAI | `https://api.openai.com/v1` | `gpt-5.4` |

The app automatically appends `/chat/completions` when needed. For an OpenAI-compatible gateway, provide its Base URL, model name, and API key.

### Privacy

- OCR runs locally on device through Apple Vision.
- Recognized text is only sent to the selected model provider when AI Summary is enabled and configured.
- Images and records are stored locally with SwiftData.
- The main app, Share Extension, and Widgets share only the required import queue and widget snapshot through App Groups.
- API keys and model settings are currently stored locally through `UserDefaults/AppStorage`. Before public distribution, consider migrating sensitive credentials to Keychain.
- The app requests Camera, Photo Library, Reminders, and Notification permissions. Usage descriptions are declared in `Info.plist`.

### Current Limitations

- Calendar writing is reserved in the UI, but the current working integration is Apple Reminders.
- Chinese/English localization and language switching are available; some long-tail strings are still being refined.
- App Group and Bundle Identifiers still contain the original author namespace and must be replaced before reuse.
- AI quality depends on the selected model, prompt behavior, and OCR text quality.

### Development Rules

Read [CODING_RULES.md](./CODING_RULES.md).

### Contributing

Issues and pull requests are welcome. A good PR should include:

- The goal and scope of the change.
- Whether it affects permissions, App Groups, Widgets, or data model migration.
- Tests or manual verification steps performed.

### License

This repository does not include a license file yet. Before publishing it as open source, add a `LICENSE` file, such as MIT, Apache-2.0, or another license that matches your distribution goals.
