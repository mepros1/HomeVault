import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../core/router.dart';
import '../../data/db/database.dart';
import '../../l10n/app_localizations.dart';
import '../analysis/analysis_providers.dart';
import '../capture/capture_providers.dart';
import '../rooms/room_providers.dart';
import 'review_providers.dart';

/// Card-stack review (spec §3.4): most expensive first, swipe right to
/// accept, swipe left to delete, tap to edit. Items under the confidence
/// threshold cannot be swipe-accepted; they need the explicit Confirm button.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  /// Ids acted on but not yet gone from the stream, so a dismissed
  /// Dismissible is never rebuilt.
  final Set<String> _hidden = {};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final room = ref.watch(roomProvider(widget.roomId)).value;
    final all =
        ref.watch(itemsForRoomProvider(widget.roomId)).value ?? const <Item>[];
    final pending =
        (ref.watch(pendingItemsForRoomProvider(widget.roomId)).value ??
                const <Item>[])
            .where((i) => !_hidden.contains(i.id))
            .toList();
    final reviewed = all.length - pending.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(room?.name ?? l10n.reviewTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              l10n.reviewProgress(reviewed, all.length),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.aiDisclosure,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: pending.isEmpty
                ? _DonePane(roomId: widget.roomId, accepted: reviewed)
                : _Stack(
                    items: pending,
                    onAccept: _accept,
                    onDelete: _delete,
                    onEdit: (item) => context.push(Routes.itemPath(item.id)),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _accept(Item item) async {
    setState(() => _hidden.add(item.id));
    await ref.read(reviewRepositoryProvider).accept(item);
  }

  Future<void> _delete(Item item) async {
    final l10n = AppLocalizations.of(context)!;
    final repo = ref.read(reviewRepositoryProvider);
    setState(() => _hidden.add(item.id));
    await repo.delete(item);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.itemDeleted(item.name)),
          action: SnackBarAction(
            label: l10n.undo,
            onPressed: () async {
              await repo.undoDelete(item);
              if (mounted) setState(() => _hidden.remove(item.id));
            },
          ),
        ),
      );
  }
}

class _Stack extends StatelessWidget {
  const _Stack({
    required this.items,
    required this.onAccept,
    required this.onDelete,
    required this.onEdit,
  });

  final List<Item> items;
  final ValueChanged<Item> onAccept;
  final ValueChanged<Item> onDelete;
  final ValueChanged<Item> onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final top = items.first;
    final lowConfidence = _isLowConfidence(top);

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                if (items.length > 1)
                  Positioned.fill(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Opacity(
                      opacity: 0.5,
                      child: _ReviewCard(item: items[1], peek: true),
                    ),
                  ),
                Dismissible(
                  key: ValueKey(top.id),
                  direction: DismissDirection.horizontal,
                  background: _SwipeBackground(
                    alignment: Alignment.centerLeft,
                    color: Theme.of(context).colorScheme.primaryContainer,
                    icon: Icons.check,
                    label: l10n.accept,
                  ),
                  secondaryBackground: _SwipeBackground(
                    alignment: Alignment.centerRight,
                    color: Theme.of(context).colorScheme.errorContainer,
                    icon: Icons.delete_outline,
                    label: l10n.deleteItem,
                  ),
                  // Low-confidence items snap back on a right swipe; the card
                  // already shows the hint and the button reads "Confirm".
                  confirmDismiss: (direction) async =>
                      !(direction == DismissDirection.startToEnd && lowConfidence),
                  onDismissed: (direction) =>
                      direction == DismissDirection.startToEnd
                      ? onAccept(top)
                      : onDelete(top),
                  child: GestureDetector(
                    onTap: () => onEdit(top),
                    child: SizedBox.expand(child: _ReviewCard(item: top)),
                  ),
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => onDelete(top),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l10n.deleteItem),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: () => onEdit(top),
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: l10n.edit,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => onAccept(top),
                    icon: Icon(lowConfidence ? Icons.task_alt : Icons.check),
                    label: Text(lowConfidence ? l10n.confirm : l10n.accept),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

bool _isLowConfidence(Item item) =>
    (item.confidence ?? 1) < Limits.lowConfidenceThreshold;

class _ReviewCard extends ConsumerWidget {
  const _ReviewCard({required this.item, this.peek = false});

  final Item item;
  final bool peek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final money = NumberFormat.simpleCurrency(
      name: item.currency,
      decimalDigits: 0,
    );
    final lowConfidence = _isLowConfidence(item);
    final captureId = item.sourceCaptureId;
    final capture = captureId == null
        ? null
        : ref.watch(captureByIdProvider(captureId)).value;
    // The peek card underneath is tiny and blurred by opacity: the thumbnail
    // is enough there. The top card fills the screen width, so it decodes the
    // original at screen resolution instead of upscaling a 320 px thumbnail.
    final photo = capture == null
        ? null
        : peek
            ? ref.watch(captureThumbPathProvider(capture)).value
            : ref.watch(captureOriginalPathProvider(capture)).value;
    final decodeWidth =
        (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round();

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: peek ? 0 : 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Photo takes whatever height the text leaves; text scrolls if it
          // still does not fit (small screens, long notes).
          Expanded(
            child: photo == null
                ? ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Icon(
                      Icons.image_not_supported_outlined,
                      size: 48,
                    ),
                  )
                : Image.file(
                    File(photo),
                    fit: BoxFit.cover,
                    cacheWidth: peek ? null : decodeWidth,
                    gaplessPlayback: true,
                  ),
          ),
          Flexible(
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      Text(
                        l10n.estimateRange(
                          money.format(item.estLow ?? 0),
                          money.format(item.estHigh ?? 0),
                        ),
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      l10n.categoryName(item.category.name),
                      if (item.brand != null) item.brand!,
                      if (item.model != null) item.model!,
                      if (item.qty > 1) l10n.quantity(item.qty),
                    ].join(' · '),
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (item.note != null) ...[
                    const SizedBox(height: 8),
                    Text(item.note!, style: theme.textTheme.bodySmall),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Chip(
                        avatar: Icon(
                          lowConfidence
                              ? Icons.help_outline
                              : Icons.verified_outlined,
                          size: 18,
                        ),
                        label: Text(
                          l10n.confidencePercent(
                            ((item.confidence ?? 0) * 100).round(),
                          ),
                        ),
                        backgroundColor: lowConfidence
                            ? theme.colorScheme.errorContainer
                            : null,
                      ),
                      if (item.isHighValue)
                        Chip(
                          avatar: const Icon(Icons.star_outline, size: 18),
                          label: Text(l10n.highValueBadge),
                          backgroundColor: theme.colorScheme.tertiaryContainer,
                        ),
                      if (item.condition != null)
                        Chip(
                          label: Text(l10n.conditionName(item.condition!.name)),
                        ),
                    ],
                  ),
                  if (lowConfidence && !peek) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.lowConfidenceHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon), Text(label)],
      ),
    );
  }
}

class _DonePane extends ConsumerWidget {
  const _DonePane({required this.roomId, required this.accepted});

  final String roomId;
  final int accepted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(l10n.reviewAllDone, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(l10n.itemsRecognised(accepted), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              Disclaimer.short,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.pop(),
              child: Text(l10n.backToRoom),
            ),
          ],
        ),
      ),
    );
  }
}
