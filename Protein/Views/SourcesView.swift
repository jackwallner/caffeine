import SwiftUI

/// Which apps count toward today, what each contributed, and how long ago.
///
/// This screen is the answer to the recurring complaint in
/// `docs/positioning.md` §4: every one of those reviews is about a number that
/// is stale or wrong, not a missing feature. Showing the provenance is cheaper
/// than promising freshness, and more honest.
struct SourcesView: View {
    @EnvironmentObject private var settings: GoalSettings
    @EnvironmentObject private var store: StoreService
    @StateObject private var health = HealthKitService.shared
    @StateObject private var gate = PlusGateModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var sources: [ProteinSourceStatus] {
        ProteinReconciliation.sources(samples: health.todaySamples, selection: settings.sourceSelection)
    }

    var body: some View {
        List {
            if sources.isEmpty {
                Section {
                    emptyState
                }
            } else {
                Section {
                    ForEach(sources) { source in
                        row(for: source)
                    }
                } header: {
                    // Not "writing now": the query proves a source produced
                    // samples in today's window, and the timestamp on each row
                    // is what says how long ago that was.
                    Text("Counting today")
                } footer: {
                    Text(footerText)
                }
            }

            Section {
                Button {
                    Task { await health.refreshCache() }
                } label: {
                    Label("Refresh from Apple Health", systemImage: "arrow.clockwise")
                }
                if let lastRefreshed = health.lastRefreshed {
                    LabeledContent("Last checked", value: ProteinFormat.freshness(from: lastRefreshed))
                }
            } footer: {
                Text("Apple Health wakes this app when a food app writes protein. Opening the app always re-reads the day.")
            }
        }
        .navigationTitle("Sources")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .plusGate(gate)
        .task { await health.refreshCache() }
    }

    private var footerText: String {
        if ProteinReconciliation.hasDuplicateRisk(sources: sources) {
            return "Two food apps are both writing protein today, so the total is probably counting some meals twice. Turn one off."
        }
        return "Every app that writes dietary protein counts by default. Turn one off if it duplicates another."
    }

    private func row(for source: ProteinSourceStatus) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(source.name)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(source.isIncluded ? Theme.textPrimary : Theme.textTertiary)
                        .lineLimit(1)
                    if source.isOurs {
                        Text("THIS APP")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Theme.protein.opacity(0.15), in: Capsule())
                            .foregroundStyle(Theme.protein)
                    }
                }
                HStack(spacing: 6) {
                    Text(ProteinFormat.grams(source.grams))
                        .font(.system(.subheadline, design: .rounded, weight: .medium).monospacedDigit())
                        .foregroundStyle(source.isIncluded ? Theme.textSecondary : Theme.textTertiary)
                    Text("·")
                        .foregroundStyle(Theme.textTertiary)
                    Text(ProteinFormat.freshness(from: source.latestEntry))
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(ProteinFormat.isStale(source.latestEntry) ? Theme.coral : Theme.textSecondary)
                }
                // Grams HealthKit refused to take still count toward today, so
                // this row has to say where they actually are rather than let
                // the user believe every gram reached Health.
                if source.localOnlyGrams > 0 {
                    Text("\(ProteinFormat.grams(source.localOnlyGrams)) on this device only, waiting for Apple Health")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.coral)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            if source.isOurs {
                // Our own entries can never be switched off. Excluding them
                // would silently drop grams the user typed in this app.
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.protein)
                    .accessibilityLabel("Always counted")
            } else {
                Toggle("", isOn: Binding(
                    get: { store.isPro && source.isIncluded },
                    set: { newValue in
                        if store.isPro {
                            settings.setSourceIncluded(newValue, bundleID: source.bundleID)
                            Task { await health.refreshCache() }
                        } else {
                            gate.present(.sources)
                        }
                    }
                ))
                .labelsHidden()
                .tint(Theme.protein)
                .accessibilityLabel("Count \(source.name) toward today")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: health.readState == .receiving ? "tray" : "heart.text.square")
                .font(.largeTitle)
                .foregroundStyle(health.readState == .receiving ? Theme.textTertiary : Theme.protein)
            Text(health.readState == .receiving ? "No protein logged today" : "Nothing from Apple Health yet")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(health.readState == .receiving
                 ? "Apps appear here as soon as they write dietary protein to Apple Health. Not every food logger does, so add grams here and this app becomes the source."
                 : "Nothing has been read from Apple Health so far. That is normal before anything is logged, but if a food app should be writing protein, check Dietary Protein under Health › Privacy › Apps.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if health.readState == .notDetermined {
                Button("Connect Apple Health") {
                    Task {
                        try? await health.requestAuthorization()
                        await health.refreshCache()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.protein)
            } else if health.readState == .noData {
                Button("Open Apple Health") {
                    if let url = URL(string: "x-apple-health://") {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.protein)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}
