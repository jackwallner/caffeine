import SwiftData
import SwiftUI
import WatchKit

/// The wrist screen, which is the product.
///
/// One number at the top and three buttons under it. Everything else — food
/// names, a database, search — is deliberately absent: the interaction has to
/// finish in a few seconds or opening a full tracker on the phone would have
/// been just as fast, and then there is no reason for this app to exist.
struct WatchTodayView: View {
    @StateObject private var settings = GoalSettings.shared
    @StateObject private var health = HealthKitService.shared
    @StateObject private var log = ProteinLogService.shared

    @Query(sort: \DailyProteinRecord.date, order: .reverse) private var records: [DailyProteinRecord]
    @Query private var localEntries: [LocalProteinEntry]

    @State private var showGramPicker = false
    @State private var justLogged: Double?
    /// Identifies the current undo window, so a second tap's timer cannot
    /// retire the row the newer tap just put back.
    @State private var undoToken = UUID()

    private var total: Double {
        if let today = records.first, DateHelpers.isSameDay(today.date, .now) {
            return today.proteinGrams
        }
        return ProteinReconciliation.total(samples: health.todaySamples, selection: settings.sourceSelection)
            + localEntries
                .filter { $0.countsTowardTotal && DateHelpers.isSameDay($0.date, .now) }
                .reduce(0) { $0 + max($1.grams, 0) }
    }

    private var target: Double { settings.targetGrams }
    private var remaining: Double { ProteinReconciliation.remaining(total: total, target: target) }
    private var overage: Double { ProteinReconciliation.overage(total: total, target: target) }
    private var canLog: Bool { ProAccess.isPro }

    var body: some View {
        // Everything the wrist needs has to fit above the fold on the smallest
        // watch (41mm, 224pt tall). A navigation title would cost ~30pt of that
        // to say "Protein" to someone who just opened Protein, and pushed the
        // action row off-screen — so the ring carries the identity instead.
        ScrollView {
            VStack(spacing: 8) {
                hero

                if canLog {
                    presetRow
                    // Undo takes the "Other" slot rather than appending a
                    // fourth row. On a 41mm screen a row below "Other" sits
                    // under the fold, and an undo you have to scroll to find is
                    // no use against the mis-tap it exists to catch — this puts
                    // it exactly where the finger already is.
                    if let justLogged {
                        undoButton(grams: justLogged)
                    } else {
                        otherButton
                    }
                } else {
                    lockedNotice
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showGramPicker) {
            WatchGramPicker { grams in
                Task { await add(grams) }
            }
        }
        .task {
            await health.synchronizeAuthorization()
            await health.refreshCache()
        }
    }

    private var hero: some View {
        ZStack {
            Circle()
                .stroke(Theme.ringTrack, style: StrokeStyle(lineWidth: 9, lineCap: .round))
            Circle()
                .trim(from: 0, to: min(ProteinReconciliation.progress(total: total, target: target), 1))
                .stroke(Theme.proteinGradient, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int((overage > 0.5 ? overage : remaining).rounded()))")
                    .font(Theme.bigNumber(34))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(overage > 0.5 ? "g over" : "g left")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(overage > 0.5 ? Theme.positive : Theme.textSecondary)
                Text(ProteinFormat.progressPair(total: total, target: target))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .padding(.horizontal, 18)
        }
        .frame(height: 96)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            overage > 0.5
                ? "\(Int(overage.rounded())) grams over your target"
                : "\(Int(remaining.rounded())) grams left of \(Int(target))"
        )
    }

    private var presetRow: some View {
        HStack(spacing: 5) {
            ForEach(Array(settings.quickAddPresets.enumerated()), id: \.offset) { _, preset in
                Button {
                    Task { await add(preset) }
                } label: {
                    Text("\(Int(preset))")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Theme.proteinGradient, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(Int(preset)) grams")
            }
        }
    }

    private var otherButton: some View {
        Button {
            showGramPicker = true
        } label: {
            Label("Other", systemImage: "plus")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 24)
        }
        .tint(Theme.protein)
    }

    private func undoButton(grams: Double) -> some View {
        Button {
            Task {
                await log.undoLast()
                justLogged = nil
            }
        } label: {
            Label("Undo \(Int(grams)) g", systemImage: "arrow.uturn.backward")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 24)
        }
        .buttonStyle(.bordered)
        .tint(Theme.textSecondary)
    }

    private var lockedNotice: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .foregroundStyle(Theme.protein)
            Text("Wrist logging is part of Protein+")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .multilineTextAlignment(.center)
            Text("Open Protein Tracker on your iPhone to turn it on. Your total and complication keep working.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 6)
    }

    private func add(_ grams: Double) async {
        guard await log.log(grams: grams) else { return }
        withAnimation(.easeInOut(duration: 0.15)) { justLogged = grams }
        undoToken = UUID()
        WKInterfaceDevice.current().play(.success)

        // Undo retires on its own and hands the slot back to "Other". It is an
        // affordance for the tap you just made, not an edit history.
        let token = undoToken
        try? await Task.sleep(for: .seconds(8))
        if undoToken == token {
            withAnimation(.easeInOut(duration: 0.15)) { justLogged = nil }
        }
    }
}

/// Digital-Crown gram entry for the amounts the presets do not cover.
private struct WatchGramPicker: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (Double) -> Void

    @State private var grams: Double = 25

    var body: some View {
        VStack(spacing: 8) {
            Text("\(Int(grams)) g")
                .font(Theme.bigNumber(40))
                .monospacedDigit()
                .focusable()
                .digitalCrownRotation(
                    $grams,
                    from: 5,
                    through: 200,
                    by: 5,
                    sensitivity: .medium,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )

            Button {
                onAdd(grams)
                dismiss()
            } label: {
                Text("Add")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .frame(maxWidth: .infinity)
            }
            .tint(Theme.protein)
        }
        .padding(.horizontal, 8)
    }
}
