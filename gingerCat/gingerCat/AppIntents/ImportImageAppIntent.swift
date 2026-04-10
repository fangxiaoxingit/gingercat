import AppIntents
import UniformTypeIdentifiers

struct ImportImageAppIntent: AppIntent {
    static let title: LocalizedStringResource = "导入图片并解析"
    static let description = IntentDescription("把图片直接发送到大橘小事并在后台完成识别，不需要手动打开 App。")
    static let openAppWhenRun = false

    @Parameter(
        title: "图片",
        supportedContentTypes: [.image],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var image: IntentFile

    // 捷径入口在后台直接执行 OCR/AI 与落库，避免还要再打开 App 才真正开始解析。
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let record = try await BackgroundImageImportPipeline.importImage(
            imageData: image.data,
            source: "Shortcuts"
        )
        let summary = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let dialog = summary.isEmpty
            ? "图片已解析并加入记录。"
            : "图片已解析并加入记录：\(summary)"

        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

struct GingerCatShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ImportImageAppIntent(),
            phrases: [
                "用 \(.applicationName) 解析图片",
                "把图片导入 \(.applicationName)"
            ],
            shortTitle: "导入并解析",
            systemImageName: "photo.badge.plus"
        )
    }
}
