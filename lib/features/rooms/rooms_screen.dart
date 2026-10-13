import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/enums.dart';
import '../../core/router.dart';
import '../../data/db/database.dart';
import '../../l10n/app_localizations.dart';
import '../paywall/pro_dialog.dart';
import 'add_room_sheet.dart';
import 'room_providers.dart';
import 'room_status_chip.dart';

class RoomsScreen extends ConsumerWidget {
  const RoomsScreen({super.key, required this.home});

  final Home home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final rooms = ref.watch(roomsForHomeProvider(home.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(home.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: l10n.reportTitle,
            onPressed: () => context.push(Routes.report),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settingsTitle,
            onPressed: () => context.push(Routes.settings),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addRoom(context, ref),
        icon: const Icon(Icons.add),
        label: Text(l10n.addRoom),
      ),
      body: rooms.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (rooms) => rooms.isEmpty
            ? _EmptyRooms(l10n: l10n)
            : ReorderableListView.builder(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: rooms.length,
                onReorderItem: (fromIndex, toIndex) =>
                    ref.read(roomRepositoryProvider).reorder(rooms, fromIndex, toIndex),
                itemBuilder: (context, index) => _RoomTile(
                  key: ValueKey(rooms[index].id),
                  room: rooms[index],
                ),
              ),
      ),
    );
  }

  Future<void> _addRoom(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final choice = await showAddRoomSheet(context);
    if (choice == null || !context.mounted) return;
    try {
      await ref.read(roomRepositoryProvider).addRoom(
            homeId: home.id,
            type: choice.type,
            name: choice.name,
          );
    } on RoomLimitReached {
      if (!context.mounted) return;
      await showProDialog(context, title: l10n.freeLimitTitle);
    }
  }
}

class _EmptyRooms extends StatelessWidget {
  const _EmptyRooms({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.meeting_room_outlined, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(l10n.roomsEmptyTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(l10n.roomsEmptyHint, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _RoomTile extends ConsumerWidget {
  const _RoomTile({super.key, required this.room});

  final Room room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final captures = ref.watch(captureCountProvider(room.id)).value ?? 0;
    return ListTile(
      leading: Icon(_iconFor(room.roomType)),
      title: Text(room.name),
      subtitle: Text(l10n.capturesCount(captures)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RoomStatusChip(status: room.status),
          PopupMenuButton<_RoomAction>(
            onSelected: (action) => _onAction(context, ref, action),
            itemBuilder: (context) => [
              PopupMenuItem(value: _RoomAction.rename, child: Text(l10n.renameRoom)),
              PopupMenuItem(value: _RoomAction.delete, child: Text(l10n.deleteRoom)),
            ],
          ),
        ],
      ),
      onTap: () => context.push(Routes.roomPath(room.id)),
    );
  }

  Future<void> _onAction(BuildContext context, WidgetRef ref, _RoomAction action) async {
    final l10n = AppLocalizations.of(context)!;
    final repo = ref.read(roomRepositoryProvider);
    switch (action) {
      case _RoomAction.rename:
        final name = await showRoomNameDialog(context, initial: room.name);
        if (name != null) await repo.rename(room.id, name);
      case _RoomAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.deleteRoom),
            content: Text(l10n.deleteRoomConfirm(room.name)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.delete),
              ),
            ],
          ),
        );
        if (confirmed == true) await repo.delete(room.id);
    }
  }

  static IconData _iconFor(RoomType type) => switch (type) {
        RoomType.livingRoom => Icons.weekend_outlined,
        RoomType.kitchen => Icons.kitchen_outlined,
        RoomType.masterBedroom || RoomType.bedroom => Icons.bed_outlined,
        RoomType.bathroom => Icons.bathtub_outlined,
        RoomType.garage => Icons.garage_outlined,
        RoomType.basement => Icons.stairs_outlined,
        RoomType.attic => Icons.roofing_outlined,
        RoomType.office => Icons.desk_outlined,
        RoomType.diningRoom => Icons.table_restaurant_outlined,
        RoomType.hallway => Icons.door_front_door_outlined,
        RoomType.closet => Icons.checkroom_outlined,
        RoomType.outdoorShed => Icons.yard_outlined,
        RoomType.custom => Icons.meeting_room_outlined,
      };
}

enum _RoomAction { rename, delete }
