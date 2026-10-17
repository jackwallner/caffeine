package com.jackwallner.caffeine.model

import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

enum class SleepState { IN_BED, AWAKE, ASLEEP }
data class SleepInterval(val start: Instant, val end: Instant, val state: SleepState)
data class NightSummary(val duration: Double, val onsetLatency: Double?, val interruptions: Int)

object SleepMath {
    fun mergedDuration(intervals: List<Pair<Instant, Instant>>): Double {
        val sorted = intervals.filter { it.second > it.first }.sortedBy { it.first }
        if (sorted.isEmpty()) return 0.0
        var current = sorted.first()
        var total = 0.0
        sorted.drop(1).forEach {
            if (it.first <= current.second) current = current.first to maxOf(current.second, it.second)
            else {
                total += seconds(current.first, current.second)
                current = it
            }
        }
        return total + seconds(current.first, current.second)
    }

    fun nights(intervals: List<SleepInterval>, zone: ZoneId = ZoneId.systemDefault()): Map<LocalDate, NightSummary> =
        intervals.filter { it.end > it.start }.groupBy { it.start.minusSeconds(43200).atZone(zone).toLocalDate() }.mapNotNull { (date, rows) ->
            val asleep = rows.filter { it.state == SleepState.ASLEEP }
            val duration = mergedDuration(asleep.map { it.start to it.end })
            if (duration < 10800) return@mapNotNull null
            val sleepStart = asleep.minOf { it.start }
            val sleepEnd = asleep.maxOf { it.end }
            val inBed = rows.filter { it.state == SleepState.IN_BED }.minOfOrNull { it.start }
            val latency = inBed?.takeIf { it < sleepStart }?.let { seconds(it, sleepStart) }?.takeIf { it <= 10800 }
            date to NightSummary(duration, latency, rows.count { it.state == SleepState.AWAKE && it.start > sleepStart && it.end < sleepEnd })
        }.toMap()

    private fun seconds(start: Instant, end: Instant): Double = Duration.between(start, end).let { it.seconds + it.nano / 1e9 }
}
