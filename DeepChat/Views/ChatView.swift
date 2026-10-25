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
        let emoji: String
        let title: String
        let prompt: String
    }

    private let suggestions: [Suggestion] = [
        Suggestion(emoji: "🐟",
                   title: "陪我聊聊天",
                   prompt: "今天有点累，陪我随便聊聊吧，说点轻松的事。"),
        Suggestion(emoji: "🎂",
                   title: "写段祝福",
                   prompt: "帮我写一段给好朋友的生日祝福，语气轻快一点、别太肉麻。"),
        Suggestion(emoji: "🍜",
                   title: "今晚吃什么",
                   prompt: "今晚吃什么好呢？给我三个简单好做、半小时内能搞定的菜。"),
        Suggestion(emoji: "💡",
                   title: "讲点冷知识",
                   prompt: "讲三个有趣的冷知识，每个不超过两句话。")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header

            if !store.hasAnyConfiguredProvider {
                setupCard
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("可以这样开始")
                    .font(.system(size: 12.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.textSecondary)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                          spacing: 10) {
                    ForEach(suggestions) { item in
                        Button {
                            onSuggestion(item.prompt)
                        } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                Text(item.emoji)
                                    .font(.system(size: 18))
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

            Spacer(minLength: 12)
        }
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.20))
                    .frame(width: 150, height: 150)
                    .blur(radius: 46)

                BrandMark(size: 62, radius: 19)
                    .overlay(alignment: .topTrailing) {
                        Text("🐾")
                            .font(.system(size: 15))
                            .offset(x: 8, y: -8)
                    }
            }
            .padding(.bottom, 16)

            Text("小圆的大肥鱼")
                .font(.system(size: 11.5, weight: .semibold))
                .tracking(4)
                .foregroundStyle(Theme.textSecondary.opacity(0.9))

            Text("小圆专属喵")
                .font(.system(size: 32, weight: .heavy))
                .italic()
                .foregroundStyle(Theme.accentGradient)
                .padding(.top, 6)

            Text("今天也要开开心心呀～ 想聊什么、想让我帮你做什么，直接说就好喵。")
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 10)

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                Text("本机直连 · 不经过任何中转服务器")
                    .font(.system(size: 11.5))
            }
            .foregroundStyle(Theme.textSecondary.opacity(0.75))
            .padding(.top, 12)
        }
        .padding(.top, 20)
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
