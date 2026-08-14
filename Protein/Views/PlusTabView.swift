import SwiftUI

/// Protein+ is both the purchase surface for free users and the subscriber's
/// own screen.
///
/// It exists because the paid half stopped being a set of locked buttons
/// scattered through the app: logging is free everywhere now, and what is left
/// is what a month of logging *means*. That has to live somewhere a subscriber
/// can open on purpose, or it is a charge with nothing behind it.
struct PlusTabView: View {
    @Environment(\.isActiveTab) private var isActiveTab
    @EnvironmentObject private var settings: GoalSettings
    @EnvironmentObject private var store: StoreService
    @StateObject private var health = HealthKitService.shared

    /// Jumps to the Settings tab. The controls the rows below point at are real
    /// settings and stay where users already look for them, so these rows send
    /// you there rather than growing a second copy of each editor.
    let onOpenSettings: () -> Void

    @State private var insights: ProteinInsights = .empty
    /// Read from the whole history rather than the window — see `load()`.
    @State private var lifetimeBestStreak = 0
    @State private var isLoading = true

    /// The comparison window: this month against the one before it. History
    /// itself is unbounded with Protein+; this is only how far "your month"
    /// reaches.
    private static let windowDays = 30

    var body: some View {
        Group {
            if store.isPro {
                subscriberHub
            } else if isActiveTab {
                PaywallView(embedded: true, impressionID: "protein_plus_tab")
                    .navigationTitle("Protein+")
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                // Every tab stays alive so each keeps its scroll position, but a
                // free user's Protein+ tab is a paywall with no state worth
                // keeping — and building it off-screen put a second screen of
                // elements in front of VoiceOver on Today. Building it on
                // arrival also means the impression is logged when it is seen.
                Color.clear
            }
        }
    }

    private var subscriberHub: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                activeHeader
                highlights
                monthSection
                setupSection
                accountNote
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.background)
        .navigationTitle("Protein+")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: settings.targetGrams) {
            guard isActiveTab else { return }
            await load()
        }
        // The hub stays mounted while the user is on other tabs, so without this
        // a streak extended by a tap on Today is stale the moment they come
        // here to look at it.
        .onChange(of: isActiveTab) { _, active in
            if active { Task { await load() } }
        }
    }

    // MARK: - Header

    private var activeHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(Theme.positive)
                .frame(width: 44, height: 44)
                .background(Theme.positive.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Protein+ active")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Every day you've logged, your own quick-add amounts, and the evening reminder.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Highlights

    /// Figures, not buttons. Deliberately a read-only table so the tappable rows
    /// underneath are the only things on the screen that look tappable.
    @ViewBuilder
    private var highlights: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 132)
                .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        } else if insights.daysOnTarget == 0 && insights.average == 0 {
            VStack(spacing: 10) {
                Image(systemName: "flame")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.protein)
                Text("Your streak starts with the first day you hit \(Int(settings.targetGrams)) g")
                    .font(.system(.headline, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("Days on target, your best run, and this month against the last one all appear here as the days land.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
            .frame(maxWidth: .infinity)
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        } else {
            VStack(spacing: 0) {
                highlightRow(
                    label: "Current streak",
                    value: dayCount(insights.currentStreak),
                    detail: streakDetail
                )
                Divider().padding(.leading, 16)
                highlightRow(
                    label: "Best streak",
                    value: dayCount(lifetimeBestStreak),
                    detail: "Longest run on target, all time"
                )
                Divider().padding(.leading, 16)
                highlightRow(
                    label: "Days on target",
                    value: "\(insights.daysOnTarget)/\(insights.daysCounted)",
                    detail: "Judged against the target each day carried"
                )
                if let best = insights.bestDay {
                    Divider().padding(.leading, 16)
                    highlightRow(
                        label: "Best day",
                        value: ProteinFormat.grams(best.grams),
                        detail: best.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
                    )
                }
            }
            .padding(.vertical, 4)
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
    }

    private var streakDetail: String {
        guard insights.currentStreak > 0 else {
            return "Hit your target today to start one"
        }
        // A day that is still in progress is not a broken streak, so say what
        // the counter is actually counting rather than leaving it to be guessed.
        return "Today counts once you reach \(Int(settings.targetGrams)) g"
    }

    private func dayCount(_ days: Int) -> String {
        "\(days)"
    }

    private func highlightRow(label: String, value: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .textCase(.uppercase)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Sections

    private var monthSection: some View {
        PlusSection(title: "Your month", caption: "Last \(Self.windowDays) days") {
            PlusLinkRow(
                icon: "calendar",
                title: "Your whole history",
                detail: averageDetail,
                value: PlusRowValue(
                    text: ProteinFormat.grams(insights.average),
                    unit: "daily average",
                    change: insights.averageChange
                ),
                isLast: true
            ) {
                HistoryView()
            }
        }
    }

    private var averageDetail: String {
        guard insights.previousAverage != nil, insights.averageChange != nil else {
            return "Daily totals against the target each day carried"
        }
        return "Against the \(Self.windowDays) days before them"
    }

    private var setupSection: some View {
        PlusSection(title: "Your setup") {
            PlusActionRow(
                icon: "bolt.fill",
                title: "Quick-add buttons",
                detail: "Set the three amounts on your phone and your Watch",
                value: PlusRowValue(text: presetSummary),
                action: onOpenSettings
            )
            PlusActionRow(
                icon: "bell.badge",
                title: "Evening reminder",
                detail: settings.reminderEnabled
                    ? "Names the exact grams you have tracked"
                    : "One notification in the evening when you are short",
                value: PlusRowValue(text: settings.reminderEnabled ? reminderTimeLabel : "Off"),
                action: onOpenSettings
            )
            PlusActionRow(
                icon: "target",
                title: "Daily target",
                detail: "Changing it asks whether to re-judge the days behind you",
                value: PlusRowValue(text: "\(Int(settings.targetGrams))", unit: "g"),
                isLast: true,
                action: onOpenSettings
            )
        }
    }

    private var presetSummary: String {
        settings.quickAddPresets.map { "\(Int($0))" }.joined(separator: " · ")
    }

    private var reminderTimeLabel: String {
        var components = DateComponents()
        components.hour = settings.reminderHour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? .now
        return date.formatted(.dateTime.hour().minute())
    }

    private var accountNote: some View {
        Text("Protein+ is active on this Apple ID. Restore Purchases is in Settings if access ever looks wrong.")
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        #if DEBUG
        if ScreenshotConfig.isEnabled {
            let seeded = ScreenshotFixtures.history(days: Self.windowDays)
            insights = ProteinInsightsBuilder.make(days: seeded)
            lifetimeBestStreak = ProteinInsightsBuilder.bestStreak(days: seeded)
            return
        }
        #endif
        let all = (try? await health.fetchFullHistory()) ?? []
        guard !all.isEmpty else {
            insights = .empty
            lifetimeBestStreak = 0
            return
        }
        let current = Array(all.suffix(Self.windowDays))
        // Bounded to one window: `all` is now everything the user has logged,
        // and an all-time average is not what "against the month before" means.
        let previous = Array(all.dropLast(current.count).suffix(Self.windowDays))
        insights = ProteinInsightsBuilder.make(days: current, previous: previous)
        // The one figure that reads the whole history rather than the window.
        // A 40-day run capped at 30 by the window would be a wrong number, not
        // a shortened one.
        lifetimeBestStreak = ProteinInsightsBuilder.bestStreak(days: all)
    }
}

// MARK: - Rows

/// A titled group drawn as one inset card with hairline separators, the idiom
/// iOS uses everywhere for "these lines do something".
private struct PlusSection<Content: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .textCase(.uppercase)
                Spacer(minLength: 8)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) { content }
                .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
    }
}

/// The figure a row already knows, printed before the tap.
private struct PlusRowValue {
    let text: String
    var unit: String?
    /// Fractional change against the previous window, when there is one.
    var change: Double?
}

private struct PlusRowLabel: View {
    let icon: String
    let title: String
    let detail: String
    var value: PlusRowValue?
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.protein)
                    .frame(width: 32, height: 32)
                    .background(Theme.protein.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if let value { figures(value) }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.protein)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if !isLast {
                Divider().padding(.leading, 58)
            }
        }
        .contentShape(Rectangle())
    }

    private func figures(_ value: PlusRowValue) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value.text)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            if let unit = value.unit {
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            if let change = value.change, abs(change) >= 0.01 {
                Text("\(change > 0 ? "▲" : "▼") \(abs(change).formatted(.percent.precision(.fractionLength(0))))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(change > 0 ? Theme.positive : Theme.textSecondary)
            }
        }
        .multilineTextAlignment(.trailing)
        .layoutPriority(1)
    }
}

private struct PlusLinkRow<Destination: View>: View {
    let icon: String
    let title: String
    let detail: String
    var value: PlusRowValue?
    var isLast = false
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink { destination() } label: {
            PlusRowLabel(icon: icon, title: title, detail: detail, value: value, isLast: isLast)
        }
        .buttonStyle(PlusRowButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens \(title)")
    }
}

private struct PlusActionRow: View {
    let icon: String
    let title: String
    let detail: String
    var value: PlusRowValue?
    var isLast = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PlusRowLabel(icon: icon, title: title, detail: detail, value: value, isLast: isLast)
        }
        .buttonStyle(PlusRowButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens Settings")
    }
}

/// Touch feedback: without it a tap on a card that only navigates a moment
/// later reads as a dead press.
private struct PlusRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.protein.opacity(0.10) : .clear)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
