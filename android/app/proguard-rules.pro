# قواعد R8 لنسخة release — يوسف
#
# السبب: WorkManager يبني اسم تطبيق Room في وقت التشغيل
# (WorkDatabase_Impl) عبر الانعكاس، فيحذفه/يعيد تسميته R8 وينهار
# التطبيق عند الإقلاع داخل InitializationProvider.

# Room: الإبقاء على تطبيقات قواعد البيانات المولَّدة وعلى أسمائها.
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class androidx.room.RoomDatabase { *; }
-keepnames class * extends androidx.room.RoomDatabase
-dontwarn androidx.room.paging.**

# WorkManager: البادئ والمستودع والعمال.
-keep class androidx.work.** { *; }
-keep class * extends androidx.work.ListenableWorker { *; }
-keep class * extends androidx.work.Worker { *; }
-keep class * extends androidx.work.CoroutineWorker { *; }
-keepnames class androidx.work.impl.WorkDatabase_Impl
-dontwarn androidx.work.**

# androidx.startup يهيّئ WorkManager عبر الانعكاس.
-keep class androidx.startup.** { *; }

# محرك الأذان (Kotlin) — يقرأ JSON ويُستدعى من المنصة.
-keep class app.yousuf.adhan.** { *; }
-keep class app.yousuf.MainActivity { *; }
-keep class app.yousuf.YousufApplication { *; }
-keep class com.batoulapps.adhan.** { *; }

# DataStore (إعدادات الأذان).
-keep class androidx.datastore.** { *; }
-dontwarn androidx.datastore.**

# إشعارات Flutter المحلية.
-keep class com.dexterous.** { *; }
