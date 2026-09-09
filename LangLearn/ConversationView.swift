import SwiftUI

/// Older catalog routes now lead into the learner's generated curriculum.
struct ConversationView: View {
    let lesson: WritingLesson
    var canDismiss = true
    var body: some View { CurrentLessonView() }
}
