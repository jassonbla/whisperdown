import SwiftUI

enum AppRadius {
    static let panel: CGFloat = Radius.container
    static let window: CGFloat = 14
    static let row: CGFloat = Radius.base
    static let control: CGFloat = Radius.base
    static let tray: CGFloat = Radius.container
}

enum AppLayout {
    static let windowInset: CGFloat = AppMetric.windowInset
    static let panelGap: CGFloat = AppMetric.panelGap
    static let sidebarWidth: CGFloat = AppMetric.sidebarWidth
    static let titleBarHeight: CGFloat = AppMetric.titleBarHeight
    static let sidebarContentTopInset: CGFloat = AppMetric.sidebarContentTopInset
    static let trafficLightTop: CGFloat = AppMetric.trafficLightTop
    static let trafficLightLeading: CGFloat = AppMetric.trafficLightLeading
    static let sidebarChromeReserveWidth: CGFloat = AppMetric.sidebarChromeReserveWidth
    static let sidebarChromeReserveHeight: CGFloat = AppMetric.sidebarChromeReserveHeight
    static let detailContentMaxWidth: CGFloat = AppMetric.detailContentMaxWidth
    static let detailHorizontalPadding: CGFloat = AppMetric.detailHorizontalPadding
}

extension View {
    func appWindowShell() -> some View {
        modifier(WindowShellModifier())
    }

    /// 캡슐 서피스. 라이트 = 불투명 서피스 + 헤어라인, 다크 = 미묘한 material glass + 헤어라인.
    func glassCapsule() -> some View {
        modifier(GlassCapsuleModifier())
    }

    /// 목업의 `@keyframes recpulse` 대응: opacity 1↔0.45, scale 1↔0.82 (1.4s 주기)
    func recPulse() -> some View {
        modifier(RecPulseModifier())
    }
}

private struct WindowShellModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.window, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.window, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark ? Color.white.opacity(0.08) : Color.panelStroke,
                        lineWidth: 1
                    )
            }
    }
}

private struct GlassCapsuleModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                if colorScheme == .dark {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(Color.appSurface.opacity(0.4))
                } else {
                    Capsule().fill(Color.appSurface)
                }
            }
            .overlay {
                Capsule()
                    .strokeBorder(Color.hairline, lineWidth: 1)
            }
    }
}

private struct RecPulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.45 : 1)
            .scaleEffect(isPulsing ? 0.82 : 1)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
