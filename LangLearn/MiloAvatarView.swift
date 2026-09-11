import SwiftUI

/// A face portrait for a live speaker or a reaction. Use `.still` for chat history.
/// Controllers are optional so existing speech owners can supply mood and amplitude.
struct MiloAvatarView: View {
    var controller: MiloController? = nil
    var mood: MiloMood = .idle
    var size: CGFloat = 72
    var mouthOpening: Float = 0
    var zoom: Float = 3.3
    var onRigStatus: ((String) -> Void)? = nil
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        MiloView(
            mood: controller?.mood ?? mood,
            size: size,
            mouthOpening: controller?.narrator.mouthOpening ?? mouthOpening,
            trigger: controller?.trigger ?? 0,
            zoom: zoom,
            onRigStatus: onRigStatus,
            animatesWhenSmall: true,
            onAnimationCompleted: { controller?.animationCompleted(trigger: $0) }
        )
        .background(LanguLearn.purple.opacity(0.08))
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(LanguLearn.purple.opacity(0.12), lineWidth: 1) }
        .accessibilityHidden(true)
        .onDisappear { controller?.stop() }
        .onChange(of: scenePhase) { if scenePhase != .active { controller?.stop() } }
    }
}
