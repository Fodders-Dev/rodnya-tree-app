part of '../create_post_screen.dart';

extension _CreatePostMedia on _CreatePostScreenState {
  Future<void> _openMediaPicker() async {
    // Big-app pattern: a colored-icon picker sheet rather than jumping
    // straight into the OS gallery. Now also surfaces video — user
    // complained "а видео нельзя что-ли?" — and the camera tile splits
    // photo / video so the user can record without scrolling out of
    // the app.
    final choice = await showAttachmentPickerSheet(
      context,
      title: 'ДОБАВИТЬ МЕДИА',
      actions: const [
        AttachmentPickerAction(
          id: 'gallery',
          icon: Icons.photo_library_rounded,
          label: 'Галерея',
          color: Color(0xFFE05A8B),
        ),
        AttachmentPickerAction(
          id: 'camera',
          icon: Icons.photo_camera_rounded,
          label: 'Снять фото',
          color: Color(0xFF3D8DFF),
        ),
        AttachmentPickerAction(
          id: 'video',
          icon: Icons.videocam_rounded,
          label: 'Видео',
          color: Color(0xFFE85A40),
        ),
        AttachmentPickerAction(
          id: 'video_camera',
          icon: Icons.video_call_rounded,
          label: 'Снять видео',
          color: Color(0xFF7B5BD6),
        ),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'camera':
        await _takePhoto();
        break;
      case 'video':
        await _pickVideoFromGallery();
        break;
      case 'video_camera':
        await _recordVideo();
        break;
      case 'gallery':
      default:
        await _pickImages();
        break;
    }
  }

  Future<void> _takePhoto() async {
    try {
      final shot = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1080,
      );
      if (shot == null || !mounted) return;
      _appendMedia(_PostMedia(file: shot, isVideo: false));
    } catch (e) {
      debugPrint('Ошибка камеры: $e');
      if (mounted) _showMessage('Не удалось сделать фото.');
    }
  }

  Future<void> _pickImages() async {
    try {
      final picked = await const GalleryMediaPicker().pickMultiple();
      if (picked.isEmpty || !mounted) {
        return;
      }
      final mapped = picked
          .map((file) => _PostMedia(file: file, isVideo: _looksLikeVideo(file)))
          .toList();
      _appendMediaBatch(mapped);
    } catch (e) {
      debugPrint('Ошибка выбора медиа: $e');
      if (mounted) {
        _showMessage('Не удалось выбрать медиа.');
      }
    }
  }

  Future<void> _pickVideoFromGallery() async {
    try {
      final clip = await _picker.pickVideo(source: ImageSource.gallery);
      if (clip == null || !mounted) return;
      _appendMedia(_PostMedia(file: clip, isVideo: true));
    } catch (e) {
      debugPrint('Ошибка выбора видео: $e');
      if (mounted) _showMessage('Не удалось выбрать видео.');
    }
  }

  Future<void> _recordVideo() async {
    try {
      // On native (iOS / Android) we use the in-app camera-plugin
      // recorder to bypass image_picker's medium-quality default
      // (the source of "качество съёмки на айфоне упало" the user
      // reported earlier — same issue stories had until commit
      // 365efb5). Web stays on image_picker because <input
      // type=file capture> can't drive a live preview loop.
      final XFile? clip;
      if (kIsWeb) {
        clip = await _picker.pickVideo(source: ImageSource.camera);
      } else {
        clip = await KruzhokRecorderScreen.showPost(context);
      }
      if (clip == null || !mounted) return;
      _appendMedia(_PostMedia(file: clip, isVideo: true));
    } catch (e) {
      debugPrint('Ошибка записи видео: $e');
      if (mounted) _showMessage('Не удалось записать видео.');
    }
  }

  /// Push one media item, respecting [kMaxPostMedia].
  void _appendMedia(_PostMedia media) {
    if (_selectedMedia.length >= kMaxPostMedia) {
      _showMessage('Можно прикрепить не более $kMaxPostMedia файлов.');
      return;
    }
    _updateCreatePostState(() {
      _selectedMedia = <_PostMedia>[..._selectedMedia, media];
    });
  }

  /// Push a batch (gallery multi-pick), capping at [kMaxPostMedia] with a
  /// snackbar notice if it had to trim.
  void _appendMediaBatch(List<_PostMedia> batch) {
    final willBeTrimmed = _selectedMedia.length + batch.length > kMaxPostMedia;
    _updateCreatePostState(() {
      final next = <_PostMedia>[..._selectedMedia, ...batch];
      _selectedMedia = next.take(kMaxPostMedia).toList();
    });
    if (willBeTrimmed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Можно добавить до $kMaxPostMedia фото за один пост — '
            'лишние не поместились.',
          ),
        ),
      );
    }
  }

  /// pickMultipleMedia returns XFile but doesn't tell us which entries
  /// are video — sniff via mime then file extension as a fallback.
  bool _looksLikeVideo(XFile file) {
    final mime = file.mimeType?.toLowerCase();
    if (mime != null && mime.startsWith('video/')) return true;
    final name = file.name.toLowerCase();
    return name.endsWith('.mp4') ||
        name.endsWith('.mov') ||
        name.endsWith('.webm') ||
        name.endsWith('.m4v') ||
        name.endsWith('.avi');
  }

  Widget _buildMediaEmptyHint() {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    // Плотность (чанк 12): плитка сидела в своей рамке ВНУТРИ уже
    // обведённой карточки композера — рамка на рамке. Отделяем hairline
    // сверху (граница карточки уже есть снаружи) вместо второго контура.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: tokens.surfaceLine),
        InkWell(
          onTap: _openMediaPicker,
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: tokens.accentSoft,
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                  ),
                  child: Icon(
                    Icons.add_photo_alternate_outlined,
                    color: tokens.accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Добавить фото или видео',
                        style: AppTheme.sans(
                          color: tokens.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Можно прикрепить до $kMaxPostMedia файлов',
                        style: AppTheme.sans(
                          color: tokens.inkSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: tokens.inkSecondary,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaPreviews() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _selectedMedia.length,
      itemBuilder: (context, index) {
        final media = _selectedMedia[index];
        return Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox.expand(
                child: _PickedMediaPreview(media: media),
              ),
            ),
            IconButton(
              tooltip: 'Удалить вложение',
              icon: const Icon(Icons.cancel, color: Colors.black54),
              iconSize: 20,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.7),
              ),
              onPressed: () {
                _updateCreatePostState(() {
                  _selectedMedia.removeAt(index);
                });
              },
            ),
          ],
        );
      },
    );
  }
}
