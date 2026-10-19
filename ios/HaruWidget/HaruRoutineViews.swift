import SwiftUI
import WidgetKit

// 오늘 루틴 위젯 (홈 작게·중간 / 잠금화면 직사각형·원형)

struct RoutineWidgetView: View {
    @Environment(\.widgetFamily) private var envFamily
    let entry: HaruEntry
    /// 미리보기 그림 도구에서 위젯 크기를 정해 줄 때만 써요.
    var forced: WidgetFamily? = nil
    private var family: WidgetFamily { forced ?? envFamily }

    var body: some View {
        let s = entry.snap
        WidgetShell(pro: s.pro) {
            if s.pro != .active {
                LockedView(family: family, state: s.pro, price: s.proInfo.price ?? "₩3,300")
            } else {
                switch family {
                case .systemSmall:
                    RoutineSmall(s: s)
                case .systemMedium:
                    RoutineMedium(s: s)
                case .accessoryRectangular:
                    RoutineRect(s: s)
                case .accessoryCircular:
                    RoutineCircle(s: s)
                default:
                    RoutineSmall(s: s)
                }
            }
        }
    }
}

struct RoutineSmall: View {
    let s: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("오늘 루틴")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.haruMuted)
            Spacer(minLength: 0)
            if s.routineTotal == 0 {
                VStack(alignment: .leading, spacing: 3) {
                    Text("루틴이 없어요")
                        .font(.system(size: 16, weight: .bold))
                    Text("앱에서 추가해 보세요")
                        .font(.system(size: 12))
                        .foregroundColor(Color.haruMuted)
                }
            } else {
                ZStack {
                    Ring(progress: s.routineProgress)
                    Text("\(s.routineDone)/\(s.routineTotal)")
                        .font(.system(size: 20, weight: .bold))
                }
                .frame(width: 84, height: 84)
                .frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct RoutineMedium: View {
    let s: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("오늘 · \(HaruDate.shortLabel(s.date))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.haruMuted)
                Spacer()
                if s.routineTotal > 0 {
                    Text("\(s.routineDone)/\(s.routineTotal) 완료")
                        .font(.system(size: 12))
                        .foregroundColor(Color.haruMuted)
                }
            }
            if s.routineTotal == 0 {
                Spacer(minLength: 0)
                Text("루틴이 없어요. 앱에서 추가해 보세요.")
                    .font(.system(size: 14))
                    .foregroundColor(Color.haruMuted)
                Spacer(minLength: 0)
            } else {
                ForEach(Array(s.routineRows.prefix(3)), id: \.id) { item in
                    HStack(spacing: 10) {
                        ToggleButton(item: item, day: s.today) {
                            CheckDot(done: item.isDone(on: s.today))
                        }
                        Text(item.title)
                            .font(.system(size: 15))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        StreakLabel(count: haruStreak(item, now: s.date))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct RoutineRect: View {
    let s: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if s.routineTotal == 0 {
                Text("루틴이 없어요")
                    .font(.system(size: 13, weight: .medium))
            } else {
                ForEach(Array(s.routineRows.prefix(3)), id: \.id) { item in
                    let done = item.isDone(on: s.today)
                    HStack(spacing: 5) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12))
                        Text(item.title)
                            .font(.system(size: 13, weight: .medium))
                            .strikethrough(done)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        if haruStreak(item, now: s.date) >= 7 {
                            Image(systemName: "flame.fill").font(.system(size: 10))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RoutineCircle: View {
    let s: Snapshot

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Ring(
                progress: s.routineProgress,
                lineWidth: 4,
                track: Color.primary.opacity(0.25),
                tint: Color.primary
            )
            .padding(5)
            VStack(spacing: -1) {
                Text("루틴").font(.system(size: 9, weight: .semibold))
                Text("\(s.routineDone)/\(s.routineTotal)").font(.system(size: 15, weight: .bold))
            }
        }
    }
}

// 연속 일수 위젯 (잠금화면 원형)

struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var envFamily
    let entry: HaruEntry
    /// 미리보기 그림 도구에서 위젯 크기를 정해 줄 때만 써요.
    var forced: WidgetFamily? = nil
    private var family: WidgetFamily { forced ?? envFamily }

    var body: some View {
        let s = entry.snap
        WidgetShell(pro: s.pro) {
            if s.pro != .active {
                LockedView(family: family, state: s.pro, price: s.proInfo.price ?? "₩3,300")
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: "flame.fill").font(.system(size: 14))
                        Text("\(s.maxStreak)일").font(.system(size: 15, weight: .bold))
                    }
                }
            }
        }
    }
}
