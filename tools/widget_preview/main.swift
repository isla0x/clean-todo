import SwiftUI
import UIKit
import WidgetKit

// 위젯 화면을 그림 파일로 뽑아보는 도구예요. (맥 빌드 검사에서 자동으로 돌아가요)
// 실제 위젯과 똑같은 화면 코드를 써서 홈/잠금화면 위젯을 PNG로 저장해요.

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/widget_previews"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func isAccessory(_ f: WidgetFamily) -> Bool {
    switch f {
    case .accessoryCircular, .accessoryRectangular, .accessoryInline: return true
    default: return false
    }
}

func entry(_ s: Snapshot) -> HaruEntry { HaruEntry(date: s.date, snap: s) }

// ── 상황별 재료 ──
let sample = Snapshot.sample()

var allDone: Snapshot = {
    var s = Snapshot.sample()
    let today = s.today
    s.items = s.items.map { item in
        var i = item
        if i.isRoutine {
            i.doneDates = (i.doneDates ?? []) + [today]
        } else {
            i.done = true
        }
        return i
    }
    return s
}()

let empty = Snapshot.make(
    items: [],
    pro: ProInfo(purchased: true, trialStart: 0, trialEnd: 0, price: nil),
    at: sample.date
)

var ended: Snapshot = {
    var s = Snapshot.sample()
    s.pro = .ended
    return s
}()

var notStarted: Snapshot = {
    var s = Snapshot.sample()
    s.pro = .notStarted
    return s
}()

// ── 한 칸 ──
struct Tile<V: View>: View {
    let title: String
    let family: WidgetFamily
    let size: CGSize
    let content: V

    var body: some View {
        let acc = isAccessory(family)
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(acc ? Color.white.opacity(0.7) : Color.gray)
            content
                .padding(acc ? 0 : 16)
                .frame(width: size.width, height: size.height)
                .background(acc ? Color.white.opacity(0.16) : Color.haruCard)
                .clipShape(RoundedRectangle(cornerRadius: acc ? 14 : 22, style: .continuous))
        }
    }
}

let small = CGSize(width: 158, height: 158)
let medium = CGSize(width: 338, height: 158)
let large = CGSize(width: 338, height: 354)
let rect = CGSize(width: 160, height: 72)
let circle = CGSize(width: 76, height: 76)
let inline = CGSize(width: 257, height: 26)

@MainActor
func save<V: View>(_ name: String, _ v: V) {
    let r = ImageRenderer(content: v)
    r.scale = 2
    if let data = r.uiImage?.pngData() {
        try? data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
        print("saved \(name)")
    } else {
        print("render failed \(name)")
    }
}

MainActor.assumeIsolated {
    let home = VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .top, spacing: 14) {
            Tile(title: "루틴 작게", family: .systemSmall, size: small, content: RoutineWidgetView(entry: entry(sample), forced: .systemSmall))
            Tile(title: "일정 작게", family: .systemSmall, size: small, content: ScheduleWidgetView(entry: entry(sample), forced: .systemSmall))
            Tile(title: "할 일 작게", family: .systemSmall, size: small, content: TodoWidgetView(entry: entry(sample), forced: .systemSmall))
        }
        HStack(alignment: .top, spacing: 14) {
            Tile(title: "일정 끝", family: .systemSmall, size: small, content: ScheduleWidgetView(entry: entry(allDone), forced: .systemSmall))
            Tile(title: "비어 있음(루틴)", family: .systemSmall, size: small, content: RoutineWidgetView(entry: entry(empty), forced: .systemSmall))
            Tile(title: "잠김(체험 끝)", family: .systemSmall, size: small, content: RoutineWidgetView(entry: entry(ended), forced: .systemSmall))
        }
        HStack(alignment: .top, spacing: 14) {
            Tile(title: "루틴 중간", family: .systemMedium, size: medium, content: RoutineWidgetView(entry: entry(sample), forced: .systemMedium))
            Tile(title: "일정 중간", family: .systemMedium, size: medium, content: ScheduleWidgetView(entry: entry(sample), forced: .systemMedium))
        }
        HStack(alignment: .top, spacing: 14) {
            Tile(title: "잠김 중간", family: .systemMedium, size: medium, content: ScheduleWidgetView(entry: entry(ended), forced: .systemMedium))
            Tile(title: "체험 전 중간", family: .systemMedium, size: medium, content: ScheduleWidgetView(entry: entry(notStarted), forced: .systemMedium))
        }
        HStack(alignment: .top, spacing: 14) {
            Tile(title: "일정 크게", family: .systemLarge, size: large, content: ScheduleWidgetView(entry: entry(sample), forced: .systemLarge))
            Tile(title: "캘린더 크게", family: .systemLarge, size: large, content: CalendarWidgetView(entry: entry(sample), forced: .systemLarge))
        }
    }
    .padding(20)
    .frame(width: 20 + 338 * 2 + 14 + 20, alignment: .topLeading)
    .background(Color(red: 0.91, green: 0.93, blue: 0.96))
    .environment(\.colorScheme, .light)

    save("home", home)

    let lock = VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .top, spacing: 14) {
            Tile(title: "직사각형 · 일정", family: .accessoryRectangular, size: rect, content: ScheduleWidgetView(entry: entry(sample), forced: .accessoryRectangular))
            Tile(title: "직사각형 · 루틴", family: .accessoryRectangular, size: rect, content: RoutineWidgetView(entry: entry(sample), forced: .accessoryRectangular))
        }
        HStack(alignment: .top, spacing: 14) {
            Tile(title: "원형 · 루틴", family: .accessoryCircular, size: circle, content: RoutineWidgetView(entry: entry(sample), forced: .accessoryCircular))
            Tile(title: "원형 · 연속", family: .accessoryCircular, size: circle, content: StreakWidgetView(entry: entry(sample), forced: .accessoryCircular))
            Tile(title: "원형 · 잠김", family: .accessoryCircular, size: circle, content: StreakWidgetView(entry: entry(ended), forced: .accessoryCircular))
        }
        HStack(alignment: .top, spacing: 14) {
            Tile(title: "한 줄 · 일정", family: .accessoryInline, size: inline, content: ScheduleWidgetView(entry: entry(sample), forced: .accessoryInline))
        }
        HStack(alignment: .top, spacing: 14) {
            Tile(title: "한 줄 · 잠김", family: .accessoryInline, size: inline, content: ScheduleWidgetView(entry: entry(ended), forced: .accessoryInline))
            Tile(title: "직사각형 · 잠김", family: .accessoryRectangular, size: rect, content: ScheduleWidgetView(entry: entry(ended), forced: .accessoryRectangular))
        }
    }
    .padding(20)
    .frame(width: 20 + 160 * 2 + 14 + 20 + 140, alignment: .topLeading)
    .background(
        LinearGradient(
            colors: [Color(red: 0.16, green: 0.29, blue: 0.49), Color(red: 0.05, green: 0.10, blue: 0.18)],
            startPoint: .top,
            endPoint: .bottom
        )
    )
    .environment(\.colorScheme, .dark)

    save("lock", lock)
}
