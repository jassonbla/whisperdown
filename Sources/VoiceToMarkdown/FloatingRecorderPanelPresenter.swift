import AppKit
import QuartzCore
import SwiftUI

struct FloatingRecorderPanelPresenter: NSViewRepresentable {
    let isPresented: Bool
    let level: Double
    let elapsed: TimeInterval
    let onStop: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.anchorView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(
            isPresented: isPresented,
            level: level,
            elapsed: elapsed,
            onStop: onStop,
            hostWindow: nsView.window
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.hide()
    }

    final class Coordinator {
        fileprivate weak var anchorView: NSView?
        private var panel: NSPanel?
        private var hostingView: NSHostingView<LiveRecordingWidget>?
        private var lastHostWindow: NSWindow?
        private static let panelSize = CGSize(width: 116, height: 38)
        private static let horizontalMargin: CGFloat = 20
        private static let topMargin: CGFloat = 20

        @MainActor
        func update(
            isPresented: Bool,
            level: Double,
            elapsed: TimeInterval,
            onStop: @escaping () -> Void,
            hostWindow: NSWindow?
        ) {
            lastHostWindow = hostWindow ?? lastHostWindow

            guard isPresented else {
                hide()
                return
            }

            let widget = LiveRecordingWidget(level: level, elapsed: elapsed, onStop: onStop)

            if let hostingView {
                hostingView.rootView = widget
            } else {
                let hostingView = NSHostingView(rootView: widget)
                hostingView.frame = CGRect(origin: .zero, size: Self.panelSize)
                self.hostingView = hostingView
                recorderPanel().contentView = hostingView
            }

            let panel = recorderPanel()
            position(panel: panel, hostWindow: lastHostWindow)

            if !panel.isVisible {
                panel.alphaValue = 0
                panel.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().alphaValue = 1
                }
            }
        }

        @MainActor
        func hide() {
            guard let panel, panel.isVisible else {
                return
            }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            } completionHandler: {
                // AppKit은 completion을 메인 스레드에서 호출한다.
                MainActor.assumeIsolated {
                    panel.orderOut(nil)
                    panel.alphaValue = 1
                }
            }
        }

        @MainActor
        private func recorderPanel() -> NSPanel {
            if let panel {
                return panel
            }

            let panel = NSPanel(
                contentRect: CGRect(origin: .zero, size: Self.panelSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.ignoresMouseEvents = false
            self.panel = panel
            return panel
        }

        @MainActor
        private func position(panel: NSPanel, hostWindow: NSWindow?) {
            let screen = hostWindow?.screen ?? anchorView?.window?.screen ?? NSScreen.main
            guard let visibleFrame = screen?.visibleFrame else {
                return
            }

            let x = visibleFrame.maxX - Self.panelSize.width - Self.horizontalMargin
            let y = visibleFrame.maxY - Self.panelSize.height - Self.topMargin
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}
