import 'dart:io';

import 'package:flutter/material.dart';

import '../models/open_case.dart';
import '../models/photo_slots.dart';
import '../services/api_client.dart';
import 'camera_screen.dart';
import 'media_preview_screen.dart';
import 'payment_screen.dart';
import 'video_capture_screen.dart';

class PhotoChecklistScreen extends StatefulWidget {
  final OpenCase openCase;

  const PhotoChecklistScreen({super.key, required this.openCase});

  @override
  State<PhotoChecklistScreen> createState() => _PhotoChecklistScreenState();
}

class _PhotoChecklistScreenState extends State<PhotoChecklistScreen> {
  final Map<String, File> _captured = {};
  final List<CustomPhotoCapture> _customCaptured = [];
  File? _video;
  bool _uploading = false;
  bool _photosSynced = false;
  String _uploadStatus = '';

  // Media already uploaded to this case (fetched when the screen opens),
  // so re-entering a case shows its existing photos and video.
  Map<String, String> _uploadedUrls = {};
  List<UploadedCustomPhoto> _serverCustom = [];
  bool _loadingExisting = true;
  bool _hasPayment = false;

  @override
  void initState() {
    super.initState();
    _loadExisting();
    _refreshPaymentFlag();
  }

  Future<void> _loadExisting() async {
    final results = await Future.wait([
      ApiClient.getUploadedMedia(widget.openCase),
      ApiClient.getUploadedCustomPhotos(widget.openCase),
    ]);
    if (!mounted) return;
    setState(() {
      _uploadedUrls = results[0] as Map<String, String>;
      _serverCustom = results[1] as List<UploadedCustomPhoto>;
      _loadingExisting = false;
    });
  }

  /// Payment is optional, so a lookup failure just leaves the badge off.
  Future<void> _refreshPaymentFlag() async {
    try {
      final payment = await ApiClient.getPayment(widget.openCase);
      if (mounted) {
        setState(() => _hasPayment = payment != null && !payment.isEmpty);
      }
    } catch (_) {}
  }

  Future<void> _openPayment() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PaymentScreen(openCase: widget.openCase),
    ));
    await _refreshPaymentFlag();
  }

  String? _uploadedUrl(String field) {
    final url = _uploadedUrls[field];
    return (url == null || url.isEmpty) ? null : url;
  }

  bool _slotDone(PhotoSlot s) =>
      _captured.containsKey(s.field) || _uploadedUrl(s.field) != null;

  bool get _videoDone => _video != null || _uploadedUrl('VehicleVideo') != null;

  // Vehicle video counts as one mandatory item alongside the starred photos.
  // Items already on the server count as done.
  int get _mandatoryDone =>
      kPhotoSlots.where((s) => s.mandatory && _slotDone(s)).length +
      (_videoDone ? 1 : 0);

  int get _mandatoryTotal => kPhotoSlots.where((s) => s.mandatory).length + 1;

  Future<void> _openCamera(PhotoSlot slot) async {
    final file = await Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          vehicleNumber: widget.openCase.vehicleNumber,
          photoField: slot.field,
          photoLabel: slot.label,
          useFrontCamera: slot.useFrontCamera,
        ),
      ),
    );
    if (file != null && mounted) {
      setState(() {
        _captured[slot.field] = file;
        _photosSynced = false; // new photo needs a fresh sync
      });
    }
  }

  /// Preview the photo when one exists (local or uploaded); the camera
  /// opens directly for empty slots, or after RETAKE from the preview.
  Future<void> _onSlotTap(PhotoSlot slot) async {
    final file = _captured[slot.field];
    final url = _uploadedUrl(slot.field);
    if (file == null && url == null) return _openCamera(slot);

    final retake = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MediaPreviewScreen(
          title: slot.label,
          isVideo: false,
          file: file,
          url: file == null ? url : null,
        ),
      ),
    );
    if (retake == true && mounted) await _openCamera(slot);
  }

  Future<void> _openVideoCapture() async {
    final file = await Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (_) =>
            VideoCaptureScreen(vehicleNumber: widget.openCase.vehicleNumber),
      ),
    );
    if (file != null && mounted) {
      setState(() => _video = file);
    }
  }

  Future<void> _onVideoTap() async {
    final url = _uploadedUrl('VehicleVideo');
    if (_video == null && url == null) return _openVideoCapture();

    final retake = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MediaPreviewScreen(
          title: 'Vehicle Video',
          isVideo: true,
          file: _video,
          url: _video == null ? url : null,
        ),
      ),
    );
    if (retake == true && mounted) await _openVideoCapture();
  }

  Future<void> _addCustomPhoto() async {
    final file = await Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          vehicleNumber: widget.openCase.vehicleNumber,
          photoField: 'CustomPhoto',
          photoLabel: 'Additional Photo',
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

    if (name != null && name.isNotEmpty && mounted) {
      setState(() {
        _customCaptured.add(CustomPhotoCapture(name, file));
        _photosSynced = false; // new photo needs a fresh sync
      });
    }
  }

  void _removeCustomPhoto(int index) {
    setState(() => _customCaptured.removeAt(index));
  }

  Future<void> _submit() async {
    if (_captured.isEmpty && _customCaptured.isEmpty && _video == null) {
      _showMessage('Take at least one photo or the video before submitting.');
      return;
    }

    if (_mandatoryDone < _mandatoryTotal) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Mandatory items missing'),
          content: Text(
            'Only $_mandatoryDone of $_mandatoryTotal mandatory '
            'items (photos + video) are taken. Submit anyway? '
            'You can add the rest later.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep taking photos'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Submit anyway'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    final totalCount = _captured.length + _customCaptured.length;
    final hasPhotos = totalCount > 0;
    setState(() {
      _uploading = true;
      _uploadStatus = 'Uploading…';
    });
    try {
      // Photos go first; skipped if they already synced and only the
      // video is being retried.
      if (hasPhotos && !_photosSynced) {
        setState(() => _uploadStatus = 'Uploading $totalCount photo(s)…');
        await ApiClient.uploadPhotos(
          widget.openCase,
          _captured,
          customPhotos: _customCaptured,
        );
        _photosSynced = true;
      }

      // Video goes in its own request so a big file can't fail the photo
      // sync and can be retried alone.
      if (_video != null) {
        setState(() => _uploadStatus = 'Uploading video… 0%');
        await ApiClient.uploadVideo(
          widget.openCase,
          _video!,
          onProgress: (f) {
            if (mounted) {
              setState(
                () => _uploadStatus = 'Uploading video… ${(f * 100).round()}%',
              );
            }
          },
        );
      }

      if (!mounted) return;
      final parts = [
        if (hasPhotos) '$totalCount photo(s)',
        if (_video != null) 'the vehicle video',
      ].join(' and ');
      // Offer payment details, but never require them.
      final addPayment = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: const Text('Upload complete'),
          content: Text(
            '$parts for ${widget.openCase.vehicleNumber} '
            'uploaded. They will now appear on the AVO page.\n\n'
            'Add payment details for this case? (optional)',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('SKIP FOR NOW'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ADD PAYMENT DETAILS'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      if (addPayment == true) {
        await _openPayment();
        if (!mounted) return;
      }
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (_photosSynced && _video != null) {
        _showMessage(
          '${e.message}\nPhotos are synced — press Submit again '
          'to retry just the video.',
        );
      } else {
        _showMessage(e.message);
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _networkThumb(String url) => Image.network(
    url,
    fit: BoxFit.cover,
    loadingBuilder: (context, child, progress) => progress == null
        ? child
        : Container(
            color: Colors.grey.shade200,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
    errorBuilder: (context, error, stack) => Container(
      color: Colors.grey.shade200,
      child: const Icon(
        Icons.broken_image_outlined,
        size: 36,
        color: Colors.grey,
      ),
    ),
  );

  Widget _buildSlotTile(PhotoSlot slot) {
    final file = _captured[slot.field];
    final url = _uploadedUrl(slot.field);
    final done = file != null || url != null;
    return InkWell(
      onTap: _uploading ? null : () => _onSlotTap(slot),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: done
                ? Colors.green
                : slot.mandatory
                ? Colors.orange
                : Colors.grey.shade400,
            width: done ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: file != null
                  ? Image.file(file, fit: BoxFit.cover)
                  : url != null
                  ? _networkThumb(url)
                  : Container(
                      color: Colors.grey.shade200,
                      child: Icon(
                        Icons.photo_camera_outlined,
                        size: 36,
                        color: slot.mandatory ? Colors.orange : Colors.grey,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  if (done)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        file != null ? Icons.check_circle : Icons.cloud_done,
                        color: Colors.green,
                        size: 16,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      slot.mandatory ? '${slot.label} *' : slot.label,
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

  Widget _buildServerCustomTile(UploadedCustomPhoto photo) {
    return InkWell(
      onTap: _uploading
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MediaPreviewScreen(
                  title: photo.name,
                  isVideo: false,
                  url: photo.url,
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
            Expanded(child: _networkThumb(photo.url)),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.cloud_done,
                      color: Colors.green,
                      size: 16,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      photo.name,
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
      onTap: _uploading
          ? null
          : () => Navigator.of(context).push(
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
                      onTap: _uploading
                          ? null
                          : () => _removeCustomPhoto(index),
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
      onTap: _uploading ? null : _addCustomPhoto,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey.shade400,
            style: BorderStyle.solid,
            width: 1,
          ),
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

  Widget _buildVideoTile() {
    final done = _videoDone;
    final String status;
    if (_video != null) {
      status = 'Recorded with watermark • tap to view';
    } else if (done) {
      status = 'Already uploaded • tap to view or re-record';
    } else {
      status =
          'Up to ${kMaxVideoLabel()} walk-around, '
          'watermarked like photos';
    }
    return InkWell(
      onTap: _uploading ? null : _onVideoTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: done ? Colors.green : Colors.orange,
            width: done ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _video != null
                  ? Icons.check_circle
                  : done
                  ? Icons.cloud_done
                  : Icons.videocam_outlined,
              color: done ? Colors.green : Colors.orange,
              size: 30,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Vehicle Video *',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    status,
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

  @override
  Widget build(BuildContext context) {
    final c = widget.openCase;
    return Scaffold(
      appBar: AppBar(
        title: Text(c.vehicleNumber),
        actions: [
          IconButton(
            tooltip: 'Payment details',
            onPressed: _uploading ? null : _openPayment,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.payments_outlined),
                if (_hasPayment)
                  const Positioned(
                    right: -1,
                    top: -1,
                    child: CircleAvatar(radius: 5, backgroundColor: Colors.green),
                  ),
              ],
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              [
                if ((c.applicantName ?? '').isNotEmpty) c.applicantName!,
                if (c.applicantContact.isNotEmpty) c.applicantContact,
              ].join(' • '),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Mandatory: $_mandatoryDone / $_mandatoryTotal • '
                    'New: ${_captured.length + _customCaptured.length}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (_loadingExisting)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
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
              itemCount:
                  kPhotoSlots.length +
                  _serverCustom.length +
                  _customCaptured.length +
                  1,
              itemBuilder: (context, index) {
                if (index < kPhotoSlots.length) {
                  return _buildSlotTile(kPhotoSlots[index]);
                }
                var rest = index - kPhotoSlots.length;
                if (rest < _serverCustom.length) {
                  return _buildServerCustomTile(_serverCustom[rest]);
                }
                rest -= _serverCustom.length;
                if (rest < _customCaptured.length) {
                  return _buildCustomTile(rest);
                }
                return _buildAddTile();
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: FilledButton.icon(
                onPressed: _uploading ? null : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: _uploading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload),
                label: Text(
                  _uploading
                      ? _uploadStatus
                      : 'SUBMIT ${_captured.length + _customCaptured.length} '
                            'PHOTO(S)${_video != null ? ' + VIDEO' : ''}',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
