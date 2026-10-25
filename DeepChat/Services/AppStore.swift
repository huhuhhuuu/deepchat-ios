//
//  AppStore.swift
//  DeepChat
//
//  全局状态：会话、设置、供应商；以及发送 / 停止 / 重生成等业务逻辑
//

import Foundation
import SwiftUI
import UIKit

@MainActor
final class AppStore: ObservableObject {

    // MARK: 对外状态

    @Published private(set) var conversations: [Conversation] = []
    @Published var settings = AppSettings()
    @Published private(set) var providers: [Provider] = []
    @Published var activeConversationID: UUID?
    @Published private(set) var isStreaming = false
    @Published var toast: String?

    // MARK: 私有

    private var streamTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    private let fileURL: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    // MARK: 生命周期

    init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("DeepChat", isDirectory: true)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("state.json")

        load()
    }

    // MARK: 计算属性

    var sortedConversations: [Conversation] {
        conversations.sorted { $0.updatedAt > $1.updatedAt }
    }

    var activeConversation: Conversation? {
        guard let id = activeConversationID else { return nil }
        return conversations.first { $0.id == id }
    }

    var activeProvider: Provider? {
        provider(id: settings.activeProviderID) ?? providers.first
    }

    var currentModel: String {
        if let conversation = activeConversation, !conversation.model.isEmpty {
            return conversation.model
        }
        return settings.activeModel
    }

    var currentProvider: Provider? {
        if let conversation = activeConversation {
            if let provider = provider(id: conversation.providerID) { return provider }
        }
        return activeProvider
    }

    var hasAnyConfiguredProvider: Bool {
        providers.contains { $0.isConfigured }
    }

    var canSend: Bool {
        !isStreaming && hasAnyConfiguredProvider
    }

    func provider(id: String?) -> Provider? {
        guard let id else { return nil }
        return providers.first { $0.id == id }
    }

    // MARK: 会话操作

    @discardableResult
    func newConversation() -> Conversation {
        let provider = activeProvider
        let conversation = Conversation(
            title: "新对话",
            providerID: provider?.id ?? "deepseek",
            model: settings.activeModel.isEmpty ? (provider?.primaryModel ?? "") : settings.activeModel
        )
        conversations.insert(conversation, at: 0)
        activeConversationID = conversation.id
        scheduleSave()
        return conversation
    }

    func select(_ id: UUID) {
        if isStreaming { stop() }
        activeConversationID = id
        if let conversation = conversations.first(where: { $0.id == id }) {
            settings.activeProviderID = conversation.providerID
            settings.activeModel = conversation.model
        }
        scheduleSave()
    }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        if activeConversationID == id {
            activeConversationID = conversations.first?.id
        }
        scheduleSave()
    }

    func rename(_ id: UUID, to title: String) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        conversations[index].title = trimmed.isEmpty ? "新对话" : String(trimmed.prefix(40))
        scheduleSave()
    }

    func clearMessages(of id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].messages.removeAll()
        conversations[index].title = "新对话"
        conversations[index].updatedAt = Date()
        scheduleSave()
    }

    // MARK: 发送

    func send(_ rawText: String) {
        guard !isStreaming else { return }
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        var conversation: Conversation
        if let active = activeConversation {
            conversation = active
        } else {
            conversation = newConversation()
        }

        guard let provider = provider(id: conversation.providerID) ?? activeProvider else {
            showToast("请先在设置里添加一个模型服务")
            return
        }
        guard provider.isConfigured else {
            showToast("请先填写 \(provider.name) 的 API Key")
            return
        }
        let model = conversation.model.isEmpty ? provider.primaryModel : conversation.model
        guard !model.isEmpty else {
            showToast("请在设置里为 \(provider.name) 添加模型")
            return
        }

        conversation.providerID = provider.id
        conversation.model = model
        conversation.messages.append(ChatMessage(role: .user, text: text))
        if conversation.title == "新对话" || conversation.title.isEmpty {
            conversation.title = String(text.prefix(24))
        }

        var assistant = ChatMessage(role: .assistant, text: "", model: model)
        assistant.isStreaming = true
        conversation.messages.append(assistant)
        conversation.updatedAt = Date()

        update(conversation)
        activeConversationID = conversation.id
        settings.activeProviderID = provider.id
        settings.activeModel = model
        scheduleSave()
        haptic()

        let history = conversation.messages.filter { $0.role != .system && !$0.text.isEmpty }
        let request = ChatRequest(
            provider: provider,
            model: model,
            messages: history,
            systemPrompt: settings.systemPrompt,
            stream: settings.stream,
            temperature: settings.temperature,
            topP: settings.topP,
            maxTokens: settings.maxTokens
        )

        runStream(request: request, conversationID: conversation.id, messageID: assistant.id)
    }

    func regenerate() {
        guard !isStreaming,
              let conversation = activeConversation,
              !conversation.messages.isEmpty else { return }

        guard let lastUserIndex = conversation.messages.lastIndex(where: { $0.role == .user }) else { return }
        var updated = conversation
        updated.messages = Array(updated.messages.prefix(through: lastUserIndex))

        let provider = provider(id: updated.providerID) ?? activeProvider
        guard let provider, provider.isConfigured else {
            showToast("请先填写 API Key")
            return
        }
        let model = updated.model.isEmpty ? provider.primaryModel : updated.model

        var assistant = ChatMessage(role: .assistant, text: "", model: model)
        assistant.isStreaming = true
        updated.messages.append(assistant)
        updated.updatedAt = Date()
        update(updated)
        scheduleSave()

        let history = updated.messages.filter { $0.role != .system && !$0.text.isEmpty }
        let request = ChatRequest(
            provider: provider,
            model: model,
            messages: history,
            systemPrompt: settings.systemPrompt,
            stream: settings.stream,
            temperature: settings.temperature,
            topP: settings.topP,
            maxTokens: settings.maxTokens
        )
        runStream(request: request, conversationID: updated.id, messageID: assistant.id)
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        if let conversation = activeConversation,
           let index = conversations.firstIndex(where: { $0.id == conversation.id }),
           let lastIndex = conversations[index].messages.indices.last {
            conversations[index].messages[lastIndex].isStreaming = false
            if conversations[index].messages[lastIndex].text.isEmpty {
                conversations[index].messages[lastIndex].text = "已停止生成"
            }
        }
        scheduleSave()
    }

    // MARK: 流式执行

    /// 流式缓冲：按时间节流写回，避免每个 token 都触发一次视图刷新
    private struct StreamBuffer {
        var text = ""
        var reasoning = ""
        var firstTokenAt: Date?
        var lastFlush = Date.distantPast
    }

    private func flushBuffer(_ buffer: inout StreamBuffer,
                             conversationID: UUID,
                             messageID: UUID,
                             startedAt: Date,
                             force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(buffer.lastFlush) > 0.05 else { return }
        buffer.lastFlush = now
        applyBuffers(conversationID: conversationID,
                     messageID: messageID,
                     text: buffer.text,
                     reasoning: buffer.reasoning,
                     firstTokenAt: buffer.firstTokenAt,
                     startedAt: startedAt)
    }

    private func runStream(request: ChatRequest, conversationID: UUID, messageID: UUID) {
        isStreaming = true
        let startedAt = Date()

        streamTask = Task { [weak self] in
            guard let self else { return }
            var buffer = StreamBuffer()
            var completed = false

            do {
                for try await event in APIClient.shared.stream(request) {
                    if Task.isCancelled { break }
                    switch event {
                    case .text(let chunk):
                        if buffer.firstTokenAt == nil { buffer.firstTokenAt = Date() }
                        buffer.text += chunk
                        self.flushBuffer(&buffer,
                                         conversationID: conversationID,
                                         messageID: messageID,
                                         startedAt: startedAt)
                    case .reasoning(let chunk):
                        if buffer.firstTokenAt == nil { buffer.firstTokenAt = Date() }
                        buffer.reasoning += chunk
                        self.flushBuffer(&buffer,
                                         conversationID: conversationID,
                                         messageID: messageID,
                                         startedAt: startedAt)
                    case .usage(let usage):
                        self.applyUsage(conversationID: conversationID, messageID: messageID, usage: usage)
                    case .finished:
                        completed = true
                    }
                }
            } catch let error as APIError {
                self.applyError(conversationID: conversationID,
                                messageID: messageID,
                                error: error,
                                partial: buffer.text)
            } catch {
                let apiError = APIError(status: 0, message: error.localizedDescription)
                self.applyError(conversationID: conversationID,
                                messageID: messageID,
                                error: apiError,
                                partial: buffer.text)
            }

            self.flushBuffer(&buffer,
                             conversationID: conversationID,
                             messageID: messageID,
                             startedAt: startedAt,
                             force: true)
            self.finishMessage(conversationID: conversationID,
                               messageID: messageID,
                               cancelled: !completed && Task.isCancelled,
                               empty: buffer.text.isEmpty && buffer.reasoning.isEmpty)
            self.isStreaming = false
            self.streamTask = nil
            self.scheduleSave()
        }
    }

    private func applyBuffers(conversationID: UUID,
                              messageID: UUID,
                              text: String,
                              reasoning: String,
                              firstTokenAt: Date?,
                              startedAt: Date) {
        guard let ci = conversations.firstIndex(where: { $0.id == conversationID }),
              let mi = conversations[ci].messages.firstIndex(where: { $0.id == messageID }) else { return }
        conversations[ci].messages[mi].text = text
        conversations[ci].messages[mi].reasoning = reasoning
        if let firstTokenAt, !reasoning.isEmpty {
            conversations[ci].messages[mi].reasoningSeconds = firstTokenAt.timeIntervalSince(startedAt)
        }
        conversations[ci].updatedAt = Date()
    }

    private func applyUsage(conversationID: UUID, messageID: UUID, usage: TokenUsage) {
        guard let ci = conversations.firstIndex(where: { $0.id == conversationID }),
              let mi = conversations[ci].messages.firstIndex(where: { $0.id == messageID }) else { return }
        var merged = conversations[ci].messages[mi].usage ?? TokenUsage()
        merged.prompt = max(merged.prompt, usage.prompt)
        merged.completion = max(merged.completion, usage.completion)
        conversations[ci].messages[mi].usage = merged
    }

    private func applyError(conversationID: UUID, messageID: UUID, error: APIError, partial: String) {
        guard let ci = conversations.firstIndex(where: { $0.id == conversationID }),
              let mi = conversations[ci].messages.firstIndex(where: { $0.id == messageID }) else { return }
        var message = error.message
        if let hint = error.hint, !message.contains(hint) {
            message += "（\(hint)）"
        }
        conversations[ci].messages[mi].error = message
        if partial.isEmpty {
            conversations[ci].messages[mi].text = ""
        }
    }

    private func finishMessage(conversationID: UUID, messageID: UUID, cancelled: Bool, empty: Bool) {
        guard let ci = conversations.firstIndex(where: { $0.id == conversationID }),
              let mi = conversations[ci].messages.firstIndex(where: { $0.id == messageID }) else { return }
        conversations[ci].messages[mi].isStreaming = false
        if empty && conversations[ci].messages[mi].error == nil {
            conversations[ci].messages[mi].text = cancelled ? "已停止生成" : "（模型没有返回内容）"
        }
        conversations[ci].updatedAt = Date()
    }

    // MARK: 模型切换

    func selectModel(providerID: String, model: String) {
        settings.activeProviderID = providerID
        settings.activeModel = model
        if let id = activeConversationID,
           let index = conversations.firstIndex(where: { $0.id == id }) {
            conversations[index].providerID = providerID
            conversations[index].model = model
            conversations[index].updatedAt = Date()
        }
        scheduleSave()
    }

    func toggleDeepThinking() {
        settings.deepThinking.toggle()
        guard let provider = currentProvider else { return }
        if settings.deepThinking {
            if let model = ThinkingModels.reasoningModel(in: provider) {
                selectModel(providerID: provider.id, model: model)
            } else {
                showToast("\(provider.name) 没有配置推理模型，将继续使用当前模型")
            }
        } else if let model = ThinkingModels.chatModel(in: provider) {
            selectModel(providerID: provider.id, model: model)
        }
        haptic()
    }

    // MARK: 供应商维护

    func addProvider(_ provider: Provider) {
        providers.append(provider)
        scheduleSave()
    }

    func updateProvider(_ provider: Provider) {
        guard let index = providers.firstIndex(where: { $0.id == provider.id }) else { return }
        providers[index] = provider
        Keychain.set(provider.apiKey, for: provider.id)
        if settings.activeProviderID == provider.id,
           !provider.models.contains(settings.activeModel) {
            settings.activeModel = provider.primaryModel
        }
        scheduleSave()
    }

    func setAPIKey(_ key: String, for providerID: String) {
        guard let index = providers.firstIndex(where: { $0.id == providerID }) else { return }
        providers[index].apiKey = key
        Keychain.set(key, for: providerID)
        scheduleSave()
    }

    func deleteProvider(_ providerID: String) {
        providers.removeAll { $0.id == providerID }
        Keychain.remove(providerID)
        if settings.activeProviderID == providerID, let first = providers.first {
            settings.activeProviderID = first.id
            settings.activeModel = first.primaryModel
        }
        scheduleSave()
    }

    // MARK: 提示

    func showToast(_ message: String) {
        toastTask?.cancel()
        toast = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    private func haptic() {
        guard settings.haptics else { return }
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred()
    }

    // MARK: 持久化

    private struct Persisted: Codable {
        var conversations: [Conversation]
        var settings: AppSettings
        var providers: [Provider]
        var activeConversationID: UUID?
    }

    private func update(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        } else {
            conversations.insert(conversation, at: 0)
        }
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        let snapshot = Persisted(conversations: conversations,
                                 settings: settings,
                                 providers: providers,
                                 activeConversationID: activeConversationID)
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // 写入失败时静默处理，避免打断用户
            print("DeepChat 保存失败: \(error)")
        }
    }

    private func load() {
        var loaded = false

        if let data = try? Data(contentsOf: fileURL),
           let snapshot = try? decoder.decode(Persisted.self, from: data) {
            conversations = snapshot.conversations
            settings = snapshot.settings
            activeConversationID = snapshot.activeConversationID
            providers = snapshot.providers.map { provider in
                var copy = provider
                copy.apiKey = Keychain.get(provider.id)
                return copy
            }
            loaded = true
        }

        if !loaded || providers.isEmpty {
            providers = ["deepseek", "openai", "anthropic", "gemini"].compactMap { id in
                ProviderPresets.makePreset(id: id)
            }
            providers = providers.map { provider in
                var copy = provider
                copy.apiKey = Keychain.get(provider.id)
                return copy
            }
        }

        // 兜底：把已有 Key 但模型为空的预设补全模型列表
        for index in providers.indices where providers[index].models.isEmpty {
            if let preset = ProviderPresets.makePreset(id: providers[index].id) {
                providers[index].models = preset.models
            }
        }

        if settings.activeModel.isEmpty {
            settings.activeModel = activeProvider?.primaryModel ?? "deepseek-chat"
        }
        if provider(id: settings.activeProviderID) == nil, let first = providers.first {
            settings.activeProviderID = first.id
            settings.activeModel = first.primaryModel
        }
    }
}
