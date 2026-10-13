import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../rooms/rooms_screen.dart';
import 'create_home_screen.dart';
import 'home_providers.dart';

/// Entry screen: onboarding until a home exists, then the room list.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(currentHomeProvider);
    return home.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context)!.appTitle)),
        body: Center(child: Text('$e')),
      ),
      data: (home) =>
          home == null ? const CreateHomeScreen() : RoomsScreen(home: home),
    );
  }
}
