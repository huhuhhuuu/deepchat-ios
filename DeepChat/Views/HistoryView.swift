//
//  HistoryView.swift
//  DeepChat
//
//  历史对话列表
//

import SwiftUI

struct ConversationSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [Conversation]
}

struct HistoryView: View {

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var renaming: Conversation?
    @State private var renameText = ""

    private var sections: [ConversationSection] {
        let calendar = Calendar.current
        var today: [Conversation] = []
        var yesterday: [Conversation] = []
        var week: [Conversation] = []
        var earlier: [Conversation] = []

        for conversation in store.sortedConversations {
            if calendar.isDateInToday(conversation.updatedAt) {
                today.append(conversation)
            } else if calendar.isDateInYesterday(conversation.updatedAt) {
                yesterday.append(conversation)
            } else if let days = calendar.dateComponents([.day], from: conversation.updatedAt, to: Date()).day,
                      days < 7 {
                week.append(conversation)
            } else {
                earlier.append(conversation)
            }
        }

        var result: [ConversationSection] = []
        if !today.isEmpty { result.append(ConversationSection(title: "今天", items: today)) }
        if !yesterday.isEmpty { result.append(ConversationSection(title: "昨天", items: yesterday)) }
        if !week.isEmpty { result.append(ConversationSection(title: "最近 7 天", items: week)) }
        if !earlier.isEmpty { result.append(ConversationSection(title: "更早", items: earlier)) }
        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.conversations.isEmpty {
                    ContentUnavailableView("还没有对话",
                                           systemImage: "bubble.left.and.bubble.right",
                                           description: Text("点击右上角的按钮开始新的对话"))
                } else {
                    List {
                        ForEach(sections) { section in
                            Section(section.title) {
                                ForEach(section.items) { conversation in
                                    row(conversation)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.newConversation()
                        dismiss()
                    } label: {
                        Label("新建对话", systemImage: "square.and.pencil")
                    }
                }
            }
            .alert("重命名对话", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("标题", text: $renameText)
                Button("取消", role: .cancel) { renaming = nil }
                Button("保存") {
                    if let conversation = renaming {
                        store.rename(conversation.id, to: renameText)
                    }
                    renaming = nil
                }
            }
        }
    }

    private func row(_ conversation: Conversation) -> some View {
        Button {
            store.select(conversation.id)
            dismiss()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(conversation.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(conversation.snippet)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(timeLabel(conversation.updatedAt))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))

                if conversation.id == store.activeConversationID {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                store.delete(conversation.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                renameText = conversation.title
                renaming = conversation
            } label: {
                Label("重命名", systemImage: "pencil")
            }
            Button(role: .destructive) {
                store.delete(conversation.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "M/d"
        }
        return formatter.string(from: date)
    }
}
