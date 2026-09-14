import Foundation

nonisolated enum OpenAIError: LocalizedError {
    case missingKey, unauthorized, rateLimited, modelUnavailable, refused, incomplete, connection, server
    var errorDescription: String? {
        switch self {
        case .missingKey: "Lägg till din OpenAI API-nyckel i Inställningar."
        case .unauthorized: "API-nyckeln nekades. Byt nyckel i Inställningar och försök igen."
        case .rateLimited: "OpenAI har nått en användningsgräns. Kontrollera API-saldo och gränser, eller försök senare."
        case .modelUnavailable: "Ditt API-projekt saknar åtkomst till den valda modellen. Kontrollera modellåtkomst hos OpenAI."
        case .refused: "Läraren kunde inte hjälpa till med det svaret. Ändra ditt svar och försök igen."
        case .incomplete: "Svaret blev inte färdigt. Försök igen; dina studier finns kvar."
        case .connection: "Kunde inte ansluta till OpenAI. Kontrollera internet och försök igen."
        case .server: "OpenAI kunde inte behandla förfrågan. Försök igen om en stund."
        }
    }
}

nonisolated struct StructuredResponse<Value: Sendable>: Sendable {
    let value: Value
    let json: Data
}

/// No provider-side conversation is created. Each request sends bounded local context.
nonisolated struct OpenAIClient: Sendable {
    static let plannerModel = "gpt-5.6-sol"
    static let teacherModel = "gpt-5.6-luna"
    let session: URLSession
    let keyProvider: @Sendable () async throws -> String?

    init(
        session: URLSession? = nil,
        keyProvider: @escaping @Sendable () async throws -> String? = Self.storedKey
    ) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 120
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        self.session = session ?? URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
        self.keyProvider = keyProvider
    }

    private static func storedKey() async throws -> String? {
        try await OpenAIKeyStore.shared.read()
    }

    /// The token argument is an initial budget. Four repair attempts can increase it;
    /// the final two defer to the model limit rather than clipping JSON locally.
    func respond<Value: Decodable & Sendable>(
        model: String, instructions: String, input: String,
        schemaName: String, schema: [String: Any], as type: Value.Type, maxOutputTokens: Int? = nil,
        validate: (Value) throws -> Void = { _ in }
    ) async throws -> StructuredResponse<Value> {
        guard let key = try await keyProvider(), !key.isEmpty else { throw OpenAIError.missingKey }
        let initialBudget = max(8192, maxOutputTokens ?? (model == Self.plannerModel ? 10000 : 8192))
        var repair = ""
        for attempt in 0...4 {
            try Task.checkCancellation()
            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var body: [String: Any] = [
                "model": model, "store": false,
                "instructions": instructions + repair,
                "input": [["role": "user", "content": input]],
                "text": ["format": ["type": "json_schema", "name": schemaName, "strict": true, "schema": schema]]
            ]
            if attempt < 3 { body["max_output_tokens"] = initialBudget * (1 << attempt) }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let data: Data
            let response: URLResponse
            do { (data, response) = try await session.data(for: request) }
            catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
                Self.debug("schema=\(schemaName) attempt=\(attempt + 1)/5 transport=\((error as NSError).code)")
                throw OpenAIError.connection
            }
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw OpenAIError.connection }
            let context = "schema=\(schemaName) model=\(model) attempt=\(attempt + 1)/5 budget=\(body["max_output_tokens"] ?? "model default") request=\(http.value(forHTTPHeaderField: "x-request-id") ?? "unknown") HTTP=\(http.statusCode)"
            Self.debug(context)
            switch http.statusCode {
            case 200...299: break
            case 401: throw OpenAIError.unauthorized
            case 403, 404: throw OpenAIError.modelUnavailable
            case 429: throw OpenAIError.rateLimited
            default: throw OpenAIError.server
            }
            // Never print provider bodies, learner text or credentials, even in DEBUG.
            do {
                let envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
                Self.debug("\(context) status=\(envelope.status) incomplete=\(envelope.incomplete_details?.reason ?? "none") outputTokens=\(envelope.usage?.output_tokens ?? 0) reasoningTokens=\(envelope.usage?.output_tokens_details?.reasoning_tokens ?? 0)")
                let content = envelope.output.flatMap { $0.content ?? [] }
                if content.contains(where: { $0.type == "refusal" }) { throw OpenAIError.refused }
                if envelope.status != "completed" {
                    let reason = envelope.incomplete_details?.reason
                    if envelope.status == "incomplete", ["max_output_tokens", "max_tokens"].contains(reason ?? "") {
                        throw RepairFailure.truncated
                    }
                    throw OpenAIError.incomplete
                }
                let outputText = content.filter { $0.type == "output_text" }.compactMap(\.text).joined()
                guard !outputText.isEmpty, outputText.utf8.count <= 1_000_000 else {
                    throw LearningValidationError.invalidContract("output_text is empty or exceeds 1 MB")
                }
                let json = Data(outputText.utf8)
                let value = try JSONDecoder().decode(type, from: json)
                try validate(value)
                try Task.checkCancellation()
                return StructuredResponse(value: value, json: json)
            } catch {
                try Task.checkCancellation()
                let reason: String
                if let decoding = error as? DecodingError {
                    reason = Self.decodingReason(decoding)
                } else if let validation = error as? LearningValidationError {
                    if case .invalidContract(let rule) = validation { reason = rule }
                    else { reason = "domain validation rejected the response" }
                } else if error is RepairFailure { reason = "JSON generation reached the output token limit" }
                else { throw error }
                Self.debug("\(context) rejected: \(reason); retry=\(attempt < 4)")
                guard attempt < 4 else {
                    if error is RepairFailure { throw OpenAIError.incomplete }
                    if error is DecodingError { throw LearningValidationError.invalidResponse }
                    throw error
                }
                repair = "\nReturn a fresh, complete JSON object matching the entire schema and all constraints. Keep explanations concise; never omit required fields or truncate JSON."
                if case LearningValidationError.invalidContract(let rule) = error {
                    // Rules are application-authored constants, never model output or learner text.
                    repair += " The previous response violated this requirement: " + rule
                }
            }
        }
        throw OpenAIError.incomplete
    }

    private enum RepairFailure: Error { case truncated }

    private static func debug(_ message: String) {
        #if DEBUG
        print("[OpenAI] " + message)
        #endif
    }

    private static func decodingReason(_ error: DecodingError) -> String {
        // Do not use debugDescription: custom decoders may include submitted content.
        switch error {
        case .keyNotFound(let key, let context):
            return "JSON missing key \(key.stringValue) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .typeMismatch(_, let context):
            return "JSON type mismatch at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .valueNotFound(_, let context):
            return "JSON null value at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .dataCorrupted(let context):
            return "JSON malformed or invalid enum at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        @unknown default: return "JSON decoding failed"
        }
    }

}

nonisolated private struct ResponseEnvelope: Decodable {
    struct Output: Decodable {
        struct Content: Decodable { var type: String; var text: String? }
        var content: [Content]?
    }
    struct Incomplete: Decodable { var reason: String? }
    struct Usage: Decodable {
        struct Details: Decodable { var reasoning_tokens: Int? }
        var output_tokens: Int?
        var output_tokens_details: Details?
    }
    var incomplete_details: Incomplete?
    var usage: Usage?
    var status: String
    var output: [Output]
}

nonisolated private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

nonisolated enum LearningSchema {
    static func object(_ properties: [String: Any]) -> [String: Any] {
        ["type": "object", "properties": properties, "required": properties.keys.sorted(), "additionalProperties": false]
    }
    static var string: [String: Any] { ["type": "string"] }
    static var boolean: [String: Any] { ["type": "boolean"] }
    static var integer: [String: Any] { ["type": "integer"] }
    static func array(_ item: [String: Any]) -> [String: Any] { ["type": "array", "items": item] }
    static func choice(_ values: [String]) -> [String: Any] { ["type": "string", "enum": values] }

    static var question: [String: Any] { object(["question": string, "translation": string, "skill": string]) }
    static func assessment(for course: LanguageCourse) -> [String: Any] {
        object([
            "schemaVersion": ["type": "integer", "enum": [1]],
            "recommendation": choice(["newPlan", "continueCurrent"]), "rationale": string,
            "profile": object([
                "nativeLanguage": choice([course.native.code]), "targetLanguage": choice([course.target.code]),
                "cefr": choice(["pre-A1", "A1", "A2", "B1", "B2", "C1", "C2"]),
                "goal": string, "strengths": array(string), "focusAreas": array(string),
                "skills": object(["reading": integer, "writing": integer,
                                  "listening": integer, "speaking": integer])
            ]),
            "lessons": array(object([
                "id": string, "title": string, "summary": string, "objectives": array(string),
                "prerequisites": array(string), "vocabulary": array(string), "scenario": string,
                "successCriteria": array(string), "estimatedMinutes": integer
            ]))
        ])
    }
    static var lesson: [String: Any] {
        object([
            "reply": string, "translation": string,
            "correction": ["anyOf": [object(["original": string, "corrected": string, "explanation": string]), ["type": "null"]]],
            "requiresRetry": boolean, "retryPrompt": string,
            "objectiveIDsAchieved": array(integer), "lessonComplete": boolean, "memory": string
        ])
    }
}

nonisolated extension LearningSchema {
    static var wrapUp: [String: Any] {
        object(["summary": string, "strengths": array(string), "nextSteps": array(string),
                "demonstratedObjectives": array(integer), "readyToAdvance": boolean])
    }
    static var planDirections: [String: Any] {
        object([
            "recommended": string,
            "options": array(object([
                "id": string, "title": string, "rationale": string, "consolidates": boolean
            ]))
        ])
    }
    static var planExtension: [String: Any] {
        object(["lessons": array(object([
            "id": string, "title": string, "summary": string, "objectives": array(string),
            "prerequisites": array(string), "vocabulary": array(string), "scenario": string,
            "successCriteria": array(string), "estimatedMinutes": integer
        ]))])
    }
    static var chatTurn: [String: Any] {
        object([
            "reply": string, "translation": string,
            "correction": ["anyOf": [object(["original": string, "corrected": string, "explanation": string]), ["type": "null"]]],
            "memory": string
        ])
    }
    static var writingFeedback: [String: Any] {
        object([
            "corrected": string, "summary": string, "strengths": array(string),
            "nextSteps": array(string), "score": integer,
            "ruleTitle": string, "ruleExplanation": string
        ])
    }
    static var pronounGame: [String: Any] {
        object([
            "overview": string,
            "pronouns": array(object([
                "pronoun": string, "meaning": string, "person": integer,
                "plural": boolean, "note": string, "pronunciation": string
            ])),
            "rounds": array(object([
                "id": string, "sentence": string, "translation": string,
                "answer": string, "explanation": string
            ]))
        ])
    }
    static var hint: [String: Any] {
        object(["encouragement": string, "hint": string, "nextWord": string])
    }
    static var practice: [String: Any] {
        object([
            "flashcards": array(object(["id": string, "cue": string, "answer": string, "example": string])),
            "puzzles": array(object(["id": string, "cue": string, "answers": array(array(string)),
                                      "words": array(string), "explanation": string]))
        ])
    }
}
