import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/env.dart';
import 'core/router.dart';
import 'data/auth/session.dart';
import 'data/entitlement.dart';
import 'data/providers.dart';
import 'features/analysis/analysis_providers.dart';
import 'features/capture/capture_providers.dart';
import 'features/report/report_providers.dart';
import 'l10n/app_localizations.dart';

class HomeVaultApp extends ConsumerStatefulWidget {
  const HomeVaultApp({super.key});

  @override
  ConsumerState<HomeVaultApp> createState() => _HomeVaultAppState();
}

class _HomeVaultAppState extends ConsumerState<HomeVaultApp> {
  @override
  void initState() {
    super.initState();
    // Play Integrity token provider; a no-op without a project number.
    ref.read(appCheckProvider).prepare();
    // Warm up the device session so the first analysis does not pay for
    // registration. Failures are fine here; the analysis call retries.
    if (Env.isApiConfigured) {
      ref.read(sessionProvider.notifier).accessToken().catchError((Object e) {
        debugPrint('device registration deferred: $e');
        return '';
      });
    }
    // Resume analyses interrupted by a restart or an offline period.
    ref.read(analysisQueueProvider).start();
    // Store connection; a no-op without REVENUECAT_API_KEY. The device id
    // becomes the RevenueCat app user id so the server webhook can map
    // purchases to this device.
    ref.read(sessionProvider.notifier).deviceId().then(
          (id) => ref.read(purchasesGatewayProvider).configure(appUserId: id),
          onError: (Object e) {
            debugPrint('device id unavailable, configuring purchases anonymously: $e');
            return ref.read(purchasesGatewayProvider).configure();
          },
        );
    // Drop photo and attachment files whose rows were deleted earlier.
    ref.read(storageJanitorProvider).sweep().catchError((Object e) {
      debugPrint('storage sweep failed: $e');
      return 0;
    });
    // Report review counters left over from the last session (spec §10).
    if (Env.isApiConfigured) {
      ref.read(reviewStatsUploaderProvider).upload().catchError((Object e) {
        debugPrint('review stats upload failed: $e');
        return false;
      });
      // PDFs generated while offline (or before backup existed).
      ref.read(reportBackupServiceProvider).backupPending().catchError((Object e) {
        debugPrint('report backup failed: $e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1F5F5B),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF1F5F5B),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: appRouter,
    );
  }
}
