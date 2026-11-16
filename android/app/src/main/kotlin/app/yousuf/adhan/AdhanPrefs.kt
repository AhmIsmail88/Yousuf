package app.yousuf.adhan

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first

private val Context.adhanDataStore by preferencesDataStore(name = "adhan")

/**
 * تخزين إعدادات الأذان محلياً عبر DataStore (SPEC §6: AdhanPrefs).
 * لا تُرسل لأي سيرفر (SPEC §10).
 */
object AdhanPrefs {
    private val keyConfig = stringPreferencesKey("config_json")

    suspend fun save(context: Context, config: AdhanConfig) {
        context.adhanDataStore.edit { prefs ->
            prefs[keyConfig] = config.toJson()
        }
    }

    suspend fun load(context: Context): AdhanConfig? {
        val prefs = context.adhanDataStore.data.first()
        val json = prefs[keyConfig] ?: return null
        return AdhanConfig.fromJson(json)
    }
}
