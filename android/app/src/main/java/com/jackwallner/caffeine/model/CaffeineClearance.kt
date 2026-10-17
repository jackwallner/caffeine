package com.jackwallner.caffeine.model

import java.time.Instant
import java.time.ZoneId
import kotlin.math.log2
import kotlin.math.max
import kotlin.math.pow

const val OWN_SOURCE = "com.jackwallner.caffeine"

data class CaffeineSample(
    val id: String,
    val sourceBundleID: String,
    val sourceName: String,
    val milligrams: Double,
    val endDate: Instant,
    val isOurs: Boolean,
    val isLocalOnly: Boolean = false,
    val drinkName: String? = null,
) {
    val displayName: String get() = drinkName?.takeIf { it.isNotEmpty() } ?: if (isOurs) "Caffeine" else sourceName
}

data class CaffeineSourceSelection(val excludedBundleIDs: Set<String> = emptySet()) {
    fun includes(bundleID: String, isOurs: Boolean): Boolean = isOurs || bundleID !in excludedBundleIDs
    fun setIncluded(included: Boolean, bundleID: String): CaffeineSourceSelection =
        copy(excludedBundleIDs = if (included) excludedBundleIDs - bundleID else excludedBundleIDs + bundleID)
}

data class CaffeineSourceStatus(
    val bundleID: String,
    val name: String,
    val milligrams: Double,
    val latestEntry: Instant,
    val sampleCount: Int,
    val isOurs: Boolean,
    val isIncluded: Boolean,
    val localOnlyMilligrams: Double,
)

data class CaffeineContribution(val sample: CaffeineSample, val remainingMilligrams: Double)
data class CaffeineForecast(val at: Instant, val estimatedMilligrams: Double, val fasterEstimate: Double, val slowerEstimate: Double)

object CaffeineClearance {
    fun remaining(dose: Double, elapsedHours: Double, halfLifeHours: Double): Double {
        if (dose <= 0 || halfLifeHours <= 0) return 0.0
        return dose * 0.5.pow(max(elapsedHours, 0.0) / halfLifeHours)
    }

    fun included(samples: List<CaffeineSample>, selection: CaffeineSourceSelection): List<CaffeineSample> =
        samples.filter { selection.includes(it.sourceBundleID, it.isOurs) }

    fun consumedToday(samples: List<CaffeineSample>, selection: CaffeineSourceSelection, now: Instant, zone: ZoneId = ZoneId.systemDefault()): Double {
        val start = now.atZone(zone).toLocalDate().atStartOfDay(zone).toInstant()
        return included(samples, selection).filter { it.endDate >= start && it.endDate <= now }.sumOf { max(it.milligrams, 0.0) }
    }

    fun remaining(samples: List<CaffeineSample>, at: Instant, selection: CaffeineSourceSelection, halfLifeHours: Double): Double =
        included(samples, selection).filter { it.endDate <= at }.sumOf {
            remaining(it.milligrams, elapsedHours(it.endDate, at), halfLifeHours)
        }

    fun contributions(samples: List<CaffeineSample>, at: Instant, selection: CaffeineSourceSelection, halfLifeHours: Double, minimumMilligrams: Double = 0.5): List<CaffeineContribution> =
        included(samples, selection).filter { it.endDate <= at }
            .map { CaffeineContribution(it, remaining(it.milligrams, elapsedHours(it.endDate, at), halfLifeHours)) }
            .filter { it.remainingMilligrams >= minimumMilligrams }
            .sortedWith(compareByDescending<CaffeineContribution> { it.remainingMilligrams }.thenByDescending { it.sample.endDate })

    fun forecast(samples: List<CaffeineSample>, at: Instant, selection: CaffeineSourceSelection, halfLifeHours: Double): CaffeineForecast =
        CaffeineForecast(at, remaining(samples, at, selection, halfLifeHours), remaining(samples, at, selection, 4.0), remaining(samples, at, selection, 6.0))

    fun forecastAdding(dose: Double, at: Instant, samples: List<CaffeineSample>, forecastDate: Instant, selection: CaffeineSourceSelection, halfLifeHours: Double): CaffeineForecast =
        forecast(samples + CaffeineSample("preview", OWN_SOURCE, "Caffeine", dose, at, true), forecastDate, selection, halfLifeHours)

    fun timeToReach(currentMilligrams: Double, threshold: Double, halfLifeHours: Double): Double? {
        if (currentMilligrams <= 0 || threshold <= 0 || halfLifeHours <= 0) return null
        if (currentMilligrams <= threshold) return 0.0
        return halfLifeHours * log2(currentMilligrams / threshold) * 3600
    }

    fun latestTimeForDose(dose: Double, existingSamples: List<CaffeineSample>, bedtime: Instant, threshold: Double, selection: CaffeineSourceSelection, halfLifeHours: Double): Instant? {
        if (dose <= 0 || threshold <= 0 || halfLifeHours <= 0) return null
        val allowance = threshold - remaining(existingSamples, bedtime, selection, halfLifeHours)
        if (allowance <= 0) return null
        if (allowance >= dose) return bedtime
        return bedtime.minusNanos((halfLifeHours * log2(dose / allowance) * 3_600_000_000_000).toLong())
    }

    fun sources(samples: List<CaffeineSample>, selection: CaffeineSourceSelection): List<CaffeineSourceStatus> =
        samples.groupBy { if (it.isOurs) OWN_SOURCE else it.sourceBundleID }.map { (bundleID, group) ->
            val newest = group.maxBy { it.endDate }
            val isOurs = group.any { it.isOurs }
            CaffeineSourceStatus(bundleID, if (isOurs) "Caffeine" else newest.sourceName,
                group.sumOf { max(it.milligrams, 0.0) }, newest.endDate, group.size, isOurs,
                selection.includes(bundleID, isOurs), group.filter { it.isLocalOnly }.sumOf { max(it.milligrams, 0.0) })
        }.sortedWith(compareByDescending<CaffeineSourceStatus> { it.isOurs }.thenByDescending { it.milligrams }.thenBy(String.CASE_INSENSITIVE_ORDER) { it.name })

    private fun elapsedHours(from: Instant, to: Instant): Double =
        (to.epochSecond - from.epochSecond + (to.nano - from.nano) / 1e9) / 3600
}
