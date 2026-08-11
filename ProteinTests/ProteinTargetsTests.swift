import XCTest
@testable import Protein

final class ProteinTargetsTests: XCTestCase {
    func testStrengthTargetScalesWithBodyWeight() {
        // 80 kg × 1.8 g/kg = 144, rounded to the nearest 5.
        XCTAssertEqual(ProteinTargets.suggestedTarget(for: .strength, bodyWeightKilograms: 80), 145)
    }

    func testGLP1RequiresAnEnteredTarget() {
        XCTAssertTrue(ProteinReason.glp1.requiresManualTarget)
        XCTAssertNil(ProteinTargets.suggestedTarget(for: .glp1, bodyWeightKilograms: 70))
    }

    /// A bariatric target is assigned by a clinic and does not scale with body
    /// weight, so the suggestion must not move when a weight is available.
    func testBariatricRequiresTheClinicTarget() {
        XCTAssertTrue(ProteinReason.bariatric.requiresManualTarget)
        XCTAssertNil(ProteinTargets.suggestedTarget(for: .bariatric, bodyWeightKilograms: 120))
        XCTAssertNil(ProteinTargets.suggestedTarget(for: .bariatric, bodyWeightKilograms: nil))
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
            for reason in ProteinReason.allCases where !reason.requiresManualTarget {
                let target = ProteinTargets.suggestedTarget(for: reason, bodyWeightKilograms: weight)
                XCTAssertEqual(
                    target?.truncatingRemainder(dividingBy: 5), 0,
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

    func testOnlyNonMedicalReasonsCanSuggestTargets() {
        XCTAssertFalse(ProteinReason.strength.requiresManualTarget)
        XCTAssertFalse(ProteinReason.general.requiresManualTarget)
        XCTAssertNotNil(ProteinTargets.suggestedTarget(for: .strength, bodyWeightKilograms: 80))
        XCTAssertNotNil(ProteinTargets.suggestedTarget(for: .general, bodyWeightKilograms: 80))
    }

    /// App Review 1.4.1: the audience copy must never claim the app sets a
    /// medical target or treats anything.
    func testReasonCopyMakesNoMedicalClaims() {
        for reason in ProteinReason.allCases {
            let copy = "\(reason.title) \(reason.detail) \(reason.targetRationale)"
            assertNoMedicalClaims(copy, context: "\(reason)")
        }
    }

    /// Multi-select builds sentences by combining reasons, so the 1.4.1 check
    /// has to cover every combination rather than the four singles.
    func testCombinedRationaleMakesNoMedicalClaims() {
        for combination in Self.everyReasonCombination() {
            let copy = ProteinReason.rationale(for: combination)
            XCTAssertFalse(copy.isEmpty)
            assertNoMedicalClaims(copy, context: "\(ProteinReason.ordered(combination))")
        }
    }

    private func assertNoMedicalClaims(_ copy: String, context: String) {
        let banned = ["treat", "cure", "diagnos", "prescrib", "prevent"]
        let lowercased = copy.lowercased()
        for word in banned {
            XCTAssertFalse(lowercased.contains(word), "\(context) copy contains the banned word '\(word)'")
        }
    }

    // MARK: - Multiple reasons

    /// The reasons stack, and the most demanding one has to win: a target that
    /// covers training also covers general health, and not the other way round.
    func testMultipleNonMedicalReasonsTakeTheHigherSuggestion() {
        let strengthOnly = ProteinTargets.suggestedTarget(for: [.strength], bodyWeightKilograms: 80)
        let both = ProteinTargets.suggestedTarget(for: [.strength, .general], bodyWeightKilograms: 80)
        XCTAssertEqual(both, strengthOnly)
        XCTAssertEqual(both, 145)
    }

    /// One medical reason anywhere in the set means the number came from the
    /// user or their clinic, however many other reasons they also picked.
    func testAnyMedicalReasonStillRequiresAnEnteredTarget() {
        XCTAssertTrue(ProteinReason.requiresManualTarget([.strength, .glp1]))
        XCTAssertNil(ProteinTargets.suggestedTarget(for: [.strength, .glp1], bodyWeightKilograms: 80))
        XCTAssertNil(ProteinTargets.suggestedTarget(for: [.general, .bariatric], bodyWeightKilograms: 80))
    }

    func testASingleReasonSetMatchesThatReasonAlone() {
        for reason in ProteinReason.allCases {
            XCTAssertEqual(
                ProteinTargets.suggestedTarget(for: [reason], bodyWeightKilograms: 80),
                ProteinTargets.suggestedTarget(for: reason, bodyWeightKilograms: 80),
                "\(reason) as a one-element set suggested a different target than on its own"
            )
            XCTAssertEqual(ProteinReason.rationale(for: [reason]), reason.targetRationale)
        }
    }

    func testEmptySelectionStillHasASentenceAndNoSuggestion() {
        XCTAssertFalse(ProteinReason.rationale(for: []).isEmpty)
        XCTAssertNil(ProteinTargets.suggestedTarget(for: [], bodyWeightKilograms: 80))
    }

    /// Selection order must not leak into anything the user reads.
    func testOrderedReasonsFollowTheListedOrder() {
        XCTAssertEqual(
            ProteinReason.ordered([.general, .strength, .glp1]),
            [.strength, .glp1, .general]
        )
    }

    private static func everyReasonCombination() -> [Set<ProteinReason>] {
        let all = ProteinReason.allCases
        return (0..<(1 << all.count)).map { mask in
            Set(all.enumerated().compactMap { index, reason in
                mask & (1 << index) == 0 ? nil : reason
            })
        }
    }
}
