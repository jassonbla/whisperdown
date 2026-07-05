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

            IconButton(systemName: "arrow.up.right.square") {
                store.saveGlossary(text)
                store.revealGlossaryInFinder()
            }
            .help(L10n.t("glossary.panel.reveal", language))

            IconButton(systemName: "xmark") {
                isOpen = false
            }
            .help(L10n.t("glossary.panel.close", language))
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: AppLayout.titleBarHeight)
        .background(Color.appBackground)
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
                .font(Typography.mono)
                .foregroundStyle(Palette.body)
                .scrollContentBackground(.hidden)
                .padding(Spacing.xs)
        }
        .background(Color.searchBackground)
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
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
            .padding(.bottom, Spacing.md)
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
