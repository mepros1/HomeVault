import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/enums.dart';
import '../../data/db/database.dart';
import '../../data/ocr/label_parser.dart';
import '../../l10n/app_localizations.dart';
import 'item_providers.dart';

/// Receipt / label / extra photos for one item (spec §3.5). A label photo is
/// run through on-device OCR and the caller gets serial / model candidates
/// to offer the user.
class AttachmentsSection extends ConsumerStatefulWidget {
  const AttachmentsSection({
    super.key,
    required this.itemId,
    required this.onLabelParsed,
  });

  final String itemId;

  /// Called after a label photo was OCR'd. Empty [LabelInfo] means nothing
  /// usable was found.
  final ValueChanged<LabelInfo> onLabelParsed;

  @override
  ConsumerState<AttachmentsSection> createState() => _AttachmentsSectionState();
}

class _AttachmentsSectionState extends ConsumerState<AttachmentsSection> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final attachments =
        ref.watch(attachmentsForItemProvider(widget.itemId)).value ?? const <Attachment>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.attachmentsTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(l10n.attachmentsHint, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        if (attachments.isNotEmpty)
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: attachments.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => _AttachmentThumb(
                attachment: attachments[i],
                onDelete: () => _delete(attachments[i]),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kind in AttachmentKind.values)
              ActionChip(
                avatar: Icon(_iconFor(kind), size: 18),
                label: Text(l10n.addAttachment(kind.name)),
                onPressed: _busy ? null : () => _add(kind),
              ),
          ],
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  Future<void> _add(AttachmentKind kind) async {
    final source = await _pickSource();
    if (source == null || !mounted) return;
    final file = await ImagePicker().pickImage(source: source, imageQuality: 92);
    if (file == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final store = ref.read(attachmentStoreProvider);
      final bytes = await file.readAsBytes();
      final attachment = await store.add(itemId: widget.itemId, kind: kind, bytes: bytes);

      if (kind == AttachmentKind.label) {
        // OCR runs on the stored original; text stays on the device.
        final text = await ref
            .read(ocrEngineProvider)
            .recognizeFile(await store.absolutePath(attachment.filePath));
        await store.setOcrText(attachment.id, text.isEmpty ? null : text);
        if (mounted) widget.onLabelParsed(LabelParser.parse(text));
      }
    } on FormatException {
      _snack((l10n) => l10n.unsupportedImage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<ImageSource?> _pickSource() {
    final l10n = AppLocalizations.of(context)!;
    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.sourceCamera),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.fromGallery),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(Attachment a) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteAttachment),
        content: Text(l10n.deleteAttachmentConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.delete)),
        ],
      ),
    );
    if (confirmed == true) await ref.read(attachmentStoreProvider).delete(a.id);
  }

  void _snack(String Function(AppLocalizations) text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text(AppLocalizations.of(context)!))),
    );
  }

  static IconData _iconFor(AttachmentKind kind) => switch (kind) {
        AttachmentKind.receipt => Icons.receipt_long_outlined,
        AttachmentKind.label => Icons.qr_code_2_outlined,
        AttachmentKind.extra => Icons.add_a_photo_outlined,
      };
}

class _AttachmentThumb extends ConsumerWidget {
  const _AttachmentThumb({required this.attachment, required this.onDelete});

  final Attachment attachment;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final path = ref.watch(attachmentThumbPathProvider(attachment)).value;
    return GestureDetector(
      onLongPress: onDelete,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 96,
          height: 96,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (path == null)
                ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest)
              else
                Image.file(File(path), fit: BoxFit.cover),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: Colors.black54,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    l10n.attachmentKindName(attachment.kind.name),
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
