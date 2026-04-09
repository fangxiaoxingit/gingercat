import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
struct CameraCaptureView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    @Binding var capturedImage: UIImage?

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = LocalizedCameraPickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // UIImagePickerController 的系统按钮在部分环境下不会跟随中文，统一在布局后覆盖常见底部按钮标题。
    final class LocalizedCameraPickerController: UIImagePickerController {
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            localizeButtons(in: view)
        }

        private func localizeButtons(in view: UIView) {
            for subview in view.subviews {
                if let button = subview as? UIButton,
                   let currentTitle = button.title(for: .normal)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   currentTitle.isEmpty == false {
                    let localizedTitle = switch currentTitle {
                    case "Cancel":
                        String(localized: "取消")
                    case "Retake":
                        String(localized: "重拍")
                    case "Use Photo":
                        String(localized: "使用照片")
                    default:
                        currentTitle
                    }

                    if localizedTitle != currentTitle {
                        button.setTitle(localizedTitle, for: .normal)
                    }
                }

                localizeButtons(in: subview)
            }
        }
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraCaptureView

        init(_ parent: CameraCaptureView) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.capturedImage = image
            }
            parent.dismiss()
        }
    }
}
#endif
