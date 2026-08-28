import Charts
import SwiftUI

/// A pending drink preview. Carries the drink so the sheet can log it with the
/// same name the button had.
struct PreviewRequest: Identifiable {
    let id = UUID()
    let drink: DrinkPreset
    /// The entry being edited, when the sheet was opened from the log rather
    /// than from a quick-log button.
    var editing: CaffeineSample?
}

struct CaffeineOnboardingView: View {
    @EnvironmentObject private var settings: CaffeineSettings
    @State private var page = 0
    @State private var bedtime = Calendar.current.date(
        bySettingHour: 22,
        minute: 30,
        second: 0,
        of: .now
    ) ?? .now
    @State private var isRequesting = false

    private static let lastPage = 2

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 24) {
                TabView(selection: $page) {
                    onboardingPage(
                        icon: "waveform.path.ecg",
                        title: "See what may still be active",
                        detail: "Log a drink in one tap. Caffeine estimates what may remain now and at bedtime using a half-life model."
                    )
                    .tag(0)

                    VStack(spacing: 24) {
                        onboardingPage(
                            icon: "moon.stars.fill",
                            title: "Plan around your bedtime",
                            detail: "Preview a drink before logging it. The forecast changes with the dose, the time, and your settings."
                        )
                        DatePicker("Usual bedtime", selection: $bedtime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxHeight: 160)
                    }
                    .tag(1)

                    onboardingPage(
                        icon: "heart.text.square.fill",
                        title: "Keep one caffeine timeline",
                        detail: "Caffeine reads and writes dietary caffeine in Apple Health, so your log stays yours and works alongside other apps. Sleep and heart data stay off until you turn them on."
                    )
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Text("Estimates are informational and vary by person. Caffeine does not diagnose, treat, or prescribe.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button(page == Self.lastPage ? "Connect Apple Health" : "Continue") {
                    guard page == Self.lastPage else {
                        withAnimation { page += 1 }
                        return
                    }
                    isRequesting = true
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: bedtime)
                    settings.bedtimeMinutes = (parts.hour ?? 22) * 60 + (parts.minute ?? 30)
                    Task {
                        try? await HealthKitService.shared.requestAuthorization()
                        settings.hasCompletedSetup = true
                        await HealthKitService.shared.refreshCache()
                        isRequesting = false
                    }
                }
                .buttonStyle(ForecastButtonStyle())
                .disabled(isRequesting)
                .padding(.horizontal, 24)

                if page == Self.lastPage {
                    // Declining Health is a supported path, not a dead end: the
                    // log falls back to this device and retries later.
                    Button("Not now") {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: bedtime)
                        settings.bedtimeMinutes = (parts.hour ?? 22) * 60 + (parts.minute ?? 30)
                        settings.hasCompletedSetup = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func onboardingPage(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 22) {
            Image(systemName: icon)
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(Theme.forecastGradient)
                .symbolEffect(.pulse)
            Text(title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 22)
        }
        .padding(.horizontal, 18)
    }
}

struct CaffeineNowView: View {
    @EnvironmentObject private var settings: CaffeineSettings
    @StateObject private var health = HealthKitService.shared
    @StateObject private var log = CaffeineLogService.shared
    @StateObject private var reviews = ReviewPromptService.shared
    @State private var preview: PreviewRequest?

    /// How long the one-tap undo stays offered after a log.
    private static let undoWindow: TimeInterval = 120
    @State private var showSettings = false

    init() {
        #if DEBUG
        let initialPreview = ProcessInfo.processInfo.arguments.contains("-PreviewSnapshot")
            ? PreviewRequest(drink: DrinkPreset(name: "Latte", milligrams: 120, symbolName: "mug.fill"))
            : nil
        _preview = State(initialValue: initialPreview)
        #else
        _preview = State(initialValue: nil)
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                remainingCard
                healthWriteBanner
                quickAdds
                previewButton
                undoRow
                todayCard
                recentEntries
                estimateNote
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Caffeine")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task { await health.refreshCache() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .accessibilityLabel("Settings")
            }
        }
        .refreshable { await health.refreshCache() }
        .sheet(item: $preview) { request in
            DrinkPreviewSheet(request: request)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { CaffeineSettingsView() }
        }
        .sheet(isPresented: $reviews.isPresented) {
            ReviewPromptSheet()
        }
    }

    private var remainingCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(CaffeineFormat.milligrams(health.remainingNow))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text("estimated remaining now")
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "waveform.path.ecg")
                    .font(.title2)
                    .foregroundStyle(Theme.cyan)
            }

            CaffeineCurve(
                samples: health.recentSamples,
                start: .now,
                end: settings.bedtimeDate,
                halfLifeHours: settings.halfLifeHours,
                selection: settings.sourceSelection,
                threshold: settings.bedtimeThreshold
            )
            .frame(height: 130)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AT BEDTIME")
                        .font(.caption2.bold())
                        .foregroundStyle(Theme.textSecondary)
                    Text(CaffeineFormat.milligrams(health.bedtimeForecast.estimatedMilligrams))
                        .font(.title2.bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(CaffeineFormat.time(settings.bedtimeDate))
                        .font(.headline)
                    Text("4-6h range \(CaffeineFormat.range(health.bedtimeForecast))")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(22)
        .foregroundStyle(Theme.textPrimary)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.cyan.opacity(0.22), lineWidth: 1)
        )
    }

    /// Entries that could not reach Apple Health used to fail silently, so the
    /// Health app simply had nothing in it and there was no way to find out why.
    @ViewBuilder
    private var healthWriteBanner: some View {
        if log.pendingWriteCount > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "\(log.pendingWriteCount) \(log.pendingWriteCount == 1 ? "entry is" : "entries are") saved on this device only",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.warning)
                Text(health.writeState == .denied
                    ? "Apple Health is not accepting writes from Caffeine. Turn on Caffeine under Health data in Settings, then retry."
                    : "They still count in every estimate here. Caffeine retries automatically each time you open the app.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 14) {
                    Button("Retry now") {
                        Task { _ = await log.retryPendingLocalEntries() }
                    }
                    .font(.caption.weight(.semibold))
                    if health.writeState == .denied, let url = HealthKitService.privacySettingsURL {
                        Link("Open Settings", destination: url)
                            .font(.caption.weight(.semibold))
                    }
                }
                .foregroundStyle(Theme.cyan)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Theme.warning.opacity(0.4), lineWidth: 1)
            )
        }
    }

    private var quickAdds: some View {
        HStack(spacing: 10) {
            ForEach(Array(settings.quickAddDrinks.enumerated()), id: \.offset) { _, drink in
                Button {
                    preview = PreviewRequest(drink: drink)
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: drink.symbolName)
                            .font(.title3)
                            .foregroundStyle(Theme.cyan)
                        Text(drink.name)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(CaffeineFormat.milligrams(drink.milligrams))
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textPrimary)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("Preview \(drink.name), \(CaffeineFormat.milligrams(drink.milligrams))")
            }
        }
    }

    private var previewButton: some View {
        Button {
            preview = PreviewRequest(drink: DrinkPreset(name: "Caffeine", milligrams: 100, symbolName: "drop.fill"))
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Preview another drink")
                    .fontWeight(.semibold)
                Spacer()
                Text("before logging")
                    .font(.caption)
                    .opacity(0.8)
            }
        }
        .buttonStyle(ForecastButtonStyle())
    }

    /// A short window to take back the last entry, which is faster than finding
    /// the row and deleting it.
    @ViewBuilder
    private var undoRow: some View {
        if let entry = log.lastEntry,
           let loggedAt = log.lastLoggedAt,
           Date.now.timeIntervalSince(loggedAt) < Self.undoWindow {
            HStack {
                Text("Logged \(entry.drinkName ?? "caffeine"), \(CaffeineFormat.milligrams(entry.milligrams))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Undo") {
                    Task { _ = await log.undoLast() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.cyan)
            }
            .padding(14)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 16))
            .transition(.opacity)
        }
    }

    private var todayCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("CONSUMED TODAY")
                    .font(.caption2.bold())
                    .foregroundStyle(Theme.textSecondary)
                Text(CaffeineFormat.milligrams(health.consumedToday))
                    .font(.title.bold())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("MODEL")
                    .font(.caption2.bold())
                    .foregroundStyle(Theme.textSecondary)
                Text("\(settings.halfLifeHours, specifier: "%.1f") hour half-life")
                    .font(.headline)
            }
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var recentEntries: some View {
        let entries = health.recentSamples
            .filter { $0.isOurs && Calendar.current.isDateInToday($0.endDate) }
            .sorted { $0.endDate > $1.endDate }
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("YOUR LOG")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.textSecondary)
                ForEach(entries) { sample in
                    Button {
                        preview = PreviewRequest(
                            drink: DrinkPreset(
                                name: sample.drinkName ?? "Caffeine",
                                milligrams: sample.milligrams,
                                symbolName: "drop.fill"
                            ),
                            editing: sample
                        )
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: sample.isLocalOnly ? "icloud.slash" : "drop.fill")
                                .foregroundStyle(sample.isLocalOnly ? Theme.warning : Theme.violet)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(sample.displayName)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.textPrimary)
                                Text(CaffeineFormat.milligrams(sample.milligrams))
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Text(CaffeineFormat.time(sample.endDate))
                                .foregroundStyle(Theme.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { _ = await log.delete(sample: sample) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                Text("Tap an entry to change the drink, amount, or time.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(18)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var estimateNote: some View {
        Text("The forecast is a mathematical estimate, not a blood measurement or a medical recommendation. Metabolism varies with the person, dose, and context.")
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 6)
    }
}

/// The drink preview, and the app's planner.
///
/// This is the one place that answers "what would another drink do?": pick the
/// drink, move the dose and time, and compare the bedtime estimate with and
/// without it, plus the latest time this specific dose still lands under the
/// bedtime preference. It doubles as the editor for an entry already logged.
struct DrinkPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: CaffeineSettings
    @StateObject private var health = HealthKitService.shared
    @StateObject private var reviews = ReviewPromptService.shared

    let request: PreviewRequest

    @State private var drinkName: String
    @State private var symbolName: String
    @State private var dose: Double
    @State private var drinkTime: Date
    @State private var isLogging = false
    @State private var showDrinkPicker = false

    init(request: PreviewRequest) {
        self.request = request
        _drinkName = State(initialValue: request.drink.name)
        _symbolName = State(initialValue: request.drink.symbolName)
        _dose = State(initialValue: request.drink.milligrams)
        _drinkTime = State(initialValue: request.editing?.endDate ?? .now)
    }

    private var isEditing: Bool { request.editing != nil }

    /// The entry being edited must not count twice: once as the existing sample
    /// and again as the proposed dose.
    private var baselineSamples: [CaffeineSample] {
        guard let editing = request.editing else { return health.recentSamples }
        return health.recentSamples.filter { $0.id != editing.id }
    }

    private var currentForecast: CaffeineForecast {
        CaffeineClearance.forecast(
            samples: baselineSamples,
            at: settings.bedtimeDate,
            selection: settings.sourceSelection,
            halfLifeHours: settings.halfLifeHours
        )
    }

    private var proposedForecast: CaffeineForecast {
        CaffeineClearance.forecastAdding(
            dose: dose,
            at: drinkTime,
            samples: baselineSamples,
            forecastDate: settings.bedtimeDate,
            selection: settings.sourceSelection,
            halfLifeHours: settings.halfLifeHours
        )
    }

    private var doseContribution: Double {
        CaffeineClearance.remaining(
            dose: dose,
            elapsedHours: settings.bedtimeDate.timeIntervalSince(drinkTime) / 3600,
            halfLifeHours: settings.halfLifeHours
        )
    }

    private var latestTime: Date? {
        CaffeineClearance.latestTimeForDose(
            dose: dose,
            existingSamples: baselineSamples,
            bedtime: settings.bedtimeDate,
            threshold: settings.bedtimeThreshold,
            selection: settings.sourceSelection,
            halfLifeHours: settings.halfLifeHours
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    doseCard
                    forecastCard
                    logButton
                    if let editing = request.editing {
                        Button(role: .destructive) {
                            Task {
                                _ = await CaffeineLogService.shared.delete(sample: editing)
                                dismiss()
                            }
                        } label: {
                            Label("Delete this entry", systemImage: "trash")
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    Text("Logging is free. The estimate uses your selected half-life and is not a measure of caffeine in your bloodstream.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(18)
            }
            .background(Theme.background)
            .navigationTitle(isEditing ? "Edit entry" : "Drink preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showDrinkPicker) {
                DrinkPickerSheet(
                    initial: DrinkPreset(name: drinkName, milligrams: dose, symbolName: symbolName),
                    title: "Choose a drink"
                ) { drink in
                    drinkName = drink.name
                    dose = drink.milligrams
                    symbolName = drink.symbolName
                }
            }
        }
    }

    private var doseCard: some View {
        VStack(spacing: 14) {
            Button {
                showDrinkPicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: symbolName)
                    Text(drinkName)
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(Theme.cyan)
            }
            .buttonStyle(.plain)

            Text("\(Int(dose)) mg")
                .font(.system(size: 50, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())

            Slider(value: $dose, in: 5...500, step: 5)
                .tint(Theme.violet)
                .accessibilityLabel("Dose in milligrams")

            DatePicker(
                "Time",
                selection: $drinkTime,
                in: Date.now.addingTimeInterval(-36 * 3600)...settings.bedtimeDate
            )
            .foregroundStyle(Theme.textPrimary)
        }
        .padding(22)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var forecastCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isEditing ? "AT BEDTIME AFTER THIS EDIT" : "IF YOU LOG THIS")
                .font(.caption.bold())
                .foregroundStyle(Theme.textSecondary)

            HStack(alignment: .center) {
                forecastValue("WITHOUT", currentForecast.estimatedMilligrams)
                Image(systemName: "arrow.right")
                    .foregroundStyle(Theme.textSecondary)
                forecastValue(isEditing ? "AS EDITED" : "WITH DRINK", proposedForecast.estimatedMilligrams)
            }

            Divider()

            Label(
                "This drink adds about \(CaffeineFormat.milligrams(doseContribution)) to the bedtime estimate",
                systemImage: "moon.stars.fill"
            )
            .font(.subheadline)
            .foregroundStyle(Theme.textPrimary)

            if let latestTime {
                Label(
                    latestTime >= settings.bedtimeDate
                        ? "At this size, the estimate stays under your \(CaffeineFormat.milligrams(settings.bedtimeThreshold)) preference right through bedtime"
                        : "Latest time this dose still lands under your preference: \(CaffeineFormat.time(latestTime))",
                    systemImage: "clock.badge.checkmark"
                )
                .font(.subheadline)
                .foregroundStyle(Theme.mint)
            } else {
                Label(
                    "Your existing bedtime estimate is already above your \(CaffeineFormat.milligrams(settings.bedtimeThreshold)) preference",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.subheadline)
                .foregroundStyle(Theme.warning)
            }

            Text("Reference range at bedtime: \(CaffeineFormat.range(proposedForecast)). A preference is a number you chose, not a safety limit.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private func forecastValue(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2.bold()).foregroundStyle(Theme.textSecondary)
            Text(CaffeineFormat.milligrams(value))
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)
            Text("at bedtime").font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var logButton: some View {
        Button {
            isLogging = true
            Task {
                if let editing = request.editing {
                    _ = await CaffeineLogService.shared.update(
                        sample: editing,
                        milligrams: dose,
                        at: drinkTime,
                        drinkName: drinkName
                    )
                } else {
                    _ = await CaffeineLogService.shared.log(
                        milligrams: dose,
                        at: drinkTime,
                        drinkName: drinkName
                    )
                    reviews.recordLoggingDay(drinkTime)
                    reviews.considerAfterGoodForecast(
                        estimatedAtBedtime: health.bedtimeForecast.estimatedMilligrams,
                        threshold: settings.bedtimeThreshold
                    )
                }
                dismiss()
            }
        } label: {
            if isLogging {
                ProgressView().tint(.white)
            } else {
                Text(isEditing ? "Save changes" : "Log \(Int(dose)) mg")
            }
        }
        .buttonStyle(ForecastButtonStyle())
        .disabled(isLogging)
    }
}

struct CaffeineTimelineView: View {
    @EnvironmentObject private var store: StoreService
    @StateObject private var health = HealthKitService.shared
    @State private var days = 7
    @State private var history: [CaffeineDaySummary] = []
    @State private var showUpgrade = false

    /// Free access is seven days. The picker used to offer 30 and 90 and then
    /// silently render seven, which read as a broken chart rather than a locked
    /// feature.
    private static let freeDays = 7
    private static let ranges = [7, 30, 90]

    private var isLocked: Bool { !store.isPro && days > Self.freeDays }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                rangePicker

                if isLocked {
                    lockedRange
                } else {
                    chart
                    HStack(spacing: 12) {
                        metric("AVG DAILY", history.average(\.milligrams))
                        metric("AVG AT BED", history.average(\.estimatedAtBedtime))
                    }
                }

                if !store.isPro {
                    Button {
                        showUpgrade = true
                    } label: {
                        Label("Unlock full history and trends", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ForecastButtonStyle())
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Timeline")
        .task { await load() }
        .sheet(isPresented: $showUpgrade) {
            CaffeinePaywallView(paywallImpressionID: "caffeine_timeline", focus: .fullHistory)
        }
    }

    private var rangePicker: some View {
        Picker("Range", selection: $days) {
            ForEach(Self.ranges, id: \.self) { range in
                Text("\(range)D").tag(range)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: days) { _, _ in Task { await load() } }
    }

    private var lockedRange: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 32))
                .foregroundStyle(Theme.violet)
            Text("\(days) days is part of Caffeine+")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("The free timeline covers the last \(Self.freeDays) days. Caffeine+ opens the full \(Self.ranges.last ?? 90) days of intake and bedtime estimates.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("See Caffeine+") { showUpgrade = true }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.cyan)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var chart: some View {
        Chart(history) { day in
            BarMark(
                x: .value("Day", day.date, unit: .day),
                y: .value("Consumed", day.milligrams)
            )
            .foregroundStyle(Theme.violet.gradient)
            LineMark(
                x: .value("Day", day.date, unit: .day),
                y: .value("At bedtime", day.estimatedAtBedtime)
            )
            .foregroundStyle(Theme.cyan)
            .interpolationMethod(.catmullRom)
        }
        .frame(height: 250)
        .chartLegend(position: .bottom)
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private func metric(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption2.bold()).foregroundStyle(Theme.textSecondary)
            Text(CaffeineFormat.milligrams(value))
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func load() async {
        guard !isLocked else { return }
        history = (try? await health.fetchHistory(days: days)) ?? []
    }
}

struct CaffeineCurve: View {
    let samples: [CaffeineSample]
    let start: Date
    let end: Date
    let halfLifeHours: Double
    let selection: CaffeineSourceSelection
    let threshold: Double

    var body: some View {
        GeometryReader { geometry in
            let values = (0...32).map { index -> Double in
                let fraction = Double(index) / 32
                let date = start.addingTimeInterval(end.timeIntervalSince(start) * fraction)
                return CaffeineClearance.remaining(
                    samples: samples,
                    at: date,
                    selection: selection,
                    halfLifeHours: halfLifeHours
                )
            }
            let maximum = max(values.max() ?? 1, threshold, 1)
            ZStack(alignment: .bottomLeading) {
                Path { path in
                    let y = geometry.size.height * (1 - min(threshold / maximum, 1))
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
                .stroke(Theme.warning.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                Path { path in
                    for (index, value) in values.enumerated() {
                        let x = geometry.size.width * CGFloat(index) / CGFloat(values.count - 1)
                        let y = geometry.size.height * (1 - CGFloat(value / maximum))
                        if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(Theme.forecastGradient, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Estimated caffeine clearance curve through bedtime")
    }
}

struct ForecastButtonStyle: SwiftUI.ButtonStyle {
    func makeBody(configuration: SwiftUI.ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .padding(.horizontal, 18)
            .background(Theme.forecastGradient, in: RoundedRectangle(cornerRadius: 17))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private extension Array where Element == CaffeineDaySummary {
    func average(_ keyPath: KeyPath<CaffeineDaySummary, Double>) -> Double {
        guard !isEmpty else { return 0 }
        return reduce(0) { $0 + $1[keyPath: keyPath] } / Double(count)
    }
}
