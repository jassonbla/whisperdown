import SwiftUI

/// 인앱 용어집 편집 패널 (우측 3번째 pane). 앱 최초의 편집 가능한 텍스트 surface.
/// 자동 저장: 입력 debounce(0.8s) + 패널 사라질 때 즉시 저장. GLOSSARY.md 원본이 진실.
struct GlossaryPanel: View {
    @Environment(\.appLanguage) private var language
    @ObservedObject var store: RecordingStore
    @Binding var isOpen: Bool

    @State private var text = ""
    @State private var didLoad = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.hairline)
            editor
            hint
        }
        .frame(width: AppLayout.glossaryPanelWidth)
        .frame(maxHeight: .infinity)
        .background(Color.appBackground)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.hairline)
                .frame(width: 1)
                .allowsHitTesting(false)
        }
        .onAppear(perform: loadIfNeeded)
        .onDisappear {
            saveTask?.cancel()
            store.saveGlossary(text)
        }
        .onChange(of: store.markdownDirectory) {
            reload()
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Text(L10n.t("glossary.panel.title", language))
                .font(Typography.headline)
                .foregroundStyle(Palette.label)

            Spacer()

            IconButton(systemName: "folder", label: L10n.t("glossary.panel.reveal", language)) {
                store.saveGlossary(text)
                store.revealGlossaryInFinder()
            }

            IconButton(systemName: "xmark", label: L10n.t("glossary.panel.close", language)) {
                isOpen = false
            }
        }
        // 닫기(ghost) 글리프를 편집기 오른쪽 선에 맞춘다.
        .padding(.leading, Spacing.md)
        .padding(.trailing, Spacing.md - AppMetric.iconButtonGlyphInset)
        .frame(height: AppLayout.titleBarHeight)
        .background(Color.appBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.hairline)
                .frame(height: 1)
                .allowsHitTesting(false)
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(L10n.t("glossary.panel.placeholder", language))
                    .font(Typography.mono)
                    .foregroundStyle(Palette.tertiaryLabel)
                    .padding(.horizontal, Spacing.sm + 4)
                    .padding(.vertical, Spacing.sm + 2)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .accessibilityLabel(L10n.t("glossary.panel.title", language))
                .font(Typography.mono)
                .foregroundStyle(Palette.body)
                .scrollContentBackground(.hidden)
                .padding(Spacing.xs)
        }
        .background(Color.searchBackground)
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .strokeBorder(Color.controlBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .padding(Spacing.md)
        .onChange(of: text) {
            guard didLoad else { return }
            scheduleSave()
        }
    }

    private var hint: some View {
        Text(L10n.t("summary.glossary.hint", language))
            .font(Typography.caption)
            .foregroundStyle(Palette.tertiaryLabel)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.md)
            // 사이드바·트랜스포트와 같은 하단 바 높이 — 세 구분선이 한 줄에 놓인다.
            .frame(height: AppMetric.bottomBarHeight)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.hairline)
                    .frame(height: 1)
                    .allowsHitTesting(false)
            }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        text = store.glossaryText() ?? RecordingStore.glossaryTemplate
        didLoad = true
    }

    private func reload() {
        saveTask?.cancel()
        text = store.glossaryText() ?? RecordingStore.glossaryTemplate
    }

    /// 입력이 멈추면 저장 — 디스크 쓰기 스로틀. 이전 예약은 취소.
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = text
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            store.saveGlossary(snapshot)
        }
    }
}
