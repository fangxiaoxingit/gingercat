//
//  gingerCatTests.swift
//  gingerCatTests
//
//  Created by fsy on 2026/4/8.
//

import Testing
@testable import gingerCat

struct gingerCatTests {
    @Test
    func pickupExtractorRecognizesExpressCode() async throws {
        let text = """
        韵达快递超市代收点
        取件码 20-2-2565
        申通快递 777401048242565
        """

        let pickupCodes = PickupCodeExtractor.extract(from: text)
        let first = try #require(pickupCodes.first)

        #expect(first.code == "20-2-2565")
        #expect(first.category == .express)
        #expect(first.label == "取件码")
        #expect(first.resolvedDisplayName.isEmpty == false)
    }

    @Test
    func pickupDisplayNameFallsBackToCategory() async throws {
        let pickup = ScanPickupCode(
            code: "A1023",
            category: .coffee,
            merchantName: nil
        )

        #expect(pickup.resolvedDisplayName == "咖啡")
        #expect(pickup.summaryText == "咖啡 取件码 A1023")
    }

}
