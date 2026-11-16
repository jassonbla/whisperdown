import AppKit
import SwiftUI

/// 버튼 변형. 색/경계/상태 반응은 전부 `ControlButtonStyle`이 결정한다 —
/// 호출부는 라벨과 변형만 고르고 hover/pressed/disabled를 직접 그리지 않는다.
enum ControlVariant {
    case outline
    case solid
    case ghost
    case destructive
    case destructiveSolid
}

/// 모든 버튼의 단일 상태 소스: rest → hover → pressed, disabled(0.5), active(토글 켜짐).
/// 키보드 포커스 링은 시스템 기본을 그대로 쓴다.
struct ControlButtonStyle: ButtonStyle {
    var variant: ControlVariant = .outline
    /// 토글형 버튼의 켜짐 상태 — 변형과 무관하게 solid로 그린다.
    var isActive = false
    /// nil이면 라벨이 스스로 크기를 정한다(아이콘 버튼).
    var height: CGFloat? = AppMetric.controlHeight
    var horizontalPadding: CGFloat = Spacing.md

    func makeBody(configuration: Configuration) -> some View {
        ControlButtonBody(
            configuration: configuration,
            variant: isActive ? .solid : variant,
            height: height,
            horizontalPadding: horizontalPadding
        )
    }
}

private struct ControlButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let variant: ControlVariant
    let height: CGFloat?
    let horizontalPadding: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
    }

    var body: some View {
        configuration.label
            .font(Typography.emphasis)
            .lineLimit(1)
            .padding(.horizontal, height == nil ? 0 : horizontalPadding)
            .frame(height: height)
            .foregroundStyle(foreground)
            .background(fill, in: shape)
            .overlay {
                shape.strokeBorder(border, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(shape)
            .onHover { isHovering = $0 }
            .animation(MotionToken.quick, value: isHovering)
            .animation(MotionToken.quick, value: configuration.isPressed)
    }

    private var isHot: Bool {
        isEnabled && (isHovering || configuration.isPressed)
    }

    private var foreground: Color {
        switch variant {
        case .outline:
            return Palette.label
        case .ghost:
            return isHot ? Palette.label : Palette.secondaryLabel
        case .solid, .destructiveSolid:
            return Palette.primaryForeground
        case .destructive:
            return Palette.destructive
        }
    }

    private var fill: Color {
        let isPressed = isEnabled && configuration.isPressed
        switch variant {
        case .outline:
            return isPressed ? Palette.strongSeparator : (isHot ? Palette.bg2 : Palette.surface)
        case .ghost:
            return isPressed ? Palette.strongSeparator : (isHot ? Palette.bg2 : Color.clear)
        case .solid:
            return Palette.primary.opacity(isPressed ? 0.7 : (isHot ? 0.85 : 1))
        case .destructive:
            return isHot ? Palette.destructive.opacity(isPressed ? 0.22 : 0.14) : Palette.dangerBackground
        case .destructiveSolid:
            return Palette.destructive.opacity(isPressed ? 0.7 : (isHot ? 0.85 : 1))
        }
    }

    private var border: Color {
        switch variant {
        case .outline:
            return Palette.input
        case .destructive:
            return Palette.destructive.opacity(0.4)
        case .ghost, .solid, .destructiveSolid:
            return Color.clear
        }
    }
}

/// 아이콘 전용 버튼. `label`은 필수 — 툴팁과 VoiceOver 이름이 같은 문자열에서 나온다.
struct IconButton: View {
    let systemName: String
    let label: String
    var isActive: Bool = false
    var variant: ControlVariant = .ghost
    var size: CGFloat = AppMetric.iconButtonSize
    var iconSize: CGFloat = 13
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .medium))
                .frame(width: size, height: size)
        }
        .buttonStyle(ControlButtonStyle(variant: variant, isActive: isActive, height: nil))
        .tooltip(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

struct RecordButton: View {
    @Environment(\.appLanguage) private var language

    let isRecording: Bool
    let isProcessing: Bool
    let size: CGFloat
    let action: () -> Void

    private var label: String {
        isRecording ? L10n.t("controls.recordButton.stop", language) : L10n.t("controls.recordButton.start", language)
    }

    var body: some View {
        Button(action: action) {
            Group {
                if isRecording {
                    Rectangle()
                        .frame(width: 10, height: 10)
                        .recPulse()
                } else {
                    Circle()
                        .frame(width: 10, height: 10)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(ControlButtonStyle(variant: isRecording ? .destructiveSolid : .destructive, height: nil))
        .disabled(isProcessing)
        .tooltip(label)
        .accessibilityLabel(label)
    }
}

struct WaveformView: View {
    let level: Double
    let isRecording: Bool
    /// 녹음 중 실제 레벨 히스토리(시간순, 마지막이 최신). 비어 있으면 level 스칼라로 폴백.
    var history: [Double] = []
    var showsTrack = true

    @Environment(\.colorScheme) private var colorScheme

    private let barCount = 80

    var body: some View {
        // 녹음 파형은 실제 입력 신호라 동작 줄이기와 무관하게 갱신한다.
        // 재생에는 쓰지 않는다 — 재생 위치는 `LinearProgressBar`가 보여 준다(가짜 파형 금지).
        TimelineView(.animation(paused: !isRecording)) { timeline in
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
            ? (rgb(0x4A4A4A), rgb(0xF97070))
            : (rgb(0xC4C4C4), rgb(0xC81E28))
    }

    private func draw(_ context: GraphicsContext, size: CGSize, time: Double) {
        let midY = size.height / 2
        let spacing = size.width / CGFloat(barCount)
        let verticalInset: CGFloat = showsTrack ? 9 : 4
        let availableHeight = size.height - verticalInset * 2
        let barWidth: CGFloat = showsTrack ? 1.0 : 1.5
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
                height = min(availableHeight, clip * availableHeight * 0.9)
                color = Color.waveLine
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
    static let controlBorder = Palette.input
    static let searchBackground = Palette.surface
    static let waveBackground = Palette.muted
    static let waveTrackBorder = Palette.separator
    static let waveLine = Palette.strongSeparator
    static let rowSelectionBackground = Palette.bg2
    static let rowSelectionStroke = Palette.separator
}

/// 밑줄 탭. 탭 목록 전체가 Tab 정지점 1개이고 ←/→로 선택을 옮긴다(선택이 곧 활성화).
struct UnderlineTabs<Value: Hashable>: View {
    let items: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: Spacing.xl) {
            ForEach(items.indices, id: \.self) { index in
                UnderlineTabItem(title: items[index].title, isSelected: items[index].value == selection) {
                    selection = items[index].value
                }
            }

            Spacer(minLength: 0)
        }
        .focusable(true, interactions: .edit)
        .onMoveCommand { direction in
            guard let current = items.firstIndex(where: { $0.value == selection }) else {
                return
            }

            switch direction {
            case .left where current > 0:
                selection = items[current - 1].value
            case .right where current < items.count - 1:
                selection = items[current + 1].value
            default:
                break
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
    }
}

private struct UnderlineTabItem: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Text(title)
            .font(Typography.emphasis)
            .foregroundStyle(isSelected || isHovering ? Palette.label : Palette.secondaryLabel)
            .frame(height: 36)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isSelected ? Palette.label : Color.clear)
                    .frame(height: 2)
            }
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .onTapGesture(perform: action)
            .animation(MotionToken.quick, value: isSelected)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, action)
    }
}

/// 직각 세그먼트 컨트롤 — 선택된 조각은 solid, 나머지는 outline. 경계는 1px 겹친다.
struct SegmentedControl<Value: Hashable>: View {
    let items: [(value: Value, title: String)]
    @Binding var selection: Value
    var height: CGFloat = AppMetric.controlHeight

    var body: some View {
        HStack(spacing: -1) {
            ForEach(items.indices, id: \.self) { index in
                let isSelected = items[index].value == selection

                Button(items[index].title) {
                    selection = items[index].value
                }
                .buttonStyle(ControlButtonStyle(variant: isSelected ? .solid : .outline, height: height, horizontalPadding: Spacing.lg))
                .zIndex(isSelected ? 1 : 0)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// 직각 라디오 표시. 선택은 안쪽 채움(색이 아닌 형태)으로 구분한다.
struct RadioMark: View {
    let isOn: Bool
    var isEnabled: Bool = true

    var body: some View {
        Rectangle()
            .fill(Palette.surface)
            .frame(width: 14, height: 14)
            .overlay {
                Rectangle().strokeBorder(isOn ? Palette.label : Palette.input, lineWidth: 1)
            }
            .overlay {
                if isOn {
                    Rectangle()
                        .fill(Palette.label)
                        .frame(width: 6, height: 6)
                }
            }
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
    }
}

/// 직각 선형 진행 막대 (0...1).
struct LinearProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Palette.bg2)
                Rectangle()
                    .fill(Palette.label)
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityValue("\(Int((min(max(value, 0), 1) * 100).rounded()))%")
    }
}

/// 누르거나 끌어 위치를 옮기는 진행 막대(0...1). 보이는 막대는 4pt지만 히트 영역은 24pt다.
/// hover·드래그 중에는 현재 위치에 손잡이가 나타난다.
struct ScrubBar: View {
    let value: Double
    let label: String
    let valueText: String
    let onScrub: (Double) -> Void
    var onDecrement: () -> Void = {}
    var onIncrement: () -> Void = {}

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    /// 드래그 중에는 모델 갱신을 기다리지 않고 손 위치를 바로 그린다.
    @State private var dragValue: Double?

    private var shownValue: Double {
        min(max(dragValue ?? value, 0), 1)
    }

    private var showsThumb: Bool {
        isEnabled && (isHovering || dragValue != nil)
    }

    var body: some View {
        GeometryReader { proxy in
            let filled = proxy.size.width * shownValue

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Palette.bg2)
                    .frame(height: 4)

                Rectangle()
                    .fill(Palette.label)
                    .frame(width: filled, height: 4)

                Rectangle()
                    .fill(Palette.label)
                    .frame(width: 2, height: 14)
                    .offset(x: min(max(filled - 1, 0), max(proxy.size.width - 2, 0)))
                    .opacity(showsThumb ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 24)
        .contentShape(Rectangle())
        .overlay {
            ScrubMouseTracker(
                onChange: { fraction in
                    dragValue = fraction
                    onScrub(fraction)
                },
                onEnd: { dragValue = nil }
            )
            .allowsHitTesting(isEnabled)
        }
        .onHover { isHovering = $0 }
        .animation(MotionToken.quick, value: showsThumb)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                onIncrement()
            case .decrement:
                onDecrement()
            @unknown default:
                break
            }
        }
    }
}

/// 막대 위의 마우스 누름·끌기를 AppKit에서 직접 받는다. 창이 `isMovableByWindowBackground`라
/// SwiftUI 드래그 제스처는 창 이동과 겹치므로, 이 뷰가 창 이동을 막고 위치 비율만 알린다.
private struct ScrubMouseTracker: NSViewRepresentable {
    let onChange: (Double) -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.onChange = onChange
        view.onEnd = onEnd
        return view
    }

    func updateNSView(_ view: TrackerView, context: Context) {
        view.onChange = onChange
        view.onEnd = onEnd
    }

    final class TrackerView: NSView {
        var onChange: ((Double) -> Void)?
        var onEnd: (() -> Void)?

        override var mouseDownCanMoveWindow: Bool { false }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            report(event)
        }

        override func mouseDragged(with event: NSEvent) {
            report(event)
        }

        override func mouseUp(with event: NSEvent) {
            onEnd?()
        }

        private func report(_ event: NSEvent) {
            guard bounds.width > 0 else {
                return
            }

            let x = convert(event.locationInWindow, from: nil).x
            onChange?(min(max(Double(x / bounds.width), 0), 1))
        }
    }
}

// MARK: - Tooltip

/// 앱이 직접 그리는 툴팁. 시스템 `.help`는 타이틀 바 영역(hiddenTitleBar + fullSizeContentView)에서
/// 타이틀 바 뷰에 가려 뜨지 않으므로, 컨트롤 설명은 이 수정자를 쓴다.
/// 조상 어딘가에 `tooltipHost()`가 있어야 그려진다(창·시트마다 하나).
struct TooltipItem {
    let text: String
    let anchor: Anchor<CGRect>
}

struct TooltipPreferenceKey: PreferenceKey {
    static var defaultValue: TooltipItem? { nil }

    static func reduce(value: inout TooltipItem?, nextValue: () -> TooltipItem?) {
        value = nextValue() ?? value
    }
}

extension View {
    func tooltip(_ text: String) -> some View {
        modifier(TooltipModifier(text: text))
    }

    func tooltipHost() -> some View {
        overlayPreferenceValue(TooltipPreferenceKey.self) { item in
            TooltipLayer(item: item)
        }
    }
}

private struct TooltipModifier: ViewModifier {
    let text: String

    @State private var isShown = false
    @State private var showTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { isHovering in
                showTask?.cancel()

                if isHovering {
                    showTask = Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        if !Task.isCancelled {
                            isShown = true
                        }
                    }
                } else {
                    isShown = false
                }
            }
            // 누르면 설명은 물러난다.
            .simultaneousGesture(TapGesture().onEnded {
                showTask?.cancel()
                isShown = false
            })
            .anchorPreference(key: TooltipPreferenceKey.self, value: .bounds) { anchor in
                isShown && !text.isEmpty ? TooltipItem(text: text, anchor: anchor) : nil
            }
            .onDisappear {
                showTask?.cancel()
                isShown = false
            }
    }
}

private struct TooltipLayer: View {
    let item: TooltipItem?

    private let gap: CGFloat = 6
    private let edgeInset: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.clear

                if let item {
                    let target = proxy[item.anchor]

                    Text(item.text)
                        .font(Typography.caption.weight(.medium))
                        .foregroundStyle(Palette.primaryForeground)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(Palette.primary)
                        // 대상 아래 가운데에 두되 호스트 밖으로 나가지 않게 한다. 아래가 모자라면 위로 올린다.
                        .alignmentGuide(.leading) { dimensions in
                            let ideal = target.midX - dimensions.width / 2
                            let maxLeading = max(edgeInset, proxy.size.width - dimensions.width - edgeInset)
                            return -min(max(ideal, edgeInset), maxLeading)
                        }
                        .alignmentGuide(.top) { dimensions in
                            let below = target.maxY + gap
                            let fitsBelow = below + dimensions.height <= proxy.size.height - edgeInset
                            return -(fitsBelow ? below : target.minY - gap - dimensions.height)
                        }
                        .transition(.opacity)
                }
            }
            .animation(MotionToken.quick, value: item?.text)
        }
        .allowsHitTesting(false)
        // 이름은 컨트롤의 accessibilityLabel이 이미 전달한다.
        .accessibilityHidden(true)
    }
}
