import Foundation

struct AppUsageGuideSectionContent: Identifiable, Hashable {
    let iconName: String
    let title: String
    let points: [String]

    var id: String { iconName }
}

enum AppUsageGuideContent {
    static func sections() -> [AppUsageGuideSectionContent] {
        [
            AppUsageGuideSectionContent(
                iconName: "square.and.pencil",
                title: String(appLocalized: "多入口导入"),
                points: [
                    String(appLocalized: "支持文字、相册、拍照导入。"),
                    String(appLocalized: "支持系统分享扩展与快捷指令。")
                ]
            ),
            AppUsageGuideSectionContent(
                iconName: "text.viewfinder",
                title: String(appLocalized: "OCR 与 AI 整理"),
                points: [
                    String(appLocalized: "先用本地 OCR 提取文本。"),
                    String(appLocalized: "启用 AI 后生成摘要与待办信息。")
                ]
            ),
            AppUsageGuideSectionContent(
                iconName: "checklist",
                title: String(appLocalized: "待办与提醒"),
                points: [
                    String(appLocalized: "识别到时间后可加入系统提醒事项。"),
                    String(appLocalized: "支持自动添加和当天到期通知。")
                ]
            ),
            AppUsageGuideSectionContent(
                iconName: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                title: String(appLocalized: "历史记录与分享"),
                points: [
                    String(appLocalized: "识别结果会保存到本地历史。"),
                    String(appLocalized: "支持搜索、备注、重识别和分享卡片。")
                ]
            ),
            AppUsageGuideSectionContent(
                iconName: "lock.shield",
                title: String(appLocalized: "隐私与数据"),
                points: [
                    String(appLocalized: "OCR 与记录默认保存在设备上。"),
                    String(appLocalized: "启用 AI 时，仅识别文本会发送到模型服务。")
                ]
            )
        ]
    }
}
