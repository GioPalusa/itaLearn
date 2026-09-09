import SwiftData
import SwiftUI

/// Screen 3a — the goal as a ring, then a numbered route through the plan.
struct LearningPathView: View {
    @Environment(LearningStore.self) private var store
    @Environment(TutorSettings.self) private var settings
    @Environment(OpenAIAccess.self) private var access
    @State private var showingSettings = false
    @State private var showingRationale = false
    @State private var planner = LearningChat()

    private var plan: LearningPlan? { store.state.activePlan }

    /// The first lesson that is neither done nor blocked by a prerequisite.
    private var currentLesson: PlannedLesson? {
        guard let plan else { return nil }
        return plan.lessons.first {
            !plan.completedLessonIDs.contains($0.id)
                && $0.prerequisites.allSatisfy(plan.completedLessonIDs.contains)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let plan {
                    header(plan).appearsInSequence(0)
                    goalCard(plan).appearsInSequence(1)
                    if let assessment = store.state.assessments.last {
                        rationaleCard(assessment).appearsInSequence(2)
                    }
                    Text("\(plan.lessons.count == 1 ? "EN LEKTION" : "\(plan.lessons.count) LEKTIONER") TILL MÅLET")
                        .font(.il(13, .semibold)).tracking(0.26)
                        .foregroundStyle(ItaLearn.inkTertiary)
                        .padding(.top, 6).padding(.horizontal, 2)
                        .appearsInSequence(3)
                    route(plan).appearsInSequence(4)
                    if plan.completedLessonIDs.count == plan.lessons.count {
                        continueCard.appearsInSequence(5)
                    }
                    reassessButton.appearsInSequence(6)
                }
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 40)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .italearnCanvas()
        .hideNavigationBar()
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(isPresented: $showingRationale) {
            if let assessment = store.state.assessments.last {
                NavigationStack { AssessmentDetailView(assessment: assessment) }
            }
        }
    }

    // MARK: - Header

    private func header(_ plan: LearningPlan) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("DIN ITALIENSKA · \(plan.profile.cefr)")
                    .font(.il(11, .semibold)).tracking(0.66)
                    .foregroundStyle(ItaLearn.magenta)
                Text("Min studieplan")
                    .font(.il(32, .bold)).foregroundStyle(ItaLearn.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.black.opacity(0.6))
                    .frame(width: 40, height: 40)
                    .background(ItaLearn.card, in: .circle)
                    .overlay { Circle().strokeBorder(ItaLearn.cardBorder, lineWidth: 1) }
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Inställningar")
        }
        .padding(.horizontal, 2).padding(.top, 6)
    }

    // MARK: - Goal

    private func goalCard(_ plan: LearningPlan) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                ProgressRing(completed: plan.completedLessonIDs.count, total: plan.lessons.count)
                VStack(alignment: .leading, spacing: 5) {
                    Text(plan.profile.goal)
                        .font(.il(21, .bold)).foregroundStyle(ItaLearn.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let emphasis = plan.profile.focusAreas.first {
                        Text(emphasis)
                            .font(.il(14)).foregroundStyle(ItaLearn.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let lesson = currentLesson, let number = number(of: lesson, in: plan) {
                NavigationLink { LessonOverviewView(lesson: lesson) } label: {
                    HStack(spacing: 8) {
                        Text(plan.completedLessonIDs.isEmpty ? "Börja lektion \(number)" : "Fortsätt lektion \(number)")
                            .font(.il(17, .semibold)).foregroundStyle(.white)
                        if let minutes = lesson.estimatedMinutes {
                            Text("· \(minutes) min")
                                .font(.il(15)).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(ItaLearn.purple, in: .capsule)
                    .shadow(color: ItaLearn.purple.opacity(0.28), radius: 4, y: 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(ItaLearn.card, in: .rect(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(ItaLearn.cardBorder, lineWidth: 1) }
        .shadow(color: .black.opacity(0.08), radius: 6, y: 6)
    }

    private func number(of lesson: PlannedLesson, in plan: LearningPlan) -> Int? {
        plan.lessons.firstIndex { $0.id == lesson.id }.map { $0 + 1 }
    }

    // MARK: - Milo's reasoning, folded away

    private func rationaleCard(_ assessment: SavedAssessment) -> some View {
        Button { showingRationale = true } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 13)).foregroundStyle(ItaLearn.purple)
                    Text("\(TeacherIdentity.name)s bedömning")
                        .font(.il(15, .semibold)).foregroundStyle(ItaLearn.ink)
                    Spacer(minLength: 0)
                    Text("Läs mer").font(.il(14)).foregroundStyle(ItaLearn.purple)
                }
                Text(assessment.result.rationale)
                    .font(.il(14)).foregroundStyle(Color.black.opacity(0.66))
                    .lineLimit(3).multilineTextAlignment(.leading)
                Text("Skriftligt underlag från \(assessment.createdAt.formatted(.dateTime.day().month())) · inte ett CEFR-prov")
                    .font(.il(12)).foregroundStyle(Color.black.opacity(0.45))
                    .padding(.top, 8)
                    .overlay(alignment: .top) { Rectangle().fill(ItaLearn.hairline).frame(height: 1) }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.62), in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(ItaLearn.cardBorder, lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    // MARK: - The route

    private func route(_ plan: LearningPlan) -> some View {
        let currentID = currentLesson?.id
        let lockedNumbers = plan.lessons.enumerated()
            .filter { !plan.completedLessonIDs.contains($0.element.id) && $0.element.id != currentID }
            .map { $0.offset + 1 }

        return HStack(alignment: .top, spacing: 12) {
            RouteRail(
                completed: plan.completedLessonIDs.count,
                currentIndex: currentID.flatMap { id in plan.lessons.firstIndex { $0.id == id } },
                total: plan.lessons.count
            )
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(plan.lessons.enumerated()), id: \.element.id) { position, lesson in
                    if plan.completedLessonIDs.contains(lesson.id) {
                        completedRow(lesson)
                    } else if lesson.id == currentID {
                        currentRow(lesson)
                    }
                }

                if !lockedNumbers.isEmpty {
                    lockedList(plan, currentID: currentID)
                    HStack(spacing: 7) {
                        Image(systemName: "lock").font(.system(size: 11))
                            .foregroundStyle(Color.black.opacity(0.35))
                        Text(lockExplanation(lockedNumbers))
                            .font(.il(12)).foregroundStyle(Color.black.opacity(0.45))
                    }
                    .padding(.horizontal, 4).padding(.top, 2)
                }
            }
        }
    }

    private func lockExplanation(_ numbers: [Int]) -> String {
        guard let first = numbers.first, let last = numbers.last else { return "" }
        let range = first == last ? "Lektion \(first)" : "Lektion \(first)–\(last)"
        return "\(range) låses upp när lektionen före är klar"
    }

    private func completedRow(_ lesson: PlannedLesson) -> some View {
        NavigationLink { LessonOverviewView(lesson: lesson) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lesson.title)
                        .font(.il(15, .semibold))
                        .foregroundStyle(Color.black.opacity(0.55))
                        .strikethrough(true, color: Color.black.opacity(0.22))
                    Text("Klar · repetera när du vill")
                        .font(.il(12)).foregroundStyle(ItaLearn.green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.3))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(.white.opacity(0.5), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func currentRow(_ lesson: PlannedLesson) -> some View {
        NavigationLink { LessonOverviewView(lesson: lesson) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("NU")
                        .font(.il(10, .semibold)).tracking(0.6)
                        .foregroundStyle(ItaLearn.purple)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(ItaLearn.purple.opacity(0.1), in: .capsule)
                    if let minutes = lesson.estimatedMinutes {
                        Text("\(minutes) min · skriva")
                            .font(.il(12)).foregroundStyle(ItaLearn.inkTertiary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(ItaLearn.purple)
                }
                Text(lesson.title)
                    .font(.il(17, .semibold)).foregroundStyle(ItaLearn.ink)
                    .multilineTextAlignment(.leading)
                LearningMarkdownText(lesson.summary)
                    .font(.il(13)).foregroundStyle(ItaLearn.inkSecondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(14).padding(.leading, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ItaLearn.card, in: .rect(cornerRadius: 14))
            .overlay(alignment: .leading) {
                Rectangle().fill(ItaLearn.purple).frame(width: 4)
            }
            .clipShape(.rect(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(ItaLearn.purple.opacity(0.22), lineWidth: 1) }
            .shadow(color: .black.opacity(0.06), radius: 4, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func lockedList(_ plan: LearningPlan, currentID: String?) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(plan.lessons.enumerated()), id: \.element.id) { position, lesson in
                if !plan.completedLessonIDs.contains(lesson.id) && lesson.id != currentID {
                    if position > 0 { Rectangle().fill(ItaLearn.hairline).frame(height: 1) }
                    HStack(spacing: 10) {
                        Text("\(position + 1)")
                            .font(.ilMono(11, .semibold))
                            .foregroundStyle(Color.black.opacity(0.42))
                            .frame(width: 22, height: 22)
                            .background(Color.black.opacity(0.06), in: .circle)
                        Text(lesson.title)
                            .font(.il(15)).foregroundStyle(Color.black.opacity(0.42))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                        if let minutes = lesson.estimatedMinutes {
                            Text("\(minutes) min")
                                .font(.il(12)).foregroundStyle(Color.black.opacity(0.3))
                        }
                    }
                    .padding(.vertical, 11).padding(.horizontal, 4)
                }
            }
        }
        .accessibilityHint("Låst tills lektionen före är klar")
    }

    /// Offered once the whole plan is done: keep the same path and add to it.
    private var continueCard: some View {
        PlanDirectionPicker(planner: planner).italearnCard()
    }

    private var reassessButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink { AdaptiveChatView(mode: .assessment) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.trianglehead.clockwise").font(.system(size: 14, weight: .semibold))
                    Text(store.state.assessment == nil ? "Testa mina kunskaper igen" : "Fortsätt min kunskapskoll")
                        .font(.il(16, .semibold))
                }
                .foregroundStyle(ItaLearn.purple)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(ItaLearn.purple.opacity(0.1), in: .capsule)
            }
            .buttonStyle(.plain)

            Text("En ny kunskapskoll kan ge en uppdaterad plan. Dina tidigare studier sparas.")
                .font(.il(12)).foregroundStyle(Color.black.opacity(0.45))
                .padding(.horizontal, 6)
        }
        .padding(.top, 6)
    }
}

/// The vertical spine beside the route: done in green, current in purple, rest grey.
private struct RouteRail: View {
    let completed: Int
    let currentIndex: Int?
    let total: Int

    var body: some View {
        VStack(spacing: 0) {
            if completed > 0 {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(ItaLearn.green, in: .circle)
            } else {
                Circle().fill(ItaLearn.purple).frame(width: 26, height: 26)
                    .overlay { Circle().strokeBorder(.white, lineWidth: 8).blendMode(.destinationOut) }
                    .compositingGroup()
            }
            Rectangle()
                .fill(LinearGradient(
                    stops: railStops,
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 3)
                .frame(maxHeight: .infinity)
        }
        .padding(.top, 6)
        .accessibilityHidden(true)
    }

    /// Green as far as the learner has finished, purple through the current lesson, then grey.
    private var railStops: [Gradient.Stop] {
        guard total > 0 else { return [.init(color: .clear, location: 0)] }
        let done = min(Double(completed) / Double(total), 1)
        let through = currentIndex.map { min(Double($0 + 1) / Double(total), 1) } ?? done
        return [
            .init(color: ItaLearn.green, location: 0),
            .init(color: ItaLearn.green, location: done),
            .init(color: ItaLearn.purple, location: done),
            .init(color: ItaLearn.purple, location: through),
            .init(color: Color.black.opacity(0.12), location: through),
            .init(color: Color.black.opacity(0.12), location: 1)
        ]
    }
}

struct LessonOverviewView: View {
    let lesson: PlannedLesson
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    MiloView(size: 76)
                    Text("Öva med Milo").font(.title2.bold())
                }
                LearningMarkdownText(lesson.summary).font(.title3)
                NavigationLink { LessonPracticeView(lesson: lesson) } label: {
                    Label("Ordkort och bygg meningar", systemImage: "rectangle.on.rectangle.angled")
                }.buttonStyle(ItaLearnSecondaryButtonStyle())
                LearningBulletCard(title: "Det här övar du", items: lesson.objectives)
                LearningBulletCard(title: "Du är klar när du kan", items: lesson.successCriteria)
                LearningBulletCard(title: "Ord att använda", items: lesson.vocabulary)
                NavigationLink {
                    AdaptiveChatView(mode: .lesson(lesson))
                } label: {
                    Label("Öppna lektionen", systemImage: "bubble.left.and.bubble.right")
                }
                .buttonStyle(ItaLearnPrimaryButtonStyle())
            }
            .padding(20).padding(.bottom, 40).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .italearnCanvas()
        .navigationTitle(lesson.title)
        .inlineNavigationTitle()
    }
}

struct CurrentLessonView: View {
    @Environment(LearningStore.self) private var store
    @Environment(TutorSettings.self) private var settings
    @Environment(OpenAIAccess.self) private var access
    @State private var planner = LearningChat()
    private var nextLesson: PlannedLesson? {
        guard let plan = store.state.activePlan else { return nil }
        return plan.lessons.first {
            !plan.completedLessonIDs.contains($0.id) && $0.prerequisites.allSatisfy { plan.completedLessonIDs.contains($0) }
        }
    }
    var body: some View {
        if let lesson = nextLesson {
            // Keep the completed conversation visible until the learner chooses the next lesson.
            LessonOverviewView(lesson: lesson)
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    PlanDirectionPicker(planner: planner).italearnCard()
                    NavigationLink("Testa mina kunskaper igen") { AdaptiveChatView(mode: .assessment) }
                        .buttonStyle(ItaLearnSecondaryButtonStyle())
                }
                .padding(20).padding(.bottom, 40)
                .frame(maxWidth: 700).frame(maxWidth: .infinity)
            }
            .italearnCanvas()
            .navigationTitle("Samtal")
        }
    }
}

/// Screen 3b — skill profile, then what the learner can do and what comes next.
struct LearningProgressView: View {
    @Environment(LearningStore.self) private var store

    private var plan: LearningPlan? { store.state.activePlan }

    private var nextLesson: PlannedLesson? {
        guard let plan else { return nil }
        return plan.lessons.first {
            !plan.completedLessonIDs.contains($0.id)
                && $0.prerequisites.allSatisfy(plan.completedLessonIDs.contains)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header.appearsInSequence(0)
                if let profile = plan?.profile {
                    if let skills = profile.skills { skillCard(skills).appearsInSequence(1) }
                    if !profile.strengths.isEmpty { canDoCard(profile.strengths).appearsInSequence(2) }
                    if !profile.focusAreas.isEmpty { nextStepsCard(profile.focusAreas).appearsInSequence(3) }
                }
                Text("HISTORIK")
                    .font(.il(13, .semibold)).tracking(0.26)
                    .foregroundStyle(ItaLearn.inkTertiary)
                    .padding(.top, 6).padding(.horizontal, 2)
                    .appearsInSequence(4)
                historyCard.appearsInSequence(5)
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 40)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .italearnCanvas()
        .hideNavigationBar()
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Mitt lärande")
                .font(.il(32, .bold)).foregroundStyle(ItaLearn.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let cefr = plan?.profile.cefr {
                Text(cefr)
                    .font(.il(14, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(ItaLearn.brandGradient, in: .capsule)
            }
        }
        .padding(.horizontal, 2).padding(.top, 6)
    }

    // MARK: - Skill profile

    private func skillCard(_ skills: SkillEstimate) -> some View {
        SkillBarsCard(skills: skills, assessmentDate: assessmentDate)
    }

    private var assessmentDate: String? {
        store.state.assessments.last?.createdAt.formatted(.dateTime.day().month())
    }

    // MARK: - Can do

    private func canDoCard(_ strengths: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(ItaLearn.deepGreen)
                    .frame(width: 22, height: 22)
                    .background(ItaLearn.green.opacity(0.16), in: .circle)
                Text("Det här kan du")
                    .font(.il(17, .semibold)).foregroundStyle(ItaLearn.ink)
                Spacer(minLength: 0)
                Text("\(strengths.count)")
                    .font(.ilMono(13)).foregroundStyle(Color.black.opacity(0.4))
            }
            .padding(.bottom, 10)

            ForEach(Array(strengths.enumerated()), id: \.offset) { _, strength in
                LearningMarkdownText(strength)
                    .font(.il(15)).foregroundStyle(Color.black.opacity(0.88))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 11)
                    .overlay(alignment: .top) { Rectangle().fill(ItaLearn.hairline).frame(height: 1) }
            }
        }
        .italearnCard()
    }

    // MARK: - Next steps

    private func nextStepsCard(_ focusAreas: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Nästa steg")
                    .font(.il(17, .semibold)).foregroundStyle(ItaLearn.ink)
                Spacer(minLength: 0)
                Text("Alla \(focusAreas.count)")
                    .font(.il(14)).foregroundStyle(ItaLearn.purple)
            }
            .padding(.bottom, 12)

            VStack(spacing: 9) {
                ForEach(Array(focusAreas.enumerated()), id: \.offset) { position, area in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            LearningMarkdownText(area)
                                .font(.il(15, .semibold)).foregroundStyle(Color.black.opacity(0.9))
                                .multilineTextAlignment(.leading)
                            if position == 0, let lesson = nextLesson {
                                Text(practiceCaption(lesson))
                                    .font(.il(12)).foregroundStyle(Color.black.opacity(0.55))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if position == 0, let lesson = nextLesson {
                            NavigationLink { LessonOverviewView(lesson: lesson) } label: {
                                Text("Öva")
                                    .font(.il(14, .semibold)).foregroundStyle(.white)
                                    .padding(.horizontal, 14).frame(height: 34)
                                    .background(ItaLearn.purple, in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .background(ItaLearn.purple.opacity(0.07), in: .rect(cornerRadius: 12))
                }
            }
        }
        .italearnCard()
    }

    private func practiceCaption(_ lesson: PlannedLesson) -> String {
        guard let plan, let position = plan.lessons.firstIndex(where: { $0.id == lesson.id }) else { return "" }
        let minutes = lesson.estimatedMinutes.map { " · \($0) min" } ?? ""
        return "Övas i lektion \(position + 1)\(minutes)"
    }

    // MARK: - History

    private var historyCard: some View {
        GroupedCard {
            NavigationLink { AssessmentListView() } label: {
                historyRow("sparkles", "Kunskapskollar",
                           detail: store.state.assessments.last?.createdAt.formatted(.dateTime.day().month()) ?? "0")
            }.buttonStyle(.plain)

            RowSeparator(inset: 41)

            NavigationLink { SavedConversationsView() } label: {
                historyRow("bubble.left", "Sparade samtal", detail: "\(store.state.sessions.count)")
            }.buttonStyle(.plain)

            RowSeparator(inset: 41)

            NavigationLink { LessonHistoryView() } label: {
                historyRow("pencil.and.scribble", "Tidigare skrivövningar", detail: "")
            }.buttonStyle(.plain)

            if !store.state.archivedPlans.isEmpty {
                RowSeparator(inset: 41)
                NavigationLink { ArchivedPlansView() } label: {
                    historyRow("clock.arrow.circlepath", "Tidigare studieplaner",
                               detail: "\(store.state.archivedPlans.count)")
                }.buttonStyle(.plain)
            }
        }
    }

    private func historyRow(_ icon: String, _ title: LocalizedStringKey, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15)).foregroundStyle(ItaLearn.purple).frame(width: 17)
            Text(title)
                .font(.il(15)).foregroundStyle(Color.black.opacity(0.88))
                .frame(maxWidth: .infinity, alignment: .leading)
            if !detail.isEmpty {
                Text(detail).font(.il(13)).foregroundStyle(Color.black.opacity(0.45))
            }
            RowChevron()
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .contentShape(.rect)
    }
}

/// The skill profile chart. Bars grow from the baseline the first time it is seen.
private struct SkillBarsCard: View {
    let skills: SkillEstimate
    let assessmentDate: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Så ser din italienska ut")
                .font(.il(17, .semibold)).foregroundStyle(ItaLearn.ink)
            // The formatted date already ends in a period, so only add one without it.
            Text(assessmentDate.map { "Uppskattat från dina skriftliga svar, \($0)" }
                 ?? "Uppskattat från dina skriftliga svar.")
                .font(.il(13)).foregroundStyle(ItaLearn.inkSecondary)
                .padding(.top, 3)

            HStack(alignment: .bottom, spacing: 14) {
                ForEach(Array(skills.pairs.enumerated()), id: \.element.label) { position, skill in
                    VStack(spacing: 8) {
                        GeometryReader { proxy in
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(barColor(skill.value, assessed: skill.assessed))
                                    .frame(height: grown
                                           ? max(proxy.size.height * Double(skill.value) / 100, 6)
                                           : 6)
                                    .animation(reduceMotion ? nil : ItaLearnMotion.fill.delay(Double(position) * 0.07),
                                               value: grown)
                            }
                        }
                        Text(skill.label)
                            .font(.il(12, .semibold))
                            .foregroundStyle(skill.assessed ? Color.black.opacity(0.7) : Color.black.opacity(0.45))
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement()
                    .accessibilityLabel(skill.label)
                    .accessibilityValue("\(skill.value) av 100")
                }
            }
            .frame(height: 96)
            .padding(.top, 16)

            Text("Lyssna och tala har inte testats i kunskapskollen — de staplarna är en försiktig gissning.")
                .font(.il(12)).foregroundStyle(Color.black.opacity(0.45))
                .padding(.top, 22)
                .overlay(alignment: .top) {
                    Rectangle().fill(ItaLearn.hairline).frame(height: 1).padding(.top, 12)
                }
        }
        .italearnCard()
        .onAppear { grown = true }
    }

    private func barColor(_ value: Int, assessed: Bool) -> Color {
        guard assessed else { return value >= 20 ? ItaLearn.cyan.opacity(0.35) : Color.black.opacity(0.1) }
        return ItaLearn.cyan
    }
}

/// Milo proposes where to go next; the learner picks, and can swap his choice.
struct PlanDirectionPicker: View {
    @Environment(LearningStore.self) private var store
    @Environment(TutorSettings.self) private var settings
    @Environment(OpenAIAccess.self) private var access
    @Bindable var planner: LearningChat

    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                MiloView(mood: .celebrating, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Du har klarat hela planen")
                        .font(.il(17, .semibold)).foregroundStyle(ItaLearn.ink)
                    Text(headline)
                        .font(.il(13)).foregroundStyle(ItaLearn.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if planner.isWorking {
                MiloLoadingView(message: loadingMessage)
            } else if let directions = planner.directions {
                VStack(spacing: 8) {
                    ForEach(directions.options) { option in
                        directionRow(option, recommended: option.id == directions.recommended)
                    }
                }
                Button("Skapa 10 lektioner", systemImage: "sparkles") {
                    guard let chosen = directions.options.first(where: { $0.id == chosenID(directions) }) else { return }
                    planner.extendPlan(store: store, settings: settings, direction: chosen)
                }
                .buttonStyle(ItaLearnPrimaryButtonStyle())
                Button("Föreslå andra vägar") { planner.suggestDirections(store: store, settings: settings) }
                    .font(.il(14)).foregroundStyle(ItaLearn.purple)
                    .frame(maxWidth: .infinity)
            } else {
                Button("Vad ska jag öva härnäst?", systemImage: "sparkles") {
                    planner.suggestDirections(store: store, settings: settings)
                }
                .buttonStyle(ItaLearnPrimaryButtonStyle())
                .disabled(!access.hasKey)
                Text(access.hasKey
                     ? "Dina avklarade lektioner ligger kvar och går att repetera."
                     : "Lägg till din OpenAI API-nyckel i Inställningar för att fortsätta planen.")
                    .font(.il(12)).foregroundStyle(Color.black.opacity(0.45))
            }

            if let error = planner.errorMessage {
                Text(error).font(.il(13)).foregroundStyle(ItaLearn.red)
            }
        }
        .motion(ItaLearnMotion.settle, planner.directions?.recommended)
    }

    private var headline: String {
        planner.directions == nil
            ? "\(TeacherIdentity.name) kan föreslå vad du övar härnäst, utifrån hur det gick."
            : "Välj vad du vill öva härnäst. Du kan byta \(TeacherIdentity.name)s förslag."
    }

    private var loadingMessage: LocalizedStringResource {
        planner.directions == nil ? "Milo funderar på vad du behöver…" : "Milo planerar dina tio lektioner…"
    }

    private func chosenID(_ directions: PlanDirections) -> String {
        selection ?? directions.recommended
    }

    private func directionRow(_ option: PlanDirection, recommended: Bool) -> some View {
        let isSelected = planner.directions.map { chosenID($0) == option.id } ?? false
        return Button {
            selection = option.id
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? ItaLearn.purple : Color.black.opacity(0.25))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(option.title)
                            .font(.il(15, .semibold)).foregroundStyle(ItaLearn.ink)
                            .multilineTextAlignment(.leading)
                        if recommended {
                            Text(option.consolidates ? "MER ÖVNING" : "MILOS VAL")
                                .font(.il(10, .semibold)).tracking(0.5)
                                .foregroundStyle(ItaLearn.magenta)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(ItaLearn.magenta.opacity(0.12), in: .capsule)
                        }
                    }
                    Text(option.rationale)
                        .font(.il(13)).foregroundStyle(ItaLearn.inkSecondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(
                isSelected ? ItaLearn.purple.opacity(0.08) : Color.black.opacity(0.03),
                in: .rect(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? ItaLearn.purple.opacity(0.35) : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Earlier study plans, kept so the learner can return to a path they left.
struct ArchivedPlansView: View {
    @Environment(LearningStore.self) private var store
    @State private var pendingPlanID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(ItaLearn.red) }
            }
            Section {
                ForEach(store.state.archivedPlans.reversed()) { plan in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(plan.profile.goal).font(.headline)
                        Text(detail(plan)).font(.caption).foregroundStyle(.secondary)
                        Button("Använd den här planen igen") { pendingPlanID = plan.id }
                            .buttonStyle(ItaLearnSecondaryButtonStyle())
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 6)
                }
            } footer: {
                Text("Din nuvarande plan arkiveras när du byter, så du kan gå tillbaka igen. Avklarade lektioner och sparade samtal följer med varje plan.")
            }
        }
        .navigationTitle("Tidigare studieplaner")
        .confirmationDialog(
            "Byt till den här planen? Din nuvarande plan arkiveras.",
            isPresented: Binding(get: { pendingPlanID != nil }, set: { if !$0 { pendingPlanID = nil } })
        ) {
            Button("Byt plan") {
                guard let pendingPlanID else { return }
                do {
                    try store.activateArchivedPlan(id: pendingPlanID)
                    errorMessage = nil
                } catch {
                    errorMessage = store.errorMessage ?? "Planen kunde inte aktiveras."
                }
                self.pendingPlanID = nil
            }
            Button("Avbryt", role: .cancel) { pendingPlanID = nil }
        }
    }

    private func detail(_ plan: LearningPlan) -> String {
        var parts = ["\(plan.lessons.count) lektioner",
                     "\(plan.completedLessonIDs.count) klara",
                     "nivå \(plan.profile.cefr)"]
        if let archived = plan.archivedAt {
            parts.append("arkiverad \(archived.formatted(.dateTime.day().month()))")
        }
        return parts.joined(separator: " · ")
    }
}

/// Split out of the old list so the history rows have real destinations.
struct AssessmentListView: View {
    @Environment(LearningStore.self) private var store
    var body: some View {
        List(store.state.assessments.reversed()) { assessment in
            NavigationLink {
                AssessmentDetailView(assessment: assessment)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(assessment.result.recommendation == .newPlan ? "Ny studieplan" : "Fortsätt på din väg").font(.headline)
                    Text(assessment.createdAt, style: .date).font(.caption)
                    Text(assessment.result.rationale).font(.subheadline).lineLimit(3)
                }
            }
        }
        .navigationTitle("Kunskapskollar")
    }
}

struct SavedConversationsView: View {
    @Environment(LearningStore.self) private var store
    var body: some View {
        List(store.state.sessions.reversed()) { session in
            NavigationLink {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if let summary = session.wrapUp { LessonSummaryCard(summary: summary, mastered: session.isComplete) }
                        ForEach(session.messages) { LearningMessageBubble(message: $0) }
                    }
                    .padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
                }
                .italearnCanvas().navigationTitle(lessonTitle(session))
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Label(lessonTitle(session), systemImage: session.isComplete ? "checkmark.circle" : "bubble.left")
                    Text(detail(session)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Sparade samtal")
    }

    private func lessonTitle(_ session: LessonSession) -> String {
        let plans = store.state.archivedPlans + [store.state.activePlan].compactMap { $0 }
        return plans.first { $0.id == session.planID }?.lessons.first { $0.id == session.lessonID }?.title ?? "Sparad lektion"
    }

    /// Shows what was recorded for this sitting, so the saved history is visible.
    private func detail(_ session: LessonSession) -> String {
        var parts = ["\(session.answerCount) svar"]
        if let retries = session.retryCount, retries > 0 { parts.append("\(retries) omtag") }
        if let practice = session.practice {
            parts.append("\(practice.solvedPuzzleIDs.count)/\(practice.pack.puzzles.count) meningar")
        }
        if let finished = session.finishedAt {
            parts.append(finished.formatted(.dateTime.day().month()))
        }
        return parts.joined(separator: " · ")
    }
}

struct AssessmentDetailView: View {
    let assessment: SavedAssessment
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(assessment.result.profile.cefr).font(.largeTitle.bold())
                LearningMarkdownText(assessment.result.rationale)
                LearningBulletCard(title: "Styrkor", items: assessment.result.profile.strengths)
                LearningBulletCard(title: "Nästa steg", items: assessment.result.profile.focusAreas)
                ShareLink(item: String(decoding: assessment.resultJSON, as: UTF8.self)) {
                    Label("Dela bedömning som JSON", systemImage: "square.and.arrow.up")
                }
                DisclosureGroup("Visa kunskapskollen") {
                    ForEach(assessment.messages) { LearningMessageBubble(message: $0) }
                }
            }
            .padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .italearnCanvas().navigationTitle("Din kunskapskoll")
    }
}

private struct LearningBulletCard: View {
    let title: String
    let items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top) {
                    Image(systemName: "circle.fill").font(.system(size: 5)).padding(.top, 8)
                    Text(item)
                }
            }
        }
        .italearnCard()
    }
}

struct AdaptiveChatView: View {
    enum Mode { case assessment, lesson(PlannedLesson) }
    let mode: Mode
    @Environment(LearningStore.self) private var store
    @Environment(OpenAIAccess.self) private var access
    @Environment(TutorSettings.self) private var settings
    @State private var chat = LearningChat()
    @State private var sessionID: UUID?
    @State private var draft = ""
    @State private var showingSettings = false
    @State private var setupError: String?
    @State private var hasStartedAssessment = false
    @State private var narrator = SpeechNarrator()
    @State private var speech = LessonSpeechInput()
    @State private var speechTask: Task<Void, Never>?
    @FocusState private var composerFocused: Bool

    private var isAssessment: Bool { if case .assessment = mode { true } else { false } }
    private var session: LessonSession? { store.state.sessions.first { $0.id == sessionID } }
    private var messages: [ChatMessage] { isAssessment ? store.state.assessment?.messages ?? [] : session?.messages ?? [] }
    private var pendingAnswer: String? { isAssessment ? store.state.assessment?.pendingAnswer : session?.pendingAnswer }
    private var assessmentFinished: Bool { isAssessment && hasStartedAssessment && store.state.assessment == nil && !store.state.assessments.isEmpty }
    private var title: String { if case .lesson(let lesson) = mode { lesson.title } else { "Din kunskapskoll" } }

    var body: some View {
        VStack(spacing: 0) {
            statusHeader
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if assessmentFinished, let result = store.state.assessments.last {
                            MiloView(mood: .celebrating, size: 110).frame(maxWidth: .infinity)
                            Text(result.result.recommendation == .newPlan ? "Din nya studieplan är klar" : "Fortsätt på din väg")
                                .font(.title2.bold())
                            LearningMarkdownText(result.result.rationale).italearnCard()
                            NavigationLink("Visa min studieplan") { LearningPathView() }
                                .buttonStyle(ItaLearnPrimaryButtonStyle())
                        }
                        ForEach(messages) { message in
                            LearningMessageBubble(message: message)
                            if !isAssessment && message.role == .assistant && !message.translation.isEmpty {
                                Button("Lyssna", systemImage: "speaker.wave.2") {
                                    narrator.stop(); narrator.speak(LearningMarkdown.spoken(message.text))
                                }
                                .font(.caption)
                                .accessibilityLabel("Lyssna på Milos italienska")
                            }
                        }
                        if let pendingAnswer {
                            LearningMessageBubble(message: ChatMessage(role: .user, text: pendingAnswer))
                            Text("Väntar på Milos svar").font(.caption).foregroundStyle(.secondary)
                        }
                        if chat.isWorking { MiloLoadingView(message: isAssessment ? "Milo funderar på din kunskapskoll…" : "Milo förbereder ditt nästa steg…") }
                        if let error = setupError ?? chat.errorMessage ?? store.errorMessage {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(error).foregroundStyle(ItaLearn.red)
                                Button("Försök igen") { resume() }
                                if pendingAnswer != nil {
                                    Button("Ändra mitt svar") {
                                        if let recovered = chat.recoverPendingAnswer(store: store, sessionID: sessionID) {
                                            draft = recovered; composerFocused = true
                                        }
                                    }
                                }
                                Button("Öppna inställningar") { showingSettings = true }
                            }
                            .italearnCard().disabled(chat.isWorking)
                        }
                        if let session, let summary = session.wrapUp, case .lesson(let lesson) = mode {
                            LessonSummaryCard(summary: summary, mastered: session.isComplete)
                            if session.isComplete, let next = nextLesson {
                                NavigationLink { AdaptiveChatView(mode: .lesson(next)) } label: {
                                    Label("Nästa lektion: \(next.title)", systemImage: "arrow.right")
                                }.buttonStyle(ItaLearnPrimaryButtonStyle())
                            } else if !session.isComplete {
                                Button("Fortsätt öva med Milo") { continueLesson(session.id) }
                                    .buttonStyle(ItaLearnPrimaryButtonStyle())
                            }
                            NavigationLink { LessonPracticeView(lesson: lesson) } label: {
                                Label("Öva med ordkort och meningar", systemImage: "rectangle.on.rectangle.angled")
                            }.buttonStyle(ItaLearnSecondaryButtonStyle())
                            NavigationLink("Till min studieplan") { LearningPathView() }
                        }
                        Color.clear.frame(height: 1).id("latest")
                    }
                    .padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
                }
                .onChange(of: messages.count) {
                    if messages.last(where: { $0.role == .user })?.text == draft { draft = "" }
                    withAnimation { proxy.scrollTo("latest", anchor: .bottom) }
                }
                .onChange(of: pendingAnswer) { if pendingAnswer != nil { draft = "" } }
                .onChange(of: chat.isWorking) { proxy.scrollTo("latest", anchor: .bottom) }
            }
            if !assessmentFinished && session?.wrapUp == nil && session?.wrapUpRequested != true { composer }
        }
        .italearnCanvas()
        .navigationTitle(title)
        .toolbar {
            Button("Inställningar", systemImage: "gearshape") { showingSettings = true }
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .task { resume() }
        .onDisappear {
            chat.cancel(); narrator.stop(); speechTask?.cancel()
            Task { await speech.cancel() }
        }
        .onChange(of: access.revision) {
            chat.errorMessage = "API-nyckeln har ändrats. Tryck på Försök igen för att fortsätta."
            chat.cancel(); narrator.stop(); speechTask?.cancel()
            Task { await speech.cancel() }
        }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isAssessment && !assessmentFinished {
                let count = store.state.assessment?.answeredCount ?? 0
                Text("FRÅGA \(min(count + 1, 6)) AV 6 · TA DET I DIN TAKT")
                    .font(.caption.weight(.semibold)).foregroundStyle(ItaLearn.magenta)
                ProgressView(value: Double(count), total: 6)
            } else if case .lesson(let lesson) = mode {
                Text(session?.requiresRetry == true ? "FÖRSÖK IGEN · DU FÅR HJÄLP PÅ VÄGEN" : "ÖVA ITALIENSKA · ETT STEG I TAGET")
                    .font(.caption.weight(.semibold)).foregroundStyle(ItaLearn.purple)
                ProgressView(value: Double(session?.achievedObjectives.count ?? 0), total: Double(lesson.objectives.count))
                Text(session?.wrapUp != nil ? "Sammanfattningen är sparad" : "\(min(session?.answerCount ?? 0, LessonSession.answerBudget)) av \(LessonSession.answerBudget) svar · sedan sammanfattar vi")
                    .font(.caption).foregroundStyle(.secondary)
                if let sessionID, session?.wrapUp == nil, (session?.answerCount ?? 0) >= 2 {
                    Button("Avsluta och sammanfatta", systemImage: "checkmark.circle") {
                        narrator.stop(); speechTask?.cancel()
                        Task { await speech.cancel() }
                        chat.finishLesson(store: store, sessionID: sessionID, settings: settings)
                    }.font(.callout).disabled(chat.isWorking || pendingAnswer != nil || speech.isListening || speech.isPreparing)
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .frame(maxWidth: 760).frame(maxWidth: .infinity)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if speech.isListening {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 13)).foregroundStyle(ItaLearn.magenta).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(speech.partialTranscript.isEmpty ? "Lyssnar…" : speech.partialTranscript)
                            .font(.callout).foregroundStyle(ItaLearn.ink)
                        Text("Texten hamnar i rutan — granska den innan du skickar.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }
            if let error = speech.errorMessage {
                Text(error).font(.caption).foregroundStyle(ItaLearn.red)
            }
            if isAssessment {
                Button("Jag vet inte ännu") { submit("Jag vet inte ännu.") }
                    .font(.caption).disabled(chat.isWorking || pendingAnswer != nil)
            }

            HStack(alignment: .bottom, spacing: 10) {
                // Writing is the lesson; dictation is one way to fill the same field.
                if !isAssessment { micButton }

                TextField(isAssessment ? "Skriv ditt svar…" : "Skriv på italienska…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(.white, in: .rect(cornerRadius: 20))
                    .focused($composerFocused)
                    .autocorrectionDisabled()
                    .writingToolsBehavior(.disabled)
                    .disabled(chat.isWorking || pendingAnswer != nil)

                Button { submit(draft) } label: {
                    Image(systemName: "arrow.up").font(.title3.bold())
                        .foregroundStyle(.white).frame(width: 48, height: 48)
                        .background(ItaLearn.purple, in: .circle)
                }
                .accessibilityLabel("Skicka svar")
                .disabled(chat.isWorking || speech.isListening || speech.isPreparing || pendingAnswer != nil || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 2000)
            }
            if draft.count > 1800 {
                Text("\(draft.count) / 2000 tecken").font(.caption)
                    .foregroundStyle(draft.count > 2000 ? ItaLearn.red : ItaLearn.inkSecondary)
            }
        }
        .motion(ItaLearnMotion.settle, speech.isListening)
        .padding(16).frame(maxWidth: 760).frame(maxWidth: .infinity)
        // The surface runs to the screen edge; the controls stay above the indicator.
        .background(ItaLearn.field.ignoresSafeArea(edges: .bottom))
    }

    /// Optional dictation into the same text field the learner types in.
    private var micButton: some View {
        Button {
            narrator.stop()
            speechTask = Task {
                if speech.isListening {
                    let heard = await speech.finish()
                    guard !Task.isCancelled else { return }
                    draft = [draft, heard].filter { !$0.isEmpty }.joined(separator: " ")
                    composerFocused = true
                } else { await speech.begin() }
            }
        } label: {
            Group {
                if speech.isPreparing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: speech.isListening ? "stop.fill" : "mic")
                        .font(.system(size: 18, weight: .medium))
                }
            }
            .foregroundStyle(speech.isListening ? .white : ItaLearn.purple)
            .frame(width: 48, height: 48)
            .background(
                speech.isListening ? AnyShapeStyle(ItaLearn.magenta) : AnyShapeStyle(ItaLearn.purple.opacity(0.1)),
                in: .circle
            )
        }
        .buttonStyle(.plain)
        .disabled(chat.isWorking || pendingAnswer != nil || speech.isPreparing)
        .accessibilityLabel(speech.isListening ? "Avsluta inspelning" : "Diktera på italienska")
        .accessibilityHint("Lägger till det du säger i textrutan")
    }

    private var nextLesson: PlannedLesson? {
        guard let plan = store.state.activePlan else { return nil }
        return plan.lessons.first {
            !plan.completedLessonIDs.contains($0.id) && $0.prerequisites.allSatisfy { plan.completedLessonIDs.contains($0) }
        }
    }

    private func continueLesson(_ id: UUID) {
        do {
            sessionID = try store.continueLesson(sessionID: id)
            if let sessionID { chat.lesson(store: store, sessionID: sessionID, settings: settings) }
        } catch { setupError = error.localizedDescription }
    }

    private func resume() {
        setupError = nil
        do {
            if isAssessment {
                if !hasStartedAssessment {
                    try store.beginAssessment()
                    hasStartedAssessment = true
                }
                if !assessmentFinished { chat.assessment(store: store) }
            } else if case .lesson(let lesson) = mode {
                sessionID = try store.lessonSession(for: lesson)
                if let sessionID { chat.lesson(store: store, sessionID: sessionID, settings: settings) }
            }
        } catch { setupError = store.errorMessage ?? error.localizedDescription }
    }

    private func submit(_ text: String) {
        guard !chat.isWorking, pendingAnswer == nil else { return }
        narrator.stop()
        if isAssessment { chat.assessment(store: store, answer: text) }
        else if let sessionID { chat.lesson(store: store, sessionID: sessionID, settings: settings, answer: text) }
        else { return }
        composerFocused = false
    }
}

struct LearningMessageBubble: View {
    let message: ChatMessage
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if message.role == .assistant {
                HStack(spacing: 8) {
                    MiloView(mood: .still, size: 32)
                    Text(TeacherIdentity.name).font(.caption.bold()).foregroundStyle(ItaLearn.purple)
                }
            }
            LearningMarkdownText(message.text).font(.body)
            if !message.translation.isEmpty {
                LearningMarkdownText(message.translation).font(.callout).foregroundStyle(.secondary)
            }
            if let correction = message.correction {
                VStack(alignment: .leading, spacing: 8) {
                    Label("En liten rättning", systemImage: "sparkles").font(.subheadline.bold())
                    Text(LearningMarkdown.correction(original: correction.original, corrected: correction.corrected))
                        .textSelection(.enabled)
                        .accessibilityLabel("Rättad mening: \(LearningMarkdown.spoken(correction.corrected))")
                    LearningMarkdownText(correction.explanation).font(.callout)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ItaLearn.purple.opacity(0.08), in: .rect(cornerRadius: 16))
            }
            if message.needsRetry { Label("Prova en gång till", systemImage: "arrow.counterclockwise").font(.subheadline.bold()) }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(message.role == .user ? Color.white : ItaLearn.ink)
        .background(message.role == .user ? ItaLearn.purple : .white, in: .rect(cornerRadius: 24))
        .padding(.leading, message.role == .user ? 36 : 0)
        .padding(.trailing, message.role == .assistant ? 12 : 0)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
/// Local fixtures for visual review. These previews never request a model response.
private struct LearningFlowPreview: View {
    var showsChat = false
    private let container: ModelContainer
    private let store: LearningStore

    init(showsChat: Bool = false) {
        self.showsChat = showsChat
        container = try! ModelContainer(for: LearningSnapshot.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        store = LearningStore()
        store.load(container: container)
        let lessons = [
            PlannedLesson(id: "greetings", title: "Berätta hur du mår", summary: "Hälsa, presentera dig och fråga hur någon mår.", objectives: ["Berätta hur du mår", "Fråga hur någon annan mår"], prerequisites: [], vocabulary: ["ciao", "sto bene"], scenario: "Un nuovo amico", successCriteria: ["Svara och ställ en egen fråga"]),
            PlannedLesson(id: "cafe", title: "En paus på kaféet", summary: "Beställ något gott och fråga vad det kostar.", objectives: ["Beställa artigt"], prerequisites: ["greetings"], vocabulary: ["vorrei"], scenario: "Al bar", successCriteria: ["Gör en beställning"]),
            PlannedLesson(id: "day", title: "Berätta om din dag", summary: "Sätt ord på det du gör i vardagen.", objectives: ["Beskriv din morgon"], prerequisites: ["cafe"], vocabulary: ["la mattina"], scenario: "La mia giornata", successCriteria: ["Använd tre vardagsverb"])
        ]
        let plan = LearningPlan(profile: LearnerProfile(nativeLanguage: "sv", targetLanguage: "it", cefr: "A1", goal: "Känn dig hemma i vardagsitalienskan", strengths: ["Du kan hälsa"], focusAreas: ["Verb i vardagen"]), lessons: lessons)
        try! store.update { state in
            state.activePlan = plan
            state.sessions = [LessonSession(planID: plan.id, lessonID: "greetings", messages: [
                ChatMessage(role: .assistant, text: "Ciao! Come stai oggi?", translation: "Hej! Hur mår du i dag?"),
                ChatMessage(role: .user, text: "Sono bene"),
                ChatMessage(role: .assistant, text: "Prova ancora: come stai?", translation: "Försök igen: hur mår du?", correction: Correction(original: "Sono bene", corrected: "Sto bene", explanation: "När du berättar hur du mår använder du stare: sto bene."), needsRetry: true),
                ChatMessage(role: .assistant, text: "Prova att svara igen med sto.")
            ], requiresRetry: true)]
        }
    }
    var body: some View {
        NavigationStack {
            if showsChat { AdaptiveChatView(mode: .lesson(store.state.activePlan!.lessons[0])) }
            else { LearningPathView() }
        }
        .environment(store).environment(OpenAIAccess())
        .environment(TutorSettings(store: UserDefaults(suiteName: "ItaLearn.preview")!))
        .modelContainer(container)
        .preferredColorScheme(.light)
    }
}

#Preview("Personlig studieplan") { LearningFlowPreview() }
#Preview("Milo med rättning och nytt försök") { LearningFlowPreview(showsChat: true) }
#endif
