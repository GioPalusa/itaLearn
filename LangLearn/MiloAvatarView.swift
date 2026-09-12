import SwiftUI

/// A face portrait for a live speaker or a reaction. Use `.still` for chat history.
/// Controllers are optional so existing speech owners can supply mood and amplitude.
struct MiloAvatarView: View {
    var controller: MiloController? = nil
    /// Wins over the controller's own mood, for an owner that knows more than it
    /// does — a speaker that is listening rather than talking, say.
    var mood: MiloMood? = nil
    var size: CGFloat = 72
    var mouthOpening: Float = 0
    var zoom: Float = 3.3
    var showsFrame = false
    var onRigStatus: ((String) -> Void)? = nil

    var body: some View {
        Group {
            if showsFrame {
                portrait
                    .background(LanguLearn.purple.opacity(0.08))
                    .clipShape(Circle())
                    .overlay { Circle().strokeBorder(LanguLearn.purple.opacity(0.12), lineWidth: 1) }
            } else {
                portrait
            }
        }
        .accessibilityHidden(true)
    }

    private var portrait: some View {
        MiloView(
            mood: mood ?? controller?.mood ?? .idle,
            size: size,
            mouthOpening: controller?.narrator.mouthOpening ?? mouthOpening,
            trigger: controller?.trigger ?? 0,
            zoom: zoom,
            onRigStatus: onRigStatus,
            onAnimationCompleted: { controller?.animationCompleted(trigger: $0) }
        )
    }
}
