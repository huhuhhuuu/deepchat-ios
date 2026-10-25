//
//  SettingsView.swift
//  DeepChat
//
//  设置：模型服务、生成参数、外观、数据
//

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var showClearConfirm = false

    private var configuredCount: Int {
        store.providers.filter { $0.isConfigured }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        ProviderListView()
                    } label: {
                        HStack {
                            Label("模型服务", systemImage: "key.horizontal")
                            Spacer()
                            Text("\(configuredCount)/\(store.providers.count) 已配置")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("连接")
                } footer: {
                    Text("API Key 只保存在本机的 Keychain 中，不会上传到任何服务器。")
                }

                Section("生成参数") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("温度")
                            Spacer()
                            Text(String(format: "%.1f", store.settings.temperature))
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $store.settings.temperature, in: 0...2, step: 0.1)
                            .tint(Theme.accent)
                    }
                    .padding(.vertical, 2)

                    Toggle("流式输出", isOn: $store.settings.stream)
                    Toggle("显示思考过程", isOn: $store.settings.showReasoning)

                    HStack {
                        Text("最大输出 tokens")
                        Spacer()
                        TextField("0", value: $store.settings.maxTokens, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("0 = 默认")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("系统提示词")
                        TextField("例如：你是一个严谨的中文助手，回答简洁准确。",
                                  text: $store.settings.systemPrompt,
                                  axis: .vertical)
                            .lineLimit(3...6)
                    }
                    .padding(.vertical, 2)
                }

                Section("外观") {
                    Picker("主题", selection: $store.settings.appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("触感反馈", isOn: $store.settings.haptics)
                }

                Section("数据") {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Text("清空所有对话")
                    }
                }

                Section {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("协议")
                        Spacer()
                        Text("OpenAI 兼容 / Anthropic / Gemini")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("关于")
                } footer: {
                    Text("DeepChat 是一个纯客户端应用：所有请求都由本机直接发送到你在设置里填写的接口地址。")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        store.saveNow()
                        dismiss()
                    }
                }
            }
            .confirmationDialog("清空所有对话？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    for conversation in store.conversations {
                        store.delete(conversation.id)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("模型服务配置会保留，对话记录将无法恢复。")
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - 模型服务列表

struct ProviderListView: View {

    @EnvironmentObject private var store: AppStore
    @State private var showPresets = false

    var body: some View {
        List {
            Section {
                ForEach(store.providers) { provider in
                    NavigationLink {
                        ProviderEditorView(provider: provider)
                    } label: {
                        HStack(spacing: 12) {
                            Text(provider.badge)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(provider.name)
                                        .font(.system(size: 15, weight: .medium))
                                    Text(provider.isConfigured ? "已配置" : "待配置")
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundStyle(provider.isConfigured ? Color.green : Color.orange)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            (provider.isConfigured ? Color.green : Color.orange).opacity(0.12),
                                            in: Capsule()
                                        )
                                }
                                Text(provider.baseURL.isEmpty ? "未填写 Base URL" : provider.host)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let provider = store.providers[index]
                        store.deleteProvider(provider.id)
                    }
                }
            } header: {
                Text("已添加的服务")
            } footer: {
                Text("支持 OpenAI 兼容接口、Anthropic Claude 与 Google Gemini 原生协议；也可以填本地 Ollama 地址。")
            }
        }
        .navigationTitle("模型服务")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showPresets = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showPresets) {
            PresetPickerView()
                .environmentObject(store)
        }
    }
}

// MARK: - 预设选择

struct PresetPickerView: View {

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    private var available: [Provider] {
        ProviderPresets.all
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(available) { preset in
                        Button {
                            var provider = preset
                            provider.apiKey = Keychain.get(provider.id)
                            if store.provider(id: provider.id) == nil {
                                store.addProvider(provider)
                            } else if let existing = store.provider(id: provider.id) {
                                store.selectModel(providerID: existing.id,
                                                  model: existing.primaryModel)
                                store.showToast("该服务已存在")
                            }
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Text(preset.badge)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.name)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.primary)
                                    Text(preset.note)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if store.provider(id: preset.id) != nil {
                                    Text("已添加")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("选择要接入的服务")
                } footer: {
                    Text("添加后填入各自的 API Key 即可使用。")
                }
            }
            .navigationTitle("添加服务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 服务编辑

struct ProviderEditorView: View {

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Provider
    @State private var newModel = ""
    @State private var revealKey = false
    @State private var status: String?
    @State private var statusIsError = false
    @State private var isLoading = false
    @State private var showDeleteConfirm = false

    init(provider: Provider) {
        _draft = State(initialValue: provider)
    }

    var body: some View {
        Form {
            Section {
                TextField("名称", text: $draft.name)

                Picker("协议", selection: $draft.kind) {
                    ForEach(APIKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }

                TextField("Base URL", text: $draft.baseURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("基础信息")
            } footer: {
                Text(draft.kind.hint)
            }

            Section {
                HStack {
                    if revealKey {
                        TextField("API Key", text: $draft.apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("API Key", text: $draft.apiKey)
                    }
                    Button {
                        revealKey.toggle()
                    } label: {
                        Image(systemName: revealKey ? "eye.slash" : "eye")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }

                if !draft.keyURL.isEmpty, let url = URL(string: draft.keyURL) {
                    Link(destination: url) {
                        Label("去官网获取 Key", systemImage: "arrow.up.right.square")
                            .font(.system(size: 13))
                    }
                }
            } header: {
                Text("API Key")
            } footer: {
                Text("Key 保存在本机 Keychain，不会同步到云端。")
            }

            Section {
                ForEach(draft.models, id: \.self) { model in
                    Text(model)
                        .font(.system(size: 14, design: .monospaced))
                }
                .onDelete { indexSet in
                    draft.models.remove(atOffsets: indexSet)
                }

                HStack {
                    TextField("添加模型名", text: $newModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("添加") {
                        let value = newModel.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty, !draft.models.contains(value) else { return }
                        draft.models.append(value)
                        newModel = ""
                    }
                    .disabled(newModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Button {
                    fetchModels()
                } label: {
                    HStack {
                        Label("获取模型列表", systemImage: "arrow.down.circle")
                        if isLoading {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isLoading)

                if let status {
                    Text(status)
                        .font(.system(size: 12.5))
                        .foregroundStyle(statusIsError ? Color.red : Color.green)
                }
            } header: {
                Text("模型")
            } footer: {
                Text("左滑可删除模型。模型名需与接口一致，例如 deepseek-chat。")
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Text("删除该服务")
                }
            }
        }
        .navigationTitle(draft.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") {
                    store.updateProvider(draft)
                    store.showToast("已保存")
                    dismiss()
                }
            }
        }
        .onDisappear {
            store.updateProvider(draft)
        }
        .confirmationDialog("删除这个服务？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                store.deleteProvider(draft.id)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会同时删除保存在本机的 API Key，历史对话不受影响。")
        }
    }

    private func fetchModels() {
        isLoading = true
        status = nil
        statusIsError = false

        let provider = draft
        Task {
            do {
                let models = try await APIClient.shared.listModels(provider)
                var merged = Set(draft.models)
                models.forEach { merged.insert($0) }
                draft.models = Array(merged).sorted()
                status = "获取成功，共 \(models.count) 个模型"
                statusIsError = false
                store.updateProvider(draft)
            } catch {
                status = (error as? APIError)?.message ?? error.localizedDescription
                statusIsError = true
            }
            isLoading = false
        }
    }
}
