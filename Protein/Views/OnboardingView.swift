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
    @State private var showPaywallFallback = false

    // Local edit buffers so a skipped setup leaves stored defaults untouched.
    @State private var reason: ProteinReason = .strength
    @State private var target: Double = 140
    @State private var bodyWeightKilograms: Double?
    @State private var isFetchingBodyWeight = false
    @State private var bodyWeightUnavailable = false
    /// Once the user drags the target slider we stop re-anchoring it to the
    /// reason, so a deliberate choice is never overwritten by a later tap.
    @State private var hasEditedTarget = false

    var body: some View {
        VStack(spacing: 0) {
            if step == .trial {
                // The trial step must NOT live in a ScrollView: Spacers need a
                // bounded height to centre the pitch above the zero-shift CTA.
                trialPage
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    .padding(.top, 48)
                    .padding(.bottom, 24)
                    .padding(.horizontal, 24)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            bottomBar
        }
        .background(Theme.background.ignoresSafeArea())
        .task {
            reason = settings.reason
            target = settings.targetGrams
            store.trackPaywallImpression(id: "protein_onboarding_trial")
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if let idx = args.firstIndex(of: "-OnboardingPage"), idx + 1 < args.count,
               let page = Int(args[idx + 1]) {
                step = [Step.welcome, .reason, .target, .trial][min(max(page, 0), 3)]
            }
            #endif
        }
        // A purchase (or restore) that flips Pro on finishes onboarding.
        .onChange(of: store.isPro) { _, isPro in
            if isPro { finishOnboarding() }
        }
        .sheet(isPresented: $showPaywallFallback) { PaywallView() }
    }

    private func finishOnboarding() {
        settings.reason = reason
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
        guard !hasEditedTarget else { return }
        target = ProteinTargets.suggestedTarget(for: reason, bodyWeightKilograms: bodyWeightKilograms)
    }

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
                Text("This only sets your starting number. Everything else in the app is the same either way.")
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

    private func reasonCard(_ option: ProteinReason) -> some View {
        let selected = reason == option
        return Button {
            reason = option
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
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
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
                Text(reason.targetRationale)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                Text("\(Int(target))")
                    .font(Theme.bigNumber(64))
                    .foregroundStyle(Theme.protein)
                    .monospacedDigit()
                Text("grams per day")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Slider(value: $target, in: 40...300, step: 5)
                    .tint(Theme.protein)
                    .onChange(of: target) { _, _ in hasEditedTarget = true }
                    .accessibilityLabel("Daily protein target")
                    .accessibilityValue("\(Int(target)) grams")
                    .accessibilityHint("Adjustable in 5 gram steps")
                if let bodyWeightKilograms {
                    Text("Suggested from the \(Int(bodyWeightKilograms.rounded())) kg body weight in Apple Health.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                } else {
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

            // App Review 1.4.1: the disclaimer belongs beside the suggested
            // number, not three screens later in Settings. The GLP-1 and
            // post-bariatric branches are exactly where a suggestion could be
            // read as an assigned clinical target.
            Text("This is a starting number, not medical advice. Set it to whatever you or your clinician decided.")
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
        target = ProteinTargets.suggestedTarget(for: reason, bodyWeightKilograms: kilograms)
    }

    /// Final step: compact pitch centred above the zero-shift CTA bar.
    private var trialPage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)

            VStack(spacing: 18) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.proteinGradient)

                VStack(spacing: 6) {
                    Text("Log it in one tap")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text("Your number, the widget, and the watch complication are free. Protein+ is the logging half:")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    TrialSellingPoint(
                        icon: "applewatch",
                        color: Theme.protein,
                        title: "Wrist logging",
                        detail: "Add grams on the Watch in about three seconds"
                    )
                    TrialSellingPoint(
                        icon: "bolt.fill",
                        color: Theme.proteinDeep,
                        title: "One-tap presets",
                        detail: "Three buttons tuned to what you actually eat"
                    )
                    TrialSellingPoint(
                        icon: "arrow.triangle.merge",
                        color: Theme.positive,
                        title: "Source control",
                        detail: "Stop two food apps counting the same meal"
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

            // Capped so the pitch settles just above the CTA bar. The leading
            // Spacer takes the remaining slack, so the button itself never moves.
            Spacer(minLength: 8).frame(maxHeight: 28)
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
                settings.reason = reason
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
            // price. Error replaces disclosure in the same slot.
            if let trialError {
                Text(trialError)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.negative)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            } else if let disclosure = trialDisclosure {
                Text(disclosure)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            } else {
                Text("Protein+ is temporarily unavailable. Continue with the free app and try again later from Settings.")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }
        }
    }

    private var legalFooter: some View {
        HStack(spacing: 14) {
            Button(isRestoring ? "Restoring…" : "Restore") { startRestore() }
                .buttonStyle(.plain)
                .disabled(isRestoring)
            Link("Terms", destination: ProteinLinks.standardEULA)
            Link("Privacy", destination: ProteinLinks.privacyPolicy)
        }
        .font(.system(.caption2, design: .rounded, weight: .semibold))
        .foregroundStyle(Theme.textTertiary)
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
        isStartingTrial = true
        Task {
            _ = await store.purchase(yearly)
            isStartingTrial = false
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
