import SwiftUI

/// Palette and shared surfaces for the Apple Intelligence tutor design.
///
/// The design is specified for light appearance only, so the ink and surface
/// colours are fixed rather than semantic. `RootView` pins the app to light.
nonisolated enum LanguLearn {
    static let purple = Color(red: 0x56 / 255, green: 0x47 / 255, blue: 0x97 / 255)
    static let magenta = Color(red: 0xC0 / 255, green: 0x33 / 255, blue: 0x8B / 255)
    static let cyan = Color(red: 0x2E / 255, green: 0xAA / 255, blue: 0xE1 / 255)
    static let green = Color(red: 0x66 / 255, green: 0xB6 / 255, blue: 0x59 / 255)
    static let deepGreen = Color(red: 0x3F / 255, green: 0x7A / 255, blue: 0x36 / 255)
    static let red = Color(red: 0xE6 / 255, green: 0x20 / 255, blue: 0x44 / 255)

    static let canvas = Color(red: 0xEE / 255, green: 0xEA / 255, blue: 0xE3 / 255)
    static let field = Color(red: 0xF7 / 255, green: 0xF5 / 255, blue: 0xF1 / 255)
    static let card = Color.white

    static let ink = Color.black.opacity(0.92)
    static let inkSecondary = Color.black.opacity(0.62)
    static let inkTertiary = Color.black.opacity(0.5)
    static let inkQuaternary = Color.black.opacity(0.42)
    static let hairline = Color.black.opacity(0.08)
    static let cardBorder = Color.black.opacity(0.06)

    static let cardRadius: CGFloat = 16

    /// `linear-gradient(225deg, #C0338B, #2EAAE1)` — top-trailing to bottom-leading.
    static let brandGradient = LinearGradient(
        colors: [magenta, cyan],
        startPoint: .topTrailing,
        endPoint: .bottomLeading
    )

    static let premiumGradient = LinearGradient(
        colors: [purple, cyan],
        startPoint: .topTrailing,
        endPoint: .bottomLeading
    )

    static let micGradient = LinearGradient(
        colors: [magenta, purple],
        startPoint: .topTrailing,
        endPoint: .bottomLeading
    )
}

extension Font {
    /// Design-sized system font. `Font.system(size:)` still scales with Dynamic Type.
    static func il(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func ilMono(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Surfaces

private struct LangLearnCardModifier: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LanguLearn.card, in: .rect(cornerRadius: LanguLearn.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: LanguLearn.cardRadius)
                    .strokeBorder(LanguLearn.cardBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 4, y: 4)
    }
}

extension View {
    func langulearnCard(padding: CGFloat = 16) -> some View {
        modifier(LangLearnCardModifier(padding: padding))
    }

    /// The tinted canvas every screen in the design sits on.
    func langulearnCanvas() -> some View {
        background(LanguLearn.canvas)
    }

    /// The design draws its own headers, so the system bar is hidden.
    /// `ToolbarPlacement.navigationBar` does not exist on macOS.
    func hideNavigationBar() -> some View {
#if os(macOS)
        self
#else
        toolbarVisibility(.hidden, for: .navigationBar)
#endif
    }

    /// Hands the large title's height back to the content, for the moments when
    /// the keyboard has taken most of the screen.
    func compactNavigationTitle(_ compact: Bool) -> some View {
#if os(macOS)
        self
#else
        navigationBarTitleDisplayMode(compact ? .inline : .large)
#endif
    }

    /// A long lesson title truncates as a large title; inline handles it better.
    /// `navigationBarTitleDisplayMode` does not exist on macOS.
    func inlineNavigationTitle() -> some View {
#if os(macOS)
        self
#else
        navigationBarTitleDisplayMode(.inline)
#endif
    }

    /// `fullScreenCover` is unavailable on macOS; fall back to a sheet.
    func onboardingCover(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
#if os(macOS)
        sheet(isPresented: isPresented, content: content)
#else
        fullScreenCover(isPresented: isPresented, content: content)
#endif
    }
}

// MARK: - Controls

/// A filled primary action with a 50 pt minimum height that grows with Dynamic Type.
struct LanguLearnPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var controlIsEnabled
    var background: AnyShapeStyle = AnyShapeStyle(LanguLearn.purple)
    var foreground: Color = .white
    var isEnabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(background, in: .capsule)
            .opacity(isEnabled && controlIsEnabled ? 1 : 0.4)
            .shadow(color: .black.opacity(0.10), radius: 4, y: 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// The 38 pt tinted capsule used for the secondary pair under a correction.
struct LanguLearnSecondaryButtonStyle: ButtonStyle {
    var tint: Color = LanguLearn.purple
    var fill: Color = LanguLearn.purple.opacity(0.10)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.il(14, .semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(fill, in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Frosted circular control — nav chevron, close button, conversation actions.
struct GlassCircle<Content: View>: View {
    var size: CGFloat = 34
    var fill: Color = .white.opacity(0.7)
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(width: size, height: size)
            .background(fill, in: .circle)
            .overlay {
                Circle().strokeBorder(LanguLearn.cardBorder, lineWidth: 1)
            }
    }
}

/// Uppercase grouped-list header, e.g. `LÄRAREN`.
struct SettingsSectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.il(12))
            .tracking(0.24)
            .foregroundStyle(LanguLearn.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.bottom, 6)
    }
}

/// A 1 pt inset separator inside a grouped card.
struct RowSeparator: View {
    var inset: CGFloat = 16

    var body: some View {
        Rectangle()
            .fill(LanguLearn.hairline)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// Grouped card that draws its own hairlines between rows.
struct GroupedCard<Content: View>: View {
    var separatorInset: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LanguLearn.card, in: .rect(cornerRadius: LanguLearn.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: LanguLearn.cardRadius)
                .strokeBorder(LanguLearn.cardBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 4, y: 4)
    }
}

/// Row of a grouped card: title, optional subtitle, trailing accessory.
struct SettingsRow<Accessory: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.il(17))
                    .foregroundStyle(LanguLearn.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.il(13))
                        .foregroundStyle(LanguLearn.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            accessory
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(.rect)
    }
}

/// The 8×14 chevron used at the end of tappable rows.
struct RowChevron: View {
    var body: some View {
        Image(systemName: "chevron.forward")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(LanguLearn.inkQuaternary)
            .accessibilityHidden(true)
    }
}

/// The sparkle badge used on the hero card, e.g. `SKAPAD FÖR DIG · A1`.
struct BrandBadge: View {
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.il(11, .semibold))
                .tracking(0.22)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.white.opacity(0.22), in: .capsule)
    }
}

/// Bulleted list used for strengths and next steps.
struct FeedbackList: View {
    let items: [String]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 9) {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                        .padding(.top, 7)
                    Text(item)
                        .font(.il(15))
                        .foregroundStyle(LanguLearn.inkSecondary)
                }
            }
        }
    }
}

// MARK: - Turn 3 components

/// Gradient progress ring with a fraction in the middle, e.g. "1 av 5".
struct ProgressRing: View {
    let completed: Int
    let total: Int
    var size: CGFloat = 76

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(completed) / Double(total), 0), 1)
    }

    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.08), lineWidth: size * 0.105)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(
                    LinearGradient(colors: [LanguLearn.magenta, LanguLearn.cyan],
                                   startPoint: .topTrailing, endPoint: .bottomLeading),
                    style: StrokeStyle(lineWidth: size * 0.105, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(completed)")
                    .font(.system(size: size * 0.29, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color.black.opacity(0.9))
                Text("av \(total)")
                    .font(.il(size * 0.13, .semibold))
                    .foregroundStyle(Color.black.opacity(0.45))
            }
        }
        .frame(width: size, height: size)
        .motion(LanguLearnMotion.fill, shown)
        .onAppear { shown = fraction }
        .onChange(of: fraction) { shown = fraction }
        .accessibilityElement()
        .accessibilityLabel("Framsteg")
        .accessibilityValue("\(completed) av \(total)")
    }
}

/// One filled bar per item, used above the practice rounds.
struct SegmentedProgress: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Capsule()
                    .fill(index <= current && total > 0 ? LanguLearn.purple : Color.black.opacity(0.12))
                    .frame(height: 5)
            }
        }
        .motion(LanguLearnMotion.settle, current)
        .accessibilityElement()
        .accessibilityLabel("Framsteg")
        .accessibilityValue("\(min(current + 1, total)) av \(total)")
    }
}

/// The header shared by the practice rounds: back control, title, counter.
struct PracticeHeader: View {
    let title: LocalizedStringKey
    let subtitle: String
    let current: Int
    let total: Int
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.7))
                    .frame(width: 38, height: 38)
                    .background(LanguLearn.card, in: .circle)
                    .overlay { Circle().strokeBorder(LanguLearn.cardBorder, lineWidth: 1) }
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tillbaka")

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.il(22, .bold)).foregroundStyle(LanguLearn.ink)
                Text(subtitle).font(.il(12)).foregroundStyle(LanguLearn.inkTertiary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                Text("\(min(current + 1, max(total, 1)))").foregroundStyle(LanguLearn.purple)
                Text("/\(total)").foregroundStyle(Color.black.opacity(0.35))
            }
            .font(.ilMono(15))
            .monospacedDigit()
        }
    }
}

// MARK: - Motion

/// The app's motion vocabulary. Every animation goes through here so Reduce Motion
/// is honoured in one place rather than remembered at each call site.
enum LanguLearnMotion {
    /// Content settling into place — cards appearing, sections expanding.
    static let settle = Animation.spring(duration: 0.42, bounce: 0.18)
    /// Something the learner moved — a tile, a card, a tab.
    static let move = Animation.spring(duration: 0.32, bounce: 0.22)
    /// A value counting up — rings and progress bars.
    static let fill = Animation.easeOut(duration: 0.65)
    /// A quick acknowledgement, like a correct answer.
    static let pop = Animation.spring(duration: 0.28, bounce: 0.4)
}

extension View {
    /// Applies an animation unless the learner asked for less motion.
    func motion(_ animation: Animation, _ value: some Equatable) -> some View {
        modifier(ReducedMotionModifier(animation: animation, value: value))
    }

    /// Fades and lifts a view in the first time it appears, staggered by `index`
    /// so a list of cards arrives in sequence instead of all at once.
    func appearsInSequence(_ index: Int) -> some View {
        modifier(SequencedAppearance(index: index))
    }
}

private struct ReducedMotionModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

private struct SequencedAppearance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    @State private var hasAppeared = false

    private var delay: Double { min(Double(index) * 0.06, 0.4) }

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 12)
            .onAppear {
                guard !hasAppeared else { return }
                if reduceMotion {
                    hasAppeared = true
                } else {
                    withAnimation(LanguLearnMotion.settle.delay(delay)) { hasAppeared = true }
                }
            }
    }
}
