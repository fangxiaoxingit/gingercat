import AppIntents
import UniformTypeIdentifiers

@available(iOS 17.0, *)
struct ImportImageAppIntent: AppIntent {
    static let title: LocalizedStringResource = "导入图片并解析"
    static let description = IntentDescription("把图片发送到大橘小事并完成识别。")
    static let openAppWhenRun = false

    @Parameter(
        title: "图片",
        supportedContentTypes: [.image],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var image: IntentFile

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
        return [
            AppShortcut(
                intent: ImportImageAppIntent(),
                phrases: [
                    "用 \(.applicationName) 解析图片",
                    "把图片导入 \(.applicationName)"
                ],
                shortTitle: "导入并解析",
                systemImageName: "photo.badge.plus"
            )
        ]
    }
}
