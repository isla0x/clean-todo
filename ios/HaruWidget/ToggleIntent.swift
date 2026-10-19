import AppIntents
import Foundation
import WidgetKit

/// 위젯의 동그라미를 눌렀을 때 완료 표시를 바꿔요. (iOS 17 이상)
@available(iOS 17.0, *)
struct ToggleItemIntent: AppIntent {
    static let title: LocalizedStringResource = "완료 표시"

    @Parameter(title: "항목")
    var itemId: String

    @Parameter(title: "날짜")
    var day: String

    @Parameter(title: "완료")
    var done: Bool

    init() {}

    init(itemId: String, day: String, done: Bool) {
        self.itemId = itemId
        self.day = day
        self.done = done
    }

    func perform() async throws -> some IntentResult {
        HaruStore.applyToggle(id: itemId, day: day, done: done)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
