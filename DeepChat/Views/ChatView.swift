//
//  ChatView.swift
//  DeepChat
//
//  对话主界面（含空状态）
//

import SwiftUI

struct ChatView: View {

    @EnvironmentObject private var store: AppStore
    @Binding var showSettings: Bool
    @Binding var showModelPicker: Bool

    @State private var draft = ""

    private var messages: [ChatMessage] {
        store.activeConversation?.messages ?? []
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if messages.isEmpty {
                        EmptyStateView(showSettings: $showSettings, onSuggestion: { text in
                            draft = ""
                            store.send(text)
                        })
                        .padding(.top, 8)
                    } else {
                        ForEach(messages.indices, id: \.self) { index in
                            MessageRow(message: messages[index], isLast: index == messages.count - 1)
                                .id(messages[index].id)
                        }
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy, animated: true)
            }
            .onChange(of: messages.last?.text) { _, _ in
                scrollToBottom(proxy, animated: false)
            }
            .onChange(of: messages.last?.reasoning) { _, _ in
                scrollToBottom(proxy, animated: false)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ComposerView(draft: $draft, showModelPicker: $showModelPicker)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard !messages.isEmpty else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}

// MARK: - 空状态

struct EmptyStateView: View {

    @EnvironmentObject private var store: AppStore
    @Binding var showSettings: Bool
    var onSuggestion: (String) -> Void

    private struct Suggestion: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let prompt: String
    }

    private let suggestions: [Suggestion] = [
        Suggestion(icon: "square.and.pencil",
                   title: "帮我写一份周报",
                   prompt: "帮我写一份本周工作周报，包含完成事项、问题和下周计划。"),
        Suggestion(icon: "lightbulb",
                   title: "解释一个概念",
                   prompt: "用一个生活化的比喻解释什么是「向量数据库」。"),
        Suggestion(icon: "character.book.closed",
                   title: "翻译并润色",
                   prompt: "把这段话翻译成地道英文，并说明你的用词选择。"),
        Suggestion(icon: "chevron.left.forwardslash.chevron.right",
                   title: "写一段代码",
                   prompt: "用 Python 实现快速排序，并解释时间复杂度。")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                BrandMark(size: 54, radius: 16)
                Text("我是 DeepChat，很高兴见到你！")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.primary)
                Text("直接接入你自己的大模型 API，不经过任何中转服务器。")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 18)

            if !store.hasAnyConfiguredProvider {
                setupCard
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("试试这样问")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                          spacing: 10) {
                    ForEach(suggestions, id: \.title) { item in
                        Button {
                            onSuggestion(item.prompt)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                Text(item.title)
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(13)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                                    .stroke(Theme.border, lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 20)
        }
    }

    private var setupCard: some View {
        Button {
            showSettings = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "key.horizontal")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("先配置一个 API Key")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("支持 DeepSeek、OpenAI、Claude、Gemini 等")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                    .stroke(Theme.accent.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
