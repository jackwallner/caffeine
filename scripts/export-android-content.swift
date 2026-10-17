import Foundation

@main
enum AndroidContentExport {
    static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    static func optional(_ value: Double?) -> Any { value.map { $0 as Any } ?? NSNull() }

    static func sample(_ index: Int, dose: Double, hours: Double, ours: Bool = true) -> CaffeineSample {
        CaffeineSample(
            id: "sample-\(index)", sourceBundleID: ours ? caffeineOwnSourceBundleID : "com.example.logger",
            sourceName: ours ? "Caffeine" : "Other logger", milligrams: dose,
            endDate: epoch.addingTimeInterval(hours * 3600), isOurs: ours
        )
    }

    static func serialized(_ sample: CaffeineSample) -> [String: Any] {
        ["id": sample.id, "source": sample.sourceBundleID, "milligrams": sample.milligrams,
         "seconds": sample.endDate.timeIntervalSince1970, "ours": sample.isOurs]
    }

    static func serialized(_ record: DailyBodyRecord) -> [String: Any] {
        ["seconds": record.date.timeIntervalSince1970, "consumed": record.consumedMilligrams,
         "bedtime": record.bedtimeMilligrams,
         "metrics": Dictionary(uniqueKeysWithValues: BodyMetric.allCases.map { ($0.rawValue, optional(record.value(for: $0))) })]
    }

    static func serialized(_ comparison: MetricComparison?) -> Any {
        guard let comparison else { return NSNull() }
        return ["split": comparison.splitMilligrams, "lowerMean": comparison.lowerMean,
                "higherMean": comparison.higherMean, "lowerCount": comparison.lowerCount,
                "higherCount": comparison.higherCount, "meaningful": comparison.isMeaningful] as [String: Any]
    }

    static func serialized(_ cutoff: CutoffFinding) -> [String: Any] {
        switch cutoff {
        case let .insufficientData(have, need): return ["state": "insufficient", "have": have, "need": need]
        case let .noMeasurableDifference(nights): return ["state": "noDifference", "nights": nights]
        case let .found(result): return ["state": "found", "milligrams": result.milligrams,
            "sleepDelta": result.sleepDelta, "above": result.nightsAbove, "below": result.nightsBelow]
        }
    }

    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Expected output directory") }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func write(_ object: Any, name: String) throws {
            var data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            data.append(10)
            try data.write(to: output.appendingPathComponent(name))
        }
        func drink(_ value: DrinkPreset) -> [String: Any] {
            ["name": value.name, "milligrams": value.milligrams, "symbol": value.symbolName]
        }
        try write([
            "schema": 1,
            "categories": DrinkCatalog.categories.map { ["name": $0.name, "drinks": $0.drinks.map(drink)] },
            "defaults": DrinkCatalog.defaultPresets.map(drink)
        ], name: "drink-catalog.json")

        var decay: [[String: Any]] = []
        for dose in [-1.0, 0, 3, 80, 95, 128, 205, 400] {
            for hours in [-2.0, 0, 0.25, 4, 5, 6, 12, 48] {
                for halfLife in [0.0, 4, 4.5, 5, 6] {
                    decay.append(["dose": dose, "hours": hours, "halfLife": halfLife,
                                  "remaining": CaffeineClearance.remaining(dose: dose, elapsedHours: hours, halfLifeHours: halfLife)])
                }
            }
        }
        let samples = [sample(0, dose: 95, hours: -10), sample(1, dose: 128, hours: -5),
                       sample(2, dose: 80, hours: -1, ours: false), sample(3, dose: 200, hours: 2),
                       sample(4, dose: -10, hours: -0.5)]
        var forecasts: [[String: Any]] = []
        for excluded in [false, true] {
            let selection = CaffeineSourceSelection(excludedBundleIDs: excluded ? ["com.example.logger", caffeineOwnSourceBundleID] : [])
            for hours in [0.0, 1, 8, 24] {
                let at = epoch.addingTimeInterval(hours * 3600)
                let forecast = CaffeineClearance.forecast(samples: samples, at: at, selection: selection, halfLifeHours: 5)
                let adding = CaffeineClearance.forecastAdding(dose: 64, at: epoch, samples: samples,
                    forecastDate: at, selection: selection, halfLifeHours: 5)
                forecasts.append([
                    "excludedExternal": excluded, "at": at.timeIntervalSince1970,
                    "estimate": forecast.estimatedMilligrams, "faster": forecast.fasterEstimate,
                    "slower": forecast.slowerEstimate, "adding64": adding.estimatedMilligrams,
                    "latest100": optional(CaffeineClearance.latestTimeForDose(dose: 100, existingSamples: samples,
                        bedtime: at, threshold: 25, selection: selection, halfLifeHours: 5)?.timeIntervalSince1970),
                    "contributions": CaffeineClearance.contributions(samples: samples, at: at, selection: selection, halfLifeHours: 5)
                        .map { ["id": $0.id, "remaining": $0.remainingMilligrams] as [String: Any] }
                ])
            }
        }
        var datasets: [[String: Any]] = []
        for scenario in 0..<8 {
            let count = [10, 20, 40, 36, 40, 30, 40, 40][scenario]
            let records = (0..<count).map { index -> DailyBodyRecord in
                let bedtime: Double
                switch scenario {
                case 1: bedtime = index < 10 ? 10 : 60
                case 3: bedtime = index < 32 ? 10 : 120
                case 5: bedtime = 40
                default: bedtime = Double(index % 20) * 5
                }
                let sleep: Double?
                switch scenario {
                case 1: sleep = index < 10 ? 8 * 3600 : 7 * 3600
                case 2: sleep = bedtime >= 50 ? 6.5 * 3600 : 7.5 * 3600
                case 3: sleep = bedtime >= 120 ? 4 * 3600 : 8 * 3600
                case 4: sleep = nil
                case 6: sleep = index % 2 == 0 ? 7 * 3600 : nil
                case 7: sleep = 7 * 3600 - bedtime * 10
                default: sleep = 7 * 3600
                }
                return DailyBodyRecord(date: epoch.addingTimeInterval(Double(index) * -86400),
                    consumedMilligrams: Double(index) * 13, bedtimeMilligrams: bedtime, sleepDuration: sleep,
                    sleepOnsetLatency: Double(index % 5) * 600, sleepInterruptions: index % 4,
                    restingHeartRate: 60 + bedtime / 20, heartRateVariability: 50 - bedtime / 10,
                    respiratoryRate: 15 + bedtime / 100, oxygenSaturation: 0.98 - bedtime / 10000,
                    steps: Double(4000 + index * 200), activeEnergy: Double(200 + index * 10))
            }
            datasets.append([
                "scenario": scenario, "records": records.map(serialized),
                "comparisons": Dictionary(uniqueKeysWithValues: BodyMetric.allCases.map {
                    ($0.rawValue, serialized(CaffeineInsights.compare(records: records, metric: $0)))
                }),
                "trends": Dictionary(uniqueKeysWithValues: BodyMetric.allCases.map {
                    ($0.rawValue, optional(CaffeineInsights.trend(records: records, metric: $0)?.coefficient))
                }),
                "cutoff": serialized(CaffeineInsights.personalCutoff(records: records))
            ])
        }
        let ages: [Int?] = [nil, 4, 12, 13, 25, 29, 30, 49, 50, 64, 65, 90, 110, 111]
        try write([
            "schema": 1, "decay": decay, "samples": samples.map(serialized), "forecasts": forecasts,
            "datasets": datasets,
            "ages": ages.map { ["age": $0.map { $0 as Any } ?? NSNull(), "halfLife": optional(CaffeineInsights.suggestedHalfLife(ageYears: $0)?.hours)] },
            "closestDrinks": [0.0, 3, 80, 95, 100, 128, 333].map { ["dose": $0, "drink": drink(DrinkCatalog.closestName(to: $0))] }
        ], name: "swift-parity.json")
        print("Exported \(DrinkCatalog.allDrinks.count) drinks, \(decay.count) decay cases, \(forecasts.count) forecasts and \(datasets.count) insight scenarios")
    }
}
