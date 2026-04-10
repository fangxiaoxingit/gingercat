import Foundation

enum AppDeepLink {
    static func recordID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == "gingercat" else { return nil }

        if url.host?.lowercased() == "record",
           let recordID = UUID(uuidString: url.lastPathComponent) {
            return recordID
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        if pathComponents.count >= 2,
           pathComponents[0].lowercased() == "record",
           let recordID = UUID(uuidString: pathComponents[1]) {
            return recordID
        }

        return nil
    }

    static func isImportImageURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "gingercat" else { return false }
        return url.host?.lowercased() == "import-image"
    }
}
