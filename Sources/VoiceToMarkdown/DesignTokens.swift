import AppKit
import SwiftUI

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// 타이포 스케일 (pt): 11 caption · 12 meta · 13 body/emphasis/mono · 14 transcript/timer ·
/// 15 headline · 18 title · 22 largeTitle(온보딩)
enum Typography {
    static let caption = Font.system(size: 11, weight: .regular)
    static let body = Font.system(size: 13, weight: .regular)
    static let emphasis = Font.system(size: 13, weight: .medium)
    static let headline = Font.system(size: 15, weight: .medium)
    static let title = Font.system(size: 18, weight: .medium)
    static let largeTitle = Font.system(size: 22, weight: .semibold)
    static let mono = Font.system(size: 13, weight: .regular, design: .monospaced)
}

/// 양 테마 시맨틱 팔레트.
/// 라이트 = HTML 목업(recorder-full-render.html)의 따뜻한 종이 팔레트 — 기준값, 변경 금지.
/// 다크 = Codex 데스크탑풍 무채색 레이어(bg0 캔버스 < bg1 서피스 < bg2 컨트롤) + 저채도 액센트.
enum Palette {
    // 배경 계층
    static let bg0 = Color(light: 0xF7F6F4, dark: 0x161616)      // 창 캔버스/사이드바
    static let bg1 = Color(light: 0xFFFFFF, dark: 0x1F1F1F)      // 메인 서피스
    static let bg2 = Color(light: 0xEFEDE9, dark: 0x2A2A2A)      // 컨트롤/hover 서피스
    static let bg1Muted = Color(light: 0xFCFCFB, dark: 0x1B1B1B) // transport 카드 등

    // 텍스트 계층
    static let label = Color(light: 0x1A1917, dark: 0xEDECEA)
    static let body = Color(light: 0x413F3B, dark: 0xC8C6C2)
    static let secondaryLabel = Color(light: 0x7C7871, dark: 0x9A9791)
    static let tertiaryLabel = Color(light: 0xA29E96, dark: 0x6B6863)

    // 보더 계층
    static let separator = Color(light: 0xE8E4DC, dark: 0x2E2E2E)
    static let strongSeparator = Color(light: 0xDDD9D2, dark: 0x3A3A3A)

    // 액센트 (다크는 채도 낮춤)
    static let destructive = Color(light: 0xD64545, dark: 0xE06C5F)
    static let success = Color(light: 0x3E9B6E, dark: 0x5BAE85)
    static let dangerBackground = Color(light: 0xFBEEEC, dark: 0x3A2724)

    // 하위호환 별칭 — 호출부 무수정 유지
    static let background = bg0
    static let secondaryBackground = bg2
    static let surface = bg1
    static let muted = bg1Muted
    static let primary = label
    static let primaryForeground = background
    static let accent = primary
    static let warning = destructive
}

enum Radius {
    static let base: CGFloat = 6
    static let container: CGFloat = 10
}

enum MotionToken {
    static let quick = Animation.easeOut(duration: 0.14)
}

enum AppMetric {
    static let windowInset: CGFloat = 0
    static let panelGap: CGFloat = 0
    static let sidebarWidth: CGFloat = 280
    static let titleBarHeight: CGFloat = 40
    static let sidebarContentTopInset: CGFloat = Spacing.lg
    static let trafficLightTop: CGFloat = 14
    static let trafficLightLeading: CGFloat = Spacing.lg
    static let sidebarChromeReserveWidth: CGFloat = 72
    static let sidebarChromeReserveHeight: CGFloat = 28
    static let detailContentMaxWidth: CGFloat = 940
    static let detailHorizontalPadding: CGFloat = 30
    static let transcriptMaxWidth: CGFloat = 840
    static let transportMaxWidth: CGFloat = transcriptMaxWidth
    static let iconButtonSize: CGFloat = 28
    static let rowMinHeight: CGFloat = 44
    static let searchHeight: CGFloat = 28
    static let waveformHeight: CGFloat = 36
    static let transportCardHeight: CGFloat = 66
    static let transportTimeWidth: CGFloat = 52
}

enum AppTypography {
    static let timer = Font.system(size: 14, weight: .medium, design: .monospaced)
    static let duration = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let meta = Font.system(size: 12, weight: .regular)
    static let listMeta = Font.system(size: 11, weight: .regular)
    static let transcript = Font.system(size: 14, weight: .regular)
}

private extension Color {
    init(light lightHex: UInt32, dark darkHex: UInt32) {
        let lightColor = NSColor(hex: lightHex)
        let darkColor = NSColor(hex: darkHex)
        let dynamicColor = NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? darkColor : lightColor
        }

        self.init(nsColor: dynamicColor)
    }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }
}
