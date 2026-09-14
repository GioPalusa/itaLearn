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

    @Test func discoveryUsesBoundedStrictResponsesAndValidatesReturnedData() async throws {
        StubURLProtocol.install { request in
            let body = try #require(JSONSerialization.jsonObject(with: Self.body(request)) as? [String: Any])
            #expect(body["max_output_tokens"] as? Int == 2500)
            #expect(body["store"] as? Bool == false)
            let format = try #require((body["text"] as? [String: Any])?["format"] as? [String: Any])
            #expect(format["name"] as? String == "journey_discovery_v1")
            #expect(format["strict"] as? Bool == true)
            let payload = String(decoding: try JSONEncoder().encode(discoveryProbe()), as: UTF8.self)
            return (200, try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [
                ["type": "message", "content": [["type": "output_text", "text": payload]]]
            ]]))
        }
        let service = OpenAIDiscoveryService(client: client())
        var request = try discoveryRequest()
        #expect(try await service.reply(to: request).mode == .write)
        request.reading = .newScript
        await #expect(throws: LearningValidationError.self) { try await service.reply(to: request) }
    }

    @Test func guidedPackRoundTripsThroughResponsesAndRejectsWrongCourse() async throws {
        StubURLProtocol.install { request in
            let body = try #require(JSONSerialization.jsonObject(with: Self.body(request)) as? [String: Any])
            #expect(body["max_output_tokens"] as? Int == 8000)
            let text = try #require(body["text"] as? [String: Any])
            let format = try #require(text["format"] as? [String: Any])
            #expect(format["name"] as? String == "guided_journey_v1")
            #expect(format["strict"] as? Bool == true)
            let payload = String(decoding: try JSONEncoder().encode(journeyExamplePack()), as: UTF8.self)
            return (200, try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [
                ["type": "message", "content": [["type": "output_text", "text": payload]]]
            ]]))
        }
        let service = OpenAIJourneyService(client: client())
        let progress = JourneyProgress(profile: JourneyProfile(hasSpoken: true, goal: "Resa"))
        let request = try JourneyRequest(course: LanguageCourse(target: .italian, native: .swedish), progress: progress, track: .mission, topic: "Hälsa", tone: "Warm")
        #expect(try await service.generate(request).steps.count == 3)
        var wrongCourse = request
        wrongCourse.course = LanguageCourse(target: .english, native: .swedish)
        await #expect(throws: LearningValidationError.self) { try await service.generate(wrongCourse) }
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

    @Test(arguments: [LearningLanguage.swedish, .english])
    func helpUsesLunaWithNativeLanguageAndCurrentExercise(native: LearningLanguage) async throws {
        StubURLProtocol.install { request in
            let body = try #require(JSONSerialization.jsonObject(with: Self.body(request)) as? [String: Any])
            #expect(body["model"] as? String == OpenAIClient.teacherModel)
            #expect(body["store"] as? Bool == false)
            let instructions = try #require(body["instructions"] as? String)
            #expect(instructions.contains("Write explanations in \(native.englishName)"))
            let input = try #require(body["input"] as? [[String: Any]])
            let content = try #require(input.first?["content"] as? String)
            let payload = try #require(JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any])
            let exercise = try #require(payload["exercise"] as? [String: Any])
            #expect(exercise["task"] as? String == "Beställ en kaffe")
            #expect(exercise["draft"] as? String == "Jag vill säga tack")
            #expect(payload["question"] as? String == "Vad betyder vorrei?")
            let format = try #require((body["text"] as? [String: Any])?["format"] as? [String: Any])
            #expect(format["name"] as? String == "exercise_help_v1")
            #expect(format["strict"] as? Bool == true)
            let response = "{\"explanation\":\"Vorrei betyder jag skulle vilja ha.\"}"
            return (200, try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [
                ["content": [["type": "output_text", "text": response]]]
            ]]))
        }
        let context = ExerciseHelpContext(course: LanguageCourse(target: .italian, native: native),
                                          activity: .lesson, task: "Beställ en kaffe",
                                          draft: "Jag vill säga tack", tone: "Patient")
        let service = OpenAILearningService(client: client())
        let reply = try await service.help(ExerciseHelpRequest(exercise: context, kind: .meaning,
                                                             question: "Vad betyder vorrei?", previousHelp: []))
        #expect(reply.explanation == "Vorrei betyder jag skulle vilja ha.")
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
