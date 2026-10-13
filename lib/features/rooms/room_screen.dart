import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/enums.dart';
import '../../core/router.dart';
import '../../data/analysis/analysis_runner.dart';
import '../../data/db/database.dart';
import '../../data/providers.dart';
import '../../l10n/app_localizations.dart';
import '../analysis/analysis_providers.dart';
import '../capture/capture_providers.dart';
import 'room_providers.dart';
import 'room_status_chip.dart';

/// Room detail: photo grid, capture entry point, analysis state and review.
class RoomScreen extends ConsumerWidget {
  const RoomScreen({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final room = ref.watch(roomProvider(roomId));
    final captures = ref.watch(capturesForRoomProvider(roomId)).value ?? const <Capture>[];
    final job = ref.watch(latestJobForRoomProvider(roomId)).value;
    final items = ref.watch(itemsForRoomProvider(roomId)).value ?? const <Item>[];

    return room.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(appBar: AppBar(), body: Center(child: Text('$e'))),
      data: (room) {
        if (room == null) {
          return Scaffold(appBar: AppBar(), body: Center(child: Text(l10n.roomNotFound)));
        }
        final atMax = captures.length >= Limits.maxCapturesPerRoom;
        final enough = captures.length >= Limits.minCapturesPerRoom;
        final jobActive = job != null &&
            (job.status == AnalysisJobStatus.queued || job.status == AnalysisJobStatus.running);

        return Scaffold(
          appBar: AppBar(
            title: Text(room.name),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(child: RoomStatusChip(status: room.status)),
              ),
            ],
          ),
          floatingActionButton: atMax
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => context.push(Routes.capturePath(roomId)),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(captures.isEmpty ? l10n.takePhotos : l10n.addMorePhotos),
                ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _AnalysisPanel(
                roomId: roomId,
                job: job,
                jobActive: jobActive,
                enough: enough,
                items: items,
              ),
              const SizedBox(height: 24),
              Text(l10n.capturesCount(captures.length),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              if (!enough)
                Text(l10n.minPhotosHint(Limits.minCapturesPerRoom),
                    style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 12),
              if (captures.isEmpty)
                Text(l10n.captureHint, style: Theme.of(context).textTheme.bodySmall)
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: captures.length,
                  itemBuilder: (context, i) => _CaptureTile(capture: captures[i]),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AnalysisPanel extends ConsumerWidget {
  const _AnalysisPanel({
    required this.roomId,
    required this.job,
    required this.jobActive,
    required this.enough,
    required this.items,
  });

  final String roomId;
  final AnalysisJob? job;
  final bool jobActive;
  final bool enough;
  final List<Item> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final failed = job?.status == AnalysisJobStatus.failed;
    // Queued with an error code: a transient failure is waiting for the next
    // drain (connectivity, app start) and can be retried by hand right now.
    final waiting = jobActive &&
        job!.status == AnalysisJobStatus.queued &&
        job!.lastError != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (waiting) ...[
              Text(
                l10n.analysisWaitingRetry(l10n.analysisErrorReason(_reasonKey(job!.lastError))),
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => ref.read(analysisQueueProvider).drain(),
                icon: const Icon(Icons.refresh),
                label: Text(l10n.retry),
              ),
            ] else if (jobActive) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(
                job!.status == AnalysisJobStatus.running
                    ? l10n.analysisRunning
                    : l10n.analysisQueued,
              ),
            ] else if (failed) ...[
              Text(
                l10n.analysisFailed(l10n.analysisErrorReason(_reasonKey(job!.lastError))),
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => ref.read(analysisQueueProvider).retry(job!.id),
                icon: const Icon(Icons.refresh),
                label: Text(l10n.retry),
              ),
            ] else ...[
              Text(l10n.itemsRecognised(items.length), style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (items.isNotEmpty)
                    FilledButton.icon(
                      onPressed: () => context.push(Routes.reviewPath(roomId)),
                      icon: const Icon(Icons.checklist),
                      label: Text(l10n.reviewItems),
                    ),
                  FilledButton.tonalIcon(
                    onPressed: enough ? () => _analyze(context, ref) : null,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: Text(items.isEmpty ? l10n.analyzeRoom : l10n.analyzeAgain),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _reasonKey(String? code) {
    if (code == null) return 'other';
    if (code.startsWith('${JobError.other}:')) return 'other';
    return code;
  }

  Future<void> _analyze(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final queue = ref.read(analysisQueueProvider);
    if (items.isNotEmpty) {
      final replaceable =
          await ref.read(appDatabaseProvider).itemsDao.countUnprotectedItems(roomId);
      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.reanalyzeTitle),
          content: Text(l10n.reanalyzeBody(replaceable)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.analyzeAgain),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await queue.enqueue(roomId);
  }
}

class _CaptureTile extends ConsumerWidget {
  const _CaptureTile({required this.capture});

  final Capture capture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final path = ref.watch(captureThumbPathProvider(capture)).value;
    return GestureDetector(
      onLongPress: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.deleteCapture),
            content: Text(l10n.deleteCaptureConfirm),
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
        if (confirmed == true) {
          await ref.read(captureStoreProvider).deleteCapture(capture.id);
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (path == null)
              ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest)
            else
              Image.file(File(path), fit: BoxFit.cover),
            if (capture.isCloseup)
              Positioned(
                left: 4,
                top: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    l10n.closeUpMode,
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
