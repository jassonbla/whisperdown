import Foundation

/// 개별 녹음의 요약 진행 상태. 성공은 상태가 아니라 `recording.summary != nil`이 진실 —
/// 완료 시 엔트리를 제거한다. 실패는 메모리에만 남는다(재시작 = 초기화, 버튼 재노출).
enum SummaryPhase: Equatable {
    case running
    case failed(String)
}

/// 요약 백그라운드 작업의 소유자. RecordingProcessor와 분리한 이유:
/// process()/retry()의 defer가 모든 @Published를 리셋하므로 그보다 오래 사는 Task를 담을 수 없고,
/// 기존 녹음의 수동 요약 경로는 process()를 아예 타지 않는다.
@MainActor
final class SummaryCoordinator: ObservableObject {
    @Published private(set) var phases: [Recording.ID: SummaryPhase] = [:]

    private var tasks: [Recording.ID: Task<Void, Never>] = [:]
    private let engine = SummaryEngine()
    private let markdownWriter = MarkdownWriter()

    func phase(for id: Recording.ID?) -> SummaryPhase? {
        id.flatMap { phases[$0] }
    }

    func summarize(recording: Recording, store: RecordingStore) {
        guard SummaryEngine.availability().isAvailable,
              recording.status == .ready,
              recording.summary == nil,
              tasks[recording.id] == nil else {
            return
        }

        let id = recording.id
        phases[id] = .running
        tasks[id] = Task { [weak self, weak store] in
            defer { self?.tasks[id] = nil }

            do {
                let glossary = store?.glossaryText()
                guard let summary = try await self?.engine.summarize(
                    segments: recording.segments,
                    transcript: recording.transcript,
                    glossary: glossary
                ) else {
                    self?.phases[id] = nil
                    return
                }

                // 엔진은 캡처한 전사본으로 돌지만, 쓰기는 최신 상태를 재조회한다 —
                // 그 사이 삭제/재전사된 녹음에 유령 쓰기를 하지 않기 위함.
                guard let self, let store, !Task.isCancelled,
                      var latest = store.recordings.first(where: { $0.id == id }),
                      latest.status == .ready, latest.summary == nil else {
                    self?.phases[id] = nil
                    return
                }

                latest.summary = summary
                self.writeSummaryToFile(latest, summary: summary)
                store.update(latest)
                self.phases[id] = nil
            } catch is CancellationError {
                self?.phases[id] = nil
            } catch {
                self?.phases[id] = .failed(error.localizedDescription)
            }
        }
    }

    func cancel(_ id: Recording.ID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        phases[id] = nil
    }

    /// `## 요약` 섹션만 타겟 교체(수동 편집 보존). 파일이 사라졌으면 full render로 재생성,
    /// 사용자가 헤딩을 지웠으면 파일은 존중하고 index에만 저장한다.
    private func writeSummaryToFile(_ recording: Recording, summary: String) {
        let url = recording.markdownURL

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            let markdown = markdownWriter.render(recording: recording)
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
            return
        }

        guard let replaced = markdownWriter.replacingSummarySection(in: content, with: summary) else {
            return
        }

        try? replaced.write(to: url, atomically: true, encoding: .utf8)
    }
}
