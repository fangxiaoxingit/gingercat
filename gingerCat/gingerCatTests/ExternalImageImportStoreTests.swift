import Foundation
import Testing
@testable import gingerCat

struct ExternalImageImportStoreTests {
    @Test
    func queueAndConsumePendingImport() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = ExternalImageImportStore(
            baseDirectoryProvider: { temporaryDirectory }
        )
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])

        // 用临时目录验证共享协议读写，避免测试依赖真实 App Group 环境。
        try store.queueImageData(
            imageData,
            suggestedFilename: "shared.png",
            source: "Share",
            autoProcess: false
        )

        let pendingImport = try store.consumePendingImport()
        let consumedImport = try #require(pendingImport)
        #expect(consumedImport.imageData == imageData)
        #expect(consumedImport.source == "Share")
        #expect(consumedImport.autoProcess == false)
        #expect(consumedImport.originalFilename == "shared.png")

        let secondRead = try store.consumePendingImport()
        #expect(secondRead == nil)
    }
}
