---
paths:
  - "Shared/Services/HealthInsightsService.swift"
  - "Shared/Utilities/CaffeineInsights.swift"
  - "Caffeine/Views/BodyInsightsView.swift"
  - "Caffeine/Info.plist"
  - "Caffeine/PrivacyInfo.xcprivacy"
  - "CaffeineTests/CaffeineInsightsTests.swift"
---

# Caffeine: body insights and HealthKit read types

Moved verbatim from CLAUDE.md. Loads when a matching file is read; update it here.

Body insights are a second, optional HealthKit authorization, requested only
when the user turns them on. `HealthInsightsService` owns those reads so
declining them cannot affect logging or the bedtime forecast. Requested types
and the shipped feature each one feeds:

| Type | Feature |
|---|---|
| `sleepAnalysis` | time asleep, onset latency, wake-ups; the personal cutoff |
| `restingHeartRate`, `heartRateVariabilitySDNN`, `respiratoryRate`, `oxygenSaturation` | overnight comparisons |
| `heartRate` | heart rate before against after each logged dose |
| `stepCount`, `activeEnergyBurned` | same-day activity comparisons |
| `workoutType` | caffeine modeled on board at workout starts |
| `bodyMass` | intake per kilogram |
| `dateOfBirth`, `biologicalSex` | suggested starting half-life |

Nothing is requested that no surface reads. Keep that table true when changing
`HealthInsightsService.readTypes` or `BodyMetric`, because it is the 5.1.3
justification.
