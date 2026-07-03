import AppKit
import SwiftUI

struct WindowChromeConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(window: view.window, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window, coordinator: context.coordinator)
        }
    }

    private func configure(window: NSWindow?, coordinator: Coordinator) {
        guard let window else {
            return
        }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        alignTrafficLights(in: window)

        // 최초 1회만 배치를 교정한다. 이후엔 사용자가 옮긴 위치를 존중(드래그를 되돌리지 않음).
        if !coordinator.didPositionWindow {
            coordinator.didPositionWindow = true
            placeOnPrimaryScreenIfNeeded(window)
        }
    }

    private func alignTrafficLights(in window: NSWindow) {
        let buttons: [NSButton?] = [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton)
        ]

        for button in buttons.compactMap({ $0 }) {
            guard let superview = button.superview else {
                continue
            }

            let titlebarCenterY = AppLayout.titleBarHeight / 2
            let targetY: CGFloat
            if superview.isFlipped {
                targetY = titlebarCenterY - button.bounds.height / 2
            } else {
                targetY = superview.bounds.maxY - titlebarCenterY - button.bounds.height / 2
            }

            button.setFrameOrigin(
                NSPoint(
                    x: button.frame.origin.x,
                    y: round(targetY)
                )
            )
        }
    }

    /// 상태 복원/캐스케이드로 창이 주 화면(메뉴바가 있는 화면) 밖이나 보조 디스플레이에
    /// 열려 "안 보이는" 문제를 막는다. 주 화면에 절반 이상 걸쳐 있지 않으면 중앙으로 옮긴다.
    private func placeOnPrimaryScreenIfNeeded(_ window: NSWindow) {
        guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main else {
            return
        }

        let visible = primary.visibleFrame
        let frame = window.frame
        let overlap = visible.intersection(frame)
        let mostlyOnPrimary = overlap.width >= frame.width * 0.5
            && overlap.height >= frame.height * 0.5

        guard !mostlyOnPrimary else {
            return
        }

        let origin = NSPoint(
            x: visible.midX - frame.width / 2,
            y: visible.midY - frame.height / 2
        )
        window.setFrameOrigin(origin)
    }

    final class Coordinator {
        var didPositionWindow = false
    }
}
