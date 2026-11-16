package app.yousuf.adhan

import com.batoulapps.adhan2.CalculationMethod
import com.batoulapps.adhan2.CalculationParameters
import com.batoulapps.adhan2.Coordinates
import com.batoulapps.adhan2.HighLatitudeRule
import com.batoulapps.adhan2.Madhab
import com.batoulapps.adhan2.Prayer
import com.batoulapps.adhan2.PrayerAdjustments
import com.batoulapps.adhan2.PrayerTimes
import com.batoulapps.adhan2.data.DateComponents
import kotlinx.datetime.Clock
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.plus
import kotlinx.datetime.toLocalDateTime

/**
 * حساب المواقيت في Kotlin — مصدر الحقيقة للجدولة على أندرويد (SPEC §2، §6).
 * نفس خوارزمية adhan_dart؛ اختبار التطابق يضمن فرق = 0 دقيقة (SPEC §11).
 */
object PrayerCalc {

    /** صلاة قادمة بوقتها المطلق. */
    data class ScheduledPrayer(val prayer: Prayer, val instant: Instant)

    private val FIVE_PRAYERS = listOf(
        Prayer.FAJR, Prayer.DHUHR, Prayer.ASR, Prayer.MAGHRIB, Prayer.ISHA,
    )

    fun timeZoneOf(config: AdhanConfig): TimeZone =
        runCatching { TimeZone.of(config.timezoneId) }
            .getOrDefault(TimeZone.currentSystemDefault())

    fun calculationMethod(id: String): CalculationMethod = when (id) {
        "egyptian" -> CalculationMethod.EGYPTIAN
        "mwl" -> CalculationMethod.MUSLIM_WORLD_LEAGUE
        "isna" -> CalculationMethod.NORTH_AMERICA
        "karachi" -> CalculationMethod.KARACHI
        "kuwait" -> CalculationMethod.KUWAIT
        "qatar" -> CalculationMethod.QATAR
        "dubai" -> CalculationMethod.DUBAI
        "singapore" -> CalculationMethod.SINGAPORE
        "turkey" -> CalculationMethod.TURKEY
        // TODO(SPEC §8): طهران تحتاج زاوية مغرب 4.5° وهي غير مدعومة في adhan2؛
        // التقريب الحالي يحسب المغرب عند الغروب. يُراجع قبل النشر.
        "tehran", "custom" -> CalculationMethod.OTHER
        else -> CalculationMethod.UMM_AL_QURA
    }

    fun parameters(config: AdhanConfig): CalculationParameters {
        var params = calculationMethod(config.method).parameters.copy(
            madhab = if (config.madhab == "hanafi") Madhab.HANAFI else Madhab.SHAFI,
            highLatitudeRule = when (config.highLatRule) {
                "seventh_of_the_night" -> HighLatitudeRule.SEVENTH_OF_THE_NIGHT
                "twilight_angle" -> HighLatitudeRule.TWILIGHT_ANGLE
                else -> HighLatitudeRule.MIDDLE_OF_THE_NIGHT
            },
            prayerAdjustments = PrayerAdjustments(
                fajr = config.adjustments["fajr"] ?: 0,
                sunrise = config.adjustments["sunrise"] ?: 0,
                dhuhr = config.adjustments["dhuhr"] ?: 0,
                asr = config.adjustments["asr"] ?: 0,
                maghrib = config.adjustments["maghrib"] ?: 0,
                isha = config.adjustments["isha"] ?: 0,
            ),
        )
        if (config.method == "tehran") {
            params = params.copy(fajrAngle = 17.7, ishaAngle = 14.0)
        }
        return params
    }

    fun timesFor(config: AdhanConfig, date: LocalDate): PrayerTimes = PrayerTimes(
        Coordinates(config.latitude, config.longitude),
        DateComponents(date.year, date.monthNumber, date.dayOfMonth),
        parameters(config),
    )

    /**
     * الصلوات القادمة (أذان) بعد [from] مرتبة بالوقت.
     *
     * [prayers] يحصر النتيجة في صلوات بعينها (المفعّلة فقط)؛ فارغة = لا شيء.
     */
    fun upcomingAdhans(
        config: AdhanConfig,
        count: Int,
        from: Instant = Clock.System.now(),
        prayers: Set<String> = AdhanConfig.PRAYER_KEYS.toSet(),
    ): List<ScheduledPrayer> {
        if (prayers.isEmpty()) return emptyList()
        val zone = timeZoneOf(config)
        var day = from.toLocalDateTime(zone).date
        val result = mutableListOf<ScheduledPrayer>()
        var guard = 0
        while (result.size < count && guard < 10) {
            val times = timesFor(config, day)
            for (prayer in FIVE_PRAYERS) {
                if (prayer.name.lowercase() !in prayers) continue
                val instant = times.timeForPrayer(prayer) ?: continue
                if (instant > from) result += ScheduledPrayer(prayer, instant)
            }
            day = day.plus(1, DateTimeUnit.DAY)
            guard++
        }
        return result.take(count)
    }
}
