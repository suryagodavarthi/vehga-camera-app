import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Full-screen viewer for a captured or uploaded photo/video.
/// Shows [file] when present, otherwise streams [url].
/// Pops `true` when the user taps RETAKE (hidden if [allowRetake] is false).
class MediaPreviewScreen extends StatefulWidget {
  final String title;
  final bool isVideo;
  final File? file;
  final String? url;
  final bool allowRetake;

  const MediaPreviewScreen({
    super.key,
    required this.title,
    required this.isVideo,
    this.file,
    this.url,
    this.allowRetake = true,
  });

  @override
  State<MediaPreviewScreen> createState() => _MediaPreviewScreenState();
}

class _MediaPreviewScreenState extends State<MediaPreviewScreen> {
  VideoPlayerController? _player;
  String? _videoError;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) _setUpPlayer();
  }

  Future<void> _setUpPlayer() async {
    try {
      final player = widget.file != null
          ? VideoPlayerController.file(widget.file!)
          : VideoPlayerController.networkUrl(Uri.parse(widget.url!));
      await player.initialize();
      await player.play();
      if (!mounted) {
        await player.dispose();
        return;
      }
      setState(() => _player = player);
    } catch (e) {
      if (mounted) {
        setState(() => _videoError = 'Could not load the video. $e');
      }
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Widget _buildPhoto() {
    final image = widget.file != null
        ? Image.file(widget.file!, fit: BoxFit.contain)
        : Image.network(
            widget.url!,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const Center(
                    child: CircularProgressIndicator(color: Colors.white)),
            errorBuilder: (context, error, stack) => const Center(
              child: Text('Could not load the photo.',
                  style: TextStyle(color: Colors.white)),
            ),
          );
    return InteractiveViewer(maxScale: 6, child: Center(child: image));
  }

  Widget _buildVideo() {
    if (_videoError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_videoError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white)),
        ),
      );
    }
    final player = _player;
    if (player == null || !player.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() =>
                player.value.isPlaying ? player.pause() : player.play()),
            child: Center(
              child: AspectRatio(
                aspectRatio: player.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(player),
                    if (!player.value.isPlaying)
                      const Icon(Icons.play_circle,
                          size: 72, color: Colors.white70),
                  ],
                ),
              ),
            ),
          ),
        ),
        VideoProgressIndicator(player,
            allowScrubbing: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: widget.isVideo ? _buildVideo() : _buildPhoto()),
            if (widget.allowRetake)
              Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white),
                      minimumSize: const Size.fromHeight(48)),
                  icon: const Icon(Icons.replay),
                  label: const Text('RETAKE'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
