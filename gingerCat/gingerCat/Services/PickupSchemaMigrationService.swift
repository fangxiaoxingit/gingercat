import Foundation
import SwiftData

@MainActor
enum PickupSchemaMigrationService {
    static func runIfNeeded(
        modelContainer: ModelContainer,
        defaults: UserDefaults = .standard
    ) {
        guard defaults.bool(forKey: AppSettingsKeys.pickupSchemaMigrationV2Done) == false else {
            return
        }

        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<ScanRecord>()
        let records = (try? context.fetch(descriptor)) ?? []

        var didChange = false
        for record in records {
            let hasPickupJSON = record.pickupCodesJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            guard hasPickupJSON else { continue }

            record.pickupCodesJSON = ""
            if record.intent == ScanIntent.pickup.rawValue {
                record.intent = ScanIntent.summary.rawValue
            }
            didChange = true
        }

        if didChange {
            try? context.save()
        }

        defaults.set(true, forKey: AppSettingsKeys.pickupSchemaMigrationV2Done)
    }
}
