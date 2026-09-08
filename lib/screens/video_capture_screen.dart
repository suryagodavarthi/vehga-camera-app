import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:video_player/video_player.dart';

import '../services/location_service.dart';
import '../services/video_watermark_service.dart';

const int kMaxVideoSeconds = 90;

/// "1 min 30 sec" style label for UI hints.
String kMaxVideoLabel() {
  final m = kMaxVideoSeconds ~/ 60, s = kMaxVideoSeconds % 60;
  if (m == 0) return '$s sec';
  return s == 0 ? '$m min' : '$m min $s sec';
}

/// Records the vehicle walk-around video (landscape-locked, padded to 4:3),
/// previews it, then burns the watermark in and saves to the gallery.
/// Pops the stamped [File]. Offline mode ([offline] = true) has no case behind
/// it, so the caller keeps the file out of any upload.
class VideoCaptureScreen extends StatefulWidget {
  final String vehicleNumber;
  final bool offline;

  const VideoCaptureScreen(
      {super.key, required this.vehicleNumber, this.offline = false});

  @override
  State<VideoCaptureScreen> createState() => _VideoCaptureScreenState();
}

enum _Phase { camera, preview, processing }

String _fmtClock(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

class _VideoCaptureScreenState extends State<VideoCaptureScreen> {
  CameraController? _controller;
  _Phase _phase = _Phase.camera;
  bool _recording = false;
  int _elapsedSeconds = 0;
  Timer? _timer;
  String? _error;

  File? _rawVideo;
  VideoPlayerController? _player;
  double _processProgress = 0;

  @override
  void initState() {
    super.initState();
    // Landscape-only so the recording is landscape before 4:3 padding.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _setUpCamera();
    // Warm up the GPS fix so processing isn't delayed later.
    LocationService.get().catchError(
        (_) => WatermarkLocation(latitude: 0, longitude: 0));
  }

  Future<void> _setUpCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera found on this device.');
        return;
      }
      final back = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first);
      final controller = CameraController(
        back,
        ResolutionPreset.high, // 720p keeps a 30s clip well under limits
        enableAudio: true,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _error = e.code == 'CameraAccessDenied'
            ? 'Camera permission is required.'
            : (e.description ?? 'Camera error.'));
      }
    }
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _timer?.cancel();
    _controller?.dispose();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _recording) {
      return;
    }
    try {
      await controller.startVideoRecording();
    } on CameraException catch (e) {
      _showMessage(e.description ?? 'Could not start recording.');
      return;
    }
    setState(() {
      _recording = true;
      _elapsedSeconds = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _elapsedSeconds++);
      if (_elapsedSeconds >= kMaxVideoSeconds) _stopRecording();
    });
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    final controller = _controller;
    if (controller == null || !_recording) return;
    setState(() => _recording = false);

    final XFile shot;
    try {
      shot = await controller.stopVideoRecording();
    } on CameraException catch (e) {
      _showMessage(e.description ?? 'Could not stop recording.');
      return;
    }

    _rawVideo = File(shot.path);
    final player = VideoPlayerController.file(_rawVideo!);
    await player.initialize();
    await player.setLooping(true);
    await player.play();
    if (!mounted) {
      await player.dispose();
      return;
    }
    setState(() {
      _player = player;
      _phase = _Phase.preview;
    });
  }

  Future<void> _retake() async {
    await _player?.dispose();
    _player = null;
    try {
      await _rawVideo?.delete();
    } catch (_) {}
    _rawVideo = null;
    if (mounted) setState(() => _phase = _Phase.camera);
  }

  Future<void> _accept() async {
    final raw = _rawVideo;
    if (raw == null) return;
    await _player?.pause();
    setState(() {
      _phase = _Phase.processing;
      _processProgress = 0;
    });

    try {
      final location = await LocationService.get();
      final stamped = await VideoWatermarkService.apply(
        input: raw,
        location: location,
        timestamp: DateTime.now(),
        vehicleNumber: widget.vehicleNumber,
        onProgress: (f) {
          if (mounted) setState(() => _processProgress = f);
        },
      );

      try {
        if (!await Gal.hasAccess(toAlbum: true)) {
          await Gal.requestAccess(toAlbum: true);
        }
        await Gal.putVideo(stamped.path, album: 'Vehga Inspections');
      } on GalException {
        // Gallery save is best-effort; the upload copy is already on disk.
      }

      try {
        await raw.delete();
      } catch (_) {}

      if (!mounted) return;
      Navigator.of(context).pop(stamped);
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString());
      setState(() => _phase = _Phase.preview);
      await _player?.play();
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: switch (_phase) {
          _Phase.camera => _buildCamera(),
          _Phase.preview => _buildPreview(),
          _Phase.processing => _buildProcessing(),
        },
      ),
    );
  }

  Widget _buildCamera() {
    final controller = _controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_error != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white)),
            ),
          )
        else if (controller != null && controller.value.isInitialized)
          Center(child: CameraPreview(controller))
        else
          const Center(child: CircularProgressIndicator()),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: _recording ? null : () => Navigator.pop(context),
              ),
              Expanded(
                child: Text(
                  widget.offline
                      ? 'Offline Video'
                      : '${widget.vehicleNumber} • Vehicle Video',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(blurRadius: 4)]),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
        if (_recording)
          Positioned(
            top: 64,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.fiber_manual_record,
                        color: Colors.red, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '${_fmtClock(_elapsedSeconds)} / '
                      '${_fmtClock(kMaxVideoSeconds)}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: _recording ? _stopRecording : _startRecording,
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 5),
                ),
                child: Icon(
                  _recording ? Icons.stop : Icons.videocam,
                  color: _recording ? Colors.red : Colors.white,
                  size: 34,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    final player = _player;
    return Column(
      children: [
        Expanded(
          child: player != null && player.value.isInitialized
              ? Center(
                  child: AspectRatio(
                    aspectRatio: player.value.aspectRatio,
                    child: VideoPlayer(player),
                  ),
                )
              : const Center(child: CircularProgressIndicator()),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _retake,
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white),
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  icon: const Icon(Icons.replay),
                  label: const Text('RETAKE'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _accept,
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  icon: const Icon(Icons.check),
                  label: const Text('USE VIDEO'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProcessing() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              value: _processProgress > 0 ? _processProgress : null,
              color: Colors.white,
            ),
            const SizedBox(height: 16),
            Text(
              _processProgress > 0
                  ? 'Stamping video… ${(_processProgress * 100).round()}%'
                  : 'Stamping video…',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Adding logo, date and location. Please wait.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
