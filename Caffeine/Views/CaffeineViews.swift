import Charts
import RevenueCat
import SwiftUI

private struct PreviewRequest: Identifiable {
    let id = UUID()
    let dose: Double
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

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 24) {
                TabView(selection: $page) {
                    onboardingPage(
                        icon: "waveform.path.ecg",
                        title: "See what may still be active",
                        detail: "Log caffeine in milligrams. Caffeine estimates what remains now and at bedtime using a half-life model."
                    )
                    .tag(0)

                    VStack(spacing: 24) {
                        onboardingPage(
                            icon: "moon.stars.fill",
                            title: "Plan around your bedtime",
                            detail: "Preview a drink before logging it. The forecast changes with the dose, time, and your settings."
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
                        detail: "Caffeine reads and writes dietary caffeine in Apple Health. You can include or exclude each source."
                    )
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Text("Estimates are informational and vary by person. Caffeine does not diagnose, treat, or prescribe.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button(page == 2 ? "Connect Apple Health" : "Continue") {
                    if page < 2 {
                        withAnimation { page += 1 }
                    } else {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: bedtime)
                        settings.bedtimeMinutes = (parts.hour ?? 22) * 60 + (parts.minute ?? 30)
                        Task {
                            try? await HealthKitService.shared.requestAuthorization()
                            settings.hasCompletedSetup = true
                            await HealthKitService.shared.refreshCache()
                        }
                    }
                }
                .buttonStyle(ForecastButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
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
    @State private var preview: PreviewRequest?

    init() {
        #if DEBUG
        let initialPreview = ProcessInfo.processInfo.arguments.contains("-PreviewSnapshot")
            ? PreviewRequest(dose: 120)
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
                previewButton
                quickAdds
                todayCard
                recentEntries
                estimateNote
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Caffeine")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await health.refreshCache() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh")
            }
        }
        .refreshable { await health.refreshCache() }
        .sheet(item: $preview) { request in
            DrinkPreviewSheet(initialDose: request.dose)
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

    private var previewButton: some View {
        Button {
            preview = PreviewRequest(dose: 100)
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Preview a drink")
                    .fontWeight(.semibold)
                Spacer()
                Text("before logging")
                    .font(.caption)
                    .opacity(0.8)
            }
        }
        .buttonStyle(ForecastButtonStyle())
    }

    private var quickAdds: some View {
        HStack(spacing: 10) {
            ForEach(settings.quickAddPresets, id: \.self) { dose in
                Button {
                    preview = PreviewRequest(dose: dose)
                } label: {
                    VStack(spacing: 4) {
                        Text("\(Int(dose))")
                            .font(.title3.bold())
                        Text("mg preview")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textPrimary)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 16))
            }
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
                    HStack {
                        Image(systemName: "drop.fill")
                            .foregroundStyle(Theme.violet)
                        Text(CaffeineFormat.milligrams(sample.milligrams))
                            .fontWeight(.semibold)
                        Spacer()
                        Text(CaffeineFormat.time(sample.endDate))
                            .foregroundStyle(Theme.textSecondary)
                        Button(role: .destructive) {
                            Task { _ = await log.delete(sample: sample) }
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    .padding(.vertical, 4)
                }
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

struct DrinkPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: CaffeineSettings
    @StateObject private var health = HealthKitService.shared
    @State private var dose: Double
    @State private var drinkTime = Date.now
    @State private var isLogging = false

    init(initialDose: Double) {
        _dose = State(initialValue: initialDose)
    }

    private var forecast: CaffeineForecast {
        CaffeineClearance.forecastAdding(
            dose: dose,
            at: drinkTime,
            samples: health.recentSamples,
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 4) {
                        Text("\(Int(dose)) mg")
                            .font(.system(size: 50, weight: .bold, design: .rounded))
                        Stepper("Dose", value: $dose, in: 5...500, step: 5)
                            .labelsHidden()
                    }

                    DatePicker("Drink time", selection: $drinkTime, in: ...settings.bedtimeDate)
                        .datePickerStyle(.compact)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("IF YOU LOG THIS")
                            .font(.caption.bold())
                            .foregroundStyle(Theme.textSecondary)
                        HStack(alignment: .firstTextBaseline) {
                            Text(CaffeineFormat.milligrams(forecast.estimatedMilligrams))
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                            Text("estimated at bedtime")
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Divider()
                        Label(
                            "This drink adds about \(CaffeineFormat.milligrams(doseContribution)) to the bedtime estimate",
                            systemImage: "moon.stars.fill"
                        )
                        .font(.subheadline)
                        Text("Reference range at bedtime: \(CaffeineFormat.range(forecast))")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(20)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))

                    Button {
                        isLogging = true
                        Task {
                            _ = await CaffeineLogService.shared.log(milligrams: dose, at: drinkTime)
                            dismiss()
                        }
                    } label: {
                        if isLogging {
                            ProgressView().tint(.white)
                        } else {
                            Text("Log \(Int(dose)) mg")
                        }
                    }
                    .buttonStyle(ForecastButtonStyle())
                    .disabled(isLogging)

                    Text("Logging is free. The estimate uses your selected half-life and is not a measure of caffeine in your bloodstream.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(18)
            }
            .background(Theme.background)
            .navigationTitle("Drink preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct CaffeineTimelineView: View {
    @EnvironmentObject private var store: StoreService
    @StateObject private var health = HealthKitService.shared
    @State private var days = 7
    @State private var history: [CaffeineDaySummary] = []
    @State private var showUpgrade = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Picker("Range", selection: $days) {
                    Text("7D").tag(7)
                    Text("30D").tag(30)
                    Text("90D").tag(90)
                }
                .pickerStyle(.segmented)
                .onChange(of: days) { _, _ in Task { await load() } }

                Chart(history) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Caffeine", day.milligrams)
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

                HStack(spacing: 12) {
                    metric("AVG DAILY", history.average(\.milligrams))
                    metric("AVG AT BED", history.average(\.estimatedAtBedtime))
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
        .sheet(isPresented: $showUpgrade) { CaffeinePurchaseView() }
    }

    private func metric(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption2.bold()).foregroundStyle(Theme.textSecondary)
            Text(CaffeineFormat.milligrams(value)).font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func load() async {
        let requested = store.isPro ? days : min(days, 7)
        history = (try? await health.fetchHistory(days: requested)) ?? []
    }
}

struct CaffeinePlannerView: View {
    @EnvironmentObject private var settings: CaffeineSettings
    @StateObject private var health = HealthKitService.shared
    @State private var dose = 120.0
    @State private var drinkTime = Date.now
    @State private var showPreview = false

    private var forecast: CaffeineForecast {
        CaffeineClearance.forecastAdding(
            dose: dose,
            at: drinkTime,
            samples: health.recentSamples,
            forecastDate: settings.bedtimeDate,
            selection: settings.sourceSelection,
            halfLifeHours: settings.halfLifeHours
        )
    }

    private var latestTime: Date? {
        CaffeineClearance.latestTimeForDose(
            dose: dose,
            existingSamples: health.recentSamples,
            bedtime: settings.bedtimeDate,
            threshold: settings.bedtimeThreshold,
            selection: settings.sourceSelection,
            halfLifeHours: settings.halfLifeHours
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    Text("PROPOSED DOSE")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.textSecondary)
                    Text("\(Int(dose)) mg")
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                    Slider(value: $dose, in: 5...400, step: 5)
                        .tint(Theme.violet)
                    DatePicker("At", selection: $drinkTime, in: ...settings.bedtimeDate)
                }
                .padding(22)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))

                VStack(alignment: .leading, spacing: 16) {
                    Text("YOUR FORECAST")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.textSecondary)
                    HStack {
                        forecastValue("WITHOUT", health.bedtimeForecast.estimatedMilligrams)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(Theme.textSecondary)
                        forecastValue("WITH DRINK", forecast.estimatedMilligrams)
                    }
                    Divider()
                    if let latestTime {
                        Label(
                            latestTime >= settings.bedtimeDate
                                ? "This dose stays within your bedtime preference through bedtime"
                                : "Latest modeled time for this dose: \(CaffeineFormat.time(latestTime))",
                            systemImage: "clock.badge.checkmark"
                        )
                        .foregroundStyle(Theme.mint)
                    } else {
                        Label(
                            "Your existing bedtime estimate is already above your \(CaffeineFormat.milligrams(settings.bedtimeThreshold)) preference",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(Theme.warning)
                    }
                    Text("A preference is not a safety limit. The calculation is an estimate based on your settings.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(22)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))

                Button("Open full drink preview") { showPreview = true }
                    .buttonStyle(ForecastButtonStyle())
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Planner")
        .sheet(isPresented: $showPreview) { DrinkPreviewSheet(initialDose: dose) }
    }

    private func forecastValue(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2.bold()).foregroundStyle(Theme.textSecondary)
            Text(CaffeineFormat.milligrams(value)).font(.title2.bold())
            Text("at bedtime").font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CaffeineSettingsView: View {
    @EnvironmentObject private var settings: CaffeineSettings
    @EnvironmentObject private var store: StoreService
    @StateObject private var health = HealthKitService.shared
    @State private var showPurchase = false
    @State private var reminderChangeInFlight = false

    private var bedtimeBinding: Binding<Date> {
        Binding {
            Calendar.current.date(
                bySettingHour: settings.bedtimeMinutes / 60,
                minute: settings.bedtimeMinutes % 60,
                second: 0,
                of: .now
            ) ?? .now
        } set: { value in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: value)
            settings.bedtimeMinutes = (parts.hour ?? 22) * 60 + (parts.minute ?? 30)
        }
    }

    var body: some View {
        Form {
            Section("Forecast") {
                DatePicker("Bedtime", selection: bedtimeBinding, displayedComponents: .hourAndMinute)
                VStack(alignment: .leading) {
                    HStack {
                        Text("Half-life")
                        Spacer()
                        Text("\(settings.halfLifeHours, specifier: "%.1f") hours")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.halfLifeHours, in: 3...8, step: 0.5)
                }
                Stepper(
                    "Bedtime preference: \(CaffeineFormat.milligrams(settings.bedtimeThreshold))",
                    value: $settings.bedtimeThreshold,
                    in: 5...100,
                    step: 5
                )
                Text("The FDA describes a typical caffeine half-life of about 4 to 6 hours. Your estimate can be adjusted because clearance varies.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Apple Health") {
                Button("Connect or review access") {
                    Task {
                        try? await health.requestAuthorization()
                        await health.refreshCache()
                    }
                }
                NavigationLink("Included sources") { CaffeineSourcesView() }
                LabeledContent("Write access", value: health.canWrite ? "On" : "Off")
            }

            Section("Quick previews") {
                ForEach(settings.quickAddPresets.indices, id: \.self) { index in
                    Stepper(
                        "Preset \(index + 1): \(CaffeineFormat.milligrams(settings.quickAddPresets[index]))",
                        value: Binding(
                            get: { settings.quickAddPresets[index] },
                            set: { value in
                                guard store.isPro else {
                                    showPurchase = true
                                    return
                                }
                                settings.quickAddPresets[index] = value
                            }
                        ),
                        in: 5...400,
                        step: 5
                    )
                }
                if !store.isPro {
                    Button("Customize with Caffeine+") { showPurchase = true }
                }
            }

            Section("Reminder") {
                Toggle("Bedtime estimate reminder", isOn: Binding(
                    get: { settings.reminderEnabled },
                    set: { enabled in
                        guard !reminderChangeInFlight else { return }
                        reminderChangeInFlight = true
                        Task {
                            if enabled {
                                let granted = await NotificationService.requestAuthorization()
                                settings.reminderEnabled = granted
                                if granted { await health.refreshCache() }
                            } else {
                                settings.reminderEnabled = false
                                NotificationService.cancelReminder()
                            }
                            reminderChangeInFlight = false
                        }
                    }
                ))
            }

            Section("Caffeine+") {
                LabeledContent("Status", value: store.isPro ? "Active" : "Free")
                Button(store.isPro ? "Manage purchase" : "See Caffeine+") { showPurchase = true }
                Button("Restore purchases") { Task { await store.restore() } }
            }

            Section("About") {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases, id: \.rawValue) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
                Link("Privacy policy", destination: CaffeineLinks.privacyPolicy)
                Link("Support", destination: CaffeineLinks.support)
                Text("Caffeine provides mathematical estimates for personal awareness. It is not medical advice or a measurement of caffeine in the body.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showPurchase) { CaffeinePurchaseView() }
    }
}

struct CaffeineSourcesView: View {
    @EnvironmentObject private var settings: CaffeineSettings
    @StateObject private var health = HealthKitService.shared

    private var sources: [CaffeineSourceStatus] {
        let live = CaffeineClearance.sources(samples: health.recentSamples, selection: settings.sourceSelection)
        let liveIDs = Set(live.map(\.bundleID))
        let stored = settings.excludedSourceNames.compactMap { id, name -> CaffeineSourceStatus? in
            guard !liveIDs.contains(id) else { return nil }
            return CaffeineSourceStatus(
                bundleID: id,
                name: name,
                milligrams: 0,
                latestEntry: .distantPast,
                sampleCount: 0,
                isOurs: false,
                isIncluded: false,
                localOnlyMilligrams: 0
            )
        }
        return live + stored
    }

    var body: some View {
        List {
            Section {
                Text("All included dietary caffeine samples contribute once. Your entries from Caffeine always remain included.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Sources from the last 48 hours") {
                ForEach(sources) { source in
                    Toggle(isOn: Binding(
                        get: { source.isIncluded },
                        set: { settings.setSourceIncluded($0, bundleID: source.bundleID, name: source.name) }
                    )) {
                        VStack(alignment: .leading) {
                            Text(source.name)
                            Text("\(CaffeineFormat.milligrams(source.milligrams)) from \(source.sampleCount) entries")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(source.isOurs)
                }
            }
        }
        .navigationTitle("Sources")
    }
}

struct CaffeinePurchaseView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: StoreService

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Theme.forecastGradient)
                    Text("Caffeine+")
                        .font(.largeTitle.bold())
                    Text("Keep the forecast free. Upgrade for full history, trends, custom quick previews, and bedtime reminders.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textSecondary)

                    ForEach(store.packages, id: \.identifier) { package in
                        Button {
                            Task {
                                if await store.purchase(package) == .purchased { dismiss() }
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(package.caffeineDisplayName).font(.headline)
                                    if let trial = store.eligibleIntroLabel(for: package) {
                                        Text(trial).font(.caption).foregroundStyle(Theme.mint)
                                    }
                                }
                                Spacer()
                                Text(package.caffeinePriceLabel).fontWeight(.semibold)
                            }
                            .padding(18)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                    }

                    if store.packages.isEmpty {
                        ProgressView("Loading plans")
                            .task { store.start(forceRefresh: true) }
                    }

                    Button("Restore purchases") { Task { await store.restore() } }
                    HStack {
                        Link("Terms", destination: CaffeineLinks.standardEULA)
                        Text("·")
                        Link("Privacy", destination: CaffeineLinks.privacyPolicy)
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    if let error = store.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(22)
            }
            .defaultScrollAnchor(.top)
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear { store.trackPaywallImpression(id: "caffeine_paywall") }
    }
}

private struct CaffeineCurve: View {
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

private struct ForecastButtonStyle: SwiftUI.ButtonStyle {
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
