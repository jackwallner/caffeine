package com.jackwallner.caffeine.model

import java.time.Instant
import java.time.ZoneId

import org.junit.Assert.*
import org.junit.Test

class CaffeineClearanceTest {
    private val now = Instant.parse("2026-03-08T16:00:00Z")
    private val all = CaffeineSourceSelection()
    private fun sample(id: String, dose: Double, at: Instant = now, ours: Boolean = true, local: Boolean = false, drink: String? = null) =
        CaffeineSample(id, if (ours) OWN_SOURCE else "other", if (ours) "Caffeine" else "Other app", dose, at, ours, local, drink)

    @Test fun thresholdTimeUsesLogarithmicHalfLife() {
        assertEquals(15 * 3600.0, checkNotNull(CaffeineClearance.timeToReach(200.0, 25.0, 5.0)), 1e-8)
        assertEquals(0.0, checkNotNull(CaffeineClearance.timeToReach(20.0, 25.0, 5.0)), 0.0)
        assertNull(CaffeineClearance.timeToReach(0.0, 25.0, 5.0))
        assertNull(CaffeineClearance.timeToReach(200.0, 0.0, 5.0))
        assertNull(CaffeineClearance.timeToReach(200.0, 25.0, 0.0))
    }

    @Test fun latestTimeIsTenHoursBeforeBedtimeFor100mgAnd25mgPreference() {
        assertEquals(now.minusSeconds(36000), CaffeineClearance.latestTimeForDose(100.0, emptyList(), now, 25.0, all, 5.0))
        assertEquals(now, CaffeineClearance.latestTimeForDose(20.0, emptyList(), now, 25.0, all, 5.0))
        assertNull(CaffeineClearance.latestTimeForDose(0.0, emptyList(), now, 25.0, all, 5.0))
    }

    @Test fun consumedTodayHonorsLocalMidnightOnDaylightSavingDayAndExcludesFuture() {
        val zone = ZoneId.of("America/Los_Angeles")
        val samples = listOf(sample("yesterday", 100.0, Instant.parse("2026-03-08T07:59:00Z")),
            sample("today", 95.0, Instant.parse("2026-03-08T08:00:00Z")), sample("future", 200.0, now.plusSeconds(1)), sample("negative", -4.0))
        assertEquals(95.0, CaffeineClearance.consumedToday(samples, all, now, zone), 0.0)
    }

    @Test fun sourcesCollapseOwnDevicesRetainLocalQueueCountAndNeverExcludeOurs() {
        val ownPhone = sample("phone", 80.0, local = true)
        val ownWatch = sample("watch", 120.0).copy(sourceBundleID = "$OWN_SOURCE.watch")
        val excluded = CaffeineSourceSelection(setOf(OWN_SOURCE, "other"))
        val sources = CaffeineClearance.sources(listOf(ownPhone, ownWatch, sample("external", 200.0, ours = false)), excluded)
        assertEquals(2, sources.size)
        assertTrue(sources[0].isOurs)
        assertEquals(200.0, sources[0].milligrams, 0.0)
        assertEquals(80.0, sources[0].localOnlyMilligrams, 0.0)
        assertEquals(2, sources[0].sampleCount)
        assertTrue(sources[0].isIncluded)
        assertFalse(sources[1].isIncluded)
        assertEquals(200.0, CaffeineClearance.remaining(listOf(ownPhone, ownWatch), now, excluded, 5.0), 0.0)
    }

    @Test fun sourceSelectionCanBeToggledWithoutChangingOwnData() {
        val excluded = all.setIncluded(false, "other")
        assertFalse(excluded.includes("other", false))
        assertTrue(excluded.includes("other", true))
        assertTrue(excluded.setIncluded(true, "other").includes("other", false))
    }

    @Test fun entriesKeepDrinkNamesAndImportedSourceNames() {
        assertEquals("Latte", sample("named", 128.0, drink = "Latte").displayName)
        assertEquals("Caffeine", sample("unnamed", 100.0).displayName)
        assertEquals("Other app", sample("external", 100.0, ours = false, drink = "").displayName)
    }

    @Test fun contributionsPreserveFractionalDoseTimesAndExcludeSpentEntries() {
        val halfLifeAgo = now.minusSeconds(18000).minusNanos(500_000_000)
        val dose = sample("precise", 100.0, halfLifeAgo)
        val actual = CaffeineClearance.contributions(listOf(dose, sample("spent", 100.0, now.minusSeconds(216000))), now, all, 5.0)
        assertEquals(1, actual.size)
        assertEquals(CaffeineClearance.remaining(100.0, 5.0 + 0.5 / 3600, 5.0), actual.single().remainingMilligrams, 1e-9)
    }
}
