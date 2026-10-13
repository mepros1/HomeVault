import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/env.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Env.isApiConfigured) {
    debugPrint('API_BASE_URL not set: run with --dart-define, see CLAUDE.md');
  }
  runApp(const ProviderScope(child: HomeVaultApp()));
}
