import 'dart:io';

import 'package:flutter/material.dart';

import '../models/photo_slots.dart';
import '../services/api_client.dart' show CustomPhotoCapture;
import 'camera_screen.dart';
import 'media_preview_screen.dart';
import 'video_capture_screen.dart';

/// Offline mode: the same checklist layout as an inspection (video tile +
/// photo grid + add-photo tile), but captures are saved to the gallery only —
/// nothing is ever uploaded.
///
/// Also the fallback when a vehicle has an open case in both companies and the
/// app cannot tell which one the photos belong to.
class OfflineCaptureScreen extends StatefulWidget {
  const OfflineCaptureScreen({super.key});

  @override
  State<OfflineCaptureScreen> createState() => _OfflineCaptureScreenState();
}

class _OfflineCaptureScreenState extends State<OfflineCaptureScreen> {
  final Map<String, File> _captured = {};
  final List<CustomPhotoCapture> _customCaptured = [];
  File? _video;

  Future<void> _openCamera(PhotoSlot slot) async {
    final file = await Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          vehicleNumber: 'Offline',
          photoField: slot.field,
          photoLabel: slot.label,
          useFrontCamera: slot.useFrontCamera,
          offline: true,
        ),
      ),
    );
    if (file != null && mounted) {
      setState(() => _captured[slot.field] = file);
    }
  }

  /// Preview when a photo exists; camera directly (or after RETAKE) otherwise.
  Future<void> _onSlotTap(PhotoSlot slot) async {
    final file = _captured[slot.field];
    if (file == null) return _openCamera(slot);
    final retake = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            MediaPreviewScreen(title: slot.label, isVideo: false, file: file),
      ),
    );
    if (retake == true && mounted) await _openCamera(slot);
  }

  Future<void> _openVideoCapture() async {
    final file = await Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (_) =>
            const VideoCaptureScreen(vehicleNumber: 'Offline', offline: true),
      ),
    );
    if (file != null && mounted) {
      setState(() => _video = file);
    }
  }

  Future<void> _onVideoTap() async {
    final video = _video;
    if (video == null) return _openVideoCapture();
    final retake = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MediaPreviewScreen(
          title: 'Vehicle Video',
          isVideo: true,
          file: video,
        ),
      ),
    );
    if (retake == true && mounted) await _openVideoCapture();
  }

  Future<void> _addCustomPhoto() async {
    final file = await Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (_) => const CameraScreen(
          vehicleNumber: 'Offline',
          photoField: 'OfflinePhoto',
          photoLabel: 'Additional Photo',
          offline: true,
        ),
      ),
    );
    if (file == null || !mounted) return;

    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Name this photo'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'e.g. Rear Bumper Dent',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (mounted) {
      setState(
        () => _customCaptured.add(
          CustomPhotoCapture(
            (name == null || name.isEmpty) ? 'Offline Photo' : name,
            file,
          ),
        ),
      );
    }
  }

  Widget _buildVideoTile() {
    final captured = _video != null;
    return InkWell(
      onTap: _onVideoTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: captured ? Colors.green : Colors.grey.shade400,
            width: captured ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              captured ? Icons.check_circle : Icons.videocam_outlined,
              color: captured ? Colors.green : Colors.grey,
              size: 30,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Vehicle Video',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    captured
                        ? 'Recorded • saved to gallery • tap to retake'
                        : 'Up to ${kMaxVideoLabel()}, stamped without logo',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildSlotTile(PhotoSlot slot, File? file) {
    return InkWell(
      onTap: () => _onSlotTap(slot),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: file != null ? Colors.green : Colors.grey.shade400,
            width: file != null ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: file != null
                  ? Image.file(file, fit: BoxFit.cover)
                  : Container(
                      color: Colors.grey.shade200,
                      child: const Icon(
                        Icons.photo_camera_outlined,
                        size: 36,
                        color: Colors.grey,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  if (file != null)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 16,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      slot.label,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomTile(int index) {
    final entry = _customCaptured[index];
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MediaPreviewScreen(
            title: entry.name,
            isVideo: false,
            file: entry.file,
            allowRetake: false,
          ),
        ),
      ),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(entry.file, fit: BoxFit.cover),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: InkWell(
                      onTap: () =>
                          setState(() => _customCaptured.removeAt(index)),
                      borderRadius: BorderRadius.circular(16),
                      child: const CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 16,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.name,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddTile() {
    return InkWell(
      onTap: _addCustomPhoto,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade400, width: 1),
          color: Colors.grey.shade100,
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_a_photo_outlined, size: 32, color: Colors.grey),
              SizedBox(height: 6),
              Text(
                'Add Photo',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _captured.length + _customCaptured.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Offline Photos')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Taken: $total • Saved to gallery only — not uploaded',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: _buildVideoTile(),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.15,
              ),
              itemCount: kPhotoSlots.length + _customCaptured.length + 1,
              itemBuilder: (context, index) {
                if (index < kPhotoSlots.length) {
                  final slot = kPhotoSlots[index];
                  return _buildSlotTile(slot, _captured[slot.field]);
                }
                final customIndex = index - kPhotoSlots.length;
                if (customIndex < _customCaptured.length) {
                  return _buildCustomTile(customIndex);
                }
                return _buildAddTile();
              },
            ),
          ),
        ],
      ),
    );
  }
}
