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

        #expect(first.codeValue == "20-2-2565")
        #expect(first.category == .express)
        #expect(first.codeLabel == "取件码")
        #expect(first.resolvedDisplayName.isEmpty == false)
        #expect(first.resolvedItemName.isEmpty == false)
    }

    @Test
    func pickupBrandNameFallsBackToOther() async throws {
        let pickup = ScanPickupCode(
            brandName: nil,
            codeValue: "A1023",
            codeLabel: "取件码",
            category: .coffee,
            pickupDate: "2026-04-21",
            pickupTime: "13:11"
        )

        #expect(pickup.resolvedBrandName == "其他")
        #expect(pickup.resolvedItemName == "咖啡")
        #expect(pickup.summaryText == "其他 取件码 A1023")
        #expect(pickup.dateTimeText == "2026-04-21 13:11")
    }

}
