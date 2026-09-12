import SwiftUI

/// A standing teacher only in space the exercise has actually left unused.
/// Measure the content without the stage: adding or removing Milo cannot change
/// that measurement, shift a word tile, or make the exercise need scrolling.
struct MiloPracticeCanvas<Content: View>: View {
    let controller: MiloController
    var thinking = false
    var extendsBodyBelowSafeArea = false
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentHeight: CGFloat?

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(spacing: 0) {
                    content
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                    if let height = stageHeight(in: viewport.size) {
                        Spacer(minLength: 16)
                        Group {
                            if height >= 240 {
                                MiloView(mood: thinking ? .thinking : controller.mood,
                                         size: height, mouthOpening: controller.narrator.mouthOpening,
                                         trigger: controller.trigger, zoom: 1.15,
                                         onAnimationCompleted: { controller.animationCompleted(trigger: $0) })
                            } else if extendsBodyBelowSafeArea && !reduceMotion {
                                Color.clear.frame(width: height, height: height * 0.8)
                            } else {
                                MiloAvatarView(controller: controller,
                                               mood: thinking ? .thinking : nil, size: height, zoom: 2.6)
                                    .frame(height: height * 0.8, alignment: .bottom)
                                    .clipped()
                            }
                        }
                        .allowsHitTesting(false)
                        .padding(.bottom, 12)
                    }
                }
                .frame(minHeight: viewport.size.height, alignment: .top)
                .frame(maxWidth: .infinity)
            }
            .overlay(alignment: .bottom) {
                if extendsBodyBelowSafeArea && !reduceMotion,
                   let size = stageHeight(in: viewport.size), size < 240 {
                    // Keep the original head slot. Only the drawing extends out
                    // of the scroll view, behind the system's bottom chrome.
                    Color.clear.frame(width: size, height: size * 0.8)
                        .overlay(alignment: .top) {
                            MiloView(mood: thinking ? .thinking : controller.mood,
                                     size: size * 2.4,
                                     mouthOpening: controller.narrator.mouthOpening,
                                     trigger: controller.trigger, zoom: 2.6 / 2.4,
                                     pinsFaceFocus: true, placeholderSize: size,
                                     onAnimationCompleted: { controller.animationCompleted(trigger: $0) })
                                // Inverse zoom keeps the head's pixel size;
                                // this offset keeps its optical center in place.
                                .offset(y: -size * 0.9)
                                .ignoresSafeArea(.container, edges: .bottom)
                        }
                        .padding(.bottom, 12)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func stageHeight(in viewport: CGSize) -> CGFloat? {
        guard let contentHeight, !typeSize.isAccessibilitySize else { return nil }
        let room = viewport.height - contentHeight - 28
        if !reduceMotion && room >= 260 && viewport.width >= 280 { return 260 }
        if room >= 152 * 0.8 && viewport.width >= 172 { return 152 }
        return nil
    }
}

/// Narration belongs to the screen, not to a portrait that may leave its layout.
private struct MiloScreenLifetime: ViewModifier {
    let controller: MiloController
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onDisappear { controller.stop() }
            .onChange(of: scenePhase) { if scenePhase != .active { controller.stop() } }
    }
}

extension View {
    func miloLifetime(_ controller: MiloController) -> some View {
        modifier(MiloScreenLifetime(controller: controller))
    }
}

/// Ways Milo joins in without taking the screen from the learner.
///
/// Everything here is additive. It stands behind a card, sits in a row that
/// already exists, or uses space a header was leaving empty; none of it has to be
/// dismissed, and none of it covers the words being read or the field being typed
/// into. One live Milo per screen is the rule — the rig costs a few hundred
/// milliseconds and a frame budget, so every other placement uses the still
/// portrait, which costs an image and nothing else.

/// Milo leaning in from behind a card. Head and shoulders show above the edge and
/// the card hides the rest, so the content keeps its own place and full width.
struct MiloPeek<Card: View>: View {
    /// Supply one to let him react to what just happened; leave it out for scenery.
    var controller: MiloController? = nil
    var mood: MiloMood = .still
    var size: CGFloat = 128
    var zoom: Float = 2.6
    /// Which part of the card's top edge he leans over.
    var edge: HorizontalAlignment = .trailing
    var inset: CGFloat = 26
    @ViewBuilder let card: Card

    var body: some View {
        // Trim transparent space above the crown, then let the card cross the
        // shoulders, not the neck. This makes the silhouette belong to the card.
        VStack(alignment: edge, spacing: -size * 0.12) {
            MiloView(
                mood: controller?.mood ?? mood,
                size: size,
                mouthOpening: controller?.narrator.mouthOpening ?? 0,
                trigger: controller?.trigger ?? 0,
                // The same head-and-shoulders framing as the still portrait, so the
                // live rig and the fallback are cropped at the same place.
                zoom: zoom,
                onAnimationCompleted: { controller?.animationCompleted(trigger: $0) }
            )
            // Wider upper-body framing places the crown higher in the camera.
            // Only close portraits have the transparent headroom to trim.
            .frame(height: size * (zoom >= 2.5 ? 0.8 : 1), alignment: .bottom)
            .clipped()
            .padding(.horizontal, inset)
            // He is scenery: every tap belongs to the card he stands behind.
            .allowsHitTesting(false)
            card
        }
    }
}

/// Milo standing on the floor of a screen that has height to spare.
///
/// This is the answer to a half-empty canvas, and the only framing where his
/// hands are in shot — so Present, Wave, Applaud and Dance are visible here and
/// nowhere else. The contact shadow belongs to the component rather than the
/// call site, because without it a large figure reads as floating rather than
/// standing. Anything drawn in `control` is drawn after him and therefore
/// crosses his shins, which is the same rule the onboarding footer follows.
struct MiloStage<Control: View>: View {
    var controller: MiloController? = nil
    var mood: MiloMood = .idle
    /// Three-quarter framing needs the height: below ~200pt use a bust instead.
    var size: CGFloat = 220
    var zoom: Float = 1.15
    /// The tab bar is a floating pill, so letting it overlap him crops him
    /// raggedly at the thigh and leaves his feet below it. A card can cut him —
    /// that is the point of `MiloPeek` — but chrome that only covers the middle
    /// of the screen cannot, so he stands clear of it.
    var floorClearance: CGFloat = 78
    @ViewBuilder let control: Control

    var body: some View {
        VStack(spacing: -size * 0.12) {
            ZStack(alignment: .bottom) {
                // Measured against the rendered figure: at this framing his soles
                // sit about 0.06 of the frame above its bottom edge, so the
                // ellipse is centred there rather than behind his ankles.
                Ellipse()
                    .fill(LanguLearn.purple.opacity(0.14))
                    .frame(width: size * 0.34, height: 17)
                    .blur(radius: 7)
                    .padding(.bottom, size * 0.022)
                MiloView(
                    mood: controller?.mood ?? mood,
                    size: size,
                    mouthOpening: controller?.narrator.mouthOpening ?? 0,
                    trigger: controller?.trigger ?? 0,
                    zoom: zoom,
                    onAnimationCompleted: { controller?.animationCompleted(trigger: $0) }
                )
            }
            .allowsHitTesting(false)
            control
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, floorClearance)
    }
}

extension MiloStage where Control == EmptyView {
    init(controller: MiloController? = nil, mood: MiloMood = .idle,
         size: CGFloat = 220, zoom: Float = 1.15, floorClearance: CGFloat = 78) {
        self.init(controller: controller, mood: mood, size: size, zoom: zoom,
                  floorClearance: floorClearance) { EmptyView() }
    }
}

/// One quiet line from Milo, sized to sit inside a row that already exists.
struct MiloWhisper: View {
    let text: LocalizedStringResource
    var mood: MiloMood = .still
    var size: CGFloat = 44
    var tint: Color = LanguLearn.inkSecondary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            MiloAvatarView(mood: mood, size: size)
            Text(text)
                .font(.il(13))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The controls for what Milo is reading aloud, with no portrait of its own: on a
/// screen where he is already leaning over the card, a second face beside the stop
/// button would be one Milo too many — and a second rig to render.
struct MiloNarrationBar: View {
    let narrator: SpeechNarrator
    @Environment(TutorSettings.self) private var settings

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 13)).foregroundStyle(LanguLearn.purple).padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                if narrator.isPreparing {
                    Text("Förbereder uppläsning…").font(.il(13)).foregroundStyle(LanguLearn.inkSecondary)
                } else if narrator.isSpeaking {
                    Text("Milo läser på \(settings.targetLanguage.displayName.lowercased())")
                        .font(.il(13)).foregroundStyle(LanguLearn.inkSecondary)
                }
                if let error = narrator.errorMessage {
                    Text(error).font(.il(13)).foregroundStyle(LanguLearn.red)
                    Button("Försök läsa upp igen") { narrator.retry() }.font(.il(13, .semibold))
                }
            }
            Spacer(minLength: 0)
            if narrator.isPreparing || narrator.isSpeaking {
                Button("Stoppa", systemImage: "stop.fill") { narrator.stop() }
                    .font(.il(13, .semibold)).labelStyle(.titleAndIcon)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LanguLearn.purple.opacity(0.06), in: .rect(cornerRadius: 14))
    }
}

/// A small live Milo answering what the learner just did. The reaction plays once
/// and settles back to idle; a tap replays it instead of opening anything, so the
/// control beside it keeps working exactly as before.
struct MiloReaction: View {
    let controller: MiloController
    var size: CGFloat = 72
    var label: LocalizedStringResource = "Milo"
    var hint: LocalizedStringResource = "Milo vinkar"
    var replay: (() -> Void)? = nil

    var body: some View {
        Button {
            if let replay { replay() } else { controller.wave() }
        } label: {
            MiloAvatarView(controller: controller, size: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityHint(Text(hint))
    }
}

#if DEBUG
#Preview("Milo bakom ett kort") {
    ScrollView {
        VStack(spacing: 28) {
            MiloPeek(size: 112) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("En paus på kaféet").font(.il(19, .semibold))
                    Text("Beställ något gott och fråga vad det kostar.")
                        .font(.il(15)).foregroundStyle(LanguLearn.inkSecondary)
                }
                .langulearnCard(padding: 18)
            }
            MiloWhisper(text: "Fastnar du? Be mig om en ledtråd, så provar vi igen.")
                .langulearnCard()
        }
        .padding(20)
    }
    .langulearnCanvas()
    .preferredColorScheme(.light)
}
#endif
