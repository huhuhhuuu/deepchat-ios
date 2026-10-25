//
//  Models.swift
//  DeepChat
//
//  数据模型、API 供应商预设、应用设置
//

import Foundation
import SwiftUI

// MARK: - 角色

enum ChatRole: String, Codable, Hashable {
    case system
    case user
    case assistant
}

// MARK: - 用量

struct TokenUsage: Codable, Hashable {
    var prompt: Int = 0
    var completion: Int = 0

    var total: Int { prompt + completion }
}

// MARK: - 消息

struct ChatMessage: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var role: ChatRole
    var text: String = ""
    var reasoning: String = ""
    var model: String = ""
    var createdAt: Date = Date()
    var error: String?
    var usage: TokenUsage?
    /// 深度思考耗时（秒）
    var reasoningSeconds: Double = 0
    var isStreaming: Bool = false

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && reasoning.isEmpty
    }
}

// MARK: - 会话

struct Conversation: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String = "新对话"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var providerID: String = "deepseek"
    var model: String = "deepseek-chat"
    var messages: [ChatMessage] = []

    /// 列表里显示的最后一条内容
    var snippet: String {
        if let last = messages.last(where: { !$0.text.isEmpty }) {
            return last.text
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "空对话"
    }

    var isEmptyConversation: Bool { messages.isEmpty }
}

// MARK: - 协议类型

enum APIKind: String, Codable, CaseIterable, Identifiable {
    case openai
    case anthropic
    case gemini

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openai: return "OpenAI 兼容"
        case .anthropic: return "Anthropic 原生"
        case .gemini: return "Gemini 原生"
        }
    }

    var hint: String {
        switch self {
        case .openai: return "DeepSeek、OpenAI、Kimi、智谱、硅基流动、中转站等"
        case .anthropic: return "api.anthropic.com/v1"
        case .gemini: return "generativelanguage.googleapis.com/v1beta"
        }
    }
}

// MARK: - 供应商

struct Provider: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var kind: APIKind
    var baseURL: String
    var models: [String]
    var badge: String
    var note: String
    var keyURL: String
    var isBuiltin: Bool
    /// 只在内存中保存，落盘到 Keychain
    var apiKey: String = ""

    enum CodingKeys: String, CodingKey {
        case id, name, kind, baseURL, models, badge, note, keyURL, isBuiltin
    }

    var isConfigured: Bool {
        !apiKey.isEmpty || baseURL.contains("localhost") || baseURL.contains("127.0.0.1")
    }

    var host: String {
        URL(string: baseURL)?.host ?? baseURL
    }

    var primaryModel: String { models.first ?? "" }
}

// MARK: - 预设

enum ProviderPresets {
    static let all: [Provider] = [
        Provider(id: "deepseek",
                 name: "DeepSeek",
                 kind: .openai,
                 baseURL: "https://api.deepseek.com/v1",
                 models: ["deepseek-chat", "deepseek-reasoner"],
                 badge: "DS",
                 note: "深度思考 · 官方接口",
                 keyURL: "https://platform.deepseek.com/api_keys",
                 isBuiltin: true),
        Provider(id: "openai",
                 name: "OpenAI",
                 kind: .openai,
                 baseURL: "https://api.openai.com/v1",
                 models: ["gpt-4o", "gpt-4o-mini", "gpt-4.1", "o3-mini"],
                 badge: "AI",
                 note: "GPT 系列官方接口",
                 keyURL: "https://platform.openai.com/api-keys",
                 isBuiltin: true),
        Provider(id: "anthropic",
                 name: "Anthropic Claude",
                 kind: .anthropic,
                 baseURL: "https://api.anthropic.com/v1",
                 models: ["claude-sonnet-4-5", "claude-opus-4-1", "claude-3-7-sonnet-latest"],
                 badge: "CL",
                 note: "Claude 原生协议",
                 keyURL: "https://console.anthropic.com/settings/keys",
                 isBuiltin: true),
        Provider(id: "gemini",
                 name: "Google Gemini",
                 kind: .gemini,
                 baseURL: "https://generativelanguage.googleapis.com/v1beta",
                 models: ["gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.0-flash"],
                 badge: "GM",
                 note: "Gemini 原生协议",
                 keyURL: "https://aistudio.google.com/app/apikey",
                 isBuiltin: true),
        Provider(id: "openrouter",
                 name: "OpenRouter",
                 kind: .openai,
                 baseURL: "https://openrouter.ai/api/v1",
                 models: ["anthropic/claude-sonnet-4.5", "openai/gpt-4o", "deepseek/deepseek-chat"],
                 badge: "OR",
                 note: "一个 Key 用遍各家模型",
                 keyURL: "https://openrouter.ai/keys",
                 isBuiltin: true),
        Provider(id: "moonshot",
                 name: "月之暗面 Kimi",
                 kind: .openai,
                 baseURL: "https://api.moonshot.cn/v1",
                 models: ["kimi-k2-0905-preview", "moonshot-v1-32k", "moonshot-v1-128k"],
                 badge: "KM",
                 note: "长上下文",
                 keyURL: "https://platform.moonshot.cn/console/api-keys",
                 isBuiltin: true),
        Provider(id: "zhipu",
                 name: "智谱 GLM",
                 kind: .openai,
                 baseURL: "https://open.bigmodel.cn/api/paas/v4",
                 models: ["glm-4.6", "glm-4.5", "glm-4-flash"],
                 badge: "GL",
                 note: "GLM 系列",
                 keyURL: "https://open.bigmodel.cn/usercenter/apikeys",
                 isBuiltin: true),
        Provider(id: "dashscope",
                 name: "阿里通义千问",
                 kind: .openai,
                 baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                 models: ["qwen-max", "qwen-plus", "qwen-turbo"],
                 badge: "QW",
                 note: "兼容模式接口",
                 keyURL: "https://bailian.console.aliyun.com/",
                 isBuiltin: true),
        Provider(id: "siliconflow",
                 name: "硅基流动",
                 kind: .openai,
                 baseURL: "https://api.siliconflow.cn/v1",
                 models: ["deepseek-ai/DeepSeek-V3", "Qwen/Qwen2.5-72B-Instruct"],
                 badge: "SF",
                 note: "聚合开源模型",
                 keyURL: "https://cloud.siliconflow.cn/account/ak",
                 isBuiltin: true),
        Provider(id: "ollama",
                 name: "本机 Ollama",
                 kind: .openai,
                 baseURL: "http://localhost:11434/v1",
                 models: ["llama3.1", "qwen2.5"],
                 badge: "OL",
                 note: "本机运行，无需 Key",
                 keyURL: "",
                 isBuiltin: true)
    ]

    static func makePreset(id: String) -> Provider? {
        all.first { $0.id == id }
    }

    static func makeCustom() -> Provider {
        Provider(id: "custom-" + UUID().uuidString.prefix(8),
                 name: "自定义服务",
                 kind: .openai,
                 baseURL: "",
                 models: [],
                 badge: "＋",
                 note: "任意 OpenAI 兼容地址",
                 keyURL: "",
                 isBuiltin: false)
    }
}

// MARK: - 外观

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - 设置

struct AppSettings: Codable {
    var stream: Bool = true
    var temperature: Double = 0.7
    var topP: Double = 1.0
    var maxTokens: Int = 0
    var systemPrompt: String = ""
    var showReasoning: Bool = true
    var appearance: AppearanceMode = .system
    var activeProviderID: String = "deepseek"
    var activeModel: String = "deepseek-chat"
    var haptics: Bool = true
    /// 输入框里的“深度思考”开关
    var deepThinking: Bool = true
}

// MARK: - 供应商里的“深度思考”模型映射

enum ThinkingModels {
    /// 推理模型关键词，用来在“深度思考”开关与模型之间做匹配
    static func reasoningModel(in provider: Provider) -> String? {
        let keys = ["reasoner", "-r1", "r1", "thinking", "o1", "o3", "o4", "glm-4.6", "qwq"]
        return provider.models.first { model in
            let lower = model.lowercased()
            return keys.contains { lower.contains($0) }
        }
    }

    static func chatModel(in provider: Provider) -> String? {
        let reasoning = reasoningModel(in: provider)
        return provider.models.first { $0 != reasoning }
    }
}
