import Foundation
import SwiftUI
import WidgetKit

// ───────────────────────── 앱과 위젯이 나눠 쓰는 저장 공간 ─────────────────────────
//
// 앱(Flutter)이 항목 목록과 PRO 상태를 App Group 저장소에 적어 두면
// 위젯이 그걸 읽어서 그려요. 위젯에서 체크한 내용은 "toggles" 목록에 쌓아 두고,
// 앱이 열릴 때 가져가요.

enum HaruShared {
    static let group = "group.com.isla0x.cleanTodo"
    static let itemsKey = "items_v1"
    static let proKey = "pro_v1"
    static let togglesKey = "toggles_v1"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: group) ?? UserDefaults.standard
    }
}

// ───────────────────────── 날짜 도우미 ─────────────────────────

enum HaruDate {
    static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.autoupdatingCurrent
        return c
    }

    /// 'yyyy-MM-dd' (앱이 저장하는 날짜 글자와 같은 모양)
    static func key(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(fromKey key: String) -> Date? {
        let p = key.split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return nil }
        return cal.date(from: DateComponents(year: y, month: m, day: d))
    }

    static func addDays(_ d: Date, _ n: Int) -> Date {
        cal.date(byAdding: .day, value: n, to: d) ?? d
    }

    static func startOfDay(_ d: Date) -> Date { cal.startOfDay(for: d) }

    /// 그날 자정부터 [minutes]분 뒤의 시각
    static func at(_ day: Date, minutes: Int) -> Date {
        cal.date(byAdding: .minute, value: minutes, to: cal.startOfDay(for: day)) ?? day
    }

    static func minutesOfDay(_ d: Date) -> Int {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// 840 → "오후 2:00"
    static func clock(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        let period = h < 12 ? "오전" : "오후"
        let h12 = h % 12 == 0 ? 12 : h % 12
        return "\(period) \(h12):" + String(format: "%02d", m)
    }

    /// 840 → "2:00" (오전/오후 없이)
    static func clockShort(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        let h12 = h % 12 == 0 ? 12 : h % 12
        return "\(h12):" + String(format: "%02d", m)
    }

    static let weekdays = ["월", "화", "수", "목", "금", "토", "일"]

    /// "10월 18일 일요일"
    static func longLabel(_ d: Date) -> String {
        let c = cal.dateComponents([.month, .day, .weekday], from: d)
        let wd = ((c.weekday ?? 1) + 5) % 7 // 일=1 → 6(일), 월=2 → 0(월)
        return "\(c.month ?? 0)월 \(c.day ?? 0)일 \(weekdays[wd])요일"
    }

    /// "10월 18일"
    static func shortLabel(_ d: Date) -> String {
        let c = cal.dateComponents([.month, .day], from: d)
        return "\(c.month ?? 0)월 \(c.day ?? 0)일"
    }
}

// ───────────────────────── 항목 ─────────────────────────

struct WItem: Codable, Identifiable {
    let id: String
    let title: String
    let isRoutine: Bool
    var done: Bool?
    var doneDates: [String]?
    let date: String?
    let time: String?
    let created: String?
    var doneOn: String?

    var minutes: Int? {
        guard let t = time else { return nil }
        let p = t.split(separator: ":")
        guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]) else { return nil }
        return h * 60 + m
    }

    func isDone(on day: String) -> Bool {
        if isRoutine { return (doneDates ?? []).contains(day) }
        return done ?? false
    }

    /// 루틴 기록이 시작된 날 (만든 날과 가장 이른 완료일 중 이른 날)
    var startDay: String? {
        var start = created
        for d in doneDates ?? [] {
            if start == nil || d < start! { start = d }
        }
        return start
    }

    /// 그 날의 목록·달력에 나타나는 항목인지 (앱의 scheduledOn과 같은 규칙)
    func scheduled(on day: String, today: String) -> Bool {
        if !isRoutine { return date == day }
        if day > today { return false }
        if day == today { return true }
        guard let s = startDay else { return false }
        return day >= s
    }
}

/// 오늘(안 했으면 어제)부터 거꾸로 이어진 연속 달성 일수
func haruStreak(_ item: WItem, now: Date) -> Int {
    let done = Set(item.doneDates ?? [])
    var cursor = HaruDate.startOfDay(now)
    if !done.contains(HaruDate.key(cursor)) { cursor = HaruDate.addDays(cursor, -1) }
    var n = 0
    while done.contains(HaruDate.key(cursor)) {
        n += 1
        cursor = HaruDate.addDays(cursor, -1)
    }
    return n
}

// ───────────────────────── PRO 상태 ─────────────────────────

enum ProState {
    case active      // 구입했거나 체험 중
    case notStarted  // 체험을 아직 시작하지 않음
    case ended       // 체험이 끝났고 구입도 안 함
}

struct ProInfo: Codable {
    var purchased: Bool
    var trialStart: Double // 밀리초, 0이면 시작 안 함
    var trialEnd: Double   // 밀리초, 0이면 시작 안 함
    var price: String?

    static let empty = ProInfo(purchased: false, trialStart: 0, trialEnd: 0, price: nil)

    var trialEndDate: Date? {
        trialEnd > 0 ? Date(timeIntervalSince1970: trialEnd / 1000) : nil
    }

    func state(at date: Date) -> ProState {
        if purchased { return .active }
        guard let end = trialEndDate else { return .notStarted }
        return date < end ? .active : .ended
    }
}

// ───────────────────────── 읽고 쓰기 ─────────────────────────

enum HaruStore {
    static func loadItems() -> [WItem] {
        guard let s = HaruShared.defaults.string(forKey: HaruShared.itemsKey),
              let data = s.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([WItem].self, from: data)) ?? []
    }

    static func loadPro() -> ProInfo {
        guard let s = HaruShared.defaults.string(forKey: HaruShared.proKey),
              let data = s.data(using: .utf8),
              let info = try? JSONDecoder().decode(ProInfo.self, from: data) else {
            return ProInfo.empty
        }
        return info
    }

    /// 위젯에서 체크했을 때: 위젯용 목록을 바로 고치고, 앱이 나중에 가져가도록 기록해 둬요.
    static func applyToggle(id: String, day: String, done: Bool) {
        let d = HaruShared.defaults

        if let s = d.string(forKey: HaruShared.itemsKey),
           let data = s.data(using: .utf8),
           var arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            for i in arr.indices {
                guard (arr[i]["id"] as? String) == id else { continue }
                let routine = (arr[i]["isRoutine"] as? Bool) ?? false
                if routine {
                    var dates = (arr[i]["doneDates"] as? [String]) ?? []
                    if done {
                        if !dates.contains(day) { dates.append(day) }
                    } else {
                        dates.removeAll { $0 == day }
                    }
                    arr[i]["doneDates"] = dates
                } else {
                    arr[i]["done"] = done
                    if done {
                        arr[i]["doneOn"] = day
                    } else {
                        arr[i]["doneOn"] = NSNull()
                    }
                }
            }
            if let out = try? JSONSerialization.data(withJSONObject: arr),
               let str = String(data: out, encoding: .utf8) {
                d.set(str, forKey: HaruShared.itemsKey)
            }
        }

        var queue: [[String: Any]] = []
        if let s = d.string(forKey: HaruShared.togglesKey),
           let data = s.data(using: .utf8),
           let a = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            queue = a
        }
        queue.append(["id": id, "day": day, "done": done])
        if let out = try? JSONSerialization.data(withJSONObject: queue),
           let str = String(data: out, encoding: .utf8) {
            d.set(str, forKey: HaruShared.togglesKey)
        }
    }
}

// ───────────────────────── 한 시점의 화면 재료 ─────────────────────────

struct Snapshot {
    var date: Date
    var today: String
    var pro: ProState
    var proInfo: ProInfo
    var items: [WItem]

    /// 모든 루틴
    var routines: [WItem] { items.filter { $0.isRoutine } }

    /// 루틴 줄: 아직 안 한 것을 먼저, 끝낸 것은 뒤로
    var routineRows: [WItem] {
        let r = routines
        return r.filter { !$0.isDone(on: today) } + r.filter { $0.isDone(on: today) }
    }

    var routineTotal: Int { routines.count }
    var routineDone: Int { routines.filter { $0.isDone(on: today) }.count }
    var routineProgress: Double {
        routineTotal == 0 ? 0 : Double(routineDone) / Double(routineTotal)
    }
    var maxStreak: Int { routines.map { haruStreak($0, now: date) }.max() ?? 0 }

    /// 오늘 시간이 정해진 투두 (시간순)
    var timed: [WItem] {
        items
            .filter { !$0.isRoutine && $0.date == today && $0.time != nil }
            .sorted { ($0.minutes ?? 0) < ($1.minutes ?? 0) }
    }

    var timedDone: Int { timed.filter { $0.isDone(on: today) }.count }

    func dueDate(_ item: WItem) -> Date? {
        guard let m = item.minutes else { return nil }
        return HaruDate.at(date, minutes: m)
    }

    /// 아직 안 끝낸, 앞으로 올 일정 중 가장 빠른 것
    var next: WItem? {
        timed.first { item in
            guard !item.isDone(on: today), let due = dueDate(item) else { return false }
            return due > date
        }
    }

    /// 시간이 지났는데 아직 안 끝낸 가장 최근 일정
    var overdue: WItem? {
        timed.last { item in
            guard !item.isDone(on: today), let due = dueDate(item) else { return false }
            return due <= date
        }
    }

    var focus: WItem? { next ?? overdue }

    /// 시간 없는 투두 (오늘 화면의 "투두" 목록과 같은 규칙)
    var untimed: [WItem] {
        items.filter { e in
            if e.isRoutine { return false }
            if e.date == today && e.time != nil { return false }
            guard let d = e.date else { return true }
            return d == today || (d < today && !(e.done ?? false))
        }
    }

    var untimedDone: Int { untimed.filter { $0.isDone(on: today) }.count }
    var untimedLeft: Int { untimed.filter { !$0.isDone(on: today) }.count }
    var untimedRows: [WItem] {
        let u = untimed
        return u.filter { !$0.isDone(on: today) } + u.filter { $0.isDone(on: today) }
    }

    /// [day]에 해야 하는 항목 수와 끝낸 수
    func progress(on day: String) -> (total: Int, done: Int) {
        var total = 0
        var done = 0
        for e in items where e.scheduled(on: day, today: today) {
            total += 1
            if e.isDone(on: day) { done += 1 }
        }
        return (total, done)
    }

    static func make(items: [WItem], pro: ProInfo, at date: Date) -> Snapshot {
        Snapshot(
            date: date,
            today: HaruDate.key(date),
            pro: pro.state(at: date),
            proInfo: pro,
            items: items
        )
    }

    /// 위젯 갤러리·미리보기용 예시
    static func sample() -> Snapshot {
        let now = Date()
        let day = HaruDate.startOfDay(now)
        let date = HaruDate.at(day, minutes: 11 * 60 + 20)
        let today = HaruDate.key(day)
        func days(_ n: Int, skipToday: Bool = false) -> [String] {
            let start = skipToday ? 1 : 0
            return (start ..< (start + n)).map { HaruDate.key(HaruDate.addDays(day, -$0)) }
        }
        let items: [WItem] = [
            WItem(id: "s1", title: "물 2L 마시기", isRoutine: true, done: false,
                  doneDates: days(12), date: nil, time: nil, created: today, doneOn: nil),
            WItem(id: "s2", title: "스트레칭 10분", isRoutine: true, done: false,
                  doneDates: days(5), date: nil, time: nil, created: today, doneOn: nil),
            WItem(id: "s3", title: "영어 단어 20개", isRoutine: true, done: false,
                  doneDates: days(3, skipToday: true), date: nil, time: nil, created: today, doneOn: nil),
            WItem(id: "s4", title: "병원 예약 전화하기", isRoutine: false, done: true,
                  doneDates: nil, date: today, time: "09:30", created: today, doneOn: today),
            WItem(id: "s5", title: "점심약속", isRoutine: false, done: false,
                  doneDates: nil, date: today, time: "14:00", created: today, doneOn: nil),
            WItem(id: "s6", title: "택배 반품 접수", isRoutine: false, done: false,
                  doneDates: nil, date: today, time: "16:30", created: today, doneOn: nil),
            WItem(id: "s7", title: "친구 생일 선물 고르기", isRoutine: false, done: false,
                  doneDates: nil, date: nil, time: nil, created: today, doneOn: nil),
            WItem(id: "s8", title: "여행 숙소 후보 3곳 비교", isRoutine: false, done: false,
                  doneDates: nil, date: nil, time: nil, created: today, doneOn: nil),
        ]
        let pro = ProInfo(purchased: true, trialStart: 0, trialEnd: 0, price: nil)
        return Snapshot.make(items: items, pro: pro, at: date)
    }
}

// ───────────────────────── 타임라인 (언제 위젯을 새로 그릴지) ─────────────────────────

struct HaruEntry: TimelineEntry {
    let date: Date
    let snap: Snapshot
}

struct HaruProvider: TimelineProvider {
    func placeholder(in context: Context) -> HaruEntry {
        let s = Snapshot.sample()
        return HaruEntry(date: s.date, snap: s)
    }

    func getSnapshot(in context: Context, completion: @escaping (HaruEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        let now = Date()
        let snap = Snapshot.make(items: HaruStore.loadItems(), pro: HaruStore.loadPro(), at: now)
        completion(HaruEntry(date: now, snap: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HaruEntry>) -> Void) {
        let now = Date()
        let items = HaruStore.loadItems()
        let pro = HaruStore.loadPro()
        let today = HaruDate.startOfDay(now)

        // 새로 그릴 시각: 지금, 오늘 일정이 시작되는 시각마다, 체험이 끝나는 시각, 자정
        var times: [Date] = [now]
        let todayKey = HaruDate.key(now)
        for item in items where !item.isRoutine && item.date == todayKey {
            if let m = item.minutes {
                let due = HaruDate.at(today, minutes: m)
                if due > now { times.append(due) }
            }
        }
        if let end = pro.trialEndDate, end > now { times.append(end) }
        let midnight = HaruDate.addDays(today, 1)
        times.append(midnight)

        let unique = Array(Set(times)).sorted().prefix(16)
        let entries = unique.map { t in
            HaruEntry(date: t, snap: Snapshot.make(items: items, pro: pro, at: t))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}
