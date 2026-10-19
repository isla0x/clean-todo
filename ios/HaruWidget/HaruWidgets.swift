import SwiftUI
import WidgetKit

struct RoutineWidget: Widget {
    let kind = "HaruRoutine"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HaruProvider()) { entry in
            RoutineWidgetView(entry: entry)
        }
        .configurationDisplayName("오늘 루틴")
        .description("오늘 루틴을 얼마나 했는지 보여줘요.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

struct ScheduleWidget: Widget {
    let kind = "HaruSchedule"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HaruProvider()) { entry in
            ScheduleWidgetView(entry: entry)
        }
        .configurationDisplayName("다음 일정")
        .description("오늘 일정과 다음 일정까지 남은 시간을 보여줘요.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct TodoWidget: Widget {
    let kind = "HaruTodo"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HaruProvider()) { entry in
            TodoWidgetView(entry: entry)
        }
        .configurationDisplayName("다음 할 일")
        .description("시간이 정해지지 않은 투두를 보여줘요.")
        .supportedFamilies([.systemSmall])
    }
}

struct CalendarWidget: Widget {
    let kind = "HaruCalendar"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HaruProvider()) { entry in
            CalendarWidgetView(entry: entry)
        }
        .configurationDisplayName("캘린더와 할 일")
        .description("이번 달 달력과 오늘 할 일을 한눈에 보여줘요.")
        .supportedFamilies([.systemLarge])
    }
}

struct StreakWidget: Widget {
    let kind = "HaruStreak"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HaruProvider()) { entry in
            StreakWidgetView(entry: entry)
        }
        .configurationDisplayName("연속 일수")
        .description("루틴을 며칠째 이어가고 있는지 보여줘요.")
        .supportedFamilies([.accessoryCircular])
    }
}

@main
struct HaruWidgetBundle: WidgetBundle {
    var body: some Widget {
        RoutineWidget()
        ScheduleWidget()
        TodoWidget()
        CalendarWidget()
        StreakWidget()
    }
}
