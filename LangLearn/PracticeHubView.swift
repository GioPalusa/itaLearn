import SwiftUI

/// A game shelf and the guided path live side by side. Quick rounds reuse
/// learned material immediately; longer activities can still ask Milo for help.
struct PracticeHubView: View {
    @Environment(LearningStore.self) private var store
    @Environment(TutorSettings.self) private var settings

    private var material: JourneyPracticeMaterial {
        JourneyPracticeMaterial(progress: store.journey, course: settings.course)
    }
    private var oldLesson: PlannedLesson? {
        guard let plan = store.state.activePlan else { return nil }
        return plan.lessons.first {
            !plan.completedLessonIDs.contains($0.id)
                && $0.prerequisites.allSatisfy(plan.completedLessonIDs.contains)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PracticeShelfHero(language: settings.targetLanguage.displayName)
                GuidedLessonShelfCard(session: store.journey.activeSession, track: store.journey.recommendedTrack)
                QuickGameShelf(material: material)
                OpenPracticeShelf()
                if let oldLesson {
                    NavigationLink { LessonPracticeView(lesson: oldLesson) } label: {
                        Label("Öppna mina tidigare ordkort och meningar", systemImage: "archivebox.fill")
                            .font(.headline).foregroundStyle(LanguLearn.purple)
                            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: .rect(cornerRadius: 22))
                    }.buttonStyle(.plain)
                }
                NavigationLink { JourneyExploreView() } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Byt spår eller välj en egen situation").font(.headline)
                            Text("När du vill styra mer själv").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        RowChevron()
                    }
                    .padding(.horizontal, 4).contentShape(.rect)
                }.buttonStyle(.plain)
            }
            .padding(20).padding(.bottom, 44)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .background(
            LinearGradient(colors: [Color(red: 0.96, green: 0.94, blue: 0.99), LanguLearn.canvas], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        )
        .navigationTitle("Spela")
    }
}

private struct PracticeShelfHero: View {
    let language: String
    @State private var milo = MiloController()

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 9) {
                Text("SNABBT ELLER GUIDAT").font(.caption.bold()).tracking(1.4).foregroundStyle(LanguLearn.magenta)
                Text("Vad känns kul nu?").font(.largeTitle.bold())
                Text("Spela direkt med ord du mött, eller fortsätt din lektion i \(language.lowercased()).")
                    .font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { milo.enthusiastic() } label: {
                MiloAvatarView(controller: milo, size: 142, zoom: 2.6)
            }
            .buttonStyle(.plain).accessibilityLabel("Milo vill spela")
        }
        .miloLifetime(milo)
    }
}

private struct GuidedLessonShelfCard: View {
    let session: JourneySession?
    let track: JourneyTrack

    var body: some View {
        NavigationLink {
            if let session { JourneyLessonView(sessionID: session.id) }
            else { JourneyStartView(track: track) }
        } label: {
            HStack(spacing: 18) {
                Image(systemName: session == nil ? "play.fill" : "arrow.right")
                    .font(.title2.bold()).foregroundStyle(.white)
                    .frame(width: 58, height: 58).background(.white.opacity(0.18), in: .circle)
                VStack(alignment: .leading, spacing: 5) {
                    Text(session == nil ? "Starta en guidad lektion" : "Fortsätt din guidade lektion")
                        .font(.title3.bold()).foregroundStyle(.white)
                    Text(session?.pack.title ?? "Milo har ett nästa steg åt dig")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [LanguLearn.purple, Color(red: 0.45, green: 0.25, blue: 0.72)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: 28)
            )
            .shadow(color: LanguLearn.purple.opacity(0.22), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
    }
}

private struct QuickGameShelf: View {
    let material: JourneyPracticeMaterial
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Snabbspel").font(.title2.bold())
                Spacer()
                Text("1–3 min").font(.subheadline.weight(.semibold)).foregroundStyle(LanguLearn.purple)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                NavigationLink { JourneyQuickPlayView(game: .cards, steps: material.cards) } label: {
                    GameTile(title: "Ordblixten", caption: "Vänd och minns", symbol: "rectangle.on.rectangle.angled.fill", color: LanguLearn.cyan, available: !material.cards.isEmpty)
                }.buttonStyle(.plain).disabled(material.cards.isEmpty)

                NavigationLink { JourneyQuickPlayView(game: .listening, steps: material.cards) } label: {
                    GameTile(title: "Lyssna & hitta", caption: "Öra före text", symbol: "waveform.circle.fill", color: LanguLearn.purple, available: !material.cards.isEmpty)
                }.buttonStyle(.plain).disabled(material.cards.isEmpty)

                NavigationLink { JourneyQuickPlayView(game: .build, steps: material.builds) } label: {
                    GameTile(title: "Bygg frasen", caption: material.builds.isEmpty ? "Öppnas av lektioner" : "Ord i rätt ordning", symbol: "square.grid.3x1.below.line.grid.1x2", color: LanguLearn.magenta, available: !material.builds.isEmpty)
                }.buttonStyle(.plain).disabled(material.builds.isEmpty)

                NavigationLink { PronounGameView() } label: {
                    GameTile(title: "Vem gör vad?", caption: "Pronomenduellen", symbol: "person.2.fill", color: LanguLearn.green, available: true)
                }.buttonStyle(.plain)
            }
            if material.cards.isEmpty {
                Text("Din första guidade lektion ger spelen ord att använda.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

private struct GameTile: View {
    let title: LocalizedStringResource
    let caption: LocalizedStringResource
    let symbol: String
    let color: Color
    let available: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Image(systemName: symbol).font(.title2).symbolRenderingMode(.hierarchical)
                .foregroundStyle(color).frame(width: 48, height: 48)
                .background(color.opacity(0.13), in: .rect(cornerRadius: 16))
            Spacer(minLength: 0)
            Text(title).font(.headline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            Text(caption).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(17).frame(maxWidth: .infinity, minHeight: 168, alignment: .leading)
        .background(.white.opacity(available ? 1 : 0.58), in: .rect(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(color.opacity(available ? 0.14 : 0.06), lineWidth: 1) }
        .opacity(available ? 1 : 0.66)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

private struct OpenPracticeShelf: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mer med Milo").font(.title2.bold())
            HStack(spacing: 12) {
                NavigationLink { AdaptiveChatView(mode: .freeChat) } label: {
                    OpenPlayButton(title: "Prata fritt", symbol: "bubble.left.and.text.bubble.right.fill", tint: LanguLearn.purple)
                }.buttonStyle(.plain)
                NavigationLink { WritingDeskView() } label: {
                    OpenPlayButton(title: "Skriv en rad", symbol: "pencil.and.scribble", tint: LanguLearn.magenta)
                }.buttonStyle(.plain)
            }
        }
    }
}

private struct OpenPlayButton: View {
    let title: LocalizedStringResource
    let symbol: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: symbol).font(.subheadline.bold()).foregroundStyle(tint)
            .padding(.horizontal, 15).padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(tint.opacity(0.10), in: .capsule)
    }
}
