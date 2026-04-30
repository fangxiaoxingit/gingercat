import Foundation
import UniformTypeIdentifiers

enum ExternalImageImportStoreError: LocalizedError {
    case missingSharedContainer
    case invalidImagePayload

    var errorDescription: String? {
        switch self {
        case .missingSharedContainer:
            return "共享容器不可用，请检查 App Group 配置。"
        case .invalidImagePayload:
            return "共享图片数据已损坏，请重新分享一次。"
        }
    }
}

struct QueuedExternalImageImport: Identifiable, Equatable {
    let id: UUID
    let imageData: Data?
    let recognizedText: String?
    let source: String
    let autoProcess: Bool
    let originalFilename: String
}

private struct StoredExternalImageImportMetadata: Codable {
    let id: UUID
    let imageFilename: String?
    let recognizedText: String?
    let originalFilename: String
    let source: String
    let autoProcess: Bool
    let createdAt: Date
}

struct ExternalImageImportStore {
    static let sharedAppGroupIdentifier = "group.com.example.GingerCat"
    static let wakeUpURL = URL(string: "gingercat://import-image")

    private let fileManager: FileManager
    private let baseDirectoryProvider: () throws -> URL

    init(
        fileManager: FileManager = .default,
        baseDirectoryProvider: @escaping () throws -> URL = {
            guard let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: Self.sharedAppGroupIdentifier
            ) else {
                throw ExternalImageImportStoreError.missingSharedContainer
            }

            return containerURL.appending(path: "IncomingImports", directoryHint: .isDirectory)
        }
    ) {
        self.fileManager = fileManager
        self.baseDirectoryProvider = baseDirectoryProvider
    }

    // 统一把外部图片写进共享队列，主 App 与扩展都按同一份协议读写，避免入口越多越难维护。
    func queueImageData(
        _ imageData: Data,
        suggestedFilename: String,
        source: String,
        autoProcess: Bool,
        recognizedText: String? = nil,
        contentType: UTType? = nil
    ) throws {
        let importsDirectoryURL = try prepareImportsDirectory()
        try clearExistingImport(in: importsDirectoryURL)

        let importID = UUID()
        let fileExtension = preferredFileExtension(
            suggestedFilename: suggestedFilename,
            contentType: contentType
        )
        let storedFilename = "\(importID.uuidString).\(fileExtension)"
        let imageURL = importsDirectoryURL.appending(path: storedFilename, directoryHint: .notDirectory)
        let metadata = StoredExternalImageImportMetadata(
            id: importID,
            imageFilename: storedFilename,
            recognizedText: normalizedRecognizedText(recognizedText),
            originalFilename: normalizedFilename(from: suggestedFilename, fallbackExtension: fileExtension),
            source: source,
            autoProcess: autoProcess,
            createdAt: .now
        )

        try imageData.write(to: imageURL, options: .atomic)
        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: metadataURL(in: importsDirectoryURL), options: .atomic)
    }

    // 主 App 每次被唤醒时消费一次共享队列，确保分享扩展与捷径都能落到同一条后续处理链路里。
    func consumePendingImport() throws -> QueuedExternalImageImport? {
        let importsDirectoryURL = try prepareImportsDirectory()
        let metadataURL = metadataURL(in: importsDirectoryURL)

        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return nil
        }

        let metadataData = try Data(contentsOf: metadataURL)
        let metadata = try JSONDecoder().decode(
            StoredExternalImageImportMetadata.self,
            from: metadataData
        )
        let imageData: Data?
        if let imageFilename = metadata.imageFilename {
            let imageURL = importsDirectoryURL.appending(path: imageFilename, directoryHint: .notDirectory)
            guard fileManager.fileExists(atPath: imageURL.path) else {
                try clearExistingImport(in: importsDirectoryURL)
                throw ExternalImageImportStoreError.invalidImagePayload
            }
            imageData = try Data(contentsOf: imageURL)
        } else {
            imageData = nil
        }

        let recognizedText = normalizedRecognizedText(metadata.recognizedText)
        guard imageData != nil || recognizedText != nil else {
            try clearExistingImport(in: importsDirectoryURL)
            throw ExternalImageImportStoreError.invalidImagePayload
        }
        try clearExistingImport(in: importsDirectoryURL)

        return QueuedExternalImageImport(
            id: metadata.id,
            imageData: imageData,
            recognizedText: recognizedText,
            source: metadata.source,
            autoProcess: metadata.autoProcess,
            originalFilename: metadata.originalFilename
        )
    }

    // 先确保目录存在，再执行读写，避免扩展首次运行时因为目录尚未创建导致导入失败。
    private func prepareImportsDirectory() throws -> URL {
        let directoryURL = try baseDirectoryProvider()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func metadataURL(in importsDirectoryURL: URL) -> URL {
        importsDirectoryURL.appending(path: "pending-import.json", directoryHint: .notDirectory)
    }

    // 共享队列暂时只保留一个待处理图片，新请求覆盖旧请求，避免 App 被多次唤醒时弹出过期确认框。
    private func clearExistingImport(in importsDirectoryURL: URL) throws {
        let metadataURL = metadataURL(in: importsDirectoryURL)
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return
        }

        if let metadataData = try? Data(contentsOf: metadataURL),
           let metadata = try? JSONDecoder().decode(
                StoredExternalImageImportMetadata.self,
                from: metadataData
           ) {
            if let imageFilename = metadata.imageFilename {
                let imageURL = importsDirectoryURL.appending(path: imageFilename, directoryHint: .notDirectory)
                if fileManager.fileExists(atPath: imageURL.path) {
                    try? fileManager.removeItem(at: imageURL)
                }
            }
        }

        try? fileManager.removeItem(at: metadataURL)
    }

    private func preferredFileExtension(
        suggestedFilename: String,
        contentType: UTType?
    ) -> String {
        let filenameExtension = URL(filePath: suggestedFilename).pathExtension
        if filenameExtension.isEmpty == false {
            return filenameExtension.lowercased()
        }

        if let preferredFilenameExtension = contentType?.preferredFilenameExtension,
           preferredFilenameExtension.isEmpty == false {
            return preferredFilenameExtension
        }

        return "jpg"
    }

    private func normalizedFilename(from filename: String, fallbackExtension: String) -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "imported-image.\(fallbackExtension)"
        }
        return trimmed
    }

    private func normalizedRecognizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
