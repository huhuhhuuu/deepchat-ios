//
//  MessageRow.swift
//  DeepChat
//
//  单条消息：用户气泡 / 助手 Markdown + 深度思考 + 操作
//

import SwiftUI
import UIKit

struct MessageRow: View {

    @EnvironmentObject private var store: AppStore
    let message: ChatMessage
    var isLast: Bool = false

    @State private var reasoningExpanded = false
    @State private var copied = false

    var body: some View {
        Group {
            if message.role == .user {
                userRow
            } else {
                assistantRow
            }
        }
    }

    // MARK: 用户

    private var userRow: some View {
        HStack(alignment: .top) {
            Spacer(minLength: 48)
            Text(message.text)
                .font(.system(size: 16))
                .lineSpacing(4)
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.userBubble)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = message.text
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                }
        }
    }

    // MARK: 助手

    private var assistantRow: some View {
        HStack(alignment: .top, spacing: 10) {
            BrandMark(size: 26, radius: 8)

            VStack(alignment: .leading, spacing: 9) {
                if store.settings.showReasoning && !message.reasoning.isEmpty {
                    reasoningView
                }

                if message.isStreaming && message.text.isEmpty {
                    typingIndicator
                } else if !message.text.isEmpty {
                    MarkdownView(text: message.text, showsCaret: message.isStreaming)
                }

                if let error = message.error {
                    errorView(error)
                }

                if !message.isStreaming {
                    actionRow
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var typingIndicator: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.textSecondary.opacity(0.7))
                    .frame(width: 6, height: 6)
                    .opacity(0.35 + 0.25 * Double(index))
                    .scaleEffect(1.0)
            }
        }
        .padding(.vertical, 8)
        .modifier(PulseEffect())
    }

    // MARK: 深度思考

    private var reasoningView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    reasoningExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 12, weight: .semibold))
                    Text(reasoningTitle)
                        .font(.system(size: 12.5, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(reasoningExpanded ? 180 : 0))
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Theme.surfaceAlt, in: Capsule())
            }
            .buttonStyle(.plain)

            if reasoningExpanded {
                Text(message.reasoning)
                    .font(.system(size: 13.5))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.leading, 12)
                    .padding(.vertical, 10)
                    .padding(.trailing, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceAlt.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.accent.opacity(0.5))
                            .frame(width: 2.5)
                            .padding(.vertical, 8)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var reasoningTitle: String {
        if message.isStreaming && message.text.isEmpty {
            return "正在深度思考…"
        }
        let seconds = Int(message.reasoningSeconds.rounded())
        if seconds > 0 {
            return "已深度思考（用时 \(seconds) 秒）"
        }
        return "深度思考"
    }

    // MARK: 错误

    private func errorView(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(Color(red: 0.74, green: 0.2, blue: 0.22))
                .fixedSize(horizontal: false, vertical: true)

            if isLast {
                Button {
                    store.regenerate()
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.red.opacity(0.22), lineWidth: 0.8)
        )
    }

    // MARK: 操作

    private var actionRow: some View {
        HStack(spacing: 14) {
            if !message.text.isEmpty {
                Button {
                    UIPasteboard.general.string = message.text
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeOut(duration: 0.15)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        withAnimation { copied = false }
                    }
                } label: {
                    Label(copied ? "已复制" : "复制",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(copied ? Theme.accent : Theme.textSecondary)
            }

            if isLast {
                Button {
                    store.regenerate()
                } label: {
                    Label("重新生成", systemImage: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            if let usage = message.usage, usage.total > 0 {
                Text("\(usage.total) tokens")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
            }
        }
        .padding(.top, 1)
    }
}

// MARK: - 打字动画

private struct PulseEffect: ViewModifier {
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0.45)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: visible)
            .onAppear { visible = true }
    }
}
