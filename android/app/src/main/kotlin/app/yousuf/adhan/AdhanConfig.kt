package app.yousuf.adhan

import org.json.JSONObject

/**
 * إعدادات محرك الأذان — مطابقة لعقد CONTRACTS §2 حرفياً.
 */
data class AdhanConfig(
    val latitude: Double,
    val longitude: Double,
    val timezoneId: String,
    val method: String,
    val madhab: String,
    val highLatRule: String,
    val adjustments: Map<String, Int> = emptyMap(),
    val prayerSounds: Map<String, Map<String, String>> = emptyMap(),
    val prePrayerAlertMinutes: Int = 15,
    val iqamaReminderMinutes: Int = 0,
    val respectSilentMode: Boolean = false,
) {
    /** نوع التنبيه لصلاة: full | takbir | notification | off. */
    fun modeFor(prayer: String): String = prayerSounds[prayer]?.get("mode") ?: "full"

    /** معرّف صوت المؤذن لصلاة. */
    fun soundFor(prayer: String): String = prayerSounds[prayer]?.get("sound") ?: "makkah"

    /** الصلوات التي لها تنبيه (ليست مطفأة) — وحدها تُجدول. */
    fun enabledPrayers(): Set<String> = PRAYER_KEYS.filter { modeFor(it) != "off" }.toSet()

    fun toJson(): String = JSONObject().apply {
        put("latitude", latitude)
        put("longitude", longitude)
        put("timezoneId", timezoneId)
        put("method", method)
        put("madhab", madhab)
        put("highLatRule", highLatRule)
        put("adjustments", JSONObject(adjustments as Map<*, *>))
        val sounds = JSONObject()
        prayerSounds.forEach { (prayer, values) ->
            sounds.put(prayer, JSONObject(values as Map<*, *>))
        }
        put("prayerSounds", sounds)
        put("prePrayerAlertMinutes", prePrayerAlertMinutes)
        put("iqamaReminderMinutes", iqamaReminderMinutes)
        put("respectSilentMode", respectSilentMode)
    }.toString()

    companion object {
        val PRAYER_KEYS = listOf("fajr", "dhuhr", "asr", "maghrib", "isha")

        fun fromJson(json: String): AdhanConfig? = runCatching {
            val o = JSONObject(json)
            val adjObj = o.optJSONObject("adjustments")
            val adjustments = PRAYER_KEYS.associateWith { key ->
                adjObj?.optInt(key, 0) ?: 0
            }
            val soundsObj = o.optJSONObject("prayerSounds")
            val sounds = PRAYER_KEYS.associateWith { key ->
                val s = soundsObj?.optJSONObject(key)
                mapOf(
                    "mode" to (s?.optString("mode", "full") ?: "full"),
                    "sound" to (s?.optString("sound", "makkah") ?: "makkah"),
                )
            }
            AdhanConfig(
                latitude = o.getDouble("latitude"),
                longitude = o.getDouble("longitude"),
                timezoneId = o.optString("timezoneId", "Asia/Riyadh"),
                method = o.optString("method", "umm_al_qura"),
                madhab = o.optString("madhab", "shafi"),
                highLatRule = o.optString("highLatRule", "middle_of_the_night"),
                adjustments = adjustments,
                prayerSounds = sounds,
                prePrayerAlertMinutes = o.optInt("prePrayerAlertMinutes", 15),
                iqamaReminderMinutes = o.optInt("iqamaReminderMinutes", 0),
                respectSilentMode = o.optBoolean("respectSilentMode", false),
            )
        }.getOrNull()

        fun fromMap(map: Map<*, *>): AdhanConfig? = runCatching {
            fromJson(JSONObject(map).toString())
        }.getOrNull()
    }
}
