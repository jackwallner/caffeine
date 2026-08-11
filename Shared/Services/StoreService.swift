import Combine
import Foundation
import os
import StoreKit
import WidgetKit
@preconcurrency import RevenueCat

enum RevenueCatConfig {
    /// Public iOS SDK key. Secret `sk_` keys must never ship in an app binary.
    static let publicSDKKey = "appl_LfYULlAJcjwywvqePrhAlZloCtF"
    /// Entitlement lookup key in RevenueCat. Must stay `Protein+`, which is what
    /// the dashboard actually has; `isPro` gates on any active entitlement, so a
    /// mismatch here would go unnoticed until someone reads this constant.
    static let proEntitlement = "Protein+"
}

/// Product identifiers, which must match `Protein.storekit` and the App Store
/// Connect subscription group exactly.
enum ProteinProduct {
    static let monthly = "com.jackwallner.protein.monthly"
    static let yearly = "com.jackwallner.protein.yearly"
    static let lifetime = "com.jackwallner.protein.pro.lifetime"
}

enum PurchaseState {
    case purchased
    case cancelled
    case pending
}

enum ProteinPackageKind: Int {
    case lifetime = 0
    case yearly = 1
    case monthly = 2
    case other = 3
}

extension ProteinPackageKind {
    init(package: Package) {
        switch package.packageType {
        case .lifetime:
            self = .lifetime
        case .annual:
            self = .yearly
        case .monthly:
            self = .monthly
        default:
            let identifiers = [package.identifier, package.storeProduct.productIdentifier].map { $0.lowercased() }
            if identifiers.contains(where: { $0.contains("lifetime") }) {
                self = .lifetime
            } else if identifiers.contains(where: { $0.contains("yearly") || $0.contains("annual") }) {
                self = .yearly
            } else if identifiers.contains(where: { $0.contains("monthly") }) {
                self = .monthly
            } else {
                self = .other
            }
        }
    }
}

extension Package {
    var proteinPackageKind: ProteinPackageKind {
        ProteinPackageKind(package: self)
    }

    var proteinDisplayName: String {
        switch proteinPackageKind {
        case .lifetime: "Lifetime"
        case .yearly: "Yearly"
        case .monthly: "Monthly"
        case .other: storeProduct.localizedTitle
        }
    }

    var proteinPriceLabel: String {
        guard let period = storeProduct.subscriptionPeriod else { return storeProduct.localizedPriceString }
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: unit = ""
        }
        if period.value == 1 {
            return "\(storeProduct.localizedPriceString) / \(unit)"
        }
        return "\(storeProduct.localizedPriceString) / \(period.value) \(unit)"
    }

    /// Per-week equivalent of the recurring price, shown on the annual card so
    /// the headline yearly figure feels small.
    var proteinPricePerWeekLabel: String? {
        guard storeProduct.subscriptionPeriod != nil else { return nil }
        return storeProduct.localizedPricePerWeek
    }

    var proteinIntroOfferLabel: String? {
        guard let intro = storeProduct.introductoryDiscount, intro.paymentMode == .freeTrial else {
            return nil
        }
        let period = intro.subscriptionPeriod
        switch period.unit {
        case .day: return "\(period.value)-day free trial"
        case .week: return "\(period.value * 7)-day free trial"
        case .month: return period.value == 1 ? "1-month free trial" : "\(period.value)-month free trial"
        case .year: return period.value == 1 ? "1-year free trial" : "\(period.value)-year free trial"
        @unknown default: return nil
        }
    }
}

extension Offering {
    var proteinSortedPackages: [Package] {
        availablePackages.sorted {
            let lhsKind = $0.proteinPackageKind
            let rhsKind = $1.proteinPackageKind
            if lhsKind.rawValue != rhsKind.rawValue {
                return lhsKind.rawValue < rhsKind.rawValue
            }
            return $0.storeProduct.productIdentifier < $1.storeProduct.productIdentifier
        }
    }
}

@MainActor
final class StoreService: NSObject, ObservableObject, PurchasesDelegate {
    static let shared = StoreService()

    /// App Group key mirroring the live `isPro` entitlement for widget and watch
    /// gating.
    static let cachedProKey = proteinCachedProKey

    @Published private(set) var isPro = false {
        didSet {
            guard oldValue != isPro else { return }
            defaults.set(isPro, forKey: Self.cachedProKey)
            WidgetCenter.shared.reloadAllTimelines()
            WatchSyncService.shared.push(settings: GoalSettings.shared.watchPayload)
            // An expired entitlement leaves Settings showing the locked reminder
            // while iOS still holds a request scheduled while Pro, so the nudge
            // keeps firing for a feature the user no longer has. The stored
            // preference is left alone: `refreshCache` puts the reminder back if
            // the entitlement returns.
            if !isPro {
                NotificationService.cancelReminder()
            }
        }
    }
    @Published private(set) var packages: [Package] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var errorMessage: String?

    /// Per-product free-trial eligibility, resolved after products load. Trial
    /// copy stays hidden until resolved so a used-trial user is never promised a
    /// free week StoreKit will not grant (Apple 3.1.2).
    @Published private(set) var introEligibility: [String: Bool] = [:]
    @Published private(set) var introEligibilityResolved = false

    private let logger = Logger(subsystem: "com.jackwallner.protein", category: "Store")
    private let defaults = UserDefaults(suiteName: proteinAppGroupID) ?? .standard
    private var isConfigured = false
    /// Dedupes session-scoped paywall impressions.
    private var paywallImpressionsThisSession: Set<String> = []

    private override init() {
        super.init()
        isPro = defaults.bool(forKey: Self.cachedProKey)
    }

    func start(forceRefresh: Bool = false) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-DemoPro") {
            isPro = true
            return
        }
        #endif
        configureIfNeeded()
        guard isConfigured else {
            #if targetEnvironment(simulator)
            // StoreKit Testing serves the local .storekit catalog under the
            // Xcode scheme and under `xcodebuild test`, so the real paywall can
            // be rendered and verified without ever configuring RevenueCat on a
            // simulator (which would create fake customers in the prod project).
            Task { await loadStoreKitTestingProducts() }
            #endif
            return
        }
        Task {
            await refreshStatus()
            await loadOffering(forceRefresh: forceRefresh)
        }
    }

    var yearlyPackage: Package? { packages.first { $0.proteinPackageKind == .yearly } }
    var lifetimePackage: Package? { packages.first { $0.proteinPackageKind == .lifetime } }

    func isEligibleForIntroOffer(_ package: Package) -> Bool {
        guard package.proteinIntroOfferLabel != nil else { return false }
        guard introEligibilityResolved else { return false }
        return introEligibility[package.storeProduct.productIdentifier] ?? false
    }

    func eligibleIntroLabel(for package: Package) -> String? {
        guard isEligibleForIntroOffer(package) else { return nil }
        return package.proteinIntroOfferLabel
    }

    /// True when the yearly plan can honestly be pitched as a free trial.
    var canPitchFreeTrial: Bool {
        guard let yearly = yearlyPackage else { return false }
        return isEligibleForIntroOffer(yearly)
    }

    /// Short CTA for locked capsule surfaces.
    var shortConversionCTALabel: String {
        ConversionCopy.shortCTALabel(eligibleForTrial: canPitchFreeTrial)
    }

    @discardableResult
    func purchase(_ package: Package) async -> PurchaseState? {
        guard isConfigured else { return nil }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            update(customerInfo: result.customerInfo)
            if result.userCancelled {
                errorMessage = ConversionCopy.purchaseCancelledMessage(
                    eligibleForTrial: isEligibleForIntroOffer(package)
                )
                return .cancelled
            }
            return isPro ? .purchased : .pending
        } catch {
            let nsError = error as NSError
            if nsError.code == ErrorCode.purchaseCancelledError.rawValue {
                errorMessage = ConversionCopy.purchaseCancelledMessage(
                    eligibleForTrial: isEligibleForIntroOffer(package)
                )
                return .cancelled
            }
            await refreshIntroEligibility()
            errorMessage = ConversionCopy.purchaseFailedMessage(
                eligibleForTrial: isEligibleForIntroOffer(package)
            )
            return nil
        }
    }

    func restore() async {
        guard isConfigured else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            update(customerInfo: try await Purchases.shared.restorePurchases())
            errorMessage = isPro ? nil : "No active Protein+ purchase was found for this Apple ID."
        } catch {
            errorMessage = "Restore failed. Please try again."
        }
    }

    /// Reports a custom-paywall impression to RevenueCat so the native paywall
    /// feeds RC's impression count and conversion %. `id` distinguishes entry
    /// points; `oncePerSession` dedupes surfaces the user can revisit.
    func trackPaywallImpression(id: String, oncePerSession: Bool = false) {
        guard isConfigured else { return }
        if oncePerSession {
            guard !paywallImpressionsThisSession.contains(id) else { return }
            paywallImpressionsThisSession.insert(id)
        }
        Purchases.shared.trackCustomPaywallImpression(
            CustomPaywallImpressionParams(paywallId: id)
        )
    }

    #if DEBUG
    func setLocalOverride(isPro: Bool) {
        self.isPro = isPro
        defaults.set(isPro, forKey: Self.cachedProKey)
    }
    #endif

    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            self.update(customerInfo: customerInfo)
        }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        #if targetEnvironment(simulator)
        // Agent/sim runs must never hit the production RevenueCat project — a
        // configure call there creates a fake customer in the live charts. Use
        // StoreKit Testing plus the local Pro override instead.
        return
        #else
        guard RevenueCatConfig.publicSDKKey.hasPrefix("appl_") else { return }
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: RevenueCatConfig.publicSDKKey)
        Purchases.shared.delegate = self
        isConfigured = true
        #endif
    }

    private func refreshStatus() async {
        do {
            update(customerInfo: try await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent))
        } catch {
            errorMessage = "Could not verify purchases."
        }
    }

    private func loadOffering(forceRefresh: Bool = false) async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let offerings: Offerings
            if forceRefresh,
               let refreshedOfferings = try await Purchases.shared.syncAttributesAndOfferingsIfNeeded() {
                offerings = refreshedOfferings
            } else {
                offerings = try await Purchases.shared.offerings()
            }
            let offering = offerings.offering(identifier: "default") ?? offerings.current
            packages = offering?.proteinSortedPackages ?? []
            errorMessage = nil
            await refreshIntroEligibility()
        } catch {
            logger.error("Product fetch failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Couldn't load purchase options. Check your connection and try again."
        }
    }

    /// Resolves StoreKit intro-offer eligibility for the loaded products. On any
    /// failure we mark resolved with an empty map so callers hide trial framing
    /// rather than over-promising.
    private func refreshIntroEligibility() async {
        let identifiers = packages
            .filter { $0.storeProduct.introductoryDiscount != nil }
            .map { $0.storeProduct.productIdentifier }
        guard !identifiers.isEmpty else {
            introEligibility = [:]
            introEligibilityResolved = true
            return
        }
        let result = await Purchases.shared.checkTrialOrIntroDiscountEligibility(productIdentifiers: identifiers)
        introEligibility = result.mapValues { $0.status == .eligible }
        introEligibilityResolved = true
    }

    private func update(customerInfo: CustomerInfo) {
        // Single premium tier: any active entitlement unlocks Protein+, which
        // survives entitlement renames or casing drift in the RC dashboard.
        isPro = !customerInfo.entitlements.active.isEmpty
        defaults.set(isPro, forKey: Self.cachedProKey)
    }

    #if targetEnvironment(simulator)
    /// Hydrates `packages` on the simulator so the *real* paywall — hero, plan
    /// cards, billed amount, disclosure, footer — can be rendered and inspected
    /// headlessly. RevenueCat is never configured here, so the production
    /// project gains no fake customers.
    ///
    /// Under `xcodebuild test` (or the Xcode scheme) StoreKit Testing serves the
    /// local `Protein.storekit` catalog, and those genuine products are used.
    /// Under a plain `simctl launch` StoreKit has no catalog at all, so the
    /// fleet's `TestStoreProduct` fixtures stand in with the same prices — the
    /// layout under test is identical either way. Purchases stay disabled in
    /// both cases; this exists to make layout verifiable, not to fake a sale.
    private func loadStoreKitTestingProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        if let live = await Self.storeKitTestingProducts(), !live.isEmpty {
            apply(simulatorProducts: live)
        } else {
            apply(simulatorProducts: Self.fixtureProducts())
        }
        introEligibility = Dictionary(uniqueKeysWithValues: packages.map { ($0.storeProduct.productIdentifier, true) })
        introEligibilityResolved = true
        errorMessage = nil
    }

    private func apply(simulatorProducts products: [StoreProduct]) {
        packages = products
            .map { product in
                Package(
                    identifier: product.productIdentifier,
                    packageType: Self.packageType(for: product.productIdentifier),
                    storeProduct: product,
                    offeringIdentifier: "default",
                    webCheckoutUrl: nil
                )
            }
            .sorted { ProteinPackageKind(package: $0).rawValue < ProteinPackageKind(package: $1).rawValue }
    }

    private static func storeKitTestingProducts() async -> [StoreProduct]? {
        let identifiers: Set<String> = [
            ProteinProduct.monthly, ProteinProduct.yearly, ProteinProduct.lifetime,
        ]
        guard let sk2 = try? await StoreKit.Product.products(for: identifiers) else { return nil }
        return sk2.map { StoreProduct(sk2Product: $0) }
    }

    /// Same prices and trial as `Protein.storekit`, for when StoreKit Testing
    /// isn't active. Keep these in sync with that file.
    private static func fixtureProducts() -> [StoreProduct] {
        let locale = Locale(identifier: "en_US")
        func weekTrial() -> TestStoreProductDiscount {
            TestStoreProductDiscount(
                identifier: "free_trial", price: 0, localizedPriceString: "$0.00",
                paymentMode: .freeTrial, subscriptionPeriod: .init(value: 1, unit: .week),
                numberOfPeriods: 1, type: .introductory
            )
        }
        return [
            TestStoreProduct(
                localizedTitle: "Protein+ Monthly", price: 5.99, currencyCode: "USD",
                localizedPriceString: "$5.99", productIdentifier: ProteinProduct.monthly,
                productType: .autoRenewableSubscription, localizedDescription: "Protein+, billed monthly.",
                subscriptionPeriod: .init(value: 1, unit: .month), introductoryDiscount: weekTrial(), locale: locale
            ).toStoreProduct(),
            TestStoreProduct(
                localizedTitle: "Protein+ Yearly", price: 29.99, currencyCode: "USD",
                localizedPriceString: "$29.99", productIdentifier: ProteinProduct.yearly,
                productType: .autoRenewableSubscription, localizedDescription: "Protein+, billed yearly.",
                subscriptionPeriod: .init(value: 1, unit: .year), introductoryDiscount: weekTrial(), locale: locale
            ).toStoreProduct(),
            TestStoreProduct(
                localizedTitle: "Protein+ Lifetime", price: 59.99, currencyCode: "USD",
                localizedPriceString: "$59.99", productIdentifier: ProteinProduct.lifetime,
                productType: .nonConsumable, localizedDescription: "Protein+, one-time purchase.",
                subscriptionPeriod: nil, introductoryDiscount: nil, locale: locale
            ).toStoreProduct(),
        ]
    }

    private static func packageType(for identifier: String) -> PackageType {
        if identifier.contains("lifetime") { return .lifetime }
        if identifier.contains("yearly") { return .annual }
        return .monthly
    }
    #endif
}
