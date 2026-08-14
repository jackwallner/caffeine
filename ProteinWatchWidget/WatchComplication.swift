import SwiftData
import SwiftUI
import WidgetKit

struct WatchProteinEntry: TimelineEntry {
    let date: Date
    let total: Double
    let target: Double

    var progress: Double { ProteinReconciliation.progress(total: total, target: target) }
    var hasTarget: Bool { target > 0 }
}

struct WatchProteinProvider: TimelineProvider {
    private static let placeholder = WatchProteinEntry(date: .now, total: 124, target: 160)

    func placeholder(in context: Context) -> WatchProteinEntry { Self.placeholder }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (WatchProteinEntry) -> Void) {
        let isPreview = context.isPreview
        Task { @MainActor in
            completion(isPreview ? Self.placeholder : loadEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<WatchProteinEntry>) -> Void) {
        Task { @MainActor in
            let entry = loadEntry()
            let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now.addingTimeInterval(3600)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    /// Reads the App Group cache the watch app writes when it reconciles. The
    /// complication deliberately keeps working whether or not Protein+ is
    /// active — it costs nothing, and taking the number away is what earns the
    /// one-star reviews the clones in `aso-plan.md` collect.
    @MainActor
    private func loadEntry() -> WatchProteinEntry {
        let defaults = UserDefaults(suiteName: proteinAppGroupID) ?? .standard
        let storedTarget = defaults.object(forKey: proteinTargetKey) as? Double

        let key = DateHelpers.dayKey(for: .now)
        let descriptor = FetchDescriptor<DailyProteinRecord>(predicate: #Predicate { $0.dateString == key })
        let record = try? DataService.sharedModelContainer.mainContext.fetch(descriptor).first

        return WatchProteinEntry(
            date: .now,
            total: record?.proteinGrams ?? 0,
            // The live target rather than the day row's snapshot — see the note
            // in the iOS provider. A target pushed from the phone lands in the
            // App Group before the watch app next reconciles.
            target: storedTarget ?? record?.targetGrams ?? 140
        )
    }
}

struct WatchProteinView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchProteinEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: min(entry.progress, 1)) {
                Image(systemName: "bolt.fill")
            } currentValueLabel: {
                // Grams tracked. A total needs no sign and no clamp: 185 past
                // a 160 target reads as 185, which is what happened.
                Text(ProteinFormat.gaugeValue(total: entry.total))
                    .font(.headline.bold())
                    .minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Theme.protein)
            .accessibilityLabel("Protein: \(ProteinFormat.trackedHeadline(total: entry.total, target: entry.target))")

        case .accessoryRectangular:
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
                    .foregroundStyle(Theme.protein)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }

        case .accessoryInline:
            Label(
                "Protein \(ProteinFormat.compactTracked(total: entry.total, target: entry.target))",
                systemImage: "bolt.fill"
            )

        case .accessoryCorner:
            Text(ProteinFormat.gaugeGrams(total: entry.total))
                .font(.headline.bold())
                .widgetLabel {
                    Gauge(value: min(entry.progress, 1)) {
                        Text("Protein")
                    }
                    .tint(Theme.protein)
                }

        default:
            Text(ProteinFormat.compactTracked(total: entry.total, target: entry.target))
        }
    }
}

@main
struct ProteinWatchWidgetBundle: WidgetBundle {
    var body: some Widget { ProteinWatchWidget() }
}

struct ProteinWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ProteinWatchWidget", provider: WatchProteinProvider()) { entry in
            WatchProteinView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Protein")
        .description("Grams of protein tracked today.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
