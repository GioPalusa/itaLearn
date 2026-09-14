import Foundation
import Testing
@testable import LangLearnCore

private actor SessionEvents {
    var values: [String] = []
    func activate() async throws {
        values.append("activating")
        try await Task.sleep(for: .milliseconds(30))
        values.append("active")
    }
    func deactivate() { values.append("inactive") }
}

@MainActor @Suite("Speech session ordering")
struct SpeechSessionTests {
    @Test func stopWhileActivatingReleasesBeforeNextSpeakerStarts() async throws {
        let events = SessionEvents()
        let session = SpeechSessionCoordinator(activate: { try await events.activate() }, deactivate: { await events.deactivate() })
        let firstID = UUID(), nextID = UUID()
        let first = Task { try await session.acquire(firstID) }
        while await events.values.isEmpty { await Task.yield() }
        let release = session.release(firstID)
        try await session.acquire(nextID)
        try await first.value; try await release.value
        #expect(await events.values == ["activating", "active", "inactive", "activating", "active"])
        // A late duplicate stop for the old speaker cannot switch off the new one.
        try await session.release(firstID).value
        #expect(await events.values.last == "active")
        try await session.release(nextID).value
        #expect(await events.values.last == "inactive")
    }
}
