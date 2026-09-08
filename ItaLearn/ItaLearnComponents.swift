import SwiftUI

struct FeedbackSection<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
                .foregroundStyle(.secondary)
        }
    }
}

struct FeedbackList: View {
    let items: [String]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(color)
                    Text(item)
                }
            }
        }
    }
}

private struct ItaLearnCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: .rect(cornerRadius: 22))
            .shadow(color: .black.opacity(0.05), radius: 12, y: 5)
    }
}

extension View {
    func italearnCard() -> some View {
        modifier(ItaLearnCardModifier())
    }
}
