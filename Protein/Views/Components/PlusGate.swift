import SwiftUI
@preconcurrency import RevenueCat

/// Presentation state for the Protein+ offer, shared by every screen that has a
/// locked control.
///
/// Three surfaces need the identical "tap a locked thing → personalized offer →
/// buy the yearly package in place → fall back to the full plan picker if
/// products never loaded" behaviour. Keeping it in one place is what stops the
/// three copies drifting apart on the CTA wording or the disclosure.
@MainActor
final class PlusGateModel: ObservableObject {
    @Published var focus: PlusFeature?
    @Published var isPresentingOffer = false
    @Published var isPresentingPaywall = false
    @Published var purchaseInFlight = false
    @Published var purchaseError: String?
    @Published var detent: PresentationDetent = .fraction(0.68)

    /// Runs `action` when Protein+ is active, otherwise opens the offer pitched
    /// at the feature the user just reached for.
    func run(_ feature: PlusFeature, isPro: Bool, action: () -> Void) {
        if isPro {
            action()
        } else {
            present(feature)
        }
    }

    func present(_ feature: PlusFeature?) {
        focus = feature
        purchaseError = nil
        detent = .fraction(0.68)
        isPresentingOffer = true
    }
}

private struct PlusGateModifier: ViewModifier {
    @ObservedObject var model: PlusGateModel
    @EnvironmentObject private var store: StoreService

    /// Always the yearly package. StoreKit applies the free trial when
    /// eligible; used-trial accounts pay the yearly price on the same product,
    /// so there is no second SKU and no nested plan picker.
    private var conversionPackage: Package? {
        store.yearlyPackage ?? store.packages.first
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $model.isPresentingOffer, onDismiss: {
                model.purchaseInFlight = false
                model.purchaseError = nil
            }) {
                let package = conversionPackage
                TrialOfferSheet(
                    focus: model.focus,
                    // Only pass a trial label when this Apple ID is still
                    // eligible — otherwise the sheet frames a straight buy.
                    offerLabel: package.flatMap { store.eligibleIntroLabel(for: $0) },
                    priceLabel: package?.proteinPriceLabel,
                    ctaTitle: ctaTitle(for: package),
                    disclosureText: disclosure(for: package),
                    directPurchase: package != nil,
                    isPurchasing: model.purchaseInFlight,
                    errorMessage: model.purchaseError,
                    onStartTrial: { startPurchase() },
                    onDismiss: { model.isPresentingOffer = false }
                )
                .presentationDetents([.fraction(0.68), .large], selection: $model.detent)
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(model.purchaseInFlight)
            }
            .sheet(isPresented: $model.isPresentingPaywall) {
                PaywallView(focus: model.focus).environmentObject(store)
            }
    }

    private func ctaTitle(for package: Package?) -> String {
        guard let package else { return "Continue with Protein+" }
        return ConversionCopy.ctaLabel(
            trialLabel: package.proteinIntroOfferLabel,
            priceLabel: package.proteinPriceLabel,
            eligibleForTrial: store.isEligibleForIntroOffer(package)
        )
    }

    private func disclosure(for package: Package?) -> String? {
        guard let package else { return nil }
        return ConversionCopy.sheetDisclosure(
            trialLabel: package.proteinIntroOfferLabel,
            priceLabel: package.proteinPriceLabel,
            eligibleForTrial: store.isEligibleForIntroOffer(package)
        )
    }

    /// Buys the yearly product in place (Apple confirm sheet). Falls back to the
    /// full plan picker when products never loaded, so the primary button is
    /// never a dead end.
    private func startPurchase() {
        guard let package = conversionPackage else {
            model.isPresentingOffer = false
            model.isPresentingPaywall = true
            return
        }
        model.purchaseError = nil
        model.purchaseInFlight = true
        Task { @MainActor in
            defer { model.purchaseInFlight = false }
            switch await store.purchase(package) {
            case .purchased, .pending:
                model.isPresentingOffer = false
            case .cancelled, .none:
                model.purchaseError = store.errorMessage
            }
        }
    }
}

extension View {
    func plusGate(_ model: PlusGateModel) -> some View {
        modifier(PlusGateModifier(model: model))
    }
}

/// Small lock chip for controls that are visible but not usable yet. Locked
/// controls stay on screen rather than disappearing, so the app never looks
/// like it is missing a feature — it looks like a feature is waiting.
struct PlusLockBadge: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(5)
            .background(Theme.protein, in: Circle())
    }
}
