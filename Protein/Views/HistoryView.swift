import Charts
import SwiftUI

/// Daily totals against the target. Seven days free, thirty with Protein+.
struct HistoryView: View {
    @EnvironmentObject private var store: StoreService
    @StateObject private var health = HealthKitService.shared
    @StateObject private var gate = PlusGateModel()

    @State private var days: [ProteinDaySummary] = []
    @State private var isLoading = true

    private var windowDays: Int { store.isPro ? 30 : 7 }

    private var hitCount: Int {
        days.filter(\.metTarget).count
    }

    private var average: Double {
        guard !days.isEmpty else { return 0 }
        return days.reduce(0) { $0 + $1.grams } / Double(days.count)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summary
                chart
                // A list of seven explicit "0 g" rows under a card that just
                // said nothing has been logged reads as loaded data, not as an
                // empty window. One statement of the empty state is enough.
                if !days.isEmpty, !days.allSatisfy({ $0.grams == 0 }) {
                    dayList
                }
                if !store.isPro {
                    unlockCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .plusGate(gate)
        .task(id: windowDays) { await load() }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            stat(value: "\(hitCount)/\(days.count)", label: "days on target")
            stat(value: ProteinFormat.grams(average), label: "daily average")
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last \(windowDays) days")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

            if isLoading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 160)
            } else if days.allSatisfy({ $0.grams == 0 }) {
                Text("Nothing logged yet. Days appear here as protein lands in Apple Health.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .multilineTextAlignment(.center)
            } else {
                Chart {
                    ForEach(days) { day in
                        BarMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Grams", day.grams)
                        )
                        .foregroundStyle(
                            day.metTarget ? Theme.protein : Theme.protein.opacity(0.35)
                        )
                        .cornerRadius(3)

                        LineMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Target", day.targetGrams)
                        )
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Theme.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 180)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var dayList: some View {
        VStack(spacing: 0) {
            ForEach(Array(days.reversed())) { day in
                let met = day.metTarget
                HStack {
                    Text(day.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(ProteinFormat.grams(day.grams))
                        .font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                    Text("of \(Int(day.targetGrams)) g")
                        .font(.system(.caption, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                    Image(systemName: met ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundStyle(met ? Theme.positive : Theme.textTertiary)
                }
                .padding(.vertical, 11)
                .accessibilityElement(children: .combine)

                if day.date != days.first?.date {
                    Divider()
                }
            }
        }
        .padding(.horizontal, 16)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var unlockCard: some View {
        Button {
            gate.present(.fullHistory)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: PlusFeature.fullHistory.symbol)
                    .foregroundStyle(Theme.protein)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(PlusFeature.fullHistory.title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(PlusFeature.fullHistory.detail)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                PlusLockBadge()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        #if DEBUG
        if ScreenshotConfig.isEnabled {
            days = ScreenshotFixtures.history(days: windowDays)
            return
        }
        #endif
        days = (try? await health.fetchHistory(days: windowDays)) ?? []
    }
}
