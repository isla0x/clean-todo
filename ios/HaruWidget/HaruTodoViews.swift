import SwiftUI
import WidgetKit

// 다음 할 일 위젯 (홈 작게) · 캘린더와 할 일 위젯 (홈 크게)

struct TodoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HaruEntry

    var body: some View {
        let s = entry.snap
        WidgetShell(pro: s.pro) {
            if s.pro != .active {
                LockedView(family: family, state: s.pro, price: s.proInfo.price ?? "₩3,300")
            } else {
                TodoSmall(s: s)
            }
        }
    }
}

struct TodoSmall: View {
    let s: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("다음 할 일")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.haruMuted)
            Spacer(minLength: 0)
            if let first = s.untimedRows.first, !first.isDone(on: s.today) {
                Text(first.title)
                    .font(.system(size: 17, weight: .bold))
                    .lineLimit(3)
                Spacer(minLength: 0)
                HStack(spacing: 7) {
                    ToggleButton(item: first, day: s.today) {
                        CheckDot(done: false, size: 20)
                    }
                    Text("투두 \(s.untimedLeft)개 남음")
                        .font(.system(size: 12))
                        .foregroundColor(Color.haruMuted)
                }
            } else {
                CheckBadge(size: 36)
                Text(s.untimed.isEmpty ? "할 일이 없어요" : "모두 끝났어요")
                    .font(.system(size: 16, weight: .bold))
                    .padding(.top, 8)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// ───────────────────────── 캘린더 ─────────────────────────

/// 달력에서 빨갛게 보이는 공휴일 (앱과 같은 목록)
let haruHolidays: Set<String> = [
    "2026-01-01", "2026-02-16", "2026-02-17", "2026-02-18", "2026-03-01", "2026-03-02",
    "2026-05-01", "2026-05-05", "2026-05-24", "2026-05-25", "2026-06-03", "2026-06-06",
    "2026-07-17", "2026-08-15", "2026-08-17", "2026-09-24", "2026-09-25", "2026-09-26",
    "2026-10-03", "2026-10-05", "2026-10-09", "2026-12-25",
    "2027-01-01", "2027-02-06", "2027-02-07", "2027-02-08", "2027-02-09", "2027-03-01",
    "2027-05-01", "2027-05-03", "2027-05-05", "2027-05-13", "2027-06-06", "2027-07-17",
    "2027-07-19", "2027-08-15", "2027-08-16", "2027-09-14", "2027-09-15", "2027-09-16",
    "2027-10-03", "2027-10-04", "2027-10-09", "2027-10-11", "2027-12-25", "2027-12-27",
]

struct CalendarWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HaruEntry

    var body: some View {
        let s = entry.snap
        WidgetShell(pro: s.pro) {
            if s.pro != .active {
                LockedView(family: family, state: s.pro, price: s.proInfo.price ?? "₩3,300")
            } else {
                CalendarLarge(s: s)
            }
        }
    }
}

struct DayCell: View {
    let date: Date?
    let s: Snapshot

    var body: some View {
        if let d = date {
            let key = HaruDate.key(d)
            let isToday = key == s.today
            let day = HaruDate.cal.component(.day, from: d)
            let weekday = HaruDate.cal.component(.weekday, from: d)
            let red = weekday == 1 || haruHolidays.contains(key)
            let p = s.progress(on: key)
            VStack(spacing: 2) {
                ZStack {
                    if isToday { Circle().fill(Color.haruAccent) }
                    Text("\(day)")
                        .font(.system(size: 13, weight: isToday ? .semibold : .regular))
                        .foregroundColor(isToday ? Color.white : (red ? Color.haruRed : Color.primary))
                }
                .frame(width: 24, height: 24)
                if p.total == 0 {
                    Color.clear.frame(width: 5, height: 5)
                } else if p.done == p.total {
                    Circle().fill(Color.haruAccent).frame(width: 5, height: 5)
                } else {
                    Circle().strokeBorder(Color.haruAccent, lineWidth: 1.2).frame(width: 5, height: 5)
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 31)
        }
    }
}

struct CalendarLarge: View {
    let s: Snapshot

    /// 이번 달의 칸들 (일요일부터 시작, 앞뒤 빈칸은 nil)
    private var weeks: [[Date?]] {
        let cal = HaruDate.cal
        let first = cal.date(from: cal.dateComponents([.year, .month], from: s.date)) ?? s.date
        let lead = cal.component(.weekday, from: first) - 1 // 일=0
        let count = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        var cells: [Date?] = Array(repeating: nil, count: lead)
        for i in 0 ..< count { cells.append(cal.date(byAdding: .day, value: i, to: first)) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0 ..< $0 + 7]) }
    }

    var body: some View {
        let w = weeks
        let rows = w.count <= 4 ? 3 : (w.count == 5 ? 2 : 1)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(HaruDate.longLabel(s.date))
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Text("루틴 \(s.routineDone)/\(s.routineTotal) · 투두 \(s.untimedDone)/\(s.untimed.count)")
                    .font(.system(size: 11))
                    .foregroundColor(Color.haruMuted)
            }
            HStack(spacing: 0) {
                ForEach(0 ..< 7, id: \.self) { i in
                    Text(["일", "월", "화", "수", "목", "금", "토"][i])
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(i == 0 ? Color.haruRed : Color.haruMuted)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0 ..< w.count, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0 ..< 7, id: \.self) { c in
                        DayCell(date: w[r][c], s: s)
                    }
                }
            }
            Rectangle().fill(Color.haruLine).frame(height: 1).padding(.top, 2)
            if s.untimed.isEmpty {
                Text("오늘 할 일이 없어요")
                    .font(.system(size: 13))
                    .foregroundColor(Color.haruMuted)
            } else {
                UntimedRows(s: s, limit: rows)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
