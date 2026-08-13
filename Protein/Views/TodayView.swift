import SwiftData
import SwiftUI

/// The whole product on one screen: how much protein is left today, and the
/// fastest possible way to close the gap.
struct TodayView: View {
    @EnvironmentObject private var settings: GoalSettings
    @StateObject private var health = HealthKitService.shared
    @StateObject private var log = ProteinLogService.shared
    @Environment(\.openURL) private var openURL

    @Query(sort: \DailyProteinRecord.date, order: .reverse) private var records: [DailyProteinRecord]

    @State private var showGramPicker = false
    @State private var showSources = false
    @State private var showEntryReview = false
    @State private var justLogged: Double?
    @State private var undoDeadline: Date?
    @State private var undoFailed = false

    /// Today's reconciled total.
    ///
    /// Read from the cached day row rather than recomputed, so the number here,
    /// the widget, and the complication cannot disagree — the freshness
    /// complaints in `docs/positioning.md` §4 are all about exactly that kind of
    /// divergence. Live samples are the fallback before the first refresh lands.
    private var total: Double {
        if let today = records.first, DateHelpers.isSameDay(today.date, .now) {
            return today.proteinGrams
        }
        // `todaySamples` already carries the local-only entries as our own
        // samples, so this is one sum over one list. Adding them again here
        // would double-count exactly the grams a write-denied user typed.
        return ProteinReconciliation.total(samples: health.todaySamples, selection: settings.sourceSelection)
    }

    private var target: Double { settings.targetGrams }
    private var remaining: Double { ProteinReconciliation.remaining(total: total, target: target) }
    private var overage: Double { ProteinReconciliation.overage(total: total, target: target) }

    private var sources: [ProteinSourceStatus] {
        ProteinReconciliation.sources(samples: health.todaySamples, selection: settings.sourceSelection)
    }

    private var ownEntries: [ProteinSample] {
        health.todaySamples
            .filter(\.isOurs)
            .sorted { $0.endDate > $1.endDate }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                hero
                quickAdd
                if let justLogged, undoDeadline != nil {
                    undoRow(grams: justLogged)
                }
                if log.lastWriteFellBack {
                    writeFallbackNotice
                }
                if !ownEntries.isEmpty {
                    reviewEntriesCard
                }
                sourcesCard
                if health.readState != .receiving {
                    connectHealthCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSources = true
                } label: {
                    Image(systemName: "arrow.triangle.merge")
                }
                .accessibilityLabel("Sources")
            }
        }
        .sheet(isPresented: $showGramPicker) {
            GramPickerSheet { grams in
                Task { await add(grams) }
            }
        }
        .sheet(isPresented: $showSources) {
            NavigationStack { SourcesView() }
                .environmentObject(settings)
        }
        .sheet(isPresented: $showEntryReview) {
            OwnEntryReviewSheet()
        }
        .alert("Could not undo", isPresented: $undoFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("That entry could not be removed. It may already be gone, or it was created on your Watch — remove it in Apple Health under Browse, Nutrition, Protein, Show All Data.")
        }
        .task {
            await health.synchronizeAuthorization()
            await ProteinLogService.shared.retryPendingLocalEntries()
            await health.refreshCache()
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                ProgressRing(
                    progress: ProteinReconciliation.progress(total: total, target: target),
                    gradient: Theme.proteinGradient,
                    glowColor: Theme.proteinGlow
                )
                VStack(spacing: 2) {
                    Text("\(Int((overage > 0.5 ? overage : remaining).rounded()))")
                        .font(Theme.bigNumber(60))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(overage > 0.5 ? "grams over" : "grams left")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(overage > 0.5 ? Theme.positive : Theme.textSecondary)
                }
                .padding(.horizontal, 28)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                overage > 0.5
                    ? "\(Int(overage.rounded())) grams over your target of \(Int(target)) grams"
                    : "\(Int(remaining.rounded())) grams left of your \(Int(target)) gram target"
            )

            HStack(spacing: 6) {
                Text(ProteinFormat.progressPair(total: total, target: target))
                    .font(.system(.headline, design: .rounded, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                Text("eaten today")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Quick add

    /// Free, all of it. The buttons are the product; the paid half is what the
    /// month of taps turns into (`PlusFeature`).
    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Add protein")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }

            HStack(spacing: 10) {
                ForEach(Array(settings.quickAddPresets.enumerated()), id: \.offset) { _, preset in
                    presetButton(preset)
                }
            }

            Button {
                showGramPicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                    Text("Another amount")
                    Spacer()
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    private func presetButton(_ grams: Double) -> some View {
        Button {
            Task { await add(grams) }
        } label: {
            VStack(spacing: 1) {
                Text("\(Int(grams))")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("g")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .background(Theme.proteinGradient, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(Int(grams)) grams")
    }

    private func undoRow(grams: Double) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.positive)
            Text("Added \(Int(grams)) g")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button("Undo") {
                Task {
                    // The row is only retired once the entry is really gone.
                    // Dropping it on a failed delete reported an undo against a
                    // total that had not changed.
                    if await log.undoLast() {
                        justLogged = nil
                        undoDeadline = nil
                    } else {
                        undoFailed = true
                    }
                }
            }
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(Theme.protein)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 14))
        .transition(.opacity)
    }

    private var writeFallbackNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.coral)
            VStack(alignment: .leading, spacing: 3) {
                Text("Saved on this device only")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Apple Health is not allowing writes, so these grams are not shared with your other apps. Turn Protein Tracker on under Health › Sharing to fix it.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.coral.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    private var reviewEntriesCard: some View {
        Button {
            showEntryReview = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(Theme.protein)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review today's entries")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Correct grams you added in Protein Tracker")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sources

    private var sourcesCard: some View {
        Button {
            showSources = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Counting today")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.textTertiary)
                }

                if sources.isEmpty {
                    Text("Nothing logged yet today.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(sources.prefix(3)) { source in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(source.isIncluded ? Theme.protein : Theme.textTertiary)
                                .frame(width: 7, height: 7)
                            Text(source.name)
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                .foregroundStyle(source.isIncluded ? Theme.textPrimary : Theme.textTertiary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(ProteinFormat.grams(source.grams))
                                .font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit())
                                .foregroundStyle(source.isIncluded ? Theme.textPrimary : Theme.textTertiary)
                            Text(ProteinFormat.freshness(from: source.latestEntry))
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }

                if ProteinReconciliation.hasDuplicateRisk(sources: sources) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                        Text("Two food apps are both counting. Tap to pick one.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.coral)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
        .buttonStyle(.plain)
    }

    /// Two honest versions of the same card.
    ///
    /// Apple never tells an app whether a read was allowed, so "we have never
    /// received a sample" is the strongest true statement available, and it
    /// covers both the user who declined the sheet and the user who allowed it
    /// and has no food logger writing protein. Neither is told they are
    /// connected, and both get the route that fixes their case.
    private var connectHealthCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "heart.text.square")
                .font(.largeTitle)
                .foregroundStyle(Theme.protein)
            Text(health.readState == .notDetermined ? "Connect Apple Health" : "Nothing from Apple Health yet")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(health.readState == .notDetermined
                 ? "Protein another app writes to Apple Health counts here once access is connected."
                 : "Nothing has been read from Apple Health so far. If your food app writes protein, check that Dietary Protein is on for Protein Tracker under Health › Privacy › Apps.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if health.readState == .notDetermined {
                Button("Connect") {
                    Task {
                        try? await health.requestAuthorization()
                        await health.refreshCache()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.protein)
            } else {
                Button("Open Apple Health") {
                    if let url = URL(string: "x-apple-health://") {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.protein)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    // MARK: - Actions

    private func add(_ grams: Double) async {
        guard await log.log(grams: grams) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            justLogged = grams
            undoDeadline = .now.addingTimeInterval(8)
        }
        // The undo affordance is for the tap you just made, so it retires on its
        // own rather than sitting there implying an edit history.
        let deadline = undoDeadline
        try? await Task.sleep(for: .seconds(8))
        if undoDeadline == deadline {
            withAnimation(.easeInOut(duration: 0.2)) {
                justLogged = nil
                undoDeadline = nil
            }
        }
    }

}

private struct OwnEntryReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var health = HealthKitService.shared
    @StateObject private var log = ProteinLogService.shared
    @State private var failedSample: ProteinSample?

    private var entries: [ProteinSample] {
        health.todaySamples
            .filter(\.isOurs)
            .sorted { $0.endDate > $1.endDate }
    }

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No entries to correct",
                        systemImage: "checkmark.circle",
                        description: Text("Entries you add in Protein Tracker appear here for the rest of the day.")
                    )
                } else {
                    Section {
                        ForEach(entries) { sample in
                            row(for: sample)
                        }
                    } footer: {
                        Text("Removing an entry also removes it from Apple Health when this device created it.")
                    }
                }
            }
            .navigationTitle("Today's entries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Could not remove entry", isPresented: Binding(
                get: { failedSample != nil },
                set: { if !$0 { failedSample = nil } }
            )) {
                Button("OK", role: .cancel) { failedSample = nil }
            } message: {
                Text("This entry may have been created on your Watch. Remove it in Apple Health under Browse, Nutrition, Protein, Show All Data.")
            }
        }
    }

    /// Ours, but not written by this bundle — i.e. saved on the paired watch.
    private func isFromWatch(_ sample: ProteinSample) -> Bool {
        sample.sourceBundleID != proteinOwnSourceBundleID
    }

    private func row(for sample: ProteinSample) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ProteinFormat.grams(sample.grams))
                    .font(.system(.headline, design: .rounded).monospacedDigit())
                HStack(spacing: 5) {
                    Text(sample.endDate, style: .time)
                    if sample.isLocalOnly {
                        Text("On this device")
                    } else if isFromWatch(sample) {
                        // HealthKit only lets an app delete what it saved, so a
                        // wrist entry can refuse the trash button. Saying where
                        // it came from beforehand beats an alert afterwards.
                        Label("From Watch", systemImage: "applewatch")
                    }
                }
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button(role: .destructive) {
                Task {
                    let removed = await log.delete(sample: sample)
                    if !removed {
                        failedSample = sample
                    }
                }
            } label: {
                Image(systemName: "trash")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(Int(sample.grams.rounded())) gram entry")
        }
        .padding(.vertical, 3)
    }
}
