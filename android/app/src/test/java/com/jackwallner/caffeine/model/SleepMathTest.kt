package com.jackwallner.caffeine.model

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

import org.junit.Assert.*
import org.junit.Test

class SleepMathTest {
    private val start = Instant.parse("2026-10-01T22:00:00Z")
    private val zone = ZoneId.of("UTC")
    private fun at(hours: Long) = start.plusSeconds(hours * 3600)

    @Test fun overlappingSourcesCountSleepOnce() {
        assertEquals(7200.0, SleepMath.mergedDuration(listOf(at(0) to at(2), at(1) to at(2))), 0.0)
    }

    @Test fun disjointIntervalsSumAndInvalidIntervalsAreIgnored() {
        assertEquals(7200.0, SleepMath.mergedDuration(listOf(at(0) to at(1), at(2) to at(3), at(5) to at(4), at(6) to at(6))), 0.0)
        assertEquals(0.0, SleepMath.mergedDuration(emptyList()), 0.0)
    }

    @Test fun touchingAndNestedIntervalsDoNotDoubleCount() {
        assertEquals(14400.0, SleepMath.mergedDuration(listOf(at(1) to at(2), at(0) to at(3), at(3) to at(4))), 0.0)
    }

    @Test fun afterMidnightSleepBelongsToPreviousCaffeineDay() {
        val result = SleepMath.nights(listOf(SleepInterval(at(3), at(9), SleepState.ASLEEP)), zone)
        assertEquals(setOf(LocalDate.of(2026, 10, 1)), result.keys)
        assertEquals(21600.0, result.values.single().duration, 0.0)
    }

    @Test fun sessionWithoutMeasuredSleepAndShortNapDoNotBecomeCutoffNights() {
        assertTrue(SleepMath.nights(listOf(SleepInterval(at(0), at(8), SleepState.IN_BED)), zone).isEmpty())
        assertTrue(SleepMath.nights(listOf(SleepInterval(at(0), at(2), SleepState.ASLEEP)), zone).isEmpty())
    }

    @Test fun onsetAndInterruptionsUseOnlyInteriorWakeWindows() {
        val result = SleepMath.nights(listOf(SleepInterval(at(0), at(8), SleepState.IN_BED),
            SleepInterval(at(1), at(4), SleepState.ASLEEP), SleepInterval(at(5), at(8), SleepState.ASLEEP),
            SleepInterval(at(4), at(5), SleepState.AWAKE), SleepInterval(at(8), at(9), SleepState.AWAKE)), zone).values.single()
        assertEquals(21600.0, result.duration, 0.0)
        assertEquals(3600.0, checkNotNull(result.onsetLatency), 0.0)
        assertEquals(1, result.interruptions)
    }

    @Test fun multiHourInBedWindowDoesNotInventSleepOnset() {
        val result = SleepMath.nights(listOf(SleepInterval(at(0), at(10), SleepState.IN_BED), SleepInterval(at(4), at(10), SleepState.ASLEEP)), zone).values.single()
        assertNull(result.onsetLatency)
    }
}
