package com.jackwallner.caffeine.model

import org.json.JSONArray
import org.json.JSONObject

data class DrinkPreset(val name: String, val milligrams: Double, val symbolName: String = "cup.and.saucer.fill") {
    val id: String get() = "$name-${milligrams.toInt()}"
}
data class DrinkCategory(val name: String, val drinks: List<DrinkPreset>)

object DrinkCatalog {
    private val exported: JSONObject by lazy {
        val stream = checkNotNull(DrinkCatalog::class.java.getResourceAsStream("/drink-catalog.json")) { "Missing exported Swift drink catalog" }
        JSONObject(stream.bufferedReader().use { it.readText() })
    }
    val categories: List<DrinkCategory> by lazy {
        val rows = exported.getJSONArray("categories")
        (0 until rows.length()).map { rows.getJSONObject(it).let { row -> DrinkCategory(row.getString("name"), drinks(row.getJSONArray("drinks"))) } }
    }
    val allDrinks: List<DrinkPreset> get() = categories.flatMap { it.drinks }
    val defaultPresets: List<DrinkPreset> by lazy { drinks(exported.getJSONArray("defaults")) }

    fun closestName(milligrams: Double): DrinkPreset {
        val match = allDrinks.minByOrNull { kotlin.math.abs(it.milligrams - milligrams) }
        if (match == null || kotlin.math.abs(match.milligrams - milligrams) > 8) return DrinkPreset("Caffeine", milligrams, "drop.fill")
        return match.copy(milligrams = milligrams)
    }

    private fun drinks(rows: JSONArray): List<DrinkPreset> = (0 until rows.length()).map {
        rows.getJSONObject(it).let { row -> DrinkPreset(row.getString("name"), row.getDouble("milligrams"), row.getString("symbol")) }
    }
}
