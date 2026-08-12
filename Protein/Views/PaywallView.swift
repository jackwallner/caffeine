import SwiftUI
@preconcurrency import RevenueCat

/// Single source of truth for what Protein+ sells.
///
/// **Logging is free, everywhere.** Adding grams on the phone and on the wrist,
/// the three quick-add buttons, and any amount you like: all of it ships in the
/// free app, because an app whose whole job is "tap a number" cannot ask to be
/// paid before the first tap. Protein+ is the part that only means anything
/// after a few weeks of that: the month behind you, what it says about you, the
/// buttons tuned to your own food, and the nudge before a day is lost.
enum PlusFeature: CaseIterable {
    case fullHistory
    case insights
    case customPresets
    case reminders

    var title: String {
        switch self {
        case .fullHistory: "Your whole history"
        case .insights: "Streaks and monthly trends"
        case .customPresets: "Quick-add buttons you set yourself"
        case .reminders: "An evening nudge when you're short"
        }
    }

    var symbol: String {
        switch self {
        case .fullHistory: "calendar"
        case .insights: "flame.fill"
        case .customPresets: "bolt.fill"
        case .reminders: "bell.badge"
        }
    }

    /// Short one-liner for the What's New sheet and Settings rows.
    var detail: String {
        switch self {
        case .fullHistory: "Every day you've logged, not just the last seven."
        case .insights: "Your streak, your days on target, and how this month compares with the one before it."
        case .customPresets: "Set the three buttons to your own shake, your own chicken, your own bar, on the phone and the wrist."
        case .reminders: "One notification in the evening, with the exact grams you have left."
        }
    }

    var tint: Color {
        switch self {
        case .fullHistory: Theme.positive
        case .insights: Theme.protein
        case .customPresets: Theme.protein
        case .reminders: Theme.proteinDeep
        }
    }

    var intentHeadline: String {
        switch self {
        case .fullHistory: "See how far you've come"
        case .insights: "Watch the streak build"
        case .customPresets: "Your usual, in one tap"
        case .reminders: "Know before the day runs out"
        }
    }

    var intentSubheadline: String {
        switch self {
        case .fullHistory: "Every day you've logged, so a bad week is visible as a week rather than a feeling."
        case .insights: "Days on target in a row, your best run, and this month's average against the last one."
        case .customPresets: "Set the three buttons to the amounts you eat over and over, and stop doing arithmetic at the fridge."
        case .reminders: "One notification in the evening that names the grams you have left, and nothing else."
        }
    }

    /// Two related features shown under an intent-driven pitch.
    var companionFeatures: [PlusFeature] {
        switch self {
        case .fullHistory: [.insights, .reminders]
        case .insights: [.fullHistory, .reminders]
        case .customPresets: [.reminders, .insights]
        case .reminders: [.insights, .customPresets]
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

    /// The entire purchase surface scrolls so pricing and disclosure remain
    /// readable at accessibility text sizes.
    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                header
                featureList
                planCards
                checkoutFooter
            }
            .padding(.horizontal, 22)
            .padding(.top, embedded ? 20 : 44)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
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
            Text(focus?.intentHeadline ?? "The month behind the number")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(focus?.intentSubheadline ?? "Logging stays free on the phone and the wrist. Protein+ adds every day you've logged, streaks and trends, your own quick-add buttons, and the evening reminder.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
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
                        .fixedSize(horizontal: false, vertical: true)
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

    /// CTA and required 3.1.2 disclosure.
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
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .opacity(store.isLoading ? 0 : 1)
                    if store.isLoading { ProgressView().tint(.white) }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .padding(.vertical, 2)
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
                        Text(disclosureText).foregroundStyle(Theme.textSecondary)
                    }
                }
                .font(.system(.caption, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        restoreButton
                        Link("Terms", destination: ProteinLinks.standardEULA)
                        Link("Privacy", destination: ProteinLinks.privacyPolicy)
                    }
                    VStack(spacing: 6) {
                        restoreButton
                        HStack(spacing: 12) {
                            Link("Terms", destination: ProteinLinks.standardEULA)
                            Link("Privacy", destination: ProteinLinks.privacyPolicy)
                        }
                    }
                }
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, embedded ? 88 : 10)
    }

    private var restoreButton: some View {
        Button("Restore") {
            Task {
                await store.restore()
                if !store.isPro {
                    restoreMessage = store.errorMessage ?? "No active Protein+ purchase was found."
                }
            }
        }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let package: Package
    let isSelected: Bool
    let savingsPercent: Int?
    let trialLabel: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    accessibilityContent
                } else {
                    standardContent
                }
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

    private var standardContent: some View {
        HStack(spacing: 12) {
            selectionIndicator
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    planName
                    planBadge
                }
                planDetail
            }
            Spacer(minLength: 8)
            planPrice
        }
    }

    private var accessibilityContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                selectionIndicator
                VStack(alignment: .leading, spacing: 5) {
                    planName
                    planBadge
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                planDetail
                Spacer(minLength: 8)
                planPrice
            }
        }
    }

    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .stroke(isSelected ? Theme.protein : Theme.textSecondary.opacity(0.35), lineWidth: 2)
                .frame(width: 22, height: 22)
            if isSelected {
                Circle().fill(Theme.protein).frame(width: 12, height: 12)
            }
        }
    }

    private var planName: some View {
        Text(package.proteinDisplayName)
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var planBadge: some View {
        if let savingsPercent {
            badge("SAVE \(savingsPercent)%")
        } else if package.proteinPackageKind == .yearly {
            badge("BEST VALUE")
        }
    }

    private var planDetail: some View {
        Group {
            if let trialLabel {
                Text(trialLabel.capitalized)
            } else if package.proteinPackageKind == .yearly,
                      let perWeek = package.proteinPricePerWeekLabel {
                Text("Works out to \(perWeek)/week")
            } else if package.proteinPackageKind == .lifetime {
                Text("One-time purchase")
            } else {
                Text(" ")
            }
        }
        .font(.system(.caption, design: .rounded))
        .foregroundStyle(Theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var planPrice: some View {
        Text(package.proteinPriceLabel)
            .font(.system(.headline, design: .rounded, weight: .heavy).monospacedDigit())
            .foregroundStyle(Theme.textPrimary)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
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
