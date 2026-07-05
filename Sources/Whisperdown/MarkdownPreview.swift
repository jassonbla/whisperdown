import SwiftUI

/// md 파일 내용을 GitHub 프리뷰처럼 스타일링해 보여주는 경량 렌더러.
/// 외부 패키지 없이(raw-swiftc 빌드 게이트) 라인 단위 블록 파싱 + AttributedString 인라인 마크다운으로 처리한다.
/// 표시 전용 — 복사/드래그는 여전히 원본 파일 바이트 그대로를 쓴다.
struct MarkdownPreview: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ForEach(Array(Self.parse(content).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    // MARK: 블록 모델

    enum Block: Equatable {
        case frontMatter([FrontMatterField])
        case heading(level: Int, text: String)
        case bullet(String)
        case quote(String)
        case paragraph(String)
    }

    struct FrontMatterField: Equatable {
        let key: String
        let value: String
    }

    // MARK: 파싱 (라인 기반 — 우리 템플릿 + 일반적인 수동 편집 범위를 커버)

    static func parse(_ content: String) -> [Block] {
        var lines = content.components(separatedBy: "\n")
        var blocks: [Block] = []

        if lines.first == "---",
           let end = lines.dropFirst().firstIndex(of: "---") {
            let fields = lines[1..<end].compactMap(parseFrontMatterLine)
            if !fields.isEmpty {
                blocks.append(.frontMatter(fields))
            }
            lines = Array(lines[(end + 1)...])
        }

        var paragraph: [String] = []
        func flushParagraph() {
            let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(.paragraph(text))
            }
            paragraph = []
        }

        for line in lines {
            if line.hasPrefix("### ") {
                flushParagraph()
                blocks.append(.heading(level: 3, text: String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                flushParagraph()
                blocks.append(.heading(level: 2, text: String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                flushParagraph()
                blocks.append(.heading(level: 1, text: String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") {
                flushParagraph()
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else if line.hasPrefix("> ") {
                flushParagraph()
                blocks.append(.quote(String(line.dropFirst(2))))
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushParagraph()
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()

        return blocks
    }

    private static func parseFrontMatterLine(_ line: String) -> FrontMatterField? {
        guard let colon = line.firstIndex(of: ":") else {
            return nil
        }

        let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
        var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }

        guard !key.isEmpty else {
            return nil
        }

        return FrontMatterField(key: key, value: value)
    }

    // MARK: 블록 렌더링

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .frontMatter(let fields):
            frontMatterCard(fields)

        case .heading(let level, let text):
            heading(level: level, text: text)

        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text("•")
                    .font(AppTypography.transcript)
                    .foregroundStyle(Palette.secondaryLabel)
                styledText(text)
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.hairline)
                    .frame(width: 3)
                styledText(text)
                    .foregroundStyle(Palette.secondaryLabel)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .paragraph(let text):
            styledText(text)
        }
    }

    @ViewBuilder
    private func heading(level: Int, text: String) -> some View {
        switch level {
        case 1:
            Text(text)
                .font(Typography.largeTitle)
                .foregroundStyle(Palette.label)
                .padding(.top, Spacing.xs)
        case 2:
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(text)
                    .font(Typography.title)
                    .foregroundStyle(Palette.label)
                Rectangle()
                    .fill(Color.hairline)
                    .frame(height: 1)
            }
            .padding(.top, Spacing.sm)
        default:
            Text(text)
                .font(Typography.headline)
                .foregroundStyle(Palette.label)
                .padding(.top, Spacing.xs)
        }
    }

    private func frontMatterCard(_ fields: [FrontMatterField]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(fields, id: \.key) { field in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(field.key)
                        .font(Typography.mono)
                        .foregroundStyle(Palette.secondaryLabel)
                        .frame(width: 92, alignment: .leading)
                    Text(field.value)
                        .font(Typography.mono)
                        .foregroundStyle(Palette.body)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.container)
                .fill(Color.controlSurface.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.container)
                .strokeBorder(Color.hairline, lineWidth: 1)
        )
    }

    /// 인라인 마크다운(`code`, **bold**, *italic*, 링크)은 Foundation 파서에 위임한다.
    private func styledText(_ text: String) -> Text {
        let attributed = (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)

        return Text(attributed)
            .font(AppTypography.transcript)
            .foregroundStyle(Palette.body)
    }
}
