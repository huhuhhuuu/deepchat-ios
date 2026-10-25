//
//  ComposerView.swift
//  DeepChat
//
//  底部输入区：输入框 + 深度思考开关 + 模型切换 + 发送/停止
//

import SwiftUI

struct ComposerView: View {

    @EnvironmentObject private var store: AppStore
    @Binding var draft: String
    @Binding var showModelPicker: Bool

    @FocusState private var focused: Bool

    private var trimmed: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canPress: Bool {
        store.isStreaming || (!trimmed.isEmpty && store.canSend)
    }

    var body: some View {
        VStack(spacing: 8) {
            inputBar
            chipBar
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Theme.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.border.opacity(0.7))
                .frame(height: 0.5)
        }
    }

    // MARK: 输入框

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("给 DeepChat 发送消息", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .font(.system(size: 16))
                .focused($focused)
                .padding(.leading, 8)
                .padding(.vertical, 9)
                .tint(Theme.accent)

            sendButton
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(focused ? Theme.accent.opacity(0.5) : Theme.border, lineWidth: focused ? 1.2 : 0.8)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 8, y: 2)
        .animation(.easeOut(duration: 0.15), value: focused)
    }

    private var sendButton: some View {
        Button(action: primaryAction) {
            ZStack {
                Circle()
                    .fill(store.isStreaming ? Theme.accentDark : Theme.accent)
                    .opacity(canPress ? 1 : 0.25)

                Image(systemName: store.isStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
                    .offset(y: store.isStreaming ? 0 : -0.5)
            }
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .disabled(!canPress)
        .animation(.easeOut(duration: 0.15), value: store.isStreaming)
        .animation(.easeOut(duration: 0.15), value: canPress)
        .accessibilityLabel(store.isStreaming ? "停止生成" : "发送")
    }

    private func primaryAction() {
        if store.isStreaming {
            store.stop()
            return
        }
        guard canPress else { return }
        let text = trimmed
        draft = ""
        store.send(text)
    }

    // MARK: 底部 chips

    private var chipBar: some View {
        HStack(spacing: 8) {
            Button {
                store.toggleDeepThinking()
            } label: {
                chip(title: "深度思考",
                     icon: "brain.head.profile",
                     active: store.settings.deepThinking)
            }
            .buttonStyle(.plain)

            Button {
                showModelPicker = true
            } label: {
                chip(title: modelTitle, icon: "cpu", active: false)
            }
            .buttonStyle(.plain)

            Spacer()

            if store.isStreaming {
                Text("生成中…")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .transition(.opacity)
            } else if !draft.isEmpty {
                Text("\(draft.count)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
            }
        }
        .padding(.horizontal, 2)
        .animation(.easeOut(duration: 0.15), value: store.isStreaming)
    }

    private var modelTitle: String {
        let model = store.currentModel
        if model.isEmpty { return "选择模型" }
        return model
    }

    private func chip(title: String, icon: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(active ? Theme.accent : Theme.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(active ? Theme.accent.opacity(0.12) : Theme.surfaceAlt, in: Capsule())
        .overlay(
            Capsule()
                .stroke(active ? Theme.accent.opacity(0.35) : Color.clear, lineWidth: 0.8)
        )
    }
}
