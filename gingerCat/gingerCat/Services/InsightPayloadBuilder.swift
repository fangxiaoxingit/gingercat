import Foundation

enum InsightPayloadBuilder {
    static func build(source: String, recognizedText: String, imageData: Data? = nil) -> InsightPayload {
        let sanitizedText = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let events = extractEvents(from: sanitizedText)

        if events.isEmpty {
            return InsightPayload(
                imageData: imageData,
                source: source,
                rawText: sanitizedText,
                summary: summaryForGeneralText(sanitizedText),
                summarySource: .local,
                mode: .summary,
                events: []
            )
        }

        return InsightPayload(
            imageData: imageData,
            source: source,
            rawText: sanitizedText,
            summary: "识别到 \(events.count) 条包含时间的信息，已进入日程模式，请勾选需要写入的事件。",
            summarySource: .local,
            mode: .schedule,
            events: events
        )
    }

    private static func extractEvents(from text: String) -> [InsightEvent] {
        guard text.isEmpty == false,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return []
        }

        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        let matches = detector.matches(in: text, options: [], range: fullRange)

        var seen = Set<String>()
        var events: [InsightEvent] = []

        for (index, match) in matches.enumerated() {
            guard let date = match.date else { continue }

            let title = titleForMatch(in: text, match: match, index: index + 1)
            let dedupKey = "\(title)-\(date.timeIntervalSince1970)"
            guard seen.insert(dedupKey).inserted else { continue }

            events.append(InsightEvent(title: title, date: date))
        }

        return events
    }

    private static func titleForMatch(in text: String, match: NSTextCheckingResult, index: Int) -> String {
        let nsText = text as NSString
        var line = nsText.substring(with: nsText.lineRange(for: match.range))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let range = Range(match.range, in: text) {
            let matchedDateString = String(text[range])
            line = line.replacingOccurrences(of: matchedDateString, with: "")
        }

        line = line.trimmingCharacters(in: CharacterSet(charactersIn: "：:;；,.，。 \n\t"))

        if line.isEmpty {
            return "待办事件 \(index)"
        }

        return line
    }

    private static func summaryForGeneralText(_ text: String) -> String {
        guard text.isEmpty == false else {
            return "未识别到有效文字，请尝试更清晰的图片。"
        }

        let preview = String(text.prefix(48))
        if text.count > preview.count {
            return "已提取文字内容：\(preview)..."
        }
        return "已提取文字内容：\(preview)"
    }
}
