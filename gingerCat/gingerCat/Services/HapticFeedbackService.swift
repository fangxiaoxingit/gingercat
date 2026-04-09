import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum HapticFeedbackService {
    // 使用统一入口承接不同页面的点击反馈，避免设置项和页面行为脱节。
    static func impact(enabled: Bool, intensity: HapticFeedbackIntensity) {
        #if canImport(UIKit)
        guard enabled else { return }
        let generator = UIImpactFeedbackGenerator(style: feedbackStyle(for: intensity))
        generator.prepare()
        generator.impactOccurred(intensity: impactValue(for: intensity))
        #endif
    }

    static func success(enabled: Bool) {
        #if canImport(UIKit)
        guard enabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        #endif
    }

    #if canImport(UIKit)
    private static func feedbackStyle(for intensity: HapticFeedbackIntensity) -> UIImpactFeedbackGenerator.FeedbackStyle {
        switch intensity {
        case .weak:
            return .soft
        case .medium:
            return .medium
        case .strong:
            return .rigid
        }
    }

    private static func impactValue(for intensity: HapticFeedbackIntensity) -> CGFloat {
        switch intensity {
        case .weak:
            return 0.45
        case .medium:
            return 0.75
        case .strong:
            return 1.0
        }
    }
    #endif
}
