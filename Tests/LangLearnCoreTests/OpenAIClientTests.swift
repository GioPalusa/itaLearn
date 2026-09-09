import Foundation
import Testing
@testable import LangLearnCore

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    static func install(_ value: @escaping @Sendable (URLRequest) throws -> (Int, Data)) {
        lock.lock(); defer { lock.unlock() }; handler = value
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()
        do {
            let handle = try #require(handler)
            let (status, data) = try handle(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

@Suite("OpenAI transport", .serialized)
struct OpenAIClientTests {
    private func client(key: String? = "unit-test-only") -> OpenAIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return OpenAIClient(session: URLSession(configuration: config), keyProvider: { key })
    }

    private func response(_ client: OpenAIClient) async throws -> StructuredResponse<AssessmentQuestion> {
        try await client.respond(model: OpenAIClient.teacherModel, instructions: "Teach Italian", input: "Ciao",
                                 schemaName: "question", schema: LearningSchema.question, as: AssessmentQuestion.self)
    }

    private static func body(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 2048)
        while stream.hasBytesAvailable {
            let length = stream.read(&buffer, maxLength: buffer.count)
            if length <= 0 { break }
            data.append(buffer, count: length)
        }
        return data
    }

    @Test func sendsStrictSchemaToRequestedModelWithoutRemoteConversationStorage() async throws {
        StubURLProtocol.install { request in
            #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer unit-test-only")
            let body = try #require(JSONSerialization.jsonObject(with: Self.body(request)) as? [String: Any])
            #expect(body["model"] as? String == "gpt-5.6-luna")
            #expect(body["store"] as? Bool == false)
            let text = try #require(body["text"] as? [String: Any])
            let format = try #require(text["format"] as? [String: Any])
            #expect(format["strict"] as? Bool == true)
            #expect(format["type"] as? String == "json_schema")
            let payload = "{\"question\":\"Come stai?\",\"translation\":\"\",\"skill\":\"greetings\"}"
            return (200, try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [
                ["type": "reasoning", "summary": []],
                ["type": "message", "content": [["type": "output_text", "text": payload]]]
            ]]))
        }
        let result = try await response(client())
        #expect(result.value.question == "Come stai?")
        #expect(try JSONDecoder().decode(AssessmentQuestion.self, from: result.json).skill == "greetings")
    }

    @Test(arguments: [401, 403, 404, 429, 500])
    func handlesAPIErrorsWithoutEchoingProviderBody(status: Int) async {
        StubURLProtocol.install { _ in (status, Data("private provider content".utf8)) }
        do {
            _ = try await response(client())
            Issue.record("Expected an API error")
        } catch {
            #expect(error is OpenAIError)
            #expect(!error.localizedDescription.contains("private provider content"))
        }
    }

    @Test(arguments: ["refusal", "incomplete", "invalidJSON", "missingOutput"])
    func rejectsUnusableResponses(kind: String) async {
        StubURLProtocol.install { _ in
            switch kind {
            case "refusal":
                return (200, Data(#"{"status":"completed","output":[{"content":[{"type":"refusal","refusal":"No"}]}]}"#.utf8))
            case "incomplete": return (200, Data(#"{"status":"incomplete","output":[]}"#.utf8))
            case "invalidJSON": return (200, Data(#"{"status":"completed","output":[{"content":[{"type":"output_text","text":"no json"}]}]}"#.utf8))
            default: return (200, Data(#"{"status":"completed","output":[]}"#.utf8))
            }
        }
        await #expect(throws: (any Error).self) { _ = try await response(client()) }
    }

    @Test func missingKeyAndCancellationNeverReachTransport() async {
        StubURLProtocol.install { _ in Issue.record("Unexpected network request"); return (500, Data()) }
        await #expect(throws: OpenAIError.self) { _ = try await response(client(key: nil)) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await response(client())
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }
}
