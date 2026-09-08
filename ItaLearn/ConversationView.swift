import AVFoundation
import Combine
import SwiftUI

/// Screen 2c — "Samtal, röstsession med mjuk rättning".
///
/// The layout, transcript and coaching bubbles are implemented; the microphone
/// runs a scripted session rather than live speech recognition, because the
/// design specifies the surface and not a speech backend.
struct ConversationView: View {
    let lesson: WritingLesson

    @Environment(TutorSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var turns: [ConversationTurn] = []
    @State private var isListening = false
    @State private var elapsed = 0
    @State private var scriptIndex = 0

    private let speaker = AVSpeechSynthesizer()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            transcript
            controls
        }
        .italearnCanvas()
        .hideNavigationBar()
        .onAppear(perform: startIfNeeded)
        .onReceive(timer) { _ in
            if !turns.isEmpty { elapsed += 1 }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SAMTAL")
                    .font(.il(11, .semibold))
                    .tracking(0.33)
                    .foregroundStyle(ItaLearn.magenta)
                Text(lesson.title)
                    .font(.il(22, .semibold))
                    .foregroundStyle(ItaLearn.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Circle()
                    .fill(ItaLearn.green)
                    .frame(width: 7, height: 7)
                Text(timeText)
                    .font(.ilMono(12, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.black.opacity(0.7))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(.white.opacity(0.7), in: .capsule)
            .overlay { Capsule().strokeBorder(ItaLearn.cardBorder, lineWidth: 1) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var timeText: String {
        String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    Text("Läraren pratar långsam \(settings.level.rawValue)-italienska")
                        .font(.il(12))
                        .foregroundStyle(ItaLearn.inkQuaternary)
                        .padding(.vertical, 4)

                    ForEach(turns) { turn in
                        // Spacer(minLength:) lets the bubble hug its text and
                        // wrap only once it runs out of room.
                        HStack(spacing: 0) {
                            if turn.role != .teacher { Spacer(minLength: 44) }
                            bubble(for: turn)
                            if turn.role == .teacher { Spacer(minLength: 44) }
                        }
                        .id(turn.id)
                    }

                    if isListening {
                        listeningBars
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .id("listening")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .onChange(of: turns.count) {
                withAnimation { proxy.scrollTo(turns.last?.id, anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private func bubble(for turn: ConversationTurn) -> some View {
        switch turn.role {
        case .teacher:
            VStack(alignment: .leading, spacing: 4) {
                Text(turn.italian)
                    .font(.il(17))
                    .foregroundStyle(ItaLearn.ink)
                if let translation = turn.swedish {
                    Text(translation)
                        .font(.il(13))
                        .foregroundStyle(ItaLearn.inkTertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(ItaLearn.card, in: .rect(cornerRadii: .init(topLeading: 18, bottomLeading: 6, bottomTrailing: 18, topTrailing: 18)))
            .overlay {
                UnevenRoundedRectangle(cornerRadii: .init(topLeading: 18, bottomLeading: 6, bottomTrailing: 18, topTrailing: 18))
                    .strokeBorder(ItaLearn.cardBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 4, y: 4)

        case .learner:
            Text(turn.italian)
                .font(.il(17))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(ItaLearn.purple, in: .rect(cornerRadii: .init(topLeading: 18, bottomLeading: 18, bottomTrailing: 6, topTrailing: 18)))
                .shadow(color: .black.opacity(0.10), radius: 4, y: 4)

        case .coaching:
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15))
                    .foregroundStyle(ItaLearn.magenta)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text(turn.italian)
                        .font(.il(15))
                        .foregroundStyle(ItaLearn.ink)
                    if let hint = turn.swedish {
                        Button("Hör skillnaden") { speak(hint) }
                            .font(.il(13))
                            .foregroundStyle(ItaLearn.purple)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.white.opacity(0.72), in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(.white.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 4, y: 4)
        }
    }

    private var listeningBars: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill([ItaLearn.magenta, ItaLearn.magenta, ItaLearn.purple, ItaLearn.purple, ItaLearn.cyan][index])
                    .frame(width: 4, height: 34)
                    .scaleEffect(y: isListening ? 1 : 0.35, anchor: .bottom)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.12),
                        value: isListening
                    )
            }
        }
        .frame(height: 34)
        .padding(.horizontal, 6)
        .accessibilityLabel("Lyssnar")
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                if let last = turns.last(where: { $0.role == .teacher }) {
                    speak(last.italian)
                }
            } label: {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.black.opacity(0.6))
                    .frame(width: 52, height: 52)
                    .background(Color.black.opacity(0.05), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Repetera")

            Button(action: advance) {
                HStack(spacing: 10) {
                    Image(systemName: "mic")
                        .font(.system(size: 20, weight: .medium))
                    Text(micLabel)
                }
                .font(.il(17, .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(ItaLearn.micGradient, in: .capsule)
                .shadow(color: .black.opacity(0.14), radius: 6, y: 6)
            }
            .buttonStyle(.plain)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.black.opacity(0.6))
                    .frame(width: 52, height: 52)
                    .background(Color.black.opacity(0.05), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Avsluta samtalet")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(ItaLearn.cardBorder).frame(height: 1)
        }
    }

    private var micLabel: LocalizedStringKey {
        if isListening { "Lyssnar …" }
        else if scriptIndex >= script.count { "Samtalet är klart" }
        else { "Håll för att prata" }
    }

    // MARK: - Scripted session

    private func startIfNeeded() {
        guard turns.isEmpty else { return }
        advance()
    }

    private func advance() {
        guard scriptIndex < script.count else { return }
        let next = script[scriptIndex]
        scriptIndex += 1

        if next.role == .learner {
            isListening = true
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                isListening = false
                turns.append(next)
                advance()
            }
        } else {
            turns.append(next)
            if next.role == .teacher { speak(next.italian) }
            if scriptIndex < script.count, script[scriptIndex].role == .coaching {
                turns.append(script[scriptIndex])
                scriptIndex += 1
            }
        }
    }

    private func speak(_ italian: String) {
        let utterance = AVSpeechUtterance(string: italian)
        utterance.voice = AVSpeechSynthesisVoice(language: "it-IT")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        speaker.speak(utterance)
    }

    private var script: [ConversationTurn] {
        ConversationScript.forLesson(lesson)
    }
}

struct ConversationTurn: Identifiable {
    enum Role {
        case teacher
        case learner
        case coaching
    }

    let id = UUID()
    let role: Role
    let italian: String
    var swedish: String?
}

/// Scripted practice dialogue per lesson, standing in for live speech.
enum ConversationScript {
    static func forLesson(_ lesson: WritingLesson) -> [ConversationTurn] {
        switch lesson.id {
        case "at-the-cafe":
            [
                ConversationTurn(role: .teacher, italian: "Buongiorno! Cosa prende?", swedish: "Godmorgon! Vad tar du?"),
                ConversationTurn(role: .learner, italian: "Voglio un cappuccino."),
                ConversationTurn(
                    role: .coaching,
                    italian: "Säg gärna vorrei i stället för voglio — artigare i en bar.",
                    swedish: "Vorrei un cappuccino."
                ),
                ConversationTurn(role: .teacher, italian: "Certo. Qualcosa da mangiare?", swedish: "Visst. Något att äta?"),
                ConversationTurn(role: .learner, italian: "Un cornetto, per favore. Quant'è?"),
                ConversationTurn(role: .teacher, italian: "Sono tre euro e cinquanta.", swedish: "Det blir tre euro och femtio.")
            ]
        default:
            [
                ConversationTurn(role: .teacher, italian: "Ciao! Come stai oggi?", swedish: "Hej! Hur mår du i dag?"),
                ConversationTurn(role: .learner, italian: "Sto bene, grazie."),
                ConversationTurn(role: .teacher, italian: "Bene! Raccontami qualcosa.", swedish: "Bra! Berätta något.")
            ]
        }
    }
}
