import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/adhkar/presentation/adhkar_screen.dart';
import '../../features/calendar/presentation/calendar_screen.dart';
import '../../features/history/presentation/history_screen.dart';
import '../../features/more/presentation/more_screen.dart';
import '../../features/hadith/presentation/hadith_screen.dart';
import '../../features/khatma/presentation/khatma_screen.dart';
import '../../features/kids/presentation/kids_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/prayer/presentation/prayer_screen.dart';
import '../../features/qibla/presentation/qibla_screen.dart';
import '../../features/quran/presentation/downloads_screen.dart';
import '../../features/quran/presentation/quran_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/tasbih/presentation/tasbih_screen.dart';
import '../core/prefs/shared_preferences_provider.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/splash/presentation/splash_screen.dart';
import '../l10n/generated/app_localizations.dart';
import 'app.dart';

/// التنقل: 4 تبويبات سفلية (الرئيسية · القرآن · الأذكار · صلاتي)،
/// وباقي الأقسام من شبكة الاختصارات وشاشة «المزيد».
///
/// البداية والترحيب مسارات في الموجّه نفسه: إعادة التوجيه تعتمد على جاهزية
/// التطبيق وإتمام الترحيب، وتُعاد عند تغيّرهما.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(appReadyProvider, (_, _) => refresh.value++);
  ref.listen(onboardingDoneProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final ready = ref.read(appReadyProvider);
      final onboarded = ref.read(onboardingDoneProvider);
      final location = state.matchedLocation;
      if (!ready) return location == '/splash' ? null : '/splash';
      if (!onboarded) return location == '/onboarding' ? null : '/onboarding';
      if (location == '/splash' || location == '/onboarding') return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            RootShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/quran',
                builder: (context, state) => const QuranScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/adhkar',
                builder: (context, state) => const AdhkarScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/prayer',
                builder: (context, state) => const PrayerScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(path: '/qibla', builder: (context, state) => const QiblaScreen()),
      GoRoute(
        path: '/tasbih',
        builder: (context, state) => const TasbihScreen(),
      ),
      GoRoute(
        path: '/downloads',
        builder: (context, state) => const DownloadsScreen(),
      ),
      GoRoute(
        path: '/hadith',
        builder: (context, state) => const HadithScreen(),
      ),
      GoRoute(
        path: '/khatma',
        builder: (context, state) => const KhatmaScreen(),
      ),
      GoRoute(path: '/kids', builder: (context, state) => const KidsScreen()),
      GoRoute(
        path: '/calendar',
        builder: (context, state) => const CalendarScreen(),
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => const HistoryScreen(),
      ),
      GoRoute(path: '/more', builder: (context, state) => const MoreScreen()),
    ],
  );
});

/// هيكل الجذر: جسم الشاشة + شريط التنقل السفلي.
///
/// شريط إيقاف الأذان يُعرض أعلى كل الشاشات من `MaterialApp.builder`.
class RootShell extends StatelessWidget {
  const RootShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.tabHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.menu_book_outlined),
            selectedIcon: const Icon(Icons.menu_book),
            label: l10n.tabQuran,
          ),
          NavigationDestination(
            icon: const Icon(Icons.auto_awesome_outlined),
            selectedIcon: const Icon(Icons.auto_awesome),
            label: l10n.tabAdhkar,
          ),
          NavigationDestination(
            icon: const Icon(Icons.mosque_outlined),
            selectedIcon: const Icon(Icons.mosque),
            label: l10n.tabPrayer,
          ),
        ],
      ),
    );
  }
}
