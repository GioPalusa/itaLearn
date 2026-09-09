import SwiftUI

/// Kept for older writing routes. API usage is billed to the user's OpenAI account.
struct PaywallView: View {
    @ObservedObject var tutor: ItalianTutor
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ContentUnavailableView {
            Label("Kontrollera ditt API-konto", systemImage: "gauge.with.dots.needle.67percent")
        } description: {
            Text("OpenAI styr saldo och användningsgränser för din API-nyckel. Dina sparade studier finns kvar.")
        } actions: {
            Link("Öppna OpenAI", destination: URL(string: "https://platform.openai.com/settings/organization/limits")!)
            Button("Klar") { dismiss() }
        }
    }
}
