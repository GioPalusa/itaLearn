import SwiftData
import SwiftUI

/// Screen 2e — "Dagens gräns nådd → Premium".
struct PaywallView: View {
    @ObservedObject var tutor: ItalianTutor

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LessonRecord.completedAt, order: .reverse)
    private var records: [LessonRecord]

    @State private var isShowingSubscriptionNotice = false


    private var reviewsToday: Int {
        let calendar = Calendar.current
        let count = records.filter { calendar.isDateInToday($0.completedAt) }.count
        return tutor.isLimitReached ? TutorSettings.dailyReviewAllowance : min(count, TutorSettings.dailyReviewAllowance)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        GlassCircle {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.6))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stäng")
                }

                limitCard
                premiumCard

                if tutor.canShowLimitOptions {
                    Button("Visa Apples alternativ för gränsen") {
                        tutor.showLimitOptions()
                    }
                    .font(.il(15))
                    .foregroundStyle(ItaLearn.purple)
                }
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .italearnCanvas()
        .alert("Prenumerationen är inte igång ännu", isPresented: $isShowingSubscriptionNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("ItaLearn Più finns inte att köpa i den här versionen. Ordkort och samtal fungerar som vanligt under tiden.")
        }
    }

    // MARK: - Limit

    private var limitCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 24))
                    .foregroundStyle(ItaLearn.magenta)
                Text("Dagens gräns är nådd")
                    .font(.il(22, .semibold))
                    .foregroundStyle(ItaLearn.ink)
            }

            Text("Private Cloud Compute har granskat \(reviewsToday) texter i dag. Du kan fortsätta skriva — läraren läser igen kl. 00:00.")
                .font(.il(17))
                .foregroundStyle(ItaLearn.inkSecondary)
                .lineSpacing(4)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(reviewsToday) AV \(TutorSettings.dailyReviewAllowance) GRANSKNINGAR")
                    Spacer()
                    Text("ÅTERSTÄLLS 00:00")
                }
                .font(.il(12, .semibold))
                .foregroundStyle(ItaLearn.inkTertiary)

                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.black.opacity(0.08))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [ItaLearn.purple, ItaLearn.magenta],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: proxy.size.width
                                        * min(Double(reviewsToday) / Double(TutorSettings.dailyReviewAllowance), 1)
                                )
                        }
                }
                .frame(height: 8)
            }
            .accessibilityElement(children: .combine)

            Rectangle()
                .fill(ItaLearn.hairline)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 10) {
                stillWorks("Skriv och spara utan gräns — rättningen köar till i morgon")
                stillWorks("Ordkort och samtalsövningar körs på enheten och fungerar som vanligt")
            }
        }
        .italearnCard(padding: 20)
    }

    private func stillWorks(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(ItaLearn.green)
                .padding(.top, 2)
            Text(text)
                .font(.il(15))
                .foregroundStyle(ItaLearn.ink)
        }
    }

    // MARK: - Premium

    private var premiumCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ITALEARN PIÙ")
                .font(.il(11, .semibold))
                .tracking(0.44)
                .foregroundStyle(.white.opacity(0.9))

            Text("Obegränsad lärare\n39 kr/mån")
                .font(.il(26, .bold))
                .foregroundStyle(.white)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                perk("Ingen daglig gräns för granskningar")
                perk("Längre samtal och egna scenarier")
                perk("Ordkort med Genmoji utan tak")
            }
            .padding(.top, 14)

            Button("Prova 7 dagar gratis") {
                isShowingSubscriptionNotice = true
            }
            .buttonStyle(
                ItaLearnPrimaryButtonStyle(
                    background: AnyShapeStyle(ItaLearn.card),
                    foreground: ItaLearn.purple
                )
            )
            .padding(.top, 18)

            Text("Avbryt när du vill i App Store")
                .font(.il(12))
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ItaLearn.premiumGradient, in: .rect(cornerRadius: ItaLearn.cardRadius))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 6)
    }

    private func perk(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(verbatim: "·")
            Text(text)
        }
        .font(.il(15))
        .foregroundStyle(.white.opacity(0.95))
    }
}
