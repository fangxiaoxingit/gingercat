import Foundation
import ActivityKit

@available(iOSApplicationExtension 16.1, *)
struct OCRLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let title: String
        let summary: String
        let dateText: String
        let isPickupPriority: Bool
        let pickupBrandName: String?
        let pickupItemName: String?
        let pickupCodeLabel: String?
        let pickupCodeValue: String?
        let pickupCategory: String?
        let pickupDate: String?
        let pickupTime: String?
        let pickupExtraCount: Int
    }

    let recordID: String
}
