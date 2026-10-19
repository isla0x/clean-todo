import SwiftUI
import WidgetKit

// 다음 일정 위젯 (홈 작게·중간·크게 / 잠금화면 직사각형·한 줄)

struct ScheduleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HaruEntry

    var body: some View {
        let s = entry.snap
        WidgetShell(pro: s.pro) {
            if s.pro != .active {
                LockedView(family: family, state: s.pro, price: s.proInfo.price ?? "₩3,300")
            } else {
                switch family {
                case .systemSmall:
                    ScheduleSmall(s: s)
                case .systemMedium:
                    ScheduleMedium(s: s)
                case .systemLarge:
                    ScheduleLarge(s: s)
                case .accessoryRectangular:
                    ScheduleRect(s: s)
                case .accessoryInline:
                    ScheduleInline(s: s)
                default:
                    ScheduleSmall(s: s)
                }
            }
        }
    }
}

/// 일정이 3개를 넘으면 지금 일정이 보이는 3개만 골라요.
func scheduleWindow(_ s: Snapshot, size: Int) -> [WItem] {
    let timed = s.timed
    if timed.count <= size { return timed }
    var start = 0
    if let f = s.focus, let idx = timed.firstIndex(where: { $0.id == f.id }) {
        start = max(0, min(idx - 1, timed.count - size))
    } else {
        start = timed.count - size
    }
    return Array(timed[start ..< start + size])
}

func markerState(_ item: WItem, _ s: Snapshot) -> MarkerState {
    if item.isDone(on: s.today) { return .done }
    if let f = s.focus, f.id == item.id { return .next }
    return .later
}

/// "다음 일정" 한 덩어리 (점 + 제목 + 몇 분 후)
struct FocusBlock: View {
    let s: Snapshot
    let item: WItem
    var titleSize: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(Color.haruAccent)
                    .frame(width: 10, height: 10)
                    .padding(.top, 5)
                Text(item.title)
                    .font(.system(size: titleSize, weight: .semibold))
                    .lineLimit(2)
            }
            if let due = s.dueDate(item) {
                RelativeTail(due: due, now: s.date)
                    .font(.system(size: 12))
                    .foregroundColor(Color.haruMuted)
                    .padding(.leading, 18)
            }
        }
    }
}

struct ScheduleSmall: View {
    let s: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let f = s.focus {
                Pill(text: "다음 일정")
                Spacer(minLength: 0)
                FocusBlock(s: s, item: f)
                Spacer(minLength: 0)
                Text(HaruDate.clock(f.minutes ?? 0))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.haruDeep)
            } else {
                Pill(text: "오늘 일정", tinted: false)
                Spacer(minLength: 0)
                CheckBadge(size: 38)
                Text(s.timed.isEmpty ? "오늘 일정이 없어요" : "모두 끝났어요")
                    .font(.system(size: 16, weight: .bold))
                    .padding(.top, 8)
                Text(s.untimedLeft > 0 ? "시간 없는 투두 \(s.untimedLeft)개" : "푹 쉬어요")
                    .font(.system(size: 12))
                    .foregroundColor(Color.haruMuted)
                    .padding(.top, 2)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// 세로 타임라인 (동그라미 + 제목 + 시간)
struct TimelineList: View {
    let rows: [WItem]
    let s: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows, id: \.id) { item in
                let done = item.isDone(on: s.today)
                let state = markerState(item, s)
                HStack(alignment: .top, spacing: 9) {
                    ToggleButton(item: item, day: s.today) {
                        Marker(state: state)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.system(size: 13, weight: state == .next ? .semibold : .regular))
                            .strikethrough(done)
                            .foregroundColor(
                                done ? Color.haruMuted : (state == .next ? Color.haruDeep : Color.primary)
                            )
                            .lineLimit(1)
                        Text(HaruDate.clock(item.minutes ?? 0))
                            .font(.system(size: 11))
                            .foregroundColor(state == .next ? Color.haruDeep : Color.haruMuted)
                    }
                }
            }
        }
        .background(alignment: .topLeading) {
            if rows.count > 1 {
                Rectangle()
                    .fill(Color.haruLine)
                    .frame(width: 1.5)
                    .padding(.leading, 8)
                    .padding(.vertical, 9)
            }
        }
    }
}

struct ScheduleMedium: View {
    let s: Snapshot

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(HaruDate.longLabel(s.date))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.haruDeep)
                Spacer(minLength: 0)
                if let f = s.focus {
                    Pill(text: "다음 일정")
                        .padding(.bottom, 6)
                    FocusBlock(s: s, item: f)
                } else {
                    CheckBadge(size: 32)
                    Text(s.timed.isEmpty ? "오늘 일정이 없어요" : "모두 끝났어요")
                        .font(.system(size: 15, weight: .bold))
                        .padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            if s.timed.isEmpty {
                Spacer(minLength: 0)
            } else {
                TimelineList(rows: scheduleWindow(s, size: 3), s: s)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct UntimedRows: View {
    let s: Snapshot
    let limit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(s.untimedRows.prefix(limit)), id: \.id) { item in
                HStack(spacing: 10) {
                    ToggleButton(item: item, day: s.today) {
                        CheckDot(done: item.isDone(on: s.today), size: 20)
                    }
                    Text(item.title)
                        .font(.system(size: 14))
                        .foregroundColor(item.isDone(on: s.today) ? Color.haruMuted : Color.primary)
                        .strikethrough(item.isDone(on: s.today))
                        .lineLimit(1)
                }
            }
        }
    }
}

struct ScheduleLarge: View {
    let s: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(HaruDate.longLabel(s.date))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.haruDeep)
                Spacer()
                if !s.timed.isEmpty {
                    Text("시간 일정 \(s.timedDone)/\(s.timed.count) 완료")
                        .font(.system(size: 12))
                        .foregroundColor(Color.haruMuted)
                }
            }
            if let f = s.focus {
                Pill(text: "다음 일정")
                FocusBlock(s: s, item: f, titleSize: 18)
            } else {
                HStack(spacing: 10) {
                    CheckBadge(size: 30)
                    Text(s.timed.isEmpty ? "오늘 일정이 없어요" : "모두 끝났어요")
                        .font(.system(size: 17, weight: .bold))
                }
            }
            if !s.timed.isEmpty {
                TimelineList(rows: scheduleWindow(s, size: 4), s: s)
            }
            Rectangle().fill(Color.haruLine).frame(height: 1)
            Text("시간 없음 · \(s.untimedDone)/\(s.untimed.count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.haruMuted)
            if s.untimed.isEmpty {
                Text("시간 없는 투두가 없어요")
                    .font(.system(size: 13))
                    .foregroundColor(Color.haruMuted)
            } else {
                UntimedRows(s: s, limit: s.timed.count > 3 ? 2 : 3)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ScheduleRect: View {
    let s: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if s.timed.isEmpty {
                Text("오늘 일정이 없어요")
                    .font(.system(size: 13, weight: .medium))
            } else {
                ForEach(scheduleWindow(s, size: 3), id: \.id) { item in
                    let done = item.isDone(on: s.today)
                    HStack(spacing: 5) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12))
                        Text(HaruDate.clockShort(item.minutes ?? 0))
                            .font(.system(size: 13, weight: .semibold))
                        Text(item.title)
                            .font(.system(size: 13))
                            .strikethrough(done)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ScheduleInline: View {
    let s: Snapshot

    var body: some View {
        if let f = s.focus {
            Label("\(f.title) · \(HaruDate.clock(f.minutes ?? 0))", systemImage: "circle")
        } else {
            Label(s.timed.isEmpty ? "오늘 일정이 없어요" : "오늘 일정 끝", systemImage: "checkmark.circle")
        }
    }
}
