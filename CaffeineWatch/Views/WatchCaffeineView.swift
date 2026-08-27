import SwiftUI

struct WatchCaffeineView: View {
    @EnvironmentObject private var settings: CaffeineSettings
    @StateObject private var health = HealthKitService.shared
    @State private var previewDose: Double?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                VStack(spacing: 1) {
                    Text(CaffeineFormat.milligrams(health.remainingNow))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.cyan)
                    Text("estimated now")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack {
                    Label(CaffeineFormat.time(settings.bedtimeDate), systemImage: "moon.fill")
                    Spacer()
                    Text(CaffeineFormat.compactMilligrams(health.bedtimeForecast.estimatedMilligrams))
                        .fontWeight(.semibold)
                }
                .font(.caption)
                .padding(8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))

                ForEach(settings.quickAddPresets, id: \.self) { dose in
                    Button("Preview \(Int(dose)) mg") { previewDose = dose }
                        .buttonStyle(.bordered)
                        .tint(Theme.violet)
                }

                if let entry = CaffeineLogService.shared.lastEntry {
                    Button("Undo \(Int(entry.milligrams)) mg") {
                        Task { _ = await CaffeineLogService.shared.undoLast() }
                    }
                    .font(.caption)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { previewDose != nil },
            set: { if !$0 { previewDose = nil } }
        )) {
            if let dose = previewDose {
                WatchDosePreview(dose: dose) { previewDose = nil }
            }
        }
    }
}

private struct WatchDosePreview: View {
    @EnvironmentObject private var settings: CaffeineSettings
    @StateObject private var health = HealthKitService.shared
    let dose: Double
    let dismiss: () -> Void

    private var estimate: Double {
        CaffeineClearance.forecastAdding(
            dose: dose,
            at: .now,
            samples: health.recentSamples,
            forecastDate: settings.bedtimeDate,
            selection: settings.sourceSelection,
            halfLifeHours: settings.halfLifeHours
        ).estimatedMilligrams
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(Theme.cyan)
                Text(CaffeineFormat.milligrams(estimate))
                    .font(.title2.bold())
                Text("estimated at bedtime")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                Button("Log \(Int(dose)) mg") {
                    Task {
                        _ = await CaffeineLogService.shared.log(milligrams: dose)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.violet)
                Button("Cancel", action: dismiss)
                    .font(.caption)
            }
        }
    }
}
