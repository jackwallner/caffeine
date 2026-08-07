import SwiftUI
@preconcurrency import RevenueCat

/// Single source of truth for what Protein+ sells.
///
/// The free app answers "how much protein have I had?" — it imports from Apple
/// Health, shows the number, and keeps the complication and widget alive.
/// Protein+ is the *logging* half: adding grams from the wrist and the phone,
/// deciding which apps count, and the nudge that keeps the day honest.
enum PlusFeature: CaseIterable {
    case wristLogging
    case quickAdd
    case sources
    case reminders
    case fullHistory

    var title: String {
        switch self {
        case .wristLogging: "Log protein from your wrist"
        case .quickAdd: "One-tap presets you set once"
        case .sources: "Choose which apps count"
        case .reminders: "An evening nudge when you're short"
        case .fullHistory: "Thirty days of history"
        }
    }

    var symbol: String {
        switch self {
        case .wristLogging: "applewatch"
        case .quickAdd: "bolt.fill"
        case .sources: "arrow.triangle.merge"
        case .reminders: "bell.badge"
        case .fullHistory: "calendar"
        }
    }

    /// Short one-liner for the What's New sheet and Settings rows.
    var detail: String {
        switch self {
        case .wristLogging: "Add grams on the Watch without touching your phone. It lands in Apple Health, so the phone already knows."
        case .quickAdd: "Three buttons tuned to what you actually eat, on both the wrist and the phone."
        case .sources: "Turn a second food logger off when two apps are counting the same meal."
        case .reminders: "One notification in the evening, with the exact grams you have left."
        case .fullHistory: "Thirty days of daily totals instead of seven."
        }
    }

    var tint: Color {
        switch self {
        case .wristLogging, .quickAdd: Theme.protein
        case .sources: Theme.proteinDeep
        case .reminders, .fullHistory: Theme.positive
        }
    }

    var intentHeadline: String {
        switch self {
        case .wristLogging: "Log it from your wrist"
        case .quickAdd: "Your usual, in one tap"
        case .sources: "Count the right apps"
        case .reminders: "Know before the day runs out"
        case .fullHistory: "See the whole month"
        }
    }

    var intentSubheadline: String {
        switch self {
        case .wristLogging: "Add grams on the Watch in about three seconds. It writes straight to Apple Health, so your phone and any other app you use see it immediately."
        case .quickAdd: "Set three buttons to the amounts you eat over and over — the shake, the chicken, the bar — and stop doing arithmetic at the fridge."
        case .sources: "See every app writing protein today, what each contributed, and how long ago. Turn one off when two are logging the same meal."
        case .reminders: "One notification in the evening that names the grams you have left, and nothing else."
        case .fullHistory: "Thirty days of daily totals, so a bad week is visible as a week rather than a feeling."
        }
    }

    /// Two related features shown under an intent-driven pitch.
    var companionFeatures: [PlusFeature] {
        switch self {
        case .wristLogging: [.quickAdd, .sources]
        case .quickAdd: [.wristLogging, .reminders]
        case .sources: [.wristLogging, .fullHistory]
        case .reminders: [.wristLogging, .quickAdd]
        case .fullHistory: [.wristLogging, .sources]
        }
    }
}

/// Apple 3.1.2(c): on every purchase surface the amount the user will actually
/// be billed must be the most clear and conspicuous pricing element, with the
/// free-trial framing subordinate in both size and position.
///
/// The billed amount is a confident visual anchor directly above the purchase
/// button. The eligible trial remains visible underneath as conversion copy,
/// but is smaller, lighter, and positioned second. The neutral CTA carries no
/// competing pricing language.
struct BilledAmountBlock: View {
    let amount: String
    let note: String?
    /// Tighter spacing for the compact trial sheet footer.
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 2 : 3) {
            Text(amount)
                .font(.system(.title2, design: .rounded, weight: .heavy).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            if let note {
                Text(note)
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isActiveTab) private var isActiveTab
    @EnvironmentObject private var store: StoreService
    var focus: PlusFeature?
    var embedded = false
    var impressionID = "protein_paywall"

    @State private var selectedPackage: Package?
    @State private var restoreMessage: String?

    private var bullets: [PlusFeature] {
        if let focus {
            return [focus] + PlusFeature.allCases.filter { $0 != focus }.prefix(3)
        }
        return PlusFeature.allCases
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if store.isLoadingProducts && store.packages.isEmpty {
                loadingState
            } else if store.packages.isEmpty {
                emptyState
            } else {
                content
            }

            if !embedded {
                closeButton
            }
        }
        .onAppear {
            // Guarded because an off-screen paywall must never count as seen.
            if isActiveTab { store.trackPaywallImpression(id: impressionID) }
            selectDefaultPackageIfNeeded()
        }
        .onChange(of: store.packages) { _, _ in selectDefaultPackageIfNeeded() }
        .onChange(of: store.isPro) { _, isPro in
            if isPro, !embedded { dismiss() }
        }
    }

    /// Hero, benefits, and plans scroll as one purchase surface. The selected
    /// plan card carries the conspicuous billed amount; the pinned footer keeps
    /// only the CTA and the required renewal disclosure.
    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                header
                featureList
                planCards
            }
            .padding(.horizontal, 22)
            .padding(.top, embedded ? 20 : 44)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            checkoutFooter
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Theme.proteinGradient)
                    .frame(width: 52, height: 52)
                    .shadow(color: Theme.protein.opacity(0.3), radius: 10, y: 4)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(focus?.intentHeadline ?? "Log it in one tap")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(focus?.intentSubheadline ?? "Reading your protein stays free. Protein+ adds the logging: wrist entry, one-tap presets, and control over which apps count.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.88)
        }
        .frame(maxWidth: .infinity)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(bullets, id: \.self) { feature in
                let highlighted = feature == focus
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: feature.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.protein)
                        .frame(width: 24)
                    Text(feature.title)
                        .font(.system(.subheadline, design: .rounded, weight: highlighted ? .semibold : .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, highlighted ? 10 : 0)
                .padding(.vertical, highlighted ? 8 : 0)
                .background {
                    if highlighted {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.protein.opacity(0.1))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var planCards: some View {
        VStack(spacing: 8) {
            ForEach(store.packages, id: \.identifier) { package in
                PlanCard(
                    package: package,
                    isSelected: selectedPackage?.identifier == package.identifier,
                    savingsPercent: savingsPercent(for: package),
                    trialLabel: store.eligibleIntroLabel(for: package)
                ) {
                    selectedPackage = package
                }
            }
        }
    }

    /// CTA + required 3.1.2 disclosure. The disclosure/legal sit in a
    /// fixed-height slot so the button never jumps when the plan changes.
    private var checkoutFooter: some View {
        VStack(spacing: 6) {
            Button {
                guard let package = selectedPackage else { return }
                Task { await store.purchase(package) }
            } label: {
                ZStack {
                    Text(ctaTitle)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .opacity(store.isLoading ? 0 : 1)
                    if store.isLoading { ProgressView().tint(.white) }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Theme.proteinGradient, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(store.isLoading || selectedPackage == nil)

            VStack(spacing: 4) {
                Group {
                    if let error = store.errorMessage {
                        Text(error).foregroundStyle(Theme.negative)
                    } else if let restoreMessage {
                        Text(restoreMessage).foregroundStyle(Theme.textSecondary)
                    } else {
                        Text(disclosureText).foregroundStyle(Theme.textTertiary)
                    }
                }
                .font(.system(.caption2, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.9)
                .frame(maxWidth: .infinity)

                HStack(spacing: 12) {
                    Button("Restore") {
                        Task {
                            await store.restore()
                            if !store.isPro {
                                restoreMessage = store.errorMessage ?? "No active Protein+ purchase was found."
                            }
                        }
                    }
                    Link("Terms", destination: ProteinLinks.standardEULA)
                    Link("Privacy", destination: ProteinLinks.privacyPolicy)
                }
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            }
            .frame(minHeight: 60, alignment: .top)
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        // The floating capsule tab bar sits ~68pt off the physical bottom and
        // its safe-area reserve does not propagate into this nested inset, so
        // the footer reserves the capsule's height explicitly when embedded.
        .padding(.bottom, embedded ? 88 : 10)
        .background(Theme.background)
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(16)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading plans…").foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 42))
                .foregroundStyle(Theme.textSecondary)
            Text("Protein+ Plans Unavailable").font(.title3.bold())
            Text("Purchases are temporarily unavailable. Your protein total and complication keep working.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again") { store.start(forceRefresh: true) }
                .buttonStyle(.borderedProminent)
                .tint(Theme.protein)
            #if targetEnvironment(simulator)
            Text("Purchases are disabled in the simulator. Use the local Pro override in Settings to inspect subscriber screens.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var ctaTitle: String {
        guard let package = selectedPackage else { return "Continue" }
        // "Unlock Lifetime" names the plan, not a competing price or trial.
        if package.proteinPackageKind == .lifetime { return "Unlock Lifetime" }
        return ConversionCopy.ctaLabel(
            trialLabel: package.proteinIntroOfferLabel,
            priceLabel: package.proteinPriceLabel,
            eligibleForTrial: store.isEligibleForIntroOffer(package)
        )
    }

    private var disclosureText: String {
        guard let package = selectedPackage else { return "" }
        if package.proteinPackageKind == .lifetime {
            return "\(package.storeProduct.localizedPriceString). One-time purchase. Lifetime access, no subscription."
        }
        return ConversionCopy.disclosure(
            trialLabel: package.proteinIntroOfferLabel,
            priceLabel: package.proteinPriceLabel,
            eligibleForTrial: store.isEligibleForIntroOffer(package),
            renewClause: "Auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel in Settings."
        )
    }

    private func selectDefaultPackageIfNeeded() {
        guard selectedPackage == nil else { return }
        selectedPackage = store.yearlyPackage ?? store.packages.first
    }

    private func savingsPercent(for package: Package) -> Int? {
        guard package.proteinPackageKind == .yearly,
              let monthly = store.packages.first(where: { $0.proteinPackageKind == .monthly }) else { return nil }
        let yearlyPrice = package.storeProduct.price as Decimal
        let annualized = (monthly.storeProduct.price as Decimal) * 12
        guard annualized > yearlyPrice, annualized > 0 else { return nil }
        let fraction = NSDecimalNumber(decimal: (annualized - yearlyPrice) / annualized).doubleValue
        return Int((fraction * 100).rounded())
    }
}

private struct PlanCard: View {
    let package: Package
    let isSelected: Bool
    let savingsPercent: Int?
    let trialLabel: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? Theme.protein : Theme.textSecondary.opacity(0.35), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle().fill(Theme.protein).frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(package.proteinDisplayName)
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        if let savingsPercent {
                            badge("SAVE \(savingsPercent)%")
                        } else if package.proteinPackageKind == .yearly {
                            badge("BEST VALUE")
                        }
                    }
                    // Apple 3.1.2(c): trial and per-week framing are secondary
                    // pricing elements, so they stay smaller and quieter than
                    // the billed amount on the trailing edge of the card.
                    Group {
                        if let trialLabel {
                            // Just the trial length. "…, then the price shown"
                            // truncated on every device at this type size, and
                            // the pinned disclosure already states the price
                            // that follows the trial in full.
                            Text(trialLabel.capitalized)
                        } else if package.proteinPackageKind == .yearly,
                                  let perWeek = package.proteinPricePerWeekLabel {
                            Text("Works out to \(perWeek)/week")
                        } else if package.proteinPackageKind == .lifetime {
                            // The cadence has to be on the card. Otherwise
                            // "$29.99" is the only thing a user reads before
                            // selecting it, and it looks like a subscription.
                            Text("One-time purchase")
                        } else {
                            Text(" ")
                        }
                    }
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 8)

                Text(package.proteinPriceLabel)
                    .font(.system(.headline, design: .rounded, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(minHeight: 54)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Theme.protein : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.protein.opacity(0.15), in: Capsule())
            .foregroundStyle(Theme.protein)
    }
}
