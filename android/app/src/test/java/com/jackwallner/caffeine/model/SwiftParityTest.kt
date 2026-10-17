package com.jackwallner.caffeine.model

import java.time.Instant

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class SwiftParityTest {
    private val fixture = JSONObject(checkNotNull(javaClass.getResource("/swift-parity.json")).readText())
    private val samples get() = fixture.getJSONArray("samples").objects().map {
        CaffeineSample(it.getString("id"), it.getString("source"), "Fixture", it.getDouble("milligrams"), instant(it.getDouble("seconds")), it.getBoolean("ours"))
    }

    @Test fun all320SwiftDecayCasesMatch() {
        val cases = fixture.getJSONArray("decay").objects()
        assertEquals(320, cases.size)
        cases.forEach { assertEquals(it.toString(), it.getDouble("remaining"), CaffeineClearance.remaining(it.getDouble("dose"), it.getDouble("hours"), it.getDouble("halfLife")), 1e-9) }
    }

    @Test fun forecastAndRangeMatchSwiftWithExcludedSourcesAndFutureDoses() {
        fixture.getJSONArray("forecasts").objects().forEach {
            val actual = CaffeineClearance.forecast(samples, instant(it.getDouble("at")), selection(it), 5.0)
            assertEquals(it.getDouble("estimate"), actual.estimatedMilligrams, 1e-9)
            assertEquals(it.getDouble("faster"), actual.fasterEstimate, 1e-9)
            assertEquals(it.getDouble("slower"), actual.slowerEstimate, 1e-9)
        }
    }

    @Test fun proposedDrinkForecastMatchesSwift() {
        fixture.getJSONArray("forecasts").objects().forEach {
            val actual = CaffeineClearance.forecastAdding(64.0, instant(1_700_000_000.0), samples, instant(it.getDouble("at")), selection(it), 5.0)
            assertEquals(it.getDouble("adding64"), actual.estimatedMilligrams, 1e-9)
        }
    }

    @Test fun doseSpecificLatestTimeMatchesSwiftIncludingNoAllowance() {
        fixture.getJSONArray("forecasts").objects().forEach {
            val actual = CaffeineClearance.latestTimeForDose(100.0, samples, instant(it.getDouble("at")), 25.0, selection(it), 5.0)
            if (it.isNull("latest100")) assertNull(actual)
            else assertEquals(it.getDouble("latest100"), checkNotNull(actual).let { date -> date.epochSecond + date.nano / 1e9 }, 1e-5)
        }
    }

    @Test fun rankedContributionsMatchSwiftIncludingThresholdAndTies() {
        fixture.getJSONArray("forecasts").objects().forEach {
            val expected = it.getJSONArray("contributions").objects()
            val actual = CaffeineClearance.contributions(samples, instant(it.getDouble("at")), selection(it), 5.0)
            assertEquals(expected.size, actual.size)
            expected.zip(actual).forEach { (reference, value) ->
                assertEquals(reference.getString("id"), value.sample.id)
                assertEquals(reference.getDouble("remaining"), value.remainingMilligrams, 1e-9)
            }
        }
    }

    @Test fun allNineMetricComparisonsMatchSwiftAcrossEightDatasets() {
        fixture.getJSONArray("datasets").objects().forEach { dataset ->
            val records = records(dataset)
            BodyMetric.entries.forEach { metric ->
                val reference = dataset.getJSONObject("comparisons")
                val actual = CaffeineInsights.compare(records, metric)
                if (reference.isNull(metric.name)) assertNull("scenario ${dataset.getInt("scenario")}, $metric", actual)
                else {
                    val expected = reference.getJSONObject(metric.name)
                    checkNotNull(actual)
                    assertEquals(expected.getDouble("split"), actual.splitMilligrams, 1e-9)
                    assertEquals(expected.getDouble("lowerMean"), actual.lowerMean, 1e-9)
                    assertEquals(expected.getDouble("higherMean"), actual.higherMean, 1e-9)
                    assertEquals(expected.getInt("lowerCount"), actual.lowerCount)
                    assertEquals(expected.getInt("higherCount"), actual.higherCount)
                    assertEquals(expected.getBoolean("meaningful"), actual.isMeaningful)
                }
            }
        }
    }

    @Test fun cutoffFindingsMatchSwiftForSparseFlatLopsidedAndStepData() {
        fixture.getJSONArray("datasets").objects().forEach { dataset ->
            val expected = dataset.getJSONObject("cutoff")
            val actual = CaffeineInsights.personalCutoff(records(dataset))
            when (expected.getString("state")) {
                "insufficient" -> assertEquals(CutoffFinding.InsufficientData(expected.getInt("have"), expected.getInt("need")), actual)
                "noDifference" -> assertEquals(CutoffFinding.NoMeasurableDifference(expected.getInt("nights")), actual)
                "found" -> {
                    assertTrue(actual is CutoffFinding.Found)
                    val cutoff = (actual as CutoffFinding.Found).cutoff
                    assertEquals(expected.getDouble("milligrams"), cutoff.milligrams, 1e-9)
                    assertEquals(expected.getDouble("sleepDelta"), cutoff.sleepDelta, 1e-9)
                    assertEquals(expected.getInt("above"), cutoff.nightsAbove)
                    assertEquals(expected.getInt("below"), cutoff.nightsBelow)
                }
                else -> fail("Unknown reference cutoff")
            }
        }
    }

    @Test fun allNineMetricTrendsMatchSwiftAcrossEightDatasets() {
        fixture.getJSONArray("datasets").objects().forEach { dataset ->
            BodyMetric.entries.forEach { metric ->
                val expected = dataset.getJSONObject("trends")
                val actual = CaffeineInsights.trend(records(dataset), metric)
                if (expected.isNull(metric.name)) assertNull(actual)
                else assertEquals(expected.getDouble(metric.name), checkNotNull(actual).coefficient, 1e-9)
            }
        }
    }

    @Test fun ageDefaultsMatchSwiftIncludingBoundariesAndMissingData() {
        fixture.getJSONArray("ages").objects().forEach {
            val actual = CaffeineInsights.suggestedHalfLife(if (it.isNull("age")) null else it.getInt("age"))
            if (it.isNull("halfLife")) assertNull(actual)
            else assertEquals(it.getDouble("halfLife"), checkNotNull(actual).hours, 0.0)
        }
    }

    @Test fun drinkCatalogAndLegacyClosestNamesMatchSwift() {
        assertEquals(20, DrinkCatalog.allDrinks.size)
        assertEquals(listOf(95.0, 128.0, 80.0), DrinkCatalog.defaultPresets.map { it.milligrams })
        fixture.getJSONArray("closestDrinks").objects().forEach {
            val expected = it.getJSONObject("drink")
            val actual = DrinkCatalog.closestName(it.getDouble("dose"))
            assertEquals(expected.getString("name"), actual.name)
            assertEquals(expected.getString("symbol"), actual.symbolName)
            assertEquals(expected.getDouble("milligrams"), actual.milligrams, 0.0)
        }
    }

    private fun selection(value: JSONObject) = CaffeineSourceSelection(if (value.getBoolean("excludedExternal")) setOf("com.example.logger", OWN_SOURCE) else emptySet())
    private fun instant(seconds: Double): Instant {
        val whole = kotlin.math.floor(seconds).toLong()
        return Instant.ofEpochSecond(whole, ((seconds - whole) * 1e9).toLong())
    }
    private fun JSONArray.objects(): List<JSONObject> = (0 until length()).map(::getJSONObject)
    private fun records(dataset: JSONObject): List<DailyBodyRecord> = dataset.getJSONArray("records").objects().map {
        val metrics = it.getJSONObject("metrics")
        fun metric(name: String): Double? = if (metrics.isNull(name)) null else metrics.getDouble(name)
        DailyBodyRecord(instant(it.getDouble("seconds")), it.getDouble("consumed"), it.getDouble("bedtime"),
            metric("sleepDuration"), metric("sleepOnset"), metric("sleepInterruptions")?.toInt(), metric("restingHeartRate"),
            metric("heartRateVariability"), metric("respiratoryRate"), metric("oxygenSaturation"), metric("steps"), metric("activeEnergy"))
    }
}
