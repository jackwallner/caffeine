import SwiftUI
@preconcurrency import RevenueCat

/// First run. Four steps, and only one of them asks the user for anything they
/// have to think about.
///
/// The audience fork lives here and nowhere else: picking a reason sets a
/// suggested number and the sentence under it, and then the app is the same app
/// for everybody (`docs/positioning.md` §2). No branch creates a second flow, a
/// second paywall, or a second theme.
struct OnboardingView: View {
    private enum Step {
        case welcome
        case reason
        case target
        case trial
    }

    @EnvironmentObject private var settings: GoalSettings
    @EnvironmentObject private var store: StoreService
    @StateObject private var health = HealthKitService.shared

    @State private var step: Step = .welcome
    @State private var hasRequestedHealthAccess = false
    @State private var isStartingTrial = false
    @State private var isRestoring = false
    @State private var trialError: String?
    @State private var trialPending = false
    @State private var showPaywallFallback = false

    // Local edit buffers so a skipped setup leaves stored defaults untouched.
    @State private var reasons: Set<ProteinReason> = [.strength]
    @State private var target: Double = 140
    @State private var targetText = "140"
    @State private var bodyWeightKilograms: Double?
    @State private var isFetchingBodyWeight = false
    @State private var bodyWeightUnavailable = false
    /// Once the user drags the target slider we stop re-anchoring it to the
    /// reason, so a deliberate choice is never overwritten by a later tap.
    @State private var hasEditedTarget = false

    var body: some View {
        VStack(spacing: 0) {
            backBar

            if step == .trial {
                ScrollView {
                    trialPage
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                ScrollView {
                    Group {
                        switch step {
                        case .welcome: welcomePage
                        case .reason: reasonPage
                        case .target: targetPage
                        case .trial: EmptyView()
                        }
                    }
                    // The back row above already carries part of the old 48pt of
                    // headroom, so this drops to keep the welcome art where it was.
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                    .padding(.horizontal, 24)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            bottomBar
        }
        .background(Theme.background.ignoresSafeArea())
        .task {
            reasons = settings.reasons
            target = settings.targetGrams
            targetText = String(Int(settings.targetGrams))
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if let idx = args.firstIndex(of: "-OnboardingPage"), idx + 1 < args.count,
               let page = Int(args[idx + 1]) {
                step = [Step.welcome, .reason, .target, .trial][min(max(page, 0), 3)]
            }
            #endif
        }
        // The trial page is the paywall, and it is the fourth step — counting the
        // impression from `.task` reported one for every install that opened the
        // welcome screen and never reached it, which is the same off-screen
        // over-count `PaywallView` guards with `isActiveTab`.
        .onChange(of: step) { _, newStep in
            guard newStep == .trial else { return }
            store.trackPaywallImpression(id: "protein_onboarding_trial", oncePerSession: true)
        }
        // A purchase (or restore) that flips Pro on finishes onboarding.
        .onChange(of: store.isPro) { _, isPro in
            if isPro { finishOnboarding() }
        }
        .sheet(isPresented: $showPaywallFallback) { PaywallView() }
    }

    private func finishOnboarding() {
        settings.reasons = reasons
        settings.targetGrams = target
        if let bodyWeightKilograms {
            settings.bodyWeightKilograms = bodyWeightKilograms
        }
        settings.hasCompletedSetup = true
    }

    /// Fire the HealthKit prompt once, when the user leaves the welcome screen,
    /// so the first thing they see is our heads-up rather than the system sheet.
    private func requestHealthAccessIfNeeded() async {
        guard !hasRequestedHealthAccess else { return }
        hasRequestedHealthAccess = true
        try? await health.requestAuthorization()
        bodyWeightKilograms = await health.fetchBodyMassKilograms()
        anchorTargetToReason()
        Task { await health.refreshCache() }
    }

    /// Snap the target to the reason-anchored suggestion unless the user has
    /// already moved the slider themselves.
    private func anchorTargetToReason() {
        guard !requiresManualTarget else {
            targetText = ""
            return
        }
        guard !hasEditedTarget else { return }
        guard let suggestion = ProteinTargets.suggestedTarget(
            for: reasons,
            bodyWeightKilograms: bodyWeightKilograms
        ) else { return }
        target = suggestion
        targetText = String(Int(suggestion))
    }

    private var requiresManualTarget: Bool { ProteinReason.requiresManualTarget(reasons) }

    private var targetIsValid: Bool {
        guard let value = Double(targetText) else { return false }
        return ProteinTargets.allowedRange.contains(value)
    }

    private var targetTextBinding: Binding<String> {
        Binding(
            get: { targetText },
            set: { newValue in
                targetText = newValue.filter(\.isNumber)
                guard let value = Double(targetText), ProteinTargets.allowedRange.contains(value) else { return }
                target = value
                hasEditedTarget = true
            }
        )
    }

    // MARK: - Back

    /// The reason a user picks steers the suggested number and the sentence under
    /// it, and it was previously unreachable once they hit Continue — the only
    /// way back was to finish setup and go looking in Settings. The row keeps its
    /// height on every step so nothing below it moves as the button appears.
    private var backBar: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    switch step {
                    case .reason: step = .welcome
                    case .target: step = .reason
                    // The trial step already has its own free exit, and going
                    // back from it would put the user behind a paywall they have
                    // just declined.
                    case .welcome, .trial: break
                    }
                }
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .opacity(canGoBack ? 1 : 0)
            .allowsHitTesting(canGoBack)
            .accessibilityHidden(!canGoBack)
            Spacer()
        }
        .frame(height: 30)
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private var canGoBack: Bool { step == .reason || step == .target }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.proteinGradient)
                        .frame(width: 76, height: 76)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text("Grams left, all day")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("One number, on your wrist. No calorie counting, no food database, no photo guessing.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 16) {
                WelcomePoint(
                    icon: "applewatch",
                    color: Theme.protein,
                    title: "Lives on your watch face",
                    detail: "A complication showing how many grams you have left, and buttons to add the food you eat every day."
                )
                WelcomePoint(
                    icon: "arrow.triangle.merge",
                    color: Theme.proteinDeep,
                    title: "Counts what you already log",
                    detail: "Next we'll ask for Apple Health access. Protein from your existing food app counts here, and grams you add here go back to Health."
                )
                WelcomePoint(
                    icon: "lock.fill",
                    color: Theme.positive,
                    title: "Stays on your device",
                    detail: "No account, no cloud, no sign-up. Your data never leaves your devices."
                )
            }
        }
    }

    private var reasonPage: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.protein)
                Text("Why protein?")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("Pick as many as apply. This helps you enter your daily target. Everything else in the app is the same either way.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                ForEach(ProteinReason.allCases) { option in
                    reasonCard(option)
                }
            }
        }
    }

    /// Multi-select. The reasons stack in real life — a lifter on a GLP-1, a
    /// post-bariatric patient who also trains — and forcing one made the
    /// suggested number wrong for whichever half was left out.
    ///
    /// Re-anchoring on every tap is deliberate: the suggestion follows the set
    /// until the user takes the number over by moving the slider, and then it
    /// stops following anything.
    private func reasonCard(_ option: ProteinReason) -> some View {
        let selected = reasons.contains(option)
        return Button {
            if selected {
                // Never empty: with nothing picked there is no sentence under
                // the target and no basis for a suggestion.
                if reasons.count > 1 { reasons.remove(option) }
            } else {
                reasons.insert(option)
            }
            hasEditedTarget = false
            anchorTargetToReason()
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: option.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? .white : Theme.protein)
                    .frame(width: 40, height: 40)
                    .background(selected ? AnyShapeStyle(Theme.proteinGradient) : AnyShapeStyle(Theme.protein.opacity(0.14)), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(option.detail)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selected ? Theme.protein : Theme.textTertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? Theme.protein : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private var targetPage: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Image(systemName: "scalemass")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.protein)
                Text("Your daily target")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(ProteinReason.rationale(for: reasons))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("Target", text: targetTextBinding)
                        .font(Theme.bigNumber(58))
                        .foregroundStyle(Theme.protein)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                        .frame(maxWidth: 180)
                        .accessibilityLabel("Daily protein target")
                        .accessibilityValue(targetIsValid ? "\(Int(target)) grams" : "Not entered")
                    Text("g")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(targetIsValid ? Theme.protein.opacity(0.45) : Theme.coral, lineWidth: 1)
                }

                Text("grams per day, from 20 to 400")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)

                if !requiresManualTarget {
                    Slider(value: $target, in: ProteinTargets.allowedRange, step: 1)
                        .tint(Theme.protein)
                        .onChange(of: target) { _, newValue in
                            hasEditedTarget = true
                            targetText = String(Int(newValue))
                        }
                        .accessibilityLabel("Daily protein target")
                        .accessibilityValue("\(Int(target)) grams")
                        .accessibilityHint("Adjustable in 1 gram steps")
                }

                if !requiresManualTarget, let bodyWeightKilograms {
                    Text("Suggested from the \(Int(bodyWeightKilograms.rounded())) kg body weight in Apple Health.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                } else if !requiresManualTarget {
                    // The Info.plist says body weight is read *if the user asks
                    // for a suggestion*, so this is where the asking happens.
                    // Without it the weight read was never authorized and every
                    // user silently got the reason's fallback number.
                    Button {
                        Task { await suggestFromBodyWeight() }
                    } label: {
                        if isFetchingBodyWeight {
                            ProgressView()
                        } else {
                            Label("Suggest from my body weight", systemImage: "scalemass")
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.protein)
                    .disabled(isFetchingBodyWeight)

                    if bodyWeightUnavailable {
                        Text("No body weight in Apple Health, so the starting number stays as it is.")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Theme.cardSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))

            Text("This app tracks the number you enter. It does not set a medical target.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Asks for body-weight read access, then re-anchors the suggestion.
    private func suggestFromBodyWeight() async {
        isFetchingBodyWeight = true
        defer { isFetchingBodyWeight = false }
        try? await health.requestBodyMassAuthorization()
        guard let kilograms = await health.fetchBodyMassKilograms() else {
            bodyWeightUnavailable = true
            return
        }
        bodyWeightKilograms = kilograms
        bodyWeightUnavailable = false
        // An explicit request overrides an earlier drag: the user just asked
        // for the suggestion, so give them the suggestion.
        if let suggestion = ProteinTargets.suggestedTarget(for: reasons, bodyWeightKilograms: kilograms) {
            target = suggestion
            targetText = String(Int(suggestion))
        }
    }

    /// Final step. It scrolls when larger text needs more room.
    private var trialPage: some View {
        VStack(spacing: 18) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.proteinGradient)

                VStack(spacing: 6) {
                    Text("The month behind the number")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text("Logging is free, on your phone and your wrist, along with the widget and the complication. Protein+ is what a month of it adds up to:")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    TrialSellingPoint(
                        icon: "calendar",
                        color: Theme.positive,
                        title: "Thirty days of history",
                        detail: "A bad week is visible as a week, not a feeling"
                    )
                    TrialSellingPoint(
                        icon: "flame.fill",
                        color: Theme.protein,
                        title: "Streaks and trends",
                        detail: "Days on target in a row, and this month against last"
                    )
                    TrialSellingPoint(
                        icon: "bell.badge",
                        color: Theme.proteinDeep,
                        title: "Evening reminder",
                        detail: "Know the exact grams left before the day ends"
                    )
                }

                // Apple 3.1.2(c): the billed amount is the largest pricing
                // element on this step — bigger than the CTA label and the
                // disclosure. It lives in the page body, not the bottom bar, so
                // the primary button keeps the exact frame Continue occupied.
                if let yearly = store.yearlyPackage {
                    BilledAmountBlock(
                        amount: ConversionCopy.billedAmount(priceLabel: yearly.proteinPriceLabel),
                        note: ConversionCopy.billedNote(
                            trialLabel: yearly.proteinIntroOfferLabel,
                            eligibleForTrial: store.isEligibleForIntroOffer(yearly)
                        )
                    )
                    // A price has to read as its own commitment, not as the tail
                    // of the last selling point above it.
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.cardSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                }
        }
    }

    // MARK: - Bottom bar (zero-shift primary CTA)

    private var bottomBar: some View {
        VStack(spacing: 12) {
            aboveButtonContent

            primaryButton

            // Fixed legal-footer slot. Identical view on every page so its
            // height never changes; only visible on the trial page.
            legalFooter
                .opacity(step == .trial ? 1 : 0)
                .allowsHitTesting(step == .trial)
                .accessibilityHidden(step != .trial)
        }
        .padding(.top, 12)
        .padding(.bottom, 24)
        .background(Theme.background)
    }

    @ViewBuilder
    private var aboveButtonContent: some View {
        switch step {
        case .welcome: welcomeTrustLine
        case .reason, .target: EmptyView()
        case .trial: trialSoftExitAndDisclosure
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .welcome:
            Button {
                Task { await requestHealthAccessIfNeeded() }
                withAnimation(.easeInOut(duration: 0.25)) { step = .reason }
            } label: {
                primaryLabel("Continue")
            }
            .padding(.horizontal, 24)
        case .reason:
            Button {
                settings.reasons = reasons
                anchorTargetToReason()
                withAnimation(.easeInOut(duration: 0.25)) { step = .target }
            } label: {
                primaryLabel("Continue")
            }
            .padding(.horizontal, 24)
        case .target:
            Button {
                settings.targetGrams = target
                withAnimation(.easeInOut(duration: 0.25)) { step = .trial }
            } label: {
                primaryLabel("Continue")
            }
            .disabled(!targetIsValid)
            .padding(.horizontal, 24)
        case .trial:
            if store.yearlyPackage != nil {
                Button {
                    startTrial()
                } label: {
                    ZStack {
                        primaryLabel(trialCTATitle)
                            .opacity(isStartingTrial ? 0 : 1)
                        if isStartingTrial {
                            ProgressView().tint(.white)
                        }
                    }
                }
                .disabled(isStartingTrial)
                .padding(.horizontal, 24)
            } else {
                Button {
                    finishOnboarding()
                } label: {
                    primaryLabel("Get Started")
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private func primaryLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.protein, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
    }

    private var welcomeTrustLine: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.protein)
            Text("Stays on your device. No account.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }

    /// Trial-page content ABOVE the primary button: the de-emphasized free exit,
    /// then disclosure or error — none of which can shift the CTA.
    private var trialSoftExitAndDisclosure: some View {
        VStack(spacing: 12) {
            if store.yearlyPackage != nil {
                Button {
                    finishOnboarding()
                } label: {
                    Text("Get Started")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
            }

            // Render no disclosure until the package loads — never a phantom
            // price. Pending and error each replace disclosure in the same slot.
            if trialPending {
                Text(ConversionCopy.purchasePendingMessage)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.protein)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            } else if let trialError {
                Text(trialError)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.negative)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            } else if let disclosure = trialDisclosure {
                Text(disclosure)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            } else {
                Text("Protein+ is temporarily unavailable. Continue with the free app and try again later from Settings.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }
        }
    }

    private var legalFooter: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                restoreOnboardingButton
                Link("Terms", destination: ProteinLinks.standardEULA)
                Link("Privacy", destination: ProteinLinks.privacyPolicy)
            }
            VStack(spacing: 6) {
                restoreOnboardingButton
                HStack(spacing: 14) {
                    Link("Terms", destination: ProteinLinks.standardEULA)
                    Link("Privacy", destination: ProteinLinks.privacyPolicy)
                }
            }
        }
        .font(.system(.caption, design: .rounded, weight: .semibold))
        .foregroundStyle(Theme.textSecondary)
    }

    private var restoreOnboardingButton: some View {
        Button(isRestoring ? "Restoring…" : "Restore") { startRestore() }
            .buttonStyle(.plain)
            .disabled(isRestoring)
    }

    // MARK: - Trial copy

    /// Neutral by design: the trial length and the billed amount are stated
    /// together in the price line directly above, so the button carries no
    /// pricing words that could outweigh it (Apple 3.1.2(c)).
    private var trialCTATitle: String { "Continue with Protein+" }

    private var trialDisclosure: String? {
        guard let yearly = store.yearlyPackage else { return nil }
        return ConversionCopy.disclosure(
            trialLabel: yearly.proteinIntroOfferLabel,
            priceLabel: yearly.proteinPriceLabel,
            eligibleForTrial: store.isEligibleForIntroOffer(yearly)
        )
    }

    // MARK: - Actions

    private func startTrial() {
        guard let yearly = store.yearlyPackage else {
            showPaywallFallback = true
            return
        }
        trialError = nil
        trialPending = false
        isStartingTrial = true
        Task {
            let state = await store.purchase(yearly)
            isStartingTrial = false
            // Pending is neither a success nor a failure: Apple has the purchase
            // and has not answered. Say so rather than leaving the button sitting
            // there as though the tap did nothing.
            if state == .pending {
                trialPending = true
                return
            }
            if let message = store.errorMessage { trialError = message }
            // Success routes through onChange(store.isPro) -> finishOnboarding().
        }
    }

    private func startRestore() {
        isRestoring = true
        trialError = nil
        Task {
            await store.restore()
            isRestoring = false
            if store.isPro {
                finishOnboarding()
            } else {
                trialError = store.errorMessage ?? "No active Protein+ purchase was found."
            }
        }
    }
}

private struct WelcomePoint: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

private struct TrialSellingPoint: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
