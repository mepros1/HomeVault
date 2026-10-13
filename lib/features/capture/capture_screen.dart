import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/constants.dart';
import '../../data/db/database.dart';
import '../../data/media/capture_store.dart';
import '../../l10n/app_localizations.dart';
import 'capture_providers.dart';

/// Camera screen (spec §3.2): overlay hint, frame counter, gallery import,
/// close-up mode. Shows an in-app rationale before the system permission
/// prompt (spec §8).
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

enum _Phase { checking, rationale, denied, starting, ready, error }

class _CaptureScreenState extends ConsumerState<CaptureScreen>
    with WidgetsBindingObserver {
  _Phase _phase = _Phase.checking;
  CameraController? _camera;
  String? _error;
  bool _closeUp = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      camera.dispose();
      _camera = null;
      setState(() => _phase = _Phase.starting);
    } else if (state == AppLifecycleState.resumed) {
      _startCamera();
    }
  }

  Future<void> _checkPermission() async {
    final status = await Permission.camera.status;
    if (!mounted) return;
    if (status.isGranted) {
      await _startCamera();
    } else if (status.isPermanentlyDenied) {
      setState(() => _phase = _Phase.denied);
    } else {
      setState(() => _phase = _Phase.rationale);
    }
  }

  Future<void> _requestPermission() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (status.isGranted) {
      await _startCamera();
    } else {
      setState(() => _phase = _Phase.denied);
    }
  }

  Future<void> _startCamera() async {
    setState(() => _phase = _Phase.starting);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('noCamera', 'No camera found');
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _camera = controller;
      setState(() => _phase = _Phase.ready);
    } on CameraException catch (e) {
      if (!mounted) return;
      if (e.code == 'CameraAccessDenied' || e.code == 'CameraAccessDeniedWithoutPrompt') {
        setState(() => _phase = _Phase.denied);
      } else {
        setState(() {
          _phase = _Phase.error;
          _error = e.description ?? e.code;
        });
      }
    }
  }

  Future<void> _shoot() async {
    final camera = _camera;
    if (camera == null || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await camera.takePicture();
      await _store(await file.readAsBytes());
    } on CameraException catch (e) {
      _showMessage((l10n) => l10n.cameraError(e.description ?? e.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_busy) return;
    final current = ref.read(capturesForRoomProvider(widget.roomId)).value?.length ?? 0;
    final remaining = Limits.maxCapturesPerRoom - current;
    if (remaining <= 0) {
      _showMessage((l10n) => l10n.captureLimitReached(Limits.maxCapturesPerRoom));
      return;
    }
    // imageQuality makes image_picker re-encode to JPEG on Android, which is
    // what turns HEIC gallery photos into something our decoder and the
    // server accept. 95 keeps the file close to the original.
    final files = await ImagePicker().pickMultiImage(limit: remaining, imageQuality: 95);
    if (files.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      for (final f in files) {
        await _store(await f.readAsBytes());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _store(Uint8List bytes) async {
    try {
      await ref.read(captureStoreProvider).addCapture(
            roomId: widget.roomId,
            originalBytes: bytes,
            isCloseup: _closeUp,
          );
    } on CaptureLimitReached catch (e) {
      _showMessage((l10n) => l10n.captureLimitReached(e.max));
    } on FormatException {
      _showMessage((l10n) => l10n.unsupportedImage);
    }
  }

  /// Resolves strings after the async gap, under a mounted check.
  void _showMessage(String Function(AppLocalizations l10n) text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text(AppLocalizations.of(context)!))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final captures = ref.watch(capturesForRoomProvider(widget.roomId)).value ?? const <Capture>[];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(l10n.captureTitle),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(l10n.done, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: switch (_phase) {
        _Phase.checking || _Phase.starting =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
        _Phase.rationale => _PermissionPane(
            title: l10n.cameraPermissionTitle,
            body: l10n.cameraPermissionBody,
            action: l10n.cameraPermissionAllow,
            onAction: _requestPermission,
            onGallery: _pickFromGallery,
            galleryLabel: l10n.fromGallery,
          ),
        _Phase.denied => _PermissionPane(
            title: l10n.cameraPermissionTitle,
            body: l10n.cameraPermissionDenied,
            action: l10n.openSettings,
            onAction: openAppSettings,
            onGallery: _pickFromGallery,
            galleryLabel: l10n.fromGallery,
          ),
        _Phase.error => _PermissionPane(
            title: l10n.captureTitle,
            body: l10n.cameraError(_error ?? ''),
            action: l10n.fromGallery,
            onAction: _pickFromGallery,
          ),
        _Phase.ready => _CameraPane(
            camera: _camera!,
            captures: captures,
            closeUp: _closeUp,
            busy: _busy,
            onToggleCloseUp: (v) => setState(() => _closeUp = v),
            onShoot: _shoot,
            onGallery: _pickFromGallery,
          ),
      },
    );
  }
}

class _PermissionPane extends StatelessWidget {
  const _PermissionPane({
    required this.title,
    required this.body,
    required this.action,
    required this.onAction,
    this.onGallery,
    this.galleryLabel,
  });

  final String title;
  final String body;
  final String action;
  final VoidCallback onAction;
  final VoidCallback? onGallery;
  final String? galleryLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_camera_outlined, size: 64, color: Colors.white70),
            const SizedBox(height: 16),
            Text(title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(body, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(onPressed: onAction, child: Text(action)),
            if (onGallery != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onGallery,
                child: Text(galleryLabel!, style: const TextStyle(color: Colors.white)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CameraPane extends ConsumerWidget {
  const _CameraPane({
    required this.camera,
    required this.captures,
    required this.closeUp,
    required this.busy,
    required this.onToggleCloseUp,
    required this.onShoot,
    required this.onGallery,
  });

  final CameraController camera;
  final List<Capture> captures;
  final bool closeUp;
  final bool busy;
  final ValueChanged<bool> onToggleCloseUp;
  final VoidCallback onShoot;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final atMax = captures.length >= Limits.maxCapturesPerRoom;

    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(child: CameraPreview(camera)),
              Positioned(
                left: 16,
                right: 16,
                top: 16,
                child: Column(
                  children: [
                    _Pill(
                      text: l10n.captureProgress(
                        captures.length,
                        Limits.maxCapturesPerRoom,
                        Limits.recommendedCapturesPerRoom,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _Pill(text: closeUp ? l10n.closeUpHint : l10n.captureHint, subtle: true),
                  ],
                ),
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: FilterChip(
                  label: Text(l10n.closeUpMode),
                  avatar: const Icon(Icons.center_focus_strong, size: 18),
                  selected: closeUp,
                  onSelected: onToggleCloseUp,
                ),
              ),
            ],
          ),
        ),
        if (captures.isNotEmpty)
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: captures.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => _Thumb(capture: captures[i]),
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton.filledTonal(
                  onPressed: busy ? null : onGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  tooltip: l10n.fromGallery,
                ),
                SizedBox(
                  width: 72,
                  height: 72,
                  child: FilledButton(
                    onPressed: busy || atMax ? null : onShoot,
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: EdgeInsets.zero,
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.camera_alt, size: 32),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.subtle = false});

  final String text;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: subtle ? 0.35 : 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: TextStyle(color: subtle ? Colors.white70 : Colors.white),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _Thumb extends ConsumerWidget {
  const _Thumb({required this.capture});

  final Capture capture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(captureThumbPathProvider(capture)).value;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 56,
        height: 56,
        child: path == null
            ? const ColoredBox(color: Colors.white12)
            : Image.file(File(path), fit: BoxFit.cover),
      ),
    );
  }
}
