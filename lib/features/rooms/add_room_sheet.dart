import 'package:flutter/material.dart';

import '../../core/enums.dart';
import '../../l10n/app_localizations.dart';

class RoomChoice {
  const RoomChoice({required this.type, required this.name});

  final RoomType type;
  final String name;
}

/// Bottom sheet with the preset list (spec §3.1) and a custom-name option.
Future<RoomChoice?> showAddRoomSheet(BuildContext context) {
  return showModalBottomSheet<RoomChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => const _AddRoomSheet(),
  );
}

class _AddRoomSheet extends StatelessWidget {
  const _AddRoomSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, controller) => ListView(
        controller: controller,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(l10n.addRoomTitle, style: Theme.of(context).textTheme.titleLarge),
          ),
          for (final type in RoomType.presets)
            ListTile(
              title: Text(l10n.roomTypeName(type.name)),
              onTap: () => Navigator.of(context).pop(
                RoomChoice(type: type, name: l10n.roomTypeName(type.name)),
              ),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(l10n.customRoom),
            onTap: () async {
              final name = await showRoomNameDialog(context);
              if (name != null && context.mounted) {
                Navigator.of(context).pop(RoomChoice(type: RoomType.custom, name: name));
              }
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Single text field dialog; returns the trimmed name or null on cancel.
Future<String?> showRoomNameDialog(BuildContext context, {String? initial}) {
  final l10n = AppLocalizations.of(context)!;
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) {
      void submit() {
        final name = controller.text.trim();
        if (name.isNotEmpty) Navigator.of(context).pop(name);
      }

      return AlertDialog(
        title: Text(l10n.customRoomNameLabel),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => submit(),
          decoration: InputDecoration(labelText: l10n.customRoomNameLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: submit,
            child: Text(initial == null ? l10n.add : l10n.save),
          ),
        ],
      );
    },
  ).whenComplete(controller.dispose);
}
