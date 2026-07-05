import AppKit
import SwiftUI

/// 공통 버튼 인터랙션: pressed 시 살짝 축소. hover 배경은 각 컨트롤이 담당.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(MotionToken.quick, value: configuration.isPressed)
    }
}

struct IconButton: View {
    let systemName: String
    var isActive: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(Typography.emphasis)
                .foregroundStyle(isActive ? Palette.label : Palette.secondaryLabel)
                .frame(width: AppMetric.iconButtonSize, height: AppMetric.iconButtonSize)
                .background(
                    isActive || isHovering ? Color.controlSurface.opacity(0.86) : Color.clear,
                    in: Circle()
                )
                .animation(MotionToken.quick, value: isHovering)
        }
        .buttonStyle(QuietButtonStyle())
        .contentShape(Circle())
        .onHover { isHovering = $0 }
    }
}

struct RecordButton: View {
    @Environment(\.appLanguage) private var language

    let isRecording: Bool
    let isProcessing: Bool
    let size: CGFloat
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isRecording ? Palette.destructive : Palette.dangerBackground)
                    .frame(width: size, height: size)

                if isRecording {
                    Circle()
                        .fill(Color.appSurface)
                        .frame(width: 12, height: 12)
                        .recPulse()
                } else {
                    Circle()
                        .fill(Palette.destructive)
                        .frame(width: 12, height: 12)
                }
            }
            .scaleEffect(isHovering ? 1.025 : 1)
            .animation(MotionToken.quick, value: isHovering)
        }
        .buttonStyle(QuietButtonStyle())
        .disabled(isProcessing)
        .help(isRecording ? L10n.t("controls.recordButton.stop", language) : L10n.t("controls.recordButton.start", language))
        .onHover { isHovering = $0 }
    }
}

struct SearchField: View {
    @Environment(\.appLanguage) private var language
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(Typography.emphasis)
                .foregroundStyle(Palette.tertiaryLabel)

            TextField(L10n.t("controls.search.placeholder", language), text: $text)
                .textFieldStyle(.plain)
                .font(Typography.emphasis)
                .foregroundStyle(Palette.label)
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: AppMetric.searchHeight)
        .background(Color.searchBackground, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        }
    }
}

struct WaveformView: View {
    let level: Double
    let isRecording: Bool
    var isPlaying: Bool = false
    var progress: Double = 0
    /// 녹음 중 실제 레벨 히스토리(시간순, 마지막이 최신). 비어 있으면 level 스칼라로 폴백.
    var history: [Double] = []
    var showsTrack = true

    @Environment(\.colorScheme) private var colorScheme

    private let barCount = 80

    var body: some View {
        TimelineView(.animation(paused: !(isRecording || isPlaying))) { timeline in
            Canvas { context, size in
                draw(context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    /// 녹음 그라데이션 끝점(dim → danger). 스킴별 고정 sRGB — Canvas 내 동적 색 해석 회피.
    private var gradientEndpoints: (dim: (CGFloat, CGFloat, CGFloat), danger: (CGFloat, CGFloat, CGFloat)) {
        func rgb(_ hex: UInt32) -> (CGFloat, CGFloat, CGFloat) {
            (
                CGFloat((hex >> 16) & 0xff) / 255,
                CGFloat((hex >> 8) & 0xff) / 255,
                CGFloat(hex & 0xff) / 255
            )
        }

        return colorScheme == .dark
            ? (rgb(0x6B6863), rgb(0xE06C5F))
            : (rgb(0xA29E96), rgb(0xD64545))
    }

    private func draw(_ context: GraphicsContext, size: CGSize, time: Double) {
        let midY = size.height / 2
        let spacing = size.width / CGFloat(barCount)
        let verticalInset: CGFloat = showsTrack ? 9 : 4
        let availableHeight = size.height - verticalInset * 2
        let barWidth: CGFloat = showsTrack ? 1.0 : 1.5
        // 재생 중일 때만 헤드 노출(정지/유휴 시 전체 회색 — 목업 idle 상태)
        let head = isPlaying ? progress : -1

        if showsTrack {
            let background = Path(
                roundedRect: CGRect(x: 0, y: 6, width: size.width, height: size.height - 12),
                cornerRadius: Radius.base
            )
            context.fill(background, with: .color(Color.waveBackground))
            context.stroke(background, with: .color(Color.waveTrackBorder), lineWidth: 0.5)
        }

        let (dim, danger) = gradientEndpoints

        for index in 0..<barCount {
            let x = CGFloat(index) * spacing + spacing / 2
            let seed = CGFloat(Double((index * 37) % 97) / 97)
            let clip = 0.22 + abs(sin(CGFloat(index) * 0.4)) * 0.55 + seed * 0.18
            let barPos = Double(index) / Double(barCount)

            let height: CGFloat
            let color: Color

            if isRecording {
                // 실제 오디오 히스토리: index가 시간축(우측 최신) → 소리가 좌로 흘러간다.
                let raw: Double
                if history.count == barCount {
                    raw = history[index]
                } else if !history.isEmpty {
                    raw = history[min(history.count - 1, Int(barPos * Double(history.count)))]
                } else {
                    raw = max(0.04, min(1, level))
                }

                // 결정적 지터(목업의 random()*0.35 대응) — 소리가 있을 때만 가미.
                let jitter = Double((index * 31 + Int(time * 20)) % 17) / 17 * 0.10
                let amp = min(1, 0.06 + raw * 0.85 + jitter * raw)
                height = max(2, CGFloat(amp) * availableHeight * 0.9)

                let t = CGFloat(barPos)
                color = Color(
                    red: lerp(dim.0, danger.0, t),
                    green: lerp(dim.1, danger.1, t),
                    blue: lerp(dim.2, danger.2, t)
                )
            } else {
                var h = clip * availableHeight * 0.9
                if isPlaying && abs(barPos - head) < 0.04 {
                    let wob = sin(time * 12 + Double(index)) * 0.12
                    h = max(0.06, clip + CGFloat(wob)) * availableHeight * 0.9
                }
                height = min(availableHeight, h)
                color = barPos <= head ? Palette.label : Color.waveLine
            }

            let path = Path(
                roundedRect: CGRect(
                    x: x - barWidth / 2,
                    y: midY - height / 2,
                    width: barWidth,
                    height: height
                ),
                cornerRadius: barWidth / 2
            )
            context.fill(path, with: .color(color))
        }
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }
}

extension Color {
    static let appCanvas = Palette.background
    static let appCanvasSecondary = Palette.secondaryBackground
    static let appSurface = Palette.surface
    static let appMuted = Palette.muted
    static let appBackground = Palette.background
    static let sidebarBackground = Palette.secondaryBackground
    static let panelStroke = Palette.strongSeparator
    static let hairline = Palette.separator
    static let controlSurface = Palette.secondaryBackground
    static let searchBackground = Palette.background
    static let waveBackground = Palette.muted
    static let waveTrackBorder = Palette.separator
    static let waveLine = Palette.strongSeparator
    static let rowSelectionBackground = Palette.bg2
    static let rowSelectionStroke = Palette.separator
}
