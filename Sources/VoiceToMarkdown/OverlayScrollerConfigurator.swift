import AppKit
import SwiftUI

/// SwiftUI ScrollView가 감싸는 NSScrollView에 오버레이 스크롤러를 강제한다.
/// 시스템 설정 "스크롤 막대 표시: 항상"에서는 `.scrollIndicators(.hidden)`이
/// legacy 상시 스크롤러를 억제하지 못하므로 NSScrollView 수준에서 오버라이드가 필요.
/// 사용: ScrollView 콘텐츠에 `.background(OverlayScrollerConfigurator())`.
struct OverlayScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        HelperView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class HelperView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyOverlayStyle()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(applyOverlayStyle),
                name: NSScroller.preferredScrollerStyleDidChangeNotification,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func applyOverlayStyle() {
            // SwiftUI 뷰 계층이 완성된 다음 틱에 enclosingScrollView가 잡히는 경우가 있어 지연 적용.
            DispatchQueue.main.async { [weak self] in
                guard let scrollView = self?.enclosingScrollView else {
                    return
                }

                scrollView.scrollerStyle = .overlay
                scrollView.autohidesScrollers = true
            }
        }
    }
}
