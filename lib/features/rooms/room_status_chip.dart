import 'package:flutter/material.dart';

import '../../core/enums.dart';
import '../../l10n/app_localizations.dart';

/// empty → captured → analyzed → reviewed (spec §3.1).
class RoomStatusChip extends StatelessWidget {
  const RoomStatusChip({super.key, required this.status});

  final RoomStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (status) {
      RoomStatus.empty => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      RoomStatus.captured => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      RoomStatus.analyzed => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      RoomStatus.reviewed => (scheme.primaryContainer, scheme.onPrimaryContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(
        l10n.roomStatusName(status.name),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
      ),
    );
  }
}
