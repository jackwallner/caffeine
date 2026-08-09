import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var settings: GoalSettings
    @EnvironmentObject private var store: StoreService
    @StateObject private var health = HealthKitService.shared
    @StateObject private var gate = PlusGateModel()

    @State private var editingPreset: Int?
    @State private var notificationsDenied = false

    /// Today's reconciled total, so a reminder scheduled from here carries the
    /// grams the user actually has left rather than a hard-coded zero.
    private var todayTotal: Double {
        ProteinReconciliation.total(samples: health.todaySamples, selection: settings.sourceSelection)
    }

    private func rescheduleReminder() async {
        await NotificationService.scheduleReminder(
            hour: settings.reminderHour,
            total: todayTotal,
            target: settings.targetGrams
        )
    }

    var body: some View {
        Form {
            healthSection
            targetSection
            presetSection
            plusSection
            appearanceSection
            supportSection
            aboutSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .plusGate(gate)
        .task {
            health.refreshWriteAuthorization()
            if settings.reminderEnabled, store.isPro {
                notificationsDenied = await !NotificationService.isAuthorized()
            }
        }
    }

    // MARK: - Apple Health

    private var healthSection: some View {
        Section {
            // Apple never reports the answer to a read request, so this row
            // reports evidence instead of a claim: samples have arrived, or
            // they have not. "Connected" for a user who tapped Don't Allow was
            // the single most misleading state in the app.
            LabeledContent("Reading protein") {
                readStatusChip
            }
            LabeledContent("Saving to Health") {
                statusChip(ok: health.canWrite, okLabel: "Allowed", badLabel: "Off")
            }

            Button {
                Task {
                    if health.isAuthorized {
                        await health.refreshCache()
                    } else {
                        try? await health.requestAuthorization()
                    }
                    await ProteinLogService.shared.retryPendingLocalEntries()
                }
            } label: {
                Label(
                    health.isAuthorized ? "Refresh from Apple Health" : "Connect Apple Health",
                    systemImage: health.isAuthorized ? "arrow.clockwise" : "heart.fill"
                )
            }

            Button {
                if let url = URL(string: "x-apple-health://") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open Apple Health", systemImage: "arrow.up.forward.app")
            }

            if let error = health.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.negative)
            }
        } header: {
            Text("Apple Health")
        } footer: {
            Text(healthFooterText)
        }
    }

    /// One explanation per state rather than one paragraph covering all of them.
    private var healthFooterText: String {
        switch health.readState {
        case .notDetermined:
            return "Protein from your other food apps counts here once Apple Health access is on."
        case .noData:
            return "Apple Health has not handed us a single protein sample yet. That is normal before anything is logged. If a food app should be writing protein, open Health › profile picture › Privacy › Apps › Protein Tracker and turn Dietary Protein on. iOS shows the permission sheet only once."
        case .receiving:
            return health.canWrite
                ? "Protein has been received from Apple Health. Grams you add here are written back so your other apps see them too."
                : "Protein has been received from Apple Health before, but writing is off. Grams you add are kept on this device and moved into Health as soon as it is allowed. Turn Dietary Protein on under Health › Privacy › Apps › Protein Tracker."
        }
    }

    @ViewBuilder
    private var readStatusChip: some View {
        switch health.readState {
        case .receiving:
            chip(text: "Data received", symbol: "checkmark.circle.fill", color: Theme.positive)
        case .notDetermined:
            chip(text: "Not set up", symbol: "exclamationmark.circle.fill", color: Theme.coral)
        case .noData:
            chip(text: "No data yet", symbol: "questionmark.circle.fill", color: Theme.textSecondary)
        }
    }

    private func chip(text: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text(text)
        }
        .foregroundStyle(color)
    }

    private func statusChip(ok: Bool, okLabel: String, badLabel: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            Text(ok ? okLabel : badLabel)
        }
        .foregroundStyle(ok ? Theme.positive : Theme.coral)
    }

    // MARK: - Target

    private var targetSection: some View {
        Section {
            VStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Daily target")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(Int(settings.targetGrams))")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Theme.protein)
                    Text("g")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Slider(
                    value: $settings.targetGrams,
                    in: ProteinTargets.allowedRange,
                    step: 1
                )
                .tint(Theme.protein)
                // The visible number is not a label: without these VoiceOver
                // announces the app's most important control as "slider".
                .accessibilityLabel("Daily protein target")
                .accessibilityValue("\(Int(settings.targetGrams)) grams")
                .accessibilityHint("Adjustable in 1 gram steps")
            }
            .padding(.vertical, 4)

            Picker("Tracking because", selection: $settings.reason) {
                ForEach(ProteinReason.allCases) { reason in
                    Text(reason.title).tag(reason)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.protein)
        } header: {
            Text("Your target")
        } footer: {
            Text("\(settings.reason.targetRationale) This app tracks a number you set; it does not diagnose, treat, or prescribe.")
        }
    }

    // MARK: - Quick add presets

    private var presetSection: some View {
        Section {
            ForEach(Array(settings.quickAddPresets.enumerated()), id: \.offset) { index, preset in
                HStack {
                    Label("Button \(index + 1)", systemImage: "bolt.fill")
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if store.isPro {
                        Stepper(
                            value: Binding(
                                get: { settings.quickAddPresets[index] },
                                set: { newValue in
                                    var presets = settings.quickAddPresets
                                    presets[index] = min(max(newValue, 1), 100)
                                    settings.quickAddPresets = presets
                                }
                            ),
                            in: 1...100,
                            step: 1
                        ) {
                            Text("\(Int(preset)) g")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .labelsHidden()
                        // Otherwise the hidden stepper label and the visible
                        // amount are announced as two controls with one value.
                        .accessibilityLabel("Button \(index + 1) amount")
                        .accessibilityValue("\(Int(preset)) grams")
                        Text("\(Int(preset)) g")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 56, alignment: .trailing)
                            .accessibilityHidden(true)
                    } else {
                        Text("\(Int(preset)) g")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(Theme.textTertiary)
                        Button {
                            gate.present(.quickAdd)
                        } label: {
                            PlusLockBadge()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } header: {
            Text("Quick add")
        } footer: {
            Text("The three buttons on the Today screen and on your Watch. Set them to the amounts you eat over and over.")
        }
    }

    // MARK: - Protein+

    private var plusSection: some View {
        Section {
            if store.isPro {
                Label("Protein+ active", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Theme.positive)
            } else {
                Button {
                    gate.present(nil)
                } label: {
                    Label(store.shortConversionCTALabel, systemImage: "bolt.fill")
                }
            }

            proToggle(
                feature: .reminders,
                isOn: Binding(
                    get: { settings.reminderEnabled },
                    set: { newValue in
                        guard newValue else {
                            settings.reminderEnabled = false
                            notificationsDenied = false
                            NotificationService.cancelReminder()
                            return
                        }
                        Task {
                            // Only persist "on" once iOS has agreed to deliver.
                            // A switch left on after a denied prompt promises a
                            // nudge that can never arrive. The request itself
                            // returns false when the prompt was already
                            // answered, so the settled state is what decides.
                            _ = await NotificationService.requestAuthorization()
                            let granted = await NotificationService.isAuthorized()
                            notificationsDenied = !granted
                            settings.reminderEnabled = granted
                            guard granted else { return }
                            await rescheduleReminder()
                        }
                    }
                )
            )

            if store.isPro, notificationsDenied {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Notifications are off for Protein Tracker", systemImage: "bell.slash.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.coral)
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.subheadline)
                }
            }

            if store.isPro, settings.reminderEnabled {
                Picker("Reminder time", selection: $settings.reminderHour) {
                    ForEach(12...22, id: \.self) { hour in
                        Text(hourLabel(hour)).tag(hour)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.protein)
                // The scheduled request carries a fixed hour, so moving the
                // picker has to rewrite it, or the new time takes
                // effect only after the next log.
                .onChange(of: settings.reminderHour) { _, _ in
                    Task { await rescheduleReminder() }
                }
            }

            Button("Restore Purchases") {
                Task { await store.restore() }
            }

            #if DEBUG
            Toggle("Local Pro override", isOn: Binding(
                get: { store.isPro },
                set: { store.setLocalOverride(isPro: $0) }
            ))
            #endif
        } header: {
            Text("Protein+")
        } footer: {
            Text(store.isPro
                ? "Wrist logging, one-tap presets, reminders, and thirty days of history are on."
                : "Reading your protein, source controls, the widget, and the Watch complication stay free. Protein+ adds logging from your wrist and phone, reminders, and thirty days of history.")
        }
    }

    /// Locked features read as real settings toggles. For non-subscribers the
    /// toggle always shows OFF and flipping it on never sticks — it snaps back
    /// and opens the personalized offer instead.
    @ViewBuilder
    private func proToggle(feature: PlusFeature, isOn: Binding<Bool>) -> some View {
        let gated = Binding(
            get: { store.isPro && isOn.wrappedValue },
            set: { newValue in
                if store.isPro {
                    isOn.wrappedValue = newValue
                } else if newValue {
                    gate.present(feature)
                }
            }
        )
        Toggle(isOn: gated) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(feature.title)
                            .font(.subheadline.weight(.semibold))
                        if !store.isPro {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    Text(feature.detail)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            } icon: {
                Image(systemName: feature.symbol).foregroundStyle(Theme.protein)
            }
        }
        .tint(Theme.protein)
        // A switch whose label is assembled from a stack can surface as a blank
        // control, which for a locked feature tells a VoiceOver user nothing at
        // all about what it would turn on.
        .accessibilityLabel(store.isPro ? feature.title : "\(feature.title), Protein+ required")
        .accessibilityHint(store.isPro ? feature.detail : "Opens the Protein+ offer")
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? .now
        return date.formatted(.dateTime.hour().minute())
    }

    // MARK: - Rest

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $settings.appearance) {
                ForEach(AppAppearance.allCases, id: \.rawValue) { appearance in
                    Text(appearance.label).tag(appearance)
                }
            }
        }
    }

    private var supportSection: some View {
        Section {
            Button {
                ReviewPromptCoordinator.shared.requestEnjoymentPrompt()
            } label: {
                Label("Rate Protein Tracker", systemImage: "star")
            }
            Button {
                ReviewPromptCoordinator.shared.requestFeedback()
            } label: {
                Label("Send feedback", systemImage: "envelope")
            }
        } header: {
            Text("Support")
        } footer: {
            Text("Feedback opens your mail app with a private draft. No analytics, no account.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Bundle.main.appVersionLabel)
            Link("Privacy Policy", destination: ProteinLinks.privacyPolicy)
            Link("Terms of Use", destination: ProteinLinks.standardEULA)
            Text("Protein Tracker helps you follow a daily protein target you or your clinician set. It does not diagnose, treat, cure, or prevent any condition, and it is not a substitute for medical or dietary advice.")
                .font(.caption)
        }
    }
}
