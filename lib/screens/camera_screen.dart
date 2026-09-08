import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';

import '../services/location_service.dart';
import '../services/watermark_service.dart';

/// Full-screen camera, locked to landscape so photos come out 4:3.
/// Returns the watermarked photo [File] via Navigator.pop. Offline mode
/// ([offline] = true) has no case behind it, so the caller keeps the file out
/// of any upload and the header shows no vehicle number.
class CameraScreen extends StatefulWidget {
  final String vehicleNumber;
  final String photoField;
  final String photoLabel;
  final bool useFrontCamera;
  final bool offline;

  const CameraScreen({
    super.key,
    required this.vehicleNumber,
    required this.photoField,
    required this.photoLabel,
    this.useFrontCamera = false,
    this.offline = false,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _usingFront = false;
  bool _processing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Landscape-only so every photo is native 4:3 with nothing lost.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _usingFront = widget.useFrontCamera;
    _setUpCamera();
    // Warm up the GPS fix so capture isn't delayed later.
    LocationService.get().catchError((_) => WatermarkLocation(
        latitude: 0, longitude: 0));
  }

  Future<void> _setUpCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _error = 'No camera found on this device.');
        return;
      }
      await _startCamera(_pickCamera());
    } on CameraException catch (e) {
      setState(() => _error = e.description ?? 'Camera error.');
    }
  }

  CameraDescription _pickCamera() {
    final wanted = _usingFront
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    return _cameras.firstWhere((c) => c.lensDirection == wanted,
        orElse: () => _cameras.first);
  }

  Future<void> _startCamera(CameraDescription description) async {
    final previous = _controller;
    _controller = null;
    if (mounted) setState(() {});
    await previous?.dispose();

    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await controller.initialize();
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _error = e.code == 'CameraAccessDenied'
            ? 'Camera permission is required.'
            : (e.description ?? 'Camera error.'));
      }
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _controller = controller);
  }

  Future<void> _flipCamera() async {
    _usingFront = !_usingFront;
    await _startCamera(_pickCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      setState(() => _controller = null);
    } else if (state == AppLifecycleState.resumed) {
      _startCamera(_pickCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _processing) {
      return;
    }

    setState(() => _processing = true);
    try {
      final shot = await controller.takePicture();
      final bytes = await shot.readAsBytes();

      final location = await LocationService.get();
      final file = await WatermarkService.apply(
        photoBytes: bytes,
        location: location,
        timestamp: DateTime.now(),
        vehicleNumber: widget.vehicleNumber,
        photoType: widget.photoField,
      );

      // Requirement: watermarked photos are also saved to the gallery.
      try {
        if (!await Gal.hasAccess(toAlbum: true)) {
          await Gal.requestAccess(toAlbum: true);
        }
        await Gal.putImage(file.path, album: 'Vehga Inspections');
      } on GalException {
        // Gallery save is best-effort; the upload copy is already on disk.
      }

      if (!mounted) return;
      Navigator.of(context).pop(file);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_error != null)
              Center(
                  child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white)),
              ))
            else if (controller != null && controller.value.isInitialized)
              Center(child: CameraPreview(controller))
            else
              const Center(child: CircularProgressIndicator()),
            // Which photo is being taken
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed:
                        _processing ? null : () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      widget.offline
                          ? widget.photoLabel
                          : '${widget.vehicleNumber} • ${widget.photoLabel}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          shadows: [Shadow(blurRadius: 4)]),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.cameraswitch, color: Colors.white),
                    onPressed: _processing ? null : _flipCamera,
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: _processing
                    ? const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 8),
                          Text('Stamping photo…',
                              style: TextStyle(color: Colors.white)),
                        ],
                      )
                    : GestureDetector(
                        onTap: _capture,
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: Colors.white, width: 5),
                          ),
                          child: const Icon(Icons.camera_alt,
                              color: Colors.white, size: 34),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
