import SwiftUI

struct LiveRecordingWidget: View {
    let level: Double
    let elapsed: TimeInterval
    let onStop: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            RecordingPulseDot()

            Text(AppFormatters.duration(elapsed))
                .font(Typography.mono)
                .monospacedDigit()
                .foregroundStyle(Palette.label)
                .frame(width: 42, alignment: .leading)

            Spacer(minLength: 0)

            ZStack {
                PillWaveform(level: level)
                    .frame(width: 17, height: 16)
                    .opacity(isHovering ? 0 : 1)

                Button(action: onStop) {
                    ZStack {
                        Circle()
                            .fill(Palette.label)

                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Palette.background)
                            .frame(width: 8, height: 8)
                    }
                    .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
                .help("녹음 정지")
            }
            .frame(width: 22, height: 22)
            .animation(.easeOut(duration: 0.16), value: isHovering)
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .frame(width: 116, height: 38)
        .background(Palette.background, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.panelStroke, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 8)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("녹음 중")
        .accessibilityValue(AppFormatters.duration(elapsed))
    }
}

private struct RecordingPulseDot: View {
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Palette.destructive)
                .frame(width: 9, height: 9)
                .opacity(isPulsing ? 0.45 : 1)
                .scaleEffect(isPulsing ? 0.82 : 1, anchor: .center)
        }
        .frame(width: 9, height: 9, alignment: .center)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

private struct PillWaveform: View {
    /// 실제 마이크 레벨(0...1). FloatingRecorderPanelPresenter가 20Hz로 주입한다.
    let level: Double

    /// 막대별 감도 오프셋 — 같은 레벨에도 막대들이 조금씩 다르게 반응.
    private static let phaseOffsets: [Double] = [0.55, 0.9, 0.7, 0.45]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(Palette.tertiaryLabel)
                    .frame(width: 2, height: 16)
                    .scaleEffect(y: max(0.2, 0.2 + level * Self.phaseOffsets[index]))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
    }
}
