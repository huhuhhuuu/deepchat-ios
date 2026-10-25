//
//  APIClient.swift
//  DeepChat
//
//  三种协议（OpenAI 兼容 / Anthropic / Gemini）的直连请求与流式解析
//

import Foundation

// MARK: - 事件

enum StreamEvent {
    case text(String)
    case reasoning(String)
    case usage(TokenUsage)
    case finished(String?)
}

// MARK: - 错误

struct APIError: LocalizedError, Identifiable {
    var id: String { "\(status)-\(message)" }
    var status: Int
    var message: String

    var errorDescription: String? { message }

    var hint: String? {
        switch status {
        case 0: return "请检查网络连接，或确认 Base URL 可以访问。"
        case 401: return "API Key 无效或未填写，请到「设置 → 模型服务」检查。"
        case 403: return "该 Key 没有访问权限，或不允许来自本应用。"
        case 404: return "接口地址或模型名不正确，Base URL 一般以 /v1 结尾。"
        case 429: return "请求过于频繁，或余额 / 配额不足。"
        default:
            return status >= 500 ? "上游服务异常，稍后重试。" : nil
        }
    }
}

// MARK: - 请求描述

struct ChatRequest {
    var provider: Provider
    var model: String
    var messages: [ChatMessage]
    var systemPrompt: String
    var stream: Bool
    var temperature: Double
    var topP: Double
    var maxTokens: Int
}

// MARK: - 客户端

final class APIClient {

    static let shared = APIClient()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 900
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    // MARK: 地址处理

    static func normalizedBase(_ raw: String, kind: APIKind) -> String {
        var base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/chat/completions") {
            base = String(base.dropLast("/chat/completions".count))
        }
        if base.hasSuffix("/messages") {
            base = String(base.dropLast("/messages".count))
        }
        if kind == .gemini && base.hasSuffix("/models") {
            base = String(base.dropLast("/models".count))
        }
        return base
    }

    private static func isReasoningModel(_ model: String) -> Bool {
        let lower = model.lowercased()
        return lower.hasPrefix("o1") || lower.hasPrefix("o3") || lower.hasPrefix("o4") || lower.hasPrefix("gpt-5")
    }

    // MARK: 构造请求

    private func buildRequest(_ request: ChatRequest) throws -> URLRequest {
        let provider = request.provider
        let base = Self.normalizedBase(provider.baseURL, kind: provider.kind)
        guard !base.isEmpty, let baseURL = URL(string: base) else {
            throw APIError(status: 0, message: "Base URL 无效，请检查模型服务配置")
        }

        var url: URL
        var headers: [String: String] = ["Content-Type": "application/json"]
        var body: [String: Any] = [:]

        switch provider.kind {
        case .openai:
            url = baseURL.appendingPathComponent("chat/completions")
            headers["Authorization"] = "Bearer \(provider.apiKey)"

            var messages: [[String: Any]] = []
            let system = request.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !system.isEmpty {
                messages.append(["role": "system", "content": system])
            }
            for message in request.messages where !message.text.isEmpty {
                messages.append(["role": message.role.rawValue, "content": message.text])
            }

            body["model"] = request.model
            body["messages"] = messages
            body["stream"] = request.stream

            let reasoning = Self.isReasoningModel(request.model)
            if !reasoning {
                body["temperature"] = request.temperature
                if request.topP < 1 { body["top_p"] = request.topP }
            }
            if request.maxTokens > 0 {
                body[reasoning ? "max_completion_tokens" : "max_tokens"] = request.maxTokens
            }

        case .anthropic:
            url = baseURL.appendingPathComponent("messages")
            headers["x-api-key"] = provider.apiKey
            headers["anthropic-version"] = "2023-06-01"
            headers["anthropic-dangerous-direct-browser-access"] = "true"

            var messages: [[String: Any]] = []
            for message in request.messages where !message.text.isEmpty && message.role != .system {
                messages.append([
                    "role": message.role == .assistant ? "assistant" : "user",
                    "content": message.text
                ])
            }
            body["model"] = request.model
            body["messages"] = messages
            body["max_tokens"] = request.maxTokens > 0 ? request.maxTokens : 4096
            body["stream"] = request.stream
            body["temperature"] = min(1.0, max(0.0, request.temperature))
            if request.topP < 1 { body["top_p"] = request.topP }
            let system = request.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !system.isEmpty { body["system"] = system }

        case .gemini:
            let cleanModel = request.model.hasPrefix("models/")
                ? String(request.model.dropFirst("models/".count))
                : request.model
            let method = request.stream ? "streamGenerateContent" : "generateContent"
            var components = URLComponents(string: base + "/models/" + cleanModel + ":" + method)
            if request.stream {
                components?.queryItems = [URLQueryItem(name: "alt", value: "sse")]
            }
            guard let finalURL = components?.url else {
                throw APIError(status: 0, message: "Gemini 接口地址无效")
            }
            url = finalURL
            headers["x-goog-api-key"] = provider.apiKey

            var contents: [[String: Any]] = []
            for message in request.messages where !message.text.isEmpty && message.role != .system {
                contents.append([
                    "role": message.role == .assistant ? "model" : "user",
                    "parts": [["text": message.text]]
                ])
            }
            body["contents"] = contents

            let system = request.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !system.isEmpty {
                body["systemInstruction"] = ["parts": [["text": system]]]
            }

            var generation: [String: Any] = [:]
            generation["temperature"] = request.temperature
            if request.topP < 1 { generation["topP"] = request.topP }
            if request.maxTokens > 0 { generation["maxOutputTokens"] = request.maxTokens }
            if request.model.contains("2.5") || request.model.contains("gemini-3") {
                generation["thinkingConfig"] = ["includeThoughts": true]
            }
            body["generationConfig"] = generation
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.allHTTPHeaderFields = headers
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        urlRequest.setValue(request.stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("DeepChat-iOS/1.0", forHTTPHeaderField: "User-Agent")
        return urlRequest
    }

    // MARK: 流式对话

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try buildRequest(request)
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw APIError(status: 0, message: "响应无效")
                    }
                    if http.statusCode >= 400 {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw APIError(status: http.statusCode,
                                       message: Self.decodeError(data: data, status: http.statusCode))
                    }

                    if request.stream {
                        try await consumeSSE(bytes.lines, kind: request.provider.kind, continuation: continuation)
                    } else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        try Self.decodeWhole(data: data, kind: request.provider.kind, continuation: continuation)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as APIError {
                    continuation.finish(throwing: error)
                } catch {
                    let nsError = error as NSError
                    if nsError.code == NSURLErrorCancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: APIError(status: 0,
                                                              message: "网络请求失败：\(error.localizedDescription)"))
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func consumeSSE<L: AsyncSequence>(
        _ lines: L,
        kind: APIKind,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws where L.Element == String {
        var eventName = ""

        for try await rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                eventName = ""
                continue
            }
            if line.hasPrefix(":") { continue }
            if line.hasPrefix("event:") {
                eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard line.hasPrefix("data:") else { continue }
            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if payload.isEmpty { continue }
            if payload == "[DONE]" { return }
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let json = object as? [String: Any] else { continue }

            try Self.handle(json: json, event: eventName, kind: kind, continuation: continuation)
        }
    }

    // MARK: 单个事件

    private static func handle(
        json: [String: Any],
        event: String,
        kind: APIKind,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) throws {
        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "接口返回错误"
            throw APIError(status: 400, message: message)
        }

        switch kind {
        case .anthropic:
            let type = (json["type"] as? String) ?? event
            switch type {
            case "content_block_delta":
                guard let delta = json["delta"] as? [String: Any] else { return }
                if let text = delta["text"] as? String, !text.isEmpty {
                    continuation.yield(.text(text))
                } else if let thinking = delta["thinking"] as? String, !thinking.isEmpty {
                    continuation.yield(.reasoning(thinking))
                }
            case "message_start":
                if let message = json["message"] as? [String: Any],
                   let usage = message["usage"] as? [String: Any] {
                    continuation.yield(.usage(usageOf(usage)))
                }
            case "message_delta":
                if let usage = json["usage"] as? [String: Any] {
                    continuation.yield(.usage(usageOf(usage)))
                }
                if let delta = json["delta"] as? [String: Any],
                   let stop = delta["stop_reason"] as? String {
                    continuation.yield(.finished(stop))
                }
            case "error":
                let error = json["error"] as? [String: Any]
                throw APIError(status: 400, message: error?["message"] as? String ?? "Claude 返回错误")
            default:
                break
            }

        case .gemini:
            if let candidates = json["candidates"] as? [[String: Any]],
               let first = candidates.first {
                if let content = first["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]] {
                    for part in parts {
                        guard let text = part["text"] as? String, !text.isEmpty else { continue }
                        let isThought = (part["thought"] as? Bool) ?? false
                        continuation.yield(isThought ? .reasoning(text) : .text(text))
                    }
                }
                if let finish = first["finishReason"] as? String, finish != "FINISH_REASON_UNSPECIFIED" {
                    continuation.yield(.finished(finish))
                }
            }
            if let meta = json["usageMetadata"] as? [String: Any] {
                var usage = TokenUsage()
                usage.prompt = meta["promptTokenCount"] as? Int ?? 0
                usage.completion = meta["candidatesTokenCount"] as? Int ?? 0
                continuation.yield(.usage(usage))
            }

        case .openai:
            if let choices = json["choices"] as? [[String: Any]], let first = choices.first {
                if let delta = first["delta"] as? [String: Any] {
                    if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
                        continuation.yield(.reasoning(reasoning))
                    } else if let reasoning = delta["reasoning"] as? String, !reasoning.isEmpty {
                        continuation.yield(.reasoning(reasoning))
                    }
                    if let text = delta["content"] as? String, !text.isEmpty {
                        continuation.yield(.text(text))
                    } else if let parts = delta["content"] as? [[String: Any]] {
                        for part in parts where (part["type"] as? String) == "text" {
                            if let text = part["text"] as? String, !text.isEmpty {
                                continuation.yield(.text(text))
                            }
                        }
                    }
                }
                if let finish = first["finish_reason"] as? String {
                    continuation.yield(.finished(finish))
                }
            }
            if let usage = json["usage"] as? [String: Any] {
                var value = TokenUsage()
                value.prompt = usage["prompt_tokens"] as? Int ?? 0
                value.completion = usage["completion_tokens"] as? Int ?? 0
                continuation.yield(.usage(value))
            }
        }
    }

    private static func usageOf(_ usage: [String: Any]) -> TokenUsage {
        var value = TokenUsage()
        value.prompt = usage["input_tokens"] as? Int ?? 0
        value.completion = usage["output_tokens"] as? Int ?? 0
        return value
    }

    // MARK: 非流式整体解析

    private static func decodeWhole(
        data: Data,
        kind: APIKind,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else {
            throw APIError(status: 0, message: "无法解析接口返回内容")
        }

        switch kind {
        case .openai:
            if let choices = json["choices"] as? [[String: Any]], let first = choices.first {
                if let message = first["message"] as? [String: Any] {
                    if let reasoning = message["reasoning_content"] as? String, !reasoning.isEmpty {
                        continuation.yield(.reasoning(reasoning))
                    }
                    if let text = message["content"] as? String, !text.isEmpty {
                        continuation.yield(.text(text))
                    }
                }
            }
            if let usage = json["usage"] as? [String: Any] {
                var value = TokenUsage()
                value.prompt = usage["prompt_tokens"] as? Int ?? 0
                value.completion = usage["completion_tokens"] as? Int ?? 0
                continuation.yield(.usage(value))
            }

        case .anthropic:
            if let blocks = json["content"] as? [[String: Any]] {
                for block in blocks {
                    let type = block["type"] as? String
                    if type == "text", let text = block["text"] as? String {
                        continuation.yield(.text(text))
                    } else if type == "thinking", let thinking = block["thinking"] as? String {
                        continuation.yield(.reasoning(thinking))
                    }
                }
            }
            if let usage = json["usage"] as? [String: Any] {
                continuation.yield(.usage(usageOf(usage)))
            }

        case .gemini:
            if let candidates = json["candidates"] as? [[String: Any]],
               let first = candidates.first,
               let content = first["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]] {
                for part in parts {
                    guard let text = part["text"] as? String, !text.isEmpty else { continue }
                    let isThought = (part["thought"] as? Bool) ?? false
                    continuation.yield(isThought ? .reasoning(text) : .text(text))
                }
            }
            if let meta = json["usageMetadata"] as? [String: Any] {
                var usage = TokenUsage()
                usage.prompt = meta["promptTokenCount"] as? Int ?? 0
                usage.completion = meta["candidatesTokenCount"] as? Int ?? 0
                continuation.yield(.usage(usage))
            }
        }
        continuation.yield(.finished(nil))
    }

    // MARK: 错误文本

    private static func decodeError(data: Data, status: Int) -> String {
        var message = ""
        if let object = try? JSONSerialization.jsonObject(with: data),
           let json = object as? [String: Any] {
            if let error = json["error"] as? [String: Any] {
                message = error["message"] as? String
                    ?? error["msg"] as? String
                    ?? error["code"] as? String
                    ?? ""
            } else if let error = json["error"] as? String {
                message = error
            } else if let value = json["message"] as? String {
                message = value
            }
        }
        if message.isEmpty {
            let raw = String(data: data, encoding: .utf8) ?? ""
            let stripped = raw.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            message = String(stripped.prefix(240))
        }
        if message.isEmpty { message = "HTTP \(status)" }
        return message
    }

    // MARK: 模型列表

    func listModels(_ provider: Provider) async throws -> [String] {
        let base = Self.normalizedBase(provider.baseURL, kind: provider.kind)
        guard var components = URLComponents(string: base) else {
            throw APIError(status: 0, message: "Base URL 无效")
        }
        var headers: [String: String] = ["Accept": "application/json"]

        switch provider.kind {
        case .openai:
            components.path += "/models"
            headers["Authorization"] = "Bearer \(provider.apiKey)"
        case .anthropic:
            components.path += "/models"
            headers["x-api-key"] = provider.apiKey
            headers["anthropic-version"] = "2023-06-01"
        case .gemini:
            components.path += "/models"
            headers["x-goog-api-key"] = provider.apiKey
        }

        guard let url = components.url else {
            throw APIError(status: 0, message: "接口地址无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = headers

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: 0, message: "响应无效")
        }
        if http.statusCode >= 400 {
            throw APIError(status: http.statusCode, message: Self.decodeError(data: data, status: http.statusCode))
        }

        guard let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else {
            throw APIError(status: 0, message: "无法解析模型列表")
        }

        var ids: [String] = []
        if let list = json["data"] as? [[String: Any]] {
            ids = list.compactMap { $0["id"] as? String }
        } else if let list = json["models"] as? [[String: Any]] {
            ids = list.compactMap { item in
                (item["name"] as? String)?.replacingOccurrences(of: "models/", with: "")
            }
        }
        return ids.sorted()
    }
}
