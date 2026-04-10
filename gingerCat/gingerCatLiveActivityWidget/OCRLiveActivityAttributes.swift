import Foundation
import ActivityKit

@available(iOSApplicationExtension 16.1, *)
struct OCRLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let title: String
        let summary: String
        let dateText: String
    }

    let recordID: String
}
