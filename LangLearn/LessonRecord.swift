import Foundation
import SwiftData

@Model
final class LessonRecord {
    @Attribute(.unique) var id: UUID
    var completedAt: Date
    var lessonID: String = "introduce-yourself"
    var lessonNumber: Int = 1
    var lessonTitle: String
    var prompt: String
    var attempt: String
    var correctedItalian: String
    var summary: String
    var strengths: [String]
    var nextSteps: [String]
    var score: Int
    var ruleTitle: String = ""
    var ruleExplanation: String = ""

    init(
        id: UUID = UUID(),
        completedAt: Date = .now,
        lessonID: String,
        lessonNumber: Int,
        lessonTitle: String,
        prompt: String,
        attempt: String,
        correctedItalian: String,
        summary: String,
        strengths: [String],
        nextSteps: [String],
        score: Int,
        ruleTitle: String = "",
        ruleExplanation: String = ""
    ) {
        self.id = id
        self.completedAt = completedAt
        self.lessonID = lessonID
        self.lessonNumber = lessonNumber
        self.lessonTitle = lessonTitle
        self.prompt = prompt
        self.attempt = attempt
        self.correctedItalian = correctedItalian
        self.summary = summary
        self.strengths = strengths
        self.nextSteps = nextSteps
        self.score = score
        self.ruleTitle = ruleTitle
        self.ruleExplanation = ruleExplanation
    }
}
