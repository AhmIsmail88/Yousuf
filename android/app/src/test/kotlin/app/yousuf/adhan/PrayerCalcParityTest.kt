package app.yousuf.adhan

import com.batoulapps.adhan2.Prayer
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

/**
 * تطابق Dart↔Kotlin: كل مدينة/تاريخ في ملف المرجع يجب أن يطابق بالدقيقة
 * (SPEC §11: 50 مدينة × 365 يوماً × 6 مواقيت، فرق = 0).
 *
 * الملف يولّده: dart run tools/parity/bin/generate_reference.dart
 */
class PrayerCalcParityTest {

    private fun findReference(): File? {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        repeat(6) {
            val current = dir ?: return null
            val candidates = listOf(
                File(current, "tools/parity/reference_times.json"),
                File(current, "yousuf/tools/parity/reference_times.json"),
            )
            candidates.firstOrNull { it.exists() }?.let { return it }
            dir = current.parentFile
        }
        return null
    }

    @Test
    fun dartAndKotlinAgreeToTheMinute() {
        val file = findReference()
        if (file == null) {
            fail("ملف المرجع غير موجود — شغّل أولاً: dart run tools/parity/bin/generate_reference.dart")
            return
        }
        val root = JSONObject(file.readText())
        val cities = root.getJSONArray("cities")
        val times = root.getJSONObject("times")

        val mismatches = mutableListOf<String>()
        var checked = 0

        for (i in 0 until cities.length()) {
            val city = cities.getJSONObject(i)
            val config = AdhanConfig(
                latitude = city.getDouble("lat"),
                longitude = city.getDouble("lng"),
                timezoneId = city.getString("tz"),
                method = city.getString("method"),
                madhab = city.getString("madhab"),
                highLatRule = "middle_of_the_night",
            )
            val zone = PrayerCalc.timeZoneOf(config)
            val prefix = city.getString("id") + "|"
            val keys = times.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                if (!key.startsWith(prefix)) continue
                val date = LocalDate.parse(key.substringAfter('|'))
                val expected = times.getJSONObject(key)
                val actual = PrayerCalc.timesFor(config, date)
                val pairs = listOf(
                    Prayer.FAJR to "fajr",
                    Prayer.SUNRISE to "sunrise",
                    Prayer.DHUHR to "dhuhr",
                    Prayer.ASR to "asr",
                    Prayer.MAGHRIB to "maghrib",
                    Prayer.ISHA to "isha",
                )
                for ((prayer, name) in pairs) {
                    val instant = actual.timeForPrayer(prayer) ?: continue
                    val local = instant.toLocalDateTime(zone)
                    val hhmm = "%02d:%02d".format(local.hour, local.minute)
                    val want = expected.getString(name)
                    if (hhmm != want) {
                        mismatches += "${city.getString("id")} $date $name: kotlin=$hhmm dart=$want"
                    }
                    checked++
                }
            }
        }

        if (mismatches.isNotEmpty()) {
            fail(
                "اختلافات Dart↔Kotlin (${mismatches.size} من $checked):\n" +
                    mismatches.take(25).joinToString("\n"),
            )
        }
        assertTrue("لم يُفحص أي مدخل — تحقق من ملف المرجع", checked > 0)
    }
}
