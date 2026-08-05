import XCTest
@testable import Protein

final class ProteinTargetsTests: XCTestCase {
    func testStrengthTargetScalesWithBodyWeight() {
        // 80 kg × 1.8 g/kg = 144, rounded to the nearest 5.
        XCTAssertEqual(ProteinTargets.suggestedTarget(for: .strength, bodyWeightKilograms: 80), 145)
    }

    func testGLP1TargetScalesWithBodyWeight() {
        // 70 kg × 1.4 g/kg = 98, rounded to the nearest 5.
        XCTAssertEqual(ProteinTargets.suggestedTarget(for: .glp1, bodyWeightKilograms: 70), 100)
    }

    /// A bariatric target is assigned by a clinic and does not scale with body
    /// weight, so the suggestion must not move when a weight is available.
    func testBariatricTargetIgnoresBodyWeight() {
        XCTAssertEqual(ProteinTargets.suggestedTarget(for: .bariatric, bodyWeightKilograms: 120), 70)
        XCTAssertEqual(ProteinTargets.suggestedTarget(for: .bariatric, bodyWeightKilograms: nil), 70)
    }

    func testMissingBodyWeightFallsBackToTheReasonDefault() {
        XCTAssertEqual(ProteinTargets.suggestedTarget(for: .strength, bodyWeightKilograms: nil), 150)
        XCTAssertEqual(ProteinTargets.suggestedTarget(for: .general, bodyWeightKilograms: nil), 80)
    }

    /// A nonsense body weight (a stale Health sample in the wrong unit, say)
    /// must not produce a 500 g suggestion.
    func testImplausibleBodyWeightFallsBackRatherThanScaling() {
        XCTAssertEqual(ProteinTargets.suggestedTarget(for: .strength, bodyWeightKilograms: 5), 150)
        XCTAssertEqual(ProteinTargets.suggestedTarget(for: .strength, bodyWeightKilograms: 800), 150)
    }

    func testVeryHeavyBodyWeightIsCappedAtThePlausibleCeiling() {
        // 180 kg × 1.8 = 324, well past what any protein guideline suggests.
        XCTAssertEqual(ProteinTargets.suggestedTarget(for: .strength, bodyWeightKilograms: 180), 250)
    }

    func testVeryLightBodyWeightIsRaisedToThePlausibleFloor() {
        // 45 kg × 1.8 = 81, under the strength floor.
        XCTAssertEqual(ProteinTargets.suggestedTarget(for: .strength, bodyWeightKilograms: 45), 90)
    }

    func testSuggestionsAlwaysLandOnAFiveGramStep() {
        for weight in stride(from: 45.0, through: 160.0, by: 1.0) {
            for reason in ProteinReason.allCases {
                let target = ProteinTargets.suggestedTarget(for: reason, bodyWeightKilograms: weight)
                XCTAssertEqual(
                    target.truncatingRemainder(dividingBy: 5), 0,
                    "\(reason) at \(weight) kg suggested \(target), which is not a 5 g step"
                )
            }
        }
    }

    func testNormalizationClampsToTheAllowedRange() {
        XCTAssertEqual(ProteinTargets.normalized(0), ProteinTargets.allowedRange.lowerBound)
        XCTAssertEqual(ProteinTargets.normalized(-40), ProteinTargets.allowedRange.lowerBound)
        XCTAssertEqual(ProteinTargets.normalized(9_000), ProteinTargets.allowedRange.upperBound)
        XCTAssertEqual(ProteinTargets.normalized(160.4), 160)
    }

    func testPoundKilogramConversionRoundTrips() {
        let kilograms = ProteinTargets.kilograms(fromPounds: 180)
        XCTAssertEqual(kilograms, 81.6466, accuracy: 0.001)
        XCTAssertEqual(ProteinTargets.pounds(fromKilograms: kilograms), 180, accuracy: 0.001)
    }

    func testEveryReasonHasCopyAndAPlausibleFallback() {
        for reason in ProteinReason.allCases {
            XCTAssertFalse(reason.title.isEmpty)
            XCTAssertFalse(reason.detail.isEmpty)
            XCTAssertFalse(reason.targetRationale.isEmpty)
            XCTAssertTrue(
                reason.plausibleRange.contains(reason.fallbackTarget),
                "\(reason) falls back to \(reason.fallbackTarget), outside its own plausible range"
            )
        }
    }

    /// App Review 1.4.1: the audience copy must never claim the app sets a
    /// medical target or treats anything.
    func testReasonCopyMakesNoMedicalClaims() {
        let banned = ["treat", "cure", "diagnos", "prescrib", "prevent"]
        for reason in ProteinReason.allCases {
            let copy = "\(reason.title) \(reason.detail) \(reason.targetRationale)".lowercased()
            for word in banned {
                XCTAssertFalse(copy.contains(word), "\(reason) copy contains the banned word '\(word)'")
            }
        }
    }
}
