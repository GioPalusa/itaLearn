import SwiftUI

/// Palette and shared surfaces for the Apple Intelligence tutor design.
///
/// The design is specified for light appearance only, so the ink and surface
/// colours are fixed rather than semantic. `RootView` pins the app to light.
enum ItaLearn {
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

private struct ItaLearnCardModifier: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ItaLearn.card, in: .rect(cornerRadius: ItaLearn.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: ItaLearn.cardRadius)
                    .strokeBorder(ItaLearn.cardBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 4, y: 4)
    }
}

extension View {
    func italearnCard(padding: CGFloat = 16) -> some View {
        modifier(ItaLearnCardModifier(padding: padding))
    }

    /// The tinted canvas every screen in the design sits on.
    func italearnCanvas() -> some View {
        background(ItaLearn.canvas)
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

/// The 50 pt filled capsule used for every primary action in the design.
struct ItaLearnPrimaryButtonStyle: ButtonStyle {
    var background: AnyShapeStyle = AnyShapeStyle(ItaLearn.purple)
    var foreground: Color = .white
    var isEnabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.il(17, .semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(background, in: .capsule)
            .opacity(isEnabled ? 1 : 0.4)
            .shadow(color: .black.opacity(0.10), radius: 4, y: 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// The 38 pt tinted capsule used for the secondary pair under a correction.
struct ItaLearnSecondaryButtonStyle: ButtonStyle {
    var tint: Color = ItaLearn.purple
    var fill: Color = ItaLearn.purple.opacity(0.10)

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
                Circle().strokeBorder(ItaLearn.cardBorder, lineWidth: 1)
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
            .foregroundStyle(ItaLearn.inkTertiary)
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
            .fill(ItaLearn.hairline)
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
        .background(ItaLearn.card, in: .rect(cornerRadius: ItaLearn.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: ItaLearn.cardRadius)
                .strokeBorder(ItaLearn.cardBorder, lineWidth: 1)
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
                    .foregroundStyle(ItaLearn.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.il(13))
                        .foregroundStyle(ItaLearn.inkSecondary)
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
            .foregroundStyle(ItaLearn.inkQuaternary)
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
                        .foregroundStyle(ItaLearn.inkSecondary)
                }
            }
        }
    }
}
