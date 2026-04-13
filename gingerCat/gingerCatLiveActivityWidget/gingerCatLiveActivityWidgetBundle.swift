import SwiftUI
import WidgetKit

@main
struct gingerCatLiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        OCRLiveActivityWidget()
        LatestTodoSquareWidget()
        RecentTodosMediumWidget()
    }
}
