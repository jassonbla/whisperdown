import SwiftUI

struct LiveRecordingWidget: View {
    let level: Double
    let elapsed: TimeInterval
    let onStop: () -> Void
    var language: AppLanguage = .en

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Palette.destructive)
                .frame(width: 9, height: 9)
                .recPulse()

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
                    Rectangle()
                        .frame(width: 8, height: 8)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(ControlButtonStyle(variant: .solid, height: nil))
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
                .help(L10n.t("controls.recordButton.stop", language))
                .accessibilityLabel(L10n.t("controls.recordButton.stop", language))
            }
            .frame(width: 22, height: 22)
            .animation(.easeOut(duration: 0.16), value: isHovering)
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .frame(width: 116, height: 38)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous)
                .strokeBorder(Color.controlBorder, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 8)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.t("sidebar.bottomStatus.recording", language))
        .accessibilityValue(AppFormatters.duration(elapsed))
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
                Rectangle()
                    .fill(Palette.tertiaryLabel)
                    .frame(width: 2, height: 16)
                    .scaleEffect(y: max(0.2, 0.2 + level * Self.phaseOffsets[index]))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
    }
}
