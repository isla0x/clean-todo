import SwiftUI
import WidgetKit

// ───────────────────────── 색 ─────────────────────────

private func dynamicColor(_ light: UInt32, _ dark: UInt32) -> Color {
    Color(UIColor { trait in
        let v = trait.userInterfaceStyle == .dark ? dark : light
        return UIColor(
            red: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    })
}

extension Color {
    /// 앱 포인트 컬러 (#55A0FA)
    static let haruAccent = Color(red: 0x55 / 255, green: 0xA0 / 255, blue: 0xFA / 255)
    /// 연한 파랑 배경, 진한 파랑 글자 (다크 모드 색도 따로)
    static let haruSoft = dynamicColor(0xE3EEFD, 0x1B2B45)
    static let haruDeep = dynamicColor(0x1F63C4, 0x8CBBFA)
    static let haruCard = dynamicColor(0xFFFFFF, 0x1C1C1E)
    static let haruMuted = dynamicColor(0x6C6C70, 0x9A9AA0)
    static let haruEmpty = dynamicColor(0xC7C7CC, 0x5A5A5E)
    static let haruLine = dynamicColor(0xE5E5EA, 0x38383A)
    static let haruPill = dynamicColor(0xF0F0F3, 0x2C2C2E)
    static let haruRed = dynamicColor(0xD70015, 0xFF6961)
    static let haruFlame = Color(red: 1.0, green: 0.55, blue: 0.1)
}

// ───────────────────────── 위젯 틀 ─────────────────────────

/// 위젯 종류(홈 / 잠금화면)에 맞는 배경을 깔고, PRO가 잠겨 있으면 누를 때 PRO 화면이 열리게 해요.
struct WidgetShell<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    let pro: ProState
    let content: Content

    init(pro: ProState, @ViewBuilder content: () -> Content) {
        self.pro = pro
        self.content = content()
    }

    private var isAccessory: Bool {
        switch family {
        case .accessoryRectangular, .accessoryCircular, .accessoryInline:
            return true
        default:
            return false
        }
    }

    var body: some View {
        framed.widgetURL(pro == .active ? nil : URL(string: "haruring://pro"))
    }

    @ViewBuilder
    private var framed: some View {
        if isAccessory {
            if #available(iOS 17.0, *) {
                content.containerBackground(for: .widget) { Color.clear }
            } else {
                content
            }
        } else {
            if #available(iOS 17.0, *) {
                content.containerBackground(for: .widget) { Color.haruCard }
            } else {
                content
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.haruCard)
            }
        }
    }
}

// ───────────────────────── 작은 부품 ─────────────────────────

struct CheckDot: View {
    let done: Bool
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            if done {
                Circle().fill(Color.haruAccent)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Circle().strokeBorder(Color.haruEmpty, lineWidth: 1.6)
            }
        }
        .frame(width: size, height: size)
    }
}

/// iOS 17 이상에서는 눌러서 바로 완료 표시, 그보다 낮으면 그냥 그림만 보여요.
struct ToggleButton<Label: View>: View {
    let item: WItem
    let day: String
    let label: Label

    init(item: WItem, day: String, @ViewBuilder label: () -> Label) {
        self.item = item
        self.day = day
        self.label = label()
    }

    var body: some View {
        if #available(iOS 17.0, *) {
            Button(intent: ToggleItemIntent(itemId: item.id, day: day, done: !item.isDone(on: day))) {
                label
            }
            .buttonStyle(.plain)
        } else {
            label
        }
    }
}

struct Pill: View {
    let text: String
    var tinted: Bool = true

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(tinted ? Color.haruDeep : Color.haruMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(tinted ? Color.haruSoft : Color.haruPill))
    }
}

struct Ring: View {
    let progress: Double
    var lineWidth: CGFloat = 9
    var track: Color = Color.haruSoft
    var tint: Color = Color.haruAccent

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            if progress > 0 {
                Circle()
                    .trim(from: 0, to: CGFloat(min(progress, 1)))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

/// "2시간 40분 후 시작" / "15분 지남" (시간은 위젯이 알아서 계속 바꿔 줘요)
struct RelativeTail: View {
    let due: Date
    let now: Date

    var body: some View {
        HStack(spacing: 3) {
            Text(Self.span(from: now, to: due))
            Text(due > now ? "후 시작" : "지남")
        }
        .lineLimit(1)
    }

    /// 초 단위 없이 분까지만: "2시간 40분" / "15분" / "1분 미만"
    static func span(from now: Date, to due: Date) -> String {
        let secs = abs(due.timeIntervalSince(now))
        let mins = Int(secs / 60)
        if mins < 1 { return "1분 미만" }
        let h = mins / 60, m = mins % 60
        if h == 0 { return "\(m)분" }
        if m == 0 { return "\(h)시간" }
        return "\(h)시간 \(m)분"
    }
}

struct StreakLabel: View {
    let count: Int

    var body: some View {
        if count > 0 {
            HStack(spacing: 3) {
                if count >= 7 {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color.haruFlame)
                }
                Text("\(count)일 연속")
                    .font(.system(size: 12))
                    .foregroundColor(Color.haruMuted)
            }
        }
    }
}

struct CheckBadge: View {
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            Circle().fill(Color.haruAccent)
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

/// 타임라인 동그라미 (끝남 / 다음 / 나중)
enum MarkerState { case done, next, later }

struct Marker: View {
    let state: MarkerState

    var body: some View {
        ZStack {
            switch state {
            case .done:
                Circle().fill(Color.haruAccent)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
            case .next:
                Circle().fill(Color.haruCard)
                Circle().strokeBorder(Color.haruAccent, lineWidth: 2.2)
            case .later:
                Circle().fill(Color.haruCard)
                Circle().strokeBorder(Color.haruEmpty, lineWidth: 1.6)
            }
        }
        .frame(width: 18, height: 18)
    }
}

// ───────────────────────── 잠긴 위젯 ─────────────────────────

struct LockBadge: View {
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().fill(Color.haruSoft)
            Image(systemName: "lock.fill")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundColor(Color.haruAccent)
        }
        .frame(width: size, height: size)
    }
}

/// 체험이 끝났거나 아직 시작 전일 때 위젯 대신 보여주는 화면
struct LockedView: View {
    let family: WidgetFamily
    let state: ProState
    let price: String

    private var ended: Bool { state == .ended }

    var body: some View {
        switch family {
        case .systemSmall:
            VStack(spacing: 8) {
                LockBadge(size: 42)
                VStack(spacing: 2) {
                    Text(ended ? "PRO에서 열기" : "3일 무료 체험")
                        .font(.system(size: 15, weight: .bold))
                    Text(ended ? "체험이 끝났어요" : "눌러서 시작하기")
                        .font(.system(size: 12))
                        .foregroundColor(Color.haruMuted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .systemMedium, .systemLarge:
            HStack(spacing: 16) {
                LockBadge(size: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ended ? "3일 체험이 끝났어요" : "3일 무료로 써보세요")
                        .font(.system(size: 18, weight: .bold))
                    Text(ended ? "하루링 PRO로 위젯을 계속 쓸 수 있어요." : "하루링 PRO 체험을 시작하면 위젯이 열려요.")
                        .font(.system(size: 13))
                        .foregroundColor(Color.haruMuted)
                    Text("\(price) · 한 번만 결제")
                        .font(.system(size: 13))
                        .foregroundColor(Color.haruMuted)
                    Pill(text: ended ? "PRO 보기" : "체험 시작")
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 15))
                VStack(alignment: .leading, spacing: 1) {
                    Text("하루링 PRO").font(.system(size: 14, weight: .semibold))
                    Text("눌러서 열기").font(.system(size: 12))
                }
                Spacer(minLength: 0)
            }

        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "lock.fill").font(.system(size: 18))
            }

        case .accessoryInline:
            Label("PRO에서 열 수 있어요", systemImage: "lock.fill")

        default:
            LockBadge(size: 42)
        }
    }
}
