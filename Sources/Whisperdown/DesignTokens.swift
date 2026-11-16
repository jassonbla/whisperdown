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

/// 타이포 스케일 (pt): 10 overline(mono) · 11 caption/meta(mono) · 13 body/emphasis/mono ·
/// 14 transcript/timer/headline · 20 title · 22 largeTitle(온보딩)
enum Typography {
    static let caption = Font.system(size: 11, weight: .regular)
    static let body = Font.system(size: 13, weight: .regular)
    static let emphasis = Font.system(size: 13, weight: .medium)
    static let headline = Font.system(size: 14, weight: .semibold)
    static let title = Font.system(size: 20, weight: .semibold)
    static let largeTitle = Font.system(size: 22, weight: .semibold)
    static let mono = Font.system(size: 13, weight: .regular, design: .monospaced)
    /// 대문자 섹션 라벨용 (트래킹은 호출부에서 `.tracking(0.6)`).
    static let overline = Font.system(size: 10, weight: .medium, design: .monospaced)
}

/// 양 테마 시맨틱 팔레트 — UI SDK(`@ui-sdk/core/web.css`) 토큰을 따르는 무채색 스케일.
/// 채도는 destructive/success에만 있다. 텍스트 계층은 모든 배경 위에서 4.5:1 이상,
/// 컨트롤 경계(`input`)는 3:1 이상 — 값을 바꾸면 대비를 다시 계산할 것.
enum Palette {
    // 배경 계층
    static let bg0 = Color(light: 0xFAFAFA, dark: 0x000000)      // 창 캔버스/사이드바
    static let bg1 = Color(light: 0xFFFFFF, dark: 0x0A0A0A)      // 메인 서피스
    static let bg2 = Color(light: 0xEBEBEB, dark: 0x1F1F1F)      // hover/선택 서피스
    static let bg1Muted = Color(light: 0xFAFAFA, dark: 0x111111) // 카드 등

    // 텍스트 계층 — 색에 `.opacity`를 덧씌우지 않는다(대비가 깨진다). 단계가 필요하면 토큰을 고른다.
    static let label = Color(light: 0x0A0A0A, dark: 0xFAFAFA)
    static let body = Color(light: 0x262626, dark: 0xD4D4D4)
    static let secondaryLabel = Color(light: 0x555555, dark: 0xA0A0A0)
    static let tertiaryLabel = Color(light: 0x666666, dark: 0x8A8A8A)

    // 보더 계층: separator = 구분선, strongSeparator = pressed 서피스/장식, input = 컨트롤 경계
    static let separator = Color(light: 0xE4E4E4, dark: 0x2A2A2A)
    static let strongSeparator = Color(light: 0xC4C4C4, dark: 0x4A4A4A)
    static let input = Color(light: 0x8F8F8F, dark: 0x6E6E6E)

    // 액센트
    static let destructive = Color(light: 0xC81E28, dark: 0xF97070)
    static let success = Color(light: 0x17753F, dark: 0x5BBF8A)
    static let dangerBackground = Color(light: 0xFDF0F0, dark: 0x2A1414)

    // 하위호환 별칭 — 호출부 무수정 유지
    static let background = bg0
    static let secondaryBackground = bg2
    static let surface = bg1
    static let muted = bg1Muted
    static let primary = label
    static let primaryForeground = bg1
    static let accent = primary
    static let warning = destructive
}

/// UI SDK 기본값과 같은 직각 모서리. 창 모서리(`AppRadius.window`)만 macOS 규약을 따른다.
enum Radius {
    static let base: CGFloat = 0
    static let container: CGFloat = 0
}

enum MotionToken {
    static let quick = Animation.easeOut(duration: 0.14)
}

enum AppMetric {
    static let windowInset: CGFloat = 0
    static let panelGap: CGFloat = 0
    static let sidebarWidth: CGFloat = 280
    static let glossaryPanelWidth: CGFloat = 320
    static let titleBarHeight: CGFloat = 40
    /// 타이틀 바 아래에서 사이드바 제목과 디테일 제목이 함께 시작하는 위쪽 여백.
    static let contentTopInset: CGFloat = Spacing.xl
    static let sidebarContentTopInset: CGFloat = contentTopInset
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
    static let controlHeight: CGFloat = 32
    /// 하단 바의 주 동작 버튼(녹음, 재생/정지) 한 변 — 두 버튼이 같은 크기로 같은 높이에 놓인다.
    static let primaryActionSize: CGFloat = 36
    static let waveformHeight: CGFloat = 36
    /// 사이드바 녹음 바와 디테일 트랜스포트가 공유하는 하단 바 높이 — 두 구분선이 한 줄에 놓인다.
    static let bottomBarHeight: CGFloat = 64
    /// ghost 아이콘 버튼(28pt 박스)의 글리프가 박스 가장자리에서 떨어진 거리.
    /// 여백 선에 글리프를 맞출 때 이만큼 박스를 여백 밖으로 내민다.
    static let iconButtonGlyphInset: CGFloat = 7
    static let transportTimeWidth: CGFloat = 52
}

enum AppTypography {
    static let timer = Font.system(size: 14, weight: .medium, design: .monospaced)
    static let duration = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let meta = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let listMeta = Font.system(size: 11, weight: .regular, design: .monospaced)
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
