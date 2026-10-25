//
//  ModelPickerView.swift
//  DeepChat
//
//  模型选择面板
//

import SwiftUI

struct ModelPickerView: View {

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""

    private var providers: [Provider] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else {
            return store.providers.filter { !$0.models.isEmpty }
        }
        return store.providers.compactMap { provider in
            if provider.name.lowercased().contains(keyword) {
                return provider
            }
            let matched = provider.models.filter { $0.lowercased().contains(keyword) }
            guard !matched.isEmpty else { return nil }
            var copy = provider
            copy.models = matched
            return copy
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(providers) { provider in
                    Section {
                        ForEach(provider.models, id: \.self) { model in
                            row(provider: provider, model: model)
                        }
                    } header: {
                        HStack(spacing: 8) {
                            Text(provider.name)
                            if !provider.isConfigured {
                                Text("未配置 Key")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(Color.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                }

                if providers.isEmpty {
                    ContentUnavailableView("没有匹配的模型",
                                           systemImage: "magnifyingglass",
                                           description: Text("换个关键词，或到设置里添加模型"))
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索模型")
            .navigationTitle("选择模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func row(provider: Provider, model: String) -> some View {
        let selected = store.currentProvider?.id == provider.id && store.currentModel == model
        return Button {
            guard provider.isConfigured else {
                store.showToast("请先在设置里填写 \(provider.name) 的 API Key")
                return
            }
            store.selectModel(providerID: provider.id, model: model)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model)
                        .font(.system(size: 15, weight: selected ? .semibold : .regular))
                        .foregroundStyle(provider.isConfigured ? Color.primary : Color.secondary)
                        .lineLimit(1)

                    if model == ThinkingModels.reasoningModel(in: provider) {
                        Text("推理模型 · 会显示深度思考过程")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Spacer()

                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                } else if !provider.isConfigured {
                    Image(systemName: "lock")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary.opacity(0.6))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
