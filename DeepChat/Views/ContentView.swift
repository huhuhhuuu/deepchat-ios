//
//  ContentView.swift
//  DeepChat
//
//  根视图：导航栏 + 会话列表入口 + 设置
//

import SwiftUI

struct ContentView: View {

    @EnvironmentObject private var store: AppStore

    @State private var showHistory = false
    @State private var showSettings = false
    @State private var showModelPicker = false

    var body: some View {
        NavigationStack {
            ChatView(showSettings: $showSettings, showModelPicker: $showModelPicker)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showHistory = true
                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        .accessibilityLabel("历史对话")
                    }

                    ToolbarItem(placement: .principal) {
                        Button {
                            showModelPicker = true
                        } label: {
                            HStack(spacing: 5) {
                                Text(modelTitle)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.surfaceAlt, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            store.newConversation()
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        .accessibilityLabel("新建对话")
                    }
                }
        }
        .tint(Theme.accent)
        .sheet(isPresented: $showHistory) {
            HistoryView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerView()
                .environmentObject(store)
                .presentationDetents([.medium, .large])
        }
        .overlay(alignment: .top) {
            if let toast = store.toast {
                Text(toast)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Theme.border, lineWidth: 0.8))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: store.toast)
    }

    private var modelTitle: String {
        let model = store.currentModel
        if model.isEmpty { return "选择模型" }
        return store.currentProvider?.name ?? model
    }
}

#Preview {
    ContentView()
        .environmentObject(AppStore())
}
