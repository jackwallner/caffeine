package com.jackwallner.caffeine.model

import java.time.Instant
import java.time.ZoneId

import org.junit.Assert.*
import org.junit.Test

class CaffeineInsightsTest {
    private val start = Instant.parse("2026-10-01T08:00:00Z")
    private fun dose(index: Int, mg: Double = 120.0) = CaffeineSample("$index", OWN_SOURCE, "Caffeine", mg, start.plusSeconds(index * 86400L), true)

    @Test fun heartRateResponseRequiresFiveUsableDosesAndIgnoresSmallDoses() {
        val doses = (0..5).map { dose(it) }
        val readings = doses.flatMap { listOf(it.endDate.minusSeconds(1800) to 60.0, it.endDate.plusSeconds(2700) to 70.0) }
        val result = checkNotNull(CaffeineInsights.heartRateResponse(doses, readings))
        assertEquals(6, result.doseCount)
        assertEquals(10.0, result.delta, 0.0)
        assertNull(CaffeineInsights.heartRateResponse(doses.take(4), readings))
        assertNull(CaffeineInsights.heartRateResponse(doses.map { it.copy(milligrams = 20.0) }, readings))
    }

    @Test fun heartRateResponseRequiresReadingsOnBothSidesAndExcludesSettlingWindow() {
        val doses = (0..5).map { dose(it) }
        val readings = doses.flatMap { listOf(it.endDate.minusSeconds(1800) to 60.0, it.endDate.plusSeconds(1199) to 100.0) }
        assertNull(CaffeineInsights.heartRateResponse(doses, readings))
    }

    @Test fun heartRateResponseIncludesExactWindowEdges() {
        val doses = (0..4).map { dose(it) }
        val readings = doses.flatMap { listOf(it.endDate.minusSeconds(3600) to 60.0, it.endDate.plusSeconds(1200) to 70.0, it.endDate.plusSeconds(5400) to 80.0) }
        val result = checkNotNull(CaffeineInsights.heartRateResponse(doses, readings))
        assertEquals(15.0, result.delta, 0.0)
    }

    @Test fun workoutEstimateUsesEachStartAndZoneAndNeedsAtLeastOneWorkout() {
        val result = checkNotNull(CaffeineInsights.workoutSummary(listOf(start.plusSeconds(18000)), listOf(dose(0, 200.0)), CaffeineSourceSelection(), 5.0, ZoneId.of("UTC")))
        assertEquals(1, result.workoutCount)
        assertEquals(100.0, result.averageOnBoard, 1e-9)
        assertEquals(13 * 60, result.typicalStartMinutes)
        assertNull(CaffeineInsights.workoutSummary(emptyList(), emptyList(), CaffeineSourceSelection(), 5.0))
    }

    @Test fun pearsonRejectsFlatShortOrMismatchedDataAndSupportsNegativePatterns() {
        assertNull(CaffeineInsights.pearson(listOf(1.0, 2.0), listOf(2.0, 4.0)))
        assertNull(CaffeineInsights.pearson(listOf(1.0, 1.0, 1.0), listOf(2.0, 3.0, 4.0)))
        assertNull(CaffeineInsights.pearson(listOf(1.0, 2.0, 3.0), listOf(2.0, 3.0)))
        assertEquals(-1.0, checkNotNull(CaffeineInsights.pearson(listOf(1.0, 2.0, 3.0), listOf(6.0, 4.0, 2.0))), 1e-9)
    }

    @Test fun doseIntensityDoesNotInventBodyMass() {
        assertNull(CaffeineInsights.doseIntensity(200.0, null))
        assertNull(CaffeineInsights.doseIntensity(200.0, 0.0))
        assertEquals(2.5, checkNotNull(CaffeineInsights.doseIntensity(200.0, 80.0)).milligramsPerKilogram, 0.0)
    }

    @Test fun trendStrengthMatchesShippedThresholds() {
        assertFalse(MetricTrend(BodyMetric.steps, 0.149, 20).hasPattern)
        assertEquals("a faint pattern", MetricTrend(BodyMetric.steps, -0.15, 20).strengthLabel)
        assertEquals("a modest pattern", MetricTrend(BodyMetric.steps, 0.3, 20).strengthLabel)
        assertEquals("a clear pattern", MetricTrend(BodyMetric.steps, -0.5, 20).strengthLabel)
    }

    @Test fun reportDistinguishesMissingBodyDataFromRecordedZero() {
        val missing = DailyBodyRecord(start, 100.0, 20.0)
        assertFalse(InsightsReport(records = listOf(missing)).hasAnyBodyData)
        assertTrue(InsightsReport(records = listOf(missing.copy(steps = 0.0))).hasAnyBodyData)
    }

    @Test fun comparisonsNeedAtLeastFivePerGroup() {
        val records = (0..<20).map { DailyBodyRecord(start.plusSeconds(it * 86400L), 0.0, if (it < 4) 10.0 else 60.0, sleepDuration = 28000.0) }
        assertNull(CaffeineInsights.compare(records, BodyMetric.sleepDuration))
    }
}
