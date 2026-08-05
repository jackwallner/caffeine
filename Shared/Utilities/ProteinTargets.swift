import Foundation

/// Why the user is tracking protein. This is the whole of the audience fork:
/// it picks a suggested starting number and the sentence under it, and then it
/// never touches the app again. One product, one number, several reasons — see
/// `docs/positioning.md` §2.
///
/// Nothing here prescribes a medical target. The copy consistently frames the
/// number as one the user (or their clinician) already has, which is also what
/// keeps this on the right side of App Review 1.4.1.
enum ProteinReason: Int, CaseIterable, Sendable, Identifiable {
    case strength = 0
    case glp1 = 1
    case bariatric = 2
    case general = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .strength: "Building or keeping muscle"
        case .glp1: "On a GLP-1 medication"
        case .bariatric: "After bariatric surgery"
        case .general: "General health"
        }
    }

    var detail: String {
        switch self {
        case .strength: "Training hard and eating enough to make it count."
        case .glp1: "Appetite is down, so protein has to be deliberate."
        case .bariatric: "Following the target your clinic set for you."
        case .general: "Just want to hit a sensible number each day."
        }
    }

    var symbol: String {
        switch self {
        case .strength: "figure.strengthtraining.traditional"
        case .glp1: "syringe"
        case .bariatric: "stethoscope"
        case .general: "heart.text.square"
        }
    }

    /// Shown under the suggested number on the target step. Every variant hands
    /// authority back to the user or their clinician.
    var targetRationale: String {
        switch self {
        case .strength: "A common starting point for people training with weights. Set it to whatever number you already work to."
        case .glp1: "A common starting point while appetite is suppressed. If a clinician gave you a number, use theirs."
        case .bariatric: "Bariatric programmes usually set a number in this range. Enter the one your clinic gave you."
        case .general: "A sensible everyday starting point. Move it wherever you like."
        }
    }

    /// Grams per kilogram of body weight. `nil` for bariatric, where the target
    /// is assigned by a clinic and does not scale with weight.
    var gramsPerKilogram: Double? {
        switch self {
        case .strength: 1.8
        case .glp1: 1.4
        case .bariatric: nil
        case .general: 1.0
        }
    }

    /// Used when body weight is unknown (Health denied, or the user skipped it).
    var fallbackTarget: Double {
        switch self {
        case .strength: 150
        case .glp1: 100
        case .bariatric: 70
        case .general: 80
        }
    }

    /// Sanity band for this reason, applied after the per-kilogram maths so a
    /// very heavy or very light body weight cannot produce an absurd suggestion.
    var plausibleRange: ClosedRange<Double> {
        switch self {
        case .strength: 90...250
        case .glp1: 60...150
        case .bariatric: 50...100
        case .general: 50...140
        }
    }
}

/// Target maths, kept pure so the suggestions are unit-tested rather than
/// eyeballed in onboarding.
enum ProteinTargets {
    /// Hard bounds on any stored target, wherever it came from.
    static let allowedRange: ClosedRange<Double> = 20...400

    /// Suggested daily grams for a reason and an optional body weight.
    /// Rounded to the nearest 5 because nobody works to a target of 147 g.
    static func suggestedTarget(for reason: ProteinReason, bodyWeightKilograms: Double?) -> Double {
        guard let perKilogram = reason.gramsPerKilogram,
              let weight = bodyWeightKilograms,
              weight > 20, weight < 400 else {
            return clamp(reason.fallbackTarget, to: reason.plausibleRange)
        }
        let raw = weight * perKilogram
        return clamp(roundToNearestFive(raw), to: reason.plausibleRange)
    }

    static func roundToNearestFive(_ value: Double) -> Double {
        (value / 5).rounded() * 5
    }

    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// Applied on every write to the stored target.
    static func normalized(_ value: Double) -> Double {
        clamp(value.rounded(), to: allowedRange)
    }

    static func kilograms(fromPounds pounds: Double) -> Double {
        pounds * 0.45359237
    }

    static func pounds(fromKilograms kilograms: Double) -> Double {
        kilograms / 0.45359237
    }
}
