import UIKit
import UniformTypeIdentifiers
@preconcurrency import Vision

private enum ShareImportError: LocalizedError {
    case missingSharedContainer
    case missingAttachment
    case unsupportedImage
    case failedToEncodeImage

    var errorDescription: String? {
        switch self {
        case .missingSharedContainer:
            return "共享容器不可用，请检查 App Group 配置。"
        case .missingAttachment:
            return "没有读取到可导入的图片。"
        case .unsupportedImage:
            return "当前分享内容不是受支持的图片。"
        case .failedToEncodeImage:
            return "图片编码失败，请换一张图片重试。"
        }
    }
}

private struct ShareExtensionStoredMetadata: Codable {
    let id: UUID
    let imageFilename: String?
    let recognizedText: String?
    let originalFilename: String
    let source: String
    let autoProcess: Bool
    let createdAt: Date
}

private struct ShareExtensionImportStore {
    static let appGroupIdentifier = "group.com.example.GingerCat"

    // 扩展只负责把图片写进共享容器，数据结构与主 App 保持一致，避免后面两边各修一套协议。
    func queueImageData(
        _ imageData: Data,
        suggestedFilename: String,
        contentType: UTType?,
        recognizedText: String?
    ) throws {
        let fileManager = FileManager.default
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        ) else {
            throw ShareImportError.missingSharedContainer
        }

        let importsDirectoryURL = containerURL.appending(path: "IncomingImports", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: importsDirectoryURL, withIntermediateDirectories: true)
        try clearExistingImport(in: importsDirectoryURL, fileManager: fileManager)

        let importID = UUID()
        let fileExtension = preferredFileExtension(
            suggestedFilename: suggestedFilename,
            contentType: contentType
        )
        let storedFilename = "\(importID.uuidString).\(fileExtension)"
        let imageURL = importsDirectoryURL.appending(path: storedFilename, directoryHint: .notDirectory)
        let metadata = ShareExtensionStoredMetadata(
            id: importID,
            imageFilename: storedFilename,
            recognizedText: normalizedRecognizedText(recognizedText),
            originalFilename: normalizedFilename(from: suggestedFilename, fallbackExtension: fileExtension),
            source: "Share",
            autoProcess: true,
            createdAt: .now
        )

        try imageData.write(to: imageURL, options: .atomic)
        let metadataURL = importsDirectoryURL.appending(path: "pending-import.json", directoryHint: .notDirectory)
        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: metadataURL, options: .atomic)
    }

    // 共享队列仅保留最近一次分享，避免用户短时间连续分享时弹出过期确认内容。
    private func clearExistingImport(in directoryURL: URL, fileManager: FileManager) throws {
        let metadataURL = directoryURL.appending(path: "pending-import.json", directoryHint: .notDirectory)
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return
        }

        if let metadataData = try? Data(contentsOf: metadataURL),
           let metadata = try? JSONDecoder().decode(
                ShareExtensionStoredMetadata.self,
                from: metadataData
           ) {
            if let imageFilename = metadata.imageFilename {
                let imageURL = directoryURL.appending(path: imageFilename, directoryHint: .notDirectory)
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
            return "shared-image.\(fallbackExtension)"
        }
        return trimmed
    }

    private func normalizedRecognizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private var hasStartedImport = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard hasStartedImport == false else { return }
        hasStartedImport = true

        // 分享扩展进入可见状态后立刻开始导入，用户不需要在扩展里再确认一次，尽量缩短从分享到账户内确认的路径。
        Task { @MainActor in
            await importSharedImage()
        }
    }

    private func configureView() {
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.text = "正在导入图片到大橘小事..."

        view.addSubview(activityIndicator)
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -26),
            statusLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 18),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    // 扩展侧直接做 OCR 并入队结果，用户分享后无需拉起主 App 即可完成解析。
    @MainActor
    private func importSharedImage() async {
        do {
            let imagePayload = try await loadFirstSupportedImage()
            let recognizedText = try await recognizeText(from: imagePayload.image)
            try ShareExtensionImportStore().queueImageData(
                imagePayload.data,
                suggestedFilename: imagePayload.filename,
                contentType: imagePayload.contentType,
                recognizedText: recognizedText
            )

            activityIndicator.stopAnimating()
            statusLabel.text = "图片已解析完成，可稍后在大橘小事查看记录。"

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        } catch {
            activityIndicator.stopAnimating()
            statusLabel.text = error.localizedDescription
            extensionContext?.cancelRequest(withError: error)
        }
    }

    private func loadFirstSupportedImage() async throws -> (
        image: UIImage,
        data: Data,
        filename: String,
        contentType: UTType?
    ) {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = extensionItem.attachments else {
            throw ShareImportError.missingAttachment
        }

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.png.identifier) {
                let data = try await loadDataRepresentation(
                    from: provider,
                    typeIdentifier: UTType.png.identifier
                )
                guard let image = UIImage(data: data) else {
                    throw ShareImportError.unsupportedImage
                }
                return (image, data, provider.suggestedName ?? "shared-image.png", .png)
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier) {
                let data = try await loadDataRepresentation(
                    from: provider,
                    typeIdentifier: UTType.jpeg.identifier
                )
                guard let image = UIImage(data: data) else {
                    throw ShareImportError.unsupportedImage
                }
                return (image, data, provider.suggestedName ?? "shared-image.jpg", .jpeg)
            }

            if provider.canLoadObject(ofClass: UIImage.self) {
                let image = try await loadUIImage(from: provider)
                if let jpegData = image.jpegData(compressionQuality: 0.92) ?? image.pngData() {
                    return (image, jpegData, provider.suggestedName ?? "shared-image.jpg", .jpeg)
                }
                throw ShareImportError.failedToEncodeImage
            }
        }

        throw ShareImportError.unsupportedImage
    }

    private func loadDataRepresentation(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data else {
                    continuation.resume(throwing: ShareImportError.unsupportedImage)
                    return
                }

                continuation.resume(returning: data)
            }
        }
    }

    private func loadUIImage(from provider: NSItemProvider) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let image = image as? UIImage else {
                    continuation.resume(throwing: ShareImportError.unsupportedImage)
                    return
                }

                continuation.resume(returning: image)
            }
        }
    }

    // 分享扩展里先完成 OCR，主 App 后续只需要消费结果并落库，避免再次做一次同样的识别。
    private func recognizeText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw ShareImportError.unsupportedImage
        }

        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.isEmpty == false }
                    .joined(separator: "\n")

                guard text.isEmpty == false else {
                    continuation.resume(throwing: ShareImportError.unsupportedImage)
                    return
                }

                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
