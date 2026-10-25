//
//  MarkdownView.swift
//  DeepChat
//
//  轻量 Markdown 渲染：标题 / 段落 / 列表 / 引用 / 代码块 / 表格 / 分割线
//

import SwiftUI
import UIKit

// MARK: - 块

enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet([String])
    case ordered([String])
    case quote(String)
    case code(language: String?, code: String)
    case table(headers: [String], rows: [[String]])
    case rule
}

// MARK: - 解析

enum MarkdownParser {

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var index = 0
        var paragraph: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                let joined = paragraph.joined(separator: "\n")
                if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.paragraph(joined))
                }
                paragraph.removeAll()
            }
        }

        while index < lines.count {
            let raw = lines[index]
            let line = raw.trimmingCharacters(in: .whitespaces)

            // 代码块
            if line.hasPrefix("```") {
                flushParagraph()
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                index += 1
                while index < lines.count {
                    let candidate = lines[index]
                    if candidate.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        index += 1
                        break
                    }
                    codeLines.append(candidate)
                    index += 1
                }
                blocks.append(.code(language: language.isEmpty ? nil : language,
                                    code: codeLines.joined(separator: "\n")))
                continue
            }

            // 空行
            if line.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            // 分割线
            if line.count >= 3,
               line.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" }) {
                flushParagraph()
                blocks.append(.rule)
                index += 1
                continue
            }

            // 标题
            if line.hasPrefix("#") {
                var level = 0
                for char in line {
                    if char == "#" { level += 1 } else { break }
                }
                if level > 0 && level <= 6 {
                    let content = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                    if !content.isEmpty {
                        flushParagraph()
                        blocks.append(.heading(level: level, text: content))
                        index += 1
                        continue
                    }
                }
            }

            // 引用
            if line.hasPrefix(">") {
                flushParagraph()
                var quoteLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    quoteLines.append(String(candidate.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }

            // 无序列表
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flushParagraph()
                var items: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if candidate.hasPrefix("- ") || candidate.hasPrefix("* ") || candidate.hasPrefix("+ ") {
                        items.append(String(candidate.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                        index += 1
                    } else if candidate.isEmpty {
                        break
                    } else if candidate.hasPrefix("  ") {
                        // 续行
                        if !items.isEmpty {
                            items[items.count - 1] += " " + candidate.trimmingCharacters(in: .whitespaces)
                        }
                        index += 1
                    } else {
                        break
                    }
                }
                blocks.append(.bullet(items))
                continue
            }

            // 有序列表
            if let _ = line.range(of: "^\\d+[.、)]\\s+", options: .regularExpression) {
                flushParagraph()
                var items: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if let range = candidate.range(of: "^\\d+[.、)]\\s+", options: .regularExpression) {
                        items.append(String(candidate[range.upperBound...]))
                        index += 1
                    } else if candidate.isEmpty {
                        break
                    } else {
                        break
                    }
                }
                blocks.append(.ordered(items))
                continue
            }

            // 表格
            if line.hasPrefix("|") {
                if let (table, consumed) = parseTable(lines: lines, start: index) {
                    flushParagraph()
                    blocks.append(table)
                    index += consumed
                    continue
                }
            }

            paragraph.append(line)
            index += 1
        }

        flushParagraph()
        return blocks
    }

    private static func parseTable(lines: [String], start: Int) -> (MarkdownBlock, Int)? {
        guard start + 1 < lines.count else { return nil }
        let separator = lines[start + 1].trimmingCharacters(in: .whitespaces)
        guard separator.contains("-"),
              separator.trimmingCharacters(in: CharacterSet(charactersIn: "|-: ")).isEmpty else {
            return nil
        }

        func split(_ line: String) -> [String] {
            var value = line.trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("|") { value.removeFirst() }
            if value.hasSuffix("|") { value.removeLast() }
            return value.components(separatedBy: "|").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
        }

        let headers = split(lines[start])
        var rows: [[String]] = []
        var index = start + 2
        while index < lines.count {
            let candidate = lines[index].trimmingCharacters(in: .whitespaces)
            guard candidate.hasPrefix("|") else { break }
            rows.append(split(lines[index]))
            index += 1
        }
        return (.table(headers: headers, rows: rows), index - start)
    }

    /// 行内 Markdown -> AttributedString
    static func inline(_ text: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible
        if let attributed = try? AttributedString(markdown: text, options: options) {
            return attributed
        }
        return AttributedString(text)
    }
}

// MARK: - 渲染

struct MarkdownView: View {
    var text: String
    var showsCaret: Bool = false

    private var blocks: [MarkdownBlock] {
        MarkdownParser.parse(text)
    }
    var body: some View {
        let list = blocks
        VStack(alignment: .leading, spacing: 10) {
            ForEach(list.indices, id: \.self) { index in
                blockView(list[index], isLast: index == list.count - 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock, isLast: Bool) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(MarkdownParser.inline(text))
                .font(.system(size: headingSize(level), weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.top, level <= 2 ? 4 : 0)

        case .paragraph(let text):
            if isLast && showsCaret {
                (Text(MarkdownParser.inline(text)) + Text(" ▍").foregroundStyle(Theme.accent))
                    .font(.system(size: 16))
                    .lineSpacing(5)
            } else {
                Text(MarkdownParser.inline(text))
                    .font(.system(size: 16))
                    .lineSpacing(5)
                    .foregroundStyle(.primary)
            }

        case .bullet(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(Theme.textSecondary)
                            .frame(width: 5, height: 5)
                            .offset(y: -2)
                        Text(MarkdownParser.inline(items[index]))
                            .font(.system(size: 16))
                            .lineSpacing(4)
                    }
                }
            }

        case .ordered(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(minWidth: 20, alignment: .trailing)
                        Text(MarkdownParser.inline(items[index]))
                            .font(.system(size: 16))
                            .lineSpacing(4)
                    }
                }
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.accent.opacity(0.6))
                    .frame(width: 3)
                Text(MarkdownParser.inline(text))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(4)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))

        case .code(let language, let code):
            CodeBlockView(language: language, code: code)

        case .table(let headers, let rows):
            MarkdownTable(headers: headers, rows: rows)

        case .rule:
            Divider().overlay(Theme.border)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 22
        case 2: return 19
        case 3: return 17
        default: return 16
        }
    }
}

// MARK: - 代码块

struct CodeBlockView: View {
    var language: String?
    var code: String

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(language?.isEmpty == false ? language! : "code")
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x8B96AB))
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeOut(duration: 0.15)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        withAnimation { copied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(copied ? "已复制" : "复制")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(copied ? Color(hex: 0x6EE7B7) : Color(hex: 0x8B96AB))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.codeHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.codeText)
                    .lineSpacing(3)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .background(Theme.codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall + 2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerSmall + 2, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.8)
        )
    }
}

// MARK: - 表格

struct MarkdownTable: View {
    var headers: [String]
    var rows: [[String]]

    private var columnCount: Int {
        max(headers.count, rows.map(\.count).max() ?? 0)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(0..<columnCount, id: \.self) { column in
                        Text(MarkdownParser.inline(value(headers, column)))
                            .font(.system(size: 13, weight: .semibold))
                            .frame(minWidth: 78, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                }
                .background(Theme.surfaceAlt)

                ForEach(rows.indices, id: \.self) { rowIndex in
                    Divider().overlay(Theme.border)
                    HStack(spacing: 0) {
                        ForEach(0..<columnCount, id: \.self) { column in
                            Text(MarkdownParser.inline(value(rows[rowIndex], column)))
                                .font(.system(size: 13))
                                .frame(minWidth: 78, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.8)
        )
    }

    private func value(_ list: [String], _ index: Int) -> String {
        index < list.count ? list[index] : ""
    }
}
