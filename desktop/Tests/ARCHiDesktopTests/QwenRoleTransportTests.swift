import Foundation
import Testing
@testable import ARCHiDesktop

@Suite(.serialized)
@MainActor
struct QwenRoleTransportTests {
    @Test func eachRoleSendsExactSchemaAndReturnsOnlyCompleteBoundResult() async throws {
        let client = makeClient()
        defer { client.disconnect() }
        try await client.connect()
        for role in [LocalModelRole.memorySelection, .memoryReminder, .reasoning] {
            let request = roleRequest(role)
            let result = try await client.generate(request)
            #expect(result.requestID == request.id)
            #expect(result.role == role)
            #expect(result.model == client.metadata)
            #expect(result.elapsedMilliseconds >= 0)
            let answer = try JSONDecoder().decode(JSONValue.self, from: Data(result.text.utf8))
            #expect(answer["requestID"]?.string == request.id)
            #expect(answer["answer"]?.string == "B 🌙")
            let http = try #require(QwenRoleFixtureProtocol.state.requests.last)
            let body = try JSONDecoder().decode(JSONValue.self, from: #require(http.httpBody))
            #expect(body["format"] == request.outputSchema)
            #expect(body["stream"] == .bool(true))
            #expect(body["think"] == .bool(false))
            #expect(body["tools"] == nil)
            #expect(body["options"]?["num_ctx"] == .number(32_768))
            #expect(body["options"]?["num_predict"] == .number(4096))
            #expect(body["options"]?["temperature"] == .number(0))
            #expect(body["messages"]?.array?.count == 2)
            #expect(body["messages"]?.array?[0]["content"]?.string == request.systemInstruction)
            let content = try #require(body["messages"]?.array?[1]["content"]?.string)
            #expect(try JSONDecoder().decode(JSONValue.self, from: Data(content.utf8)) == request.input)
        }
        let requests = QwenRoleFixtureProtocol.state.requests
        #expect(requests.allSatisfy { $0.url?.host == "127.0.0.1" && $0.url?.port == 11434 })
        #expect(requests.map(\.url!.path) == ["/api/tags", "/api/show",
            "/api/tags", "/api/show", "/api/chat", "/api/tags", "/api/show", "/api/chat",
            "/api/tags", "/api/show", "/api/chat"])
    }

    @Test func resultCapturesInstalledModelIdentityBeyondConnectionLifetime() async throws {
        let client = makeClient(model: "qwen3:8b")
        try await client.connect()
        let result = try await client.generate(roleRequest())
        client.disconnect()
        #expect(client.metadata == nil)
        #expect(result.model.name == "qwen3:8b")
        #expect(result.model.family == "qwen3")
        #expect(result.model.parameterSize == "8.2B")
        #expect(result.model.quantization == "Q4_K_M")
        #expect(result.model.digest == String(repeating: "a", count: 64))
    }

    @Test func inputSchemaAndEscapedWireBytesShareOnePreflightBudget() async throws {
        let client = makeClient()
        defer { client.disconnect() }
        try await client.connect()
        let id = UUID().uuidString
        let requests = [
            LocalRoleRequest(id: id, role: .reasoning,
                input: .object(["requestID": .string(id), "source": .string(String(repeating: "é", count: 12_000))]),
                outputSchema: .object(["type": .string("object")])),
            LocalRoleRequest(id: id, role: .memorySelection,
                input: .object(["requestID": .string(id)]),
                outputSchema: .object(["type": .string("object"),
                    "description": .string(String(repeating: "s", count: 24_000))])),
            // Input is JSON encoded inside a JSON message: both escaping levels
            // count. A source-only byte check would incorrectly admit this.
            LocalRoleRequest(id: id, role: .memoryReminder,
                input: .object(["requestID": .string(id), "source": .string(String(repeating: "\"", count: 7_000))]),
                outputSchema: .object(["type": .string("object")]))
        ]
        for request in requests {
            await #expect(throws: QwenFailure.contextLimit) { try await client.generate(request) }
        }
        #expect(QwenRoleFixtureProtocol.state.requests.count == 2)
        #expect(client.metadata != nil)
    }

    @Test func invalidRequestBindingNeverSendsRoleContent() async throws {
        let client = makeClient()
        defer { client.disconnect() }
        try await client.connect()
        let id = UUID().uuidString
        for request in [
            LocalRoleRequest(id: "not-a-uuid", role: .reasoning,
                input: .object(["requestID": .string("not-a-uuid")]), outputSchema: .object([:])),
            LocalRoleRequest(id: id, role: .reasoning,
                input: .object(["requestID": .string(UUID().uuidString)]), outputSchema: .object([:])),
            LocalRoleRequest(id: id, role: .reasoning,
                input: .object(["requestID": .string(id)]), outputSchema: .string("json")),
            LocalRoleRequest(id: id, role: .reasoning,
                input: .object(["requestID": .string(id)]), outputSchema: .object(["maximum": .number(.infinity)]))
        ] {
            await #expect(throws: QwenFailure.invalidResponse) { try await client.generate(request) }
        }
        #expect(QwenRoleFixtureProtocol.state.requests.count == 2)
    }

    @Test func EOFWithoutDoneAndWrongStreamIdentityCannotYieldRoleResult() async throws {
        for mode in [QwenRoleFixtureMode.noDone, .wrongModel] {
            let client = makeClient(mode)
            defer { client.disconnect() }
            try await client.connect()
            await #expect(throws: QwenFailure.invalidResponse) { try await client.generate(roleRequest()) }
            #expect(client.metadata == nil)
        }
    }

    @Test func completeNonJSONRemainsRawForReceivingRoleValidator() async throws {
        let client = makeClient(.nonJSON)
        defer { client.disconnect() }
        try await client.connect()
        let result = try await client.generate(roleRequest())
        #expect(result.text == "Untrusted prose instead of JSON")
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(JSONValue.self, from: Data(result.text.utf8))
        }
        #expect(result.model == client.metadata)
    }

    @Test func changedAliasPreventsRoleGeneration() async throws {
        let client = makeClient(.changedDigest)
        defer { client.disconnect() }
        try await client.connect()
        await #expect(throws: QwenFailure.modelChanged) { try await client.generate(roleRequest()) }
        let chats = QwenRoleFixtureProtocol.state.requests.filter { $0.url?.path == "/api/chat" }
        #expect(chats.isEmpty)
        #expect(client.metadata == nil)
    }

    @Test func canceledRoleCannotFinishOrDisconnectAReplacement() async throws {
        let client = makeClient(.holdFirstChat)
        defer { client.disconnect() }
        try await client.connect()
        let oldRequest = roleRequest(.memorySelection)
        let old = Task { try await client.generate(oldRequest) }
        try await waitForChat()
        await #expect(throws: QwenFailure.busy) { try await client.generate(roleRequest()) }
        old.cancel()
        // Reconnect before joining the old task, so its queued cancellation and
        // catch/defer paths run against a potentially newer generation owner.
        try await client.connect()
        let replacementRequest = roleRequest(.reasoning)
        let replacement = try await client.generate(replacementRequest)
        await #expect(throws: QwenFailure.stopped) { try await old.value }
        #expect(replacement.requestID == replacementRequest.id)
        #expect(replacement.requestID != oldRequest.id)
        #expect(client.metadata == replacement.model)
    }

    private func makeClient(_ mode: QwenRoleFixtureMode = .normal,
                            model: String = QwenAssistant.defaultModel) -> QwenAssistant {
        QwenRoleFixtureProtocol.state.reset(mode: mode, model: model)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QwenRoleFixtureProtocol.self]
        return QwenAssistant(model: model, configuration: configuration)
    }

    private func roleRequest(_ role: LocalModelRole = .reasoning) -> LocalRoleRequest {
        let id = UUID().uuidString
        return LocalRoleRequest(id: id, role: role,
            input: .object(["requestID": .string(id), "source": .string("Option A\nOption B 🌙")]),
            outputSchema: .object(["type": .string("object"), "additionalProperties": .bool(false),
                "required": .array([.string("requestID"), .string("answer")]),
                "properties": .object(["requestID": .object(["type": .string("string")]),
                    "answer": .object(["type": .string("string")])])]))
    }

    private func waitForChat() async throws {
        for _ in 0..<100 {
            if QwenRoleFixtureProtocol.state.requests.contains(where: { $0.url?.path == "/api/chat" }) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Role fixture did not receive the request")
        throw QwenFailure.timedOut
    }
}

private enum QwenRoleFixtureMode: Sendable {
    case normal, noDone, nonJSON, changedDigest, wrongModel, holdFirstChat
}

private final class QwenRoleFixtureState: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URLRequest] = []
    private var mode: QwenRoleFixtureMode = .normal
    private var model = "qwen3.5:9b"
    var requests: [URLRequest] { lock.withLock { stored } }
    func reset(mode: QwenRoleFixtureMode, model: String) {
        lock.withLock { stored = []; self.mode = mode; self.model = model }
    }
    func record(_ request: URLRequest) -> (mode: QwenRoleFixtureMode, model: String, tags: Int, chats: Int) {
        lock.withLock {
            stored.append(request)
            return (mode, model, stored.filter { $0.url?.path == "/api/tags" }.count,
                stored.filter { $0.url?.path == "/api/chat" }.count)
        }
    }
}

private final class QwenRoleFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let state = QwenRoleFixtureState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            captured.httpBody = data
        }
        let fixture = Self.state.record(captured)
        let family = fixture.model == "qwen3:8b" ? "qwen3" : "qwen35"
        let details: JSONValue = .object(["format": .string("gguf"), "family": .string(family),
            "parameter_size": .string(fixture.model == "qwen3:8b" ? "8.2B" : "9.7B"),
            "quantization_level": .string("Q4_K_M")])
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/x-ndjson"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        switch request.url!.path {
        case "/api/tags":
            send(.object(["models": .array([.object(["name": .string(fixture.model), "model": .string(fixture.model),
                "details": details, "digest": .string(String(repeating:
                    fixture.mode == .changedDigest && fixture.tags > 1 ? "b" : "a", count: 64))])])]))
        case "/api/show":
            send(.object(["details": details, "model_info": .object(["general.architecture": .string(family)]),
                "capabilities": .array([.string("completion"), .string("thinking")])]))
        case "/api/chat":
            let body = try! JSONDecoder().decode(JSONValue.self, from: captured.httpBody!)
            let input = try! JSONDecoder().decode(JSONValue.self,
                from: Data(body["messages"]!.array![1]["content"]!.string!.utf8))
            let object: JSONValue = .object(["requestID": input["requestID"]!, "answer": .string("B 🌙")])
            let answer = fixture.mode == .nonJSON ? "Untrusted prose instead of JSON"
                : String(decoding: try! JSONEncoder().encode(object), as: UTF8.self)
            let split = answer.index(answer.startIndex, offsetBy: answer.count / 2)
            let model = fixture.mode == .wrongModel ? "qwen-other" : fixture.model
            send(chunk(String(answer[..<split]), model: model, done: false), newline: true)
            if fixture.mode == .holdFirstChat && fixture.chats == 1 { return }
            send(chunk(String(answer[split...]), model: model, done: false), newline: true)
            if fixture.mode != .noDone { send(chunk("", model: model, done: true), newline: true) }
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    private func send(_ value: JSONValue, newline: Bool = false) {
        var data = try! JSONEncoder().encode(value)
        if newline { data.append(10) }
        let split = data.count / 2
        client?.urlProtocol(self, didLoad: data.prefix(split))
        client?.urlProtocol(self, didLoad: data.suffix(data.count - split))
    }

    private func chunk(_ text: String, model: String, done: Bool) -> JSONValue {
        .object(["model": .string(model), "message": .object(["role": .string("assistant"),
            "content": .string(text)]), "done": .bool(done), "done_reason": .string("stop")])
    }
}
