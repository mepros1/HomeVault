import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../l10n/app_localizations.dart';

/// "This needs Pro" prompt used by every gated feature; leads to the paywall.
Future<void> showProDialog(BuildContext context, {required String title}) {
  final l10n = AppLocalizations.of(context)!;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(l10n.freeLimitBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            context.push(Routes.paywall);
          },
          child: Text(l10n.seePro),
        ),
      ],
    ),
  );
}
