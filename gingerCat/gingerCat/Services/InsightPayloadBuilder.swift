import Foundation

enum InsightPayloadBuilder {
    static func build(source: String, recognizedText: String, imageData: Data? = nil) -> InsightPayload {
        let sanitizedText = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        // 本地链路只保留 OCR 原文，避免再额外生成“本地摘要”文案。
        return InsightPayload(
            imageData: imageData,
            source: source,
            rawText: sanitizedText,
            summary: sanitizedText,
            summarySource: .local,
            mode: .summary,
            events: []
        )
    }
}
