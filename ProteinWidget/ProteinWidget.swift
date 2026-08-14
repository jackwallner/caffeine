import SwiftData
import SwiftUI
import WidgetKit

struct ProteinEntry: TimelineEntry {
    let date: Date
    let total: Double
    let target: Double
    let lastUpdated: Date?

    var progress: Double { ProteinReconciliation.progress(total: total, target: target) }
}

struct ProteinProvider: TimelineProvider {
    private static let placeholder = ProteinEntry(date: .now, total: 124, target: 160, lastUpdated: .now)

    func placeholder(in context: Context) -> ProteinEntry { Self.placeholder }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (ProteinEntry) -> Void) {
        let isPreview = context.isPreview
        Task { @MainActor in
            completion(isPreview ? Self.placeholder : loadEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<ProteinEntry>) -> Void) {
        Task { @MainActor in
            let entry = loadEntry()
            // Hourly fallback entries. The app reloads timelines whenever
            // HealthKit delivers, so this is the floor on freshness, not the
            // mechanism — a widget that only refreshed hourly is exactly the
            // complaint the competitors collect.
            let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now.addingTimeInterval(3600)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    /// Widgets cannot query HealthKit, so this reads the App Group cache the app
    /// writes on every reconcile.
    @MainActor
    private func loadEntry() -> ProteinEntry {
        let defaults = UserDefaults(suiteName: proteinAppGroupID) ?? .standard
        let storedTarget = defaults.object(forKey: proteinTargetKey) as? Double

        let key = DateHelpers.dayKey(for: .now)
        let descriptor = FetchDescriptor<DailyProteinRecord>(predicate: #Predicate { $0.dateString == key })
        let record = try? DataService.sharedModelContainer.mainContext.fetch(descriptor).first

        return ProteinEntry(
            date: .now,
            total: record?.proteinGrams ?? 0,
            // The live target, not the day row's copy. That copy is a snapshot
            // taken on the last reconcile so history can show the target that
            // was in force then; moving the slider reloads timelines
            // immediately, and reading the snapshot here would render the new
            // total against the old number until HealthKit next delivered.
            target: storedTarget ?? record?.targetGrams ?? 140,
            lastUpdated: record?.lastUpdated
        )
    }
}

struct ProteinWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ProteinEntry

    var body: some View {
        switch family {
        case .systemMedium: medium
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline:
            Text("Protein · \(ProteinFormat.compactTracked(total: entry.total, target: entry.target))")
        default: small
        }
    }

    private var headline: String {
        ProteinFormat.trackedHeadline(total: entry.total, target: entry.target)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("PROTEIN", systemImage: "bolt.fill")
                .font(.caption2.bold())
                .foregroundStyle(Theme.protein)
            Spacer()
            Text("\(Int(entry.total.rounded()))")
                .font(Theme.bigNumber(40))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("g tracked")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(ProteinFormat.targetCaption(total: entry.total, target: entry.target))
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Protein: \(headline)")
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Protein today", systemImage: "bolt.fill")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.protein)
                Spacer()
                Text("\(Int(entry.total.rounded()))")
                    .font(Theme.bigNumber(46))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("grams tracked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                Gauge(value: min(entry.progress, 1)) {
                    EmptyView()
                } currentValueLabel: {
                    // The grams are already the hero to the left, so the ring
                    // carries the one thing they do not say on their own: how
                    // far through the target the day is. It keeps climbing
                    // past 100% rather than pinning, even though the arc caps.
                    Text("\(Int((entry.progress * 100).rounded()))%")
                        .font(.system(.footnote, design: .rounded, weight: .bold))
                        .minimumScaleFactor(0.6)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(Theme.protein)
                Text(ProteinFormat.targetCaption(total: entry.total, target: entry.target))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var circular: some View {
        Gauge(value: min(entry.progress, 1)) {
            Image(systemName: "bolt.fill")
        } currentValueLabel: {
            // Grams tracked. A total needs no sign and no clamp: 185 past a
            // 160 target reads as 185, which is exactly what happened.
            Text(ProteinFormat.gaugeValue(total: entry.total))
                .font(.headline.bold())
                .minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(Theme.protein)
        .accessibilityLabel("Protein: \(headline)")
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("PROTEIN")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(ProteinFormat.grams(entry.total))
                .font(.title3.bold())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(ProteinFormat.targetCaption(total: entry.total, target: entry.target))
                .font(.caption)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct ProteinWidgetBundle: WidgetBundle {
    var body: some Widget { ProteinWidget() }
}

struct ProteinWidget: Widget {
    let kind = "ProteinWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProteinProvider()) { entry in
            ProteinWidgetView(entry: entry)
        }
        .configurationDisplayName("Protein")
        .description("Grams of protein tracked today.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .systemSmall) {
    ProteinWidget()
} timeline: {
    ProteinEntry(date: .now, total: 124, target: 160, lastUpdated: .now)
}
