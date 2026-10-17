package com.jackwallner.caffeine.model

import java.time.Instant
import java.time.ZoneId
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sqrt

enum class BodyMetric(val title: String, val noiseFloor: Double, val isOvernight: Boolean = true) {
    sleepDuration("Time asleep", 900.0),
    sleepOnset("Time to fall asleep", 300.0),
    sleepInterruptions("Times awake", 0.5),
    restingHeartRate("Resting heart rate", 1.5),
    heartRateVariability("Heart rate variability (RMSSD)", 3.0),
    respiratoryRate("Respiratory rate", 0.3),
    oxygenSaturation("Blood oxygen", 0.4),
    steps("Steps", 500.0, false),
    activeEnergy("Active energy", 40.0, false),
}

data class DailyBodyRecord(
    val date: Instant,
    val consumedMilligrams: Double,
    val bedtimeMilligrams: Double,
    val sleepDuration: Double? = null,
    val sleepOnsetLatency: Double? = null,
    val sleepInterruptions: Int? = null,
    val restingHeartRate: Double? = null,
    val heartRateVariability: Double? = null,
    val respiratoryRate: Double? = null,
    val oxygenSaturation: Double? = null,
    val steps: Double? = null,
    val activeEnergy: Double? = null,
) {
    fun value(metric: BodyMetric): Double? = when (metric) {
        BodyMetric.sleepDuration -> sleepDuration
        BodyMetric.sleepOnset -> sleepOnsetLatency
        BodyMetric.sleepInterruptions -> sleepInterruptions?.toDouble()
        BodyMetric.restingHeartRate -> restingHeartRate
        BodyMetric.heartRateVariability -> heartRateVariability
        BodyMetric.respiratoryRate -> respiratoryRate
        BodyMetric.oxygenSaturation -> oxygenSaturation
        BodyMetric.steps -> steps
        BodyMetric.activeEnergy -> activeEnergy
    }
    fun exposure(metric: BodyMetric): Double = if (metric.isOvernight) bedtimeMilligrams else consumedMilligrams
}

data class MetricComparison(val metric: BodyMetric, val splitMilligrams: Double, val lowerMean: Double, val higherMean: Double, val lowerCount: Int, val higherCount: Int) {
    val delta: Double get() = higherMean - lowerMean
    val sampleCount: Int get() = lowerCount + higherCount
    val isMeaningful: Boolean get() = abs(delta) >= metric.noiseFloor
}

data class PersonalCutoff(val milligrams: Double, val sleepDelta: Double, val nightsAbove: Int, val nightsBelow: Int)
sealed interface CutoffFinding {
    data class InsufficientData(val have: Int, val need: Int = CaffeineInsights.minimumCutoffNights) : CutoffFinding
    data class NoMeasurableDifference(val nights: Int) : CutoffFinding
    data class Found(val cutoff: PersonalCutoff) : CutoffFinding
}
data class MetricTrend(val metric: BodyMetric, val coefficient: Double, val sampleCount: Int) {
    val hasPattern: Boolean get() = abs(coefficient) >= 0.15
    val strengthLabel: String get() = when {
        abs(coefficient) >= 0.5 -> "a clear pattern"
        abs(coefficient) >= 0.3 -> "a modest pattern"
        abs(coefficient) >= 0.15 -> "a faint pattern"
        else -> "no clear pattern"
    }
}
data class HeartRateResponse(val doseCount: Int, val baselineBPM: Double, val afterBPM: Double) {
    val delta: Double get() = afterBPM - baselineBPM
}
data class WorkoutCaffeineSummary(val workoutCount: Int, val averageOnBoard: Double, val typicalStartMinutes: Int)
data class DoseIntensity(val milligrams: Double, val bodyMassKilograms: Double) {
    val milligramsPerKilogram: Double get() = if (bodyMassKilograms > 0) milligrams / bodyMassKilograms else 0.0
}
data class HalfLifeSuggestion(val hours: Double, val reason: String)
data class InsightsReport(
    val records: List<DailyBodyRecord> = emptyList(),
    val comparisons: List<MetricComparison> = emptyList(),
    val cutoff: CutoffFinding = CutoffFinding.InsufficientData(0),
    val heartRateResponse: HeartRateResponse? = null,
    val workouts: WorkoutCaffeineSummary? = null,
    val doseIntensity: DoseIntensity? = null,
    val bodyMassKilograms: Double? = null,
    val emptyMetrics: List<BodyMetric> = emptyList(),
) {
    val hasAnyBodyData: Boolean get() = records.any { record -> BodyMetric.entries.any { record.value(it) != null } }
}

object CaffeineInsights {
    const val minimumRecords = 14
    const val minimumPerGroup = 5
    const val minimumCutoffNights = 21
    const val cutoffSleepFloor = 1200.0
    const val minimumGroupShare = 0.25

    fun compare(records: List<DailyBodyRecord>, metric: BodyMetric): MetricComparison? {
        val usable = records.filter { it.value(metric) != null }
        if (usable.size < minimumRecords) return null
        val exposures = usable.map { it.exposure(metric) }.sorted()
        val split = exposures[exposures.size / 2]
        if (split <= exposures.first()) return null
        val (lower, higher) = usable.partition { it.exposure(metric) < split }
        if (lower.size < minimumPerGroup || higher.size < minimumPerGroup) return null
        return MetricComparison(metric, split, lower.mapNotNull { it.value(metric) }.average(), higher.mapNotNull { it.value(metric) }.average(), lower.size, higher.size)
    }

    fun comparisons(records: List<DailyBodyRecord>): List<MetricComparison> = BodyMetric.entries.mapNotNull { compare(records, it) }

    fun personalCutoff(records: List<DailyBodyRecord>): CutoffFinding {
        val nights = records.filter { it.sleepDuration != null }
        if (nights.size < minimumCutoffNights) return CutoffFinding.InsufficientData(nights.size)
        val floor = max(minimumPerGroup, ceil(nights.size * minimumGroupShare).toInt())
        var best: PersonalCutoff? = null
        for (candidate in 10..150 step 5) {
            val (above, below) = nights.partition { it.bedtimeMilligrams >= candidate }
            if (above.size < floor || below.size < floor) continue
            val delta = above.mapNotNull { it.sleepDuration }.average() - below.mapNotNull { it.sleepDuration }.average()
            if (delta > -cutoffSleepFloor) continue
            if (best == null || delta < best.sleepDelta) best = PersonalCutoff(candidate.toDouble(), delta, above.size, below.size)
        }
        return best?.let { CutoffFinding.Found(it) } ?: CutoffFinding.NoMeasurableDifference(nights.size)
    }

    fun trend(records: List<DailyBodyRecord>, metric: BodyMetric): MetricTrend? {
        val usable = records.filter { it.value(metric) != null }
        if (usable.size < minimumRecords) return null
        return pearson(usable.map { it.exposure(metric) }, usable.mapNotNull { it.value(metric) })?.let { MetricTrend(metric, it, usable.size) }
    }

    fun pearson(x: List<Double>, y: List<Double>): Double? {
        if (x.size != y.size || x.size <= 2) return null
        val meanX = x.average()
        val meanY = y.average()
        var covariance = 0.0
        var varianceX = 0.0
        var varianceY = 0.0
        x.indices.forEach {
            val dx = x[it] - meanX
            val dy = y[it] - meanY
            covariance += dx * dy
            varianceX += dx * dx
            varianceY += dy * dy
        }
        if (varianceX <= 0 || varianceY <= 0) return null
        return covariance / sqrt(varianceX * varianceY)
    }

    fun heartRateResponse(doses: List<CaffeineSample>, heartRates: List<Pair<Instant, Double>>, minimumDose: Double = 40.0): HeartRateResponse? {
        val values = doses.filter { it.milligrams >= minimumDose }.mapNotNull { dose ->
            val before = heartRates.filter { it.first >= dose.endDate.minusSeconds(3600) && it.first < dose.endDate }.map { it.second }
            val after = heartRates.filter { it.first >= dose.endDate.plusSeconds(1200) && it.first <= dose.endDate.plusSeconds(5400) }.map { it.second }
            if (before.isEmpty() || after.isEmpty()) null else before.average() to after.average()
        }
        if (values.size < 5) return null
        return HeartRateResponse(values.size, values.map { it.first }.average(), values.map { it.second }.average())
    }

    fun workoutSummary(workoutStarts: List<Instant>, samples: List<CaffeineSample>, selection: CaffeineSourceSelection, halfLifeHours: Double, zone: ZoneId = ZoneId.systemDefault()): WorkoutCaffeineSummary? {
        if (workoutStarts.isEmpty()) return null
        val onBoard = workoutStarts.map { CaffeineClearance.remaining(samples, it, selection, halfLifeHours) }
        val minutes = workoutStarts.map { it.atZone(zone).let { date -> date.hour * 60 + date.minute } }
        return WorkoutCaffeineSummary(workoutStarts.size, onBoard.average(), minutes.average().roundToInt())
    }

    fun suggestedHalfLife(ageYears: Int?): HalfLifeSuggestion? {
        if (ageYears == null || ageYears !in 13..110) return null
        return when {
            ageYears < 30 -> HalfLifeSuggestion(4.5, "Adults under 30 sit toward the faster end of the reference range.")
            ageYears < 50 -> HalfLifeSuggestion(5.0, "The commonly cited adult average sits near the middle of the range.")
            ageYears < 65 -> HalfLifeSuggestion(5.5, "Reported clearance slows gradually with age.")
            else -> HalfLifeSuggestion(6.0, "Reported clearance slows gradually with age.")
        }
    }

    fun doseIntensity(milligrams: Double, bodyMassKilograms: Double?): DoseIntensity? =
        bodyMassKilograms?.takeIf { it > 0 }?.let { DoseIntensity(milligrams, it) }
}
