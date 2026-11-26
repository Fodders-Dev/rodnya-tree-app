part of '../relative_details_screen.dart';

extension _RelativeDetailsGallery on _RelativeDetailsScreenState {
  Future<void> _pickAndUploadGalleryImage() async {
    if (_person == null ||
        _currentTreeId == null ||
        !_canEditOrDelete() ||
        _isUpdatingGallery) {
      return;
    }

    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
    );
    if (image == null) {
      return;
    }

    _updateRelativeDetailsState(() {
      _isUpdatingGallery = true;
    });

    try {
      final uploadedUrl = await _storageService.uploadImage(image, 'relatives');
      if (uploadedUrl == null || uploadedUrl.isEmpty) {
        throw Exception('backend не вернул URL после загрузки фото');
      }

      final updatedPerson = await _familyService.addRelativeMedia(
        treeId: _currentTreeId!,
        personId: _person!.id,
        mediaData: {
          'url': uploadedUrl,
          'type': 'image',
          'contentType': image.mimeType,
          'isPrimary': _person!.photoGallery.isEmpty,
        },
      );

      if (!mounted) {
        return;
      }

      _updateRelativeDetailsState(() {
        _person = updatedPerson;
      });
      await _refreshHistory();
      if (!mounted) {
        return;
      }
      _showRelativeSnackBar('Фото добавлено в галерею.');
    } catch (e) {
      debugPrint('Ошибка загрузки фото родственника: $e');
      if (mounted) {
        _showRelativeSnackBar(
          _describeRelativeActionError(
            e,
            fallbackMessage:
                'Не удалось добавить фото. Попробуйте выбрать другой файл или повторить позже.',
          ),
        );
      }
    } finally {
      if (mounted) {
        _updateRelativeDetailsState(() {
          _isUpdatingGallery = false;
        });
      }
    }
  }

  Future<void> _setPrimaryGalleryMedia(Map<String, dynamic> media) async {
    final mediaId = media['id']?.toString();
    if (_person == null ||
        _currentTreeId == null ||
        !_canEditOrDelete() ||
        _isUpdatingGallery ||
        mediaId == null ||
        mediaId.isEmpty ||
        media['isPrimary'] == true) {
      return;
    }

    _updateRelativeDetailsState(() {
      _isUpdatingGallery = true;
    });

    try {
      final updatedPerson = await _familyService.updateRelativeMedia(
        treeId: _currentTreeId!,
        personId: _person!.id,
        mediaId: mediaId,
        mediaData: const {'isPrimary': true},
      );

      if (!mounted) {
        return;
      }

      _updateRelativeDetailsState(() {
        _person = updatedPerson;
      });
      await _refreshHistory();
      if (!mounted) {
        return;
      }
      _showRelativeSnackBar('Основное фото обновлено.');
    } catch (e) {
      debugPrint('Ошибка обновления основного фото: $e');
      if (mounted) {
        _showRelativeSnackBar(
          _describeRelativeActionError(
            e,
            fallbackMessage:
                'Не удалось сменить основное фото. Попробуйте ещё раз.',
          ),
        );
      }
    } finally {
      if (mounted) {
        _updateRelativeDetailsState(() {
          _isUpdatingGallery = false;
        });
      }
    }
  }

  Future<void> _deleteGalleryMedia(Map<String, dynamic> media) async {
    final mediaId = media['id']?.toString();
    if (_person == null ||
        _currentTreeId == null ||
        !_canEditOrDelete() ||
        _isUpdatingGallery ||
        mediaId == null ||
        mediaId.isEmpty) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить фото?'),
        content: const Text(
          'Фотография исчезнет из карточки родственника и из списка дерева.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Удалить',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    _updateRelativeDetailsState(() {
      _isUpdatingGallery = true;
    });

    try {
      final updatedPerson = await _familyService.deleteRelativeMedia(
        treeId: _currentTreeId!,
        personId: _person!.id,
        mediaId: mediaId,
        // Send URL as fallback for clients that cached synthetic IDs (photo-1, etc.)
        fallbackUrl: media['url']?.toString(),
      );

      final deletedUrl = media['url']?.toString();
      if (deletedUrl != null && deletedUrl.isNotEmpty) {
        try {
          await _storageService.deleteImage(deletedUrl);
        } catch (storageError) {
          debugPrint('Не удалось удалить файл из storage: $storageError');
        }
      }

      if (!mounted) {
        return;
      }

      _updateRelativeDetailsState(() {
        _person = updatedPerson;
      });
      await _refreshHistory();
      if (!mounted) {
        return;
      }
      _showRelativeSnackBar('Фото удалено из галереи.');
    } catch (e) {
      debugPrint('Ошибка удаления фото родственника: $e');
      if (mounted) {
        _showRelativeSnackBar(
          _describeRelativeActionError(
            e,
            fallbackMessage:
                'Не удалось удалить фото. Попробуйте ещё раз чуть позже.',
          ),
        );
      }
    } finally {
      if (mounted) {
        _updateRelativeDetailsState(() {
          _isUpdatingGallery = false;
        });
      }
    }
  }

  void _openHistorySheet() {
    if (_currentTreeId == null || _person == null) {
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return TreeHistorySheet(
          historyFuture: _historyRecords.isNotEmpty && !_isLoadingHistory
              ? Future.value(_historyRecords)
              : _familyService.getTreeHistory(
                  treeId: _currentTreeId!,
                  personId: _person!.id,
                ),
          title: 'История изменений',
          subtitle: _person!.displayName,
          currentUserId: _authService.currentUserId,
          emptyMessage: 'Для этой карточки пока нет записей в журнале.',
          onOpenPerson: (personId) {
            Navigator.of(sheetContext).pop();
            if (!mounted || personId == _person!.id) {
              return;
            }
            context.push(
              relativeDetailsRoute(personId, treeId: _currentTreeId),
            );
          },
        );
      },
    );
  }

  void _openGalleryViewer(
    List<Map<String, dynamic>> galleryEntries, {
    required int initialIndex,
  }) {
    // Profile Redesign: route through the shared MediaLightbox so the
    // relative gallery, the post feed, and chat attachments all use
    // the same fullscreen viewer (pinch-to-zoom, swipe-to-dismiss,
    // dark scrim, caption rail). Removes ~150 LOC of bespoke
    // PageView + Dialog plumbing that lived here.
    if (galleryEntries.isEmpty) return;

    final items = <MediaLightboxItem>[];
    for (var i = 0; i < galleryEntries.length; i++) {
      final entry = galleryEntries[i];
      final url = entry['url']?.toString() ?? '';
      if (url.isEmpty) continue;
      final captionRaw = entry['caption']?.toString().trim() ?? '';
      final isPrimary = entry['isPrimary'] == true;
      final positionLabel = '${i + 1} / ${galleryEntries.length}';
      final caption = [
        if (isPrimary) 'Основное фото',
        if (captionRaw.isNotEmpty) captionRaw,
        positionLabel,
      ].join(' · ');
      items.add(MediaLightboxItem(
        imageUrl: normalizePhotoUrl(url) ?? url,
        caption: caption.isEmpty ? null : caption,
      ));
    }
    if (items.isEmpty) return;
    final clampedIndex = initialIndex.clamp(0, items.length - 1);
    MediaLightbox.show(
      context,
      items: items,
      initialIndex: clampedIndex,
    );
  }

  void _openAllPhotos() {
    final person = _person;
    if (person == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileAllPhotosScreen(
          personId: person.id,
          personName: person.name,
        ),
      ),
    );
  }

  Widget _buildGallerySection(List<Map<String, dynamic>> galleryEntries) {
    final canManageGallery = _canEditOrDelete();
    // Пустое состояние — одной короткой строкой рядом с кнопкой: раньше под
    // ней шла ещё карточка-подсказка о том же, а мотивация «добавьте фото»
    // и так есть в плашке заполненности выше.
    final countLabel = galleryEntries.isEmpty
        ? 'Фотографий пока нет'
        : galleryEntries.length == 1
            ? '1 фото'
            : '${galleryEntries.length} фото';

    return _buildInfoSection('Фотографии', [
      Row(
        children: [
          Expanded(
            child: Text(
              countLabel,
              style: TextStyle(color: Colors.grey[700]),
            ),
          ),
          if (_isUpdatingGallery)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (canManageGallery)
            OutlinedButton.icon(
              onPressed: _pickAndUploadGalleryImage,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('Добавить фото'),
            ),
        ],
      ),
      if (galleryEntries.isNotEmpty) const SizedBox(height: 10),
      if (galleryEntries.isNotEmpty)
        SizedBox(
          height: 146,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: galleryEntries.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final media = galleryEntries[index];
              final mediaUrl = media['url']?.toString() ?? '';
              final normalizedMediaUrl = normalizePhotoUrl(mediaUrl);
              final isPrimary = media['isPrimary'] == true;

              return InkWell(
                onTap: normalizedMediaUrl == null
                    ? null
                    : () => _openGalleryViewer(
                          galleryEntries,
                          initialIndex: index,
                        ),
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  width: 116,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isPrimary
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context)
                                          .colorScheme
                                          .outlineVariant,
                                  width: isPrimary ? 2 : 1,
                                ),
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerLowest,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: normalizedMediaUrl == null
                                  ? Center(
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: Colors.grey[600],
                                      ),
                                    )
                                  : CachedNetworkImage(
                                      imageUrl: normalizedMediaUrl,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      // M2: тайл галереи карточки — 116dp.
                                      memCacheWidth:
                                          decodeCacheWidth(context, 116),
                                      errorWidget: (context, url, error) =>
                                          Center(
                                        child: Icon(
                                          Icons.broken_image_outlined,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ),
                            ),
                            Positioned(
                              left: 8,
                              top: 8,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.58),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    isPrimary ? 'Основное' : 'Фото',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (canManageGallery)
                              Positioned(
                                right: 4,
                                top: 4,
                                child: PopupMenuButton<_RelativeGalleryAction>(
                                  tooltip: 'Действия с фото',
                                  onSelected: (action) {
                                    switch (action) {
                                      case _RelativeGalleryAction.makePrimary:
                                        _setPrimaryGalleryMedia(media);
                                        break;
                                      case _RelativeGalleryAction.delete:
                                        _deleteGalleryMedia(media);
                                        break;
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    if (!isPrimary)
                                      const PopupMenuItem<
                                          _RelativeGalleryAction>(
                                        value:
                                            _RelativeGalleryAction.makePrimary,
                                        child: Text('Сделать основным'),
                                      ),
                                    const PopupMenuItem<_RelativeGalleryAction>(
                                      value: _RelativeGalleryAction.delete,
                                      child: Text('Удалить фото'),
                                    ),
                                  ],
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.55),
                                      shape: BoxShape.circle,
                                    ),
                                    padding: const EdgeInsets.all(6),
                                    child: const Icon(
                                      Icons.more_vert,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isPrimary ? 'Используется в дереве' : 'Дополнительное',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey[800],
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
    ]);
  }

  Widget _buildHistorySection() {
    final latestRecord =
        _historyRecords.isNotEmpty ? _historyRecords.first : null;
    final summaryLabel = _historyRecords.isEmpty
        ? 'Журнал пока пуст'
        : _historyRecords.length == 1
            ? '1 запись'
            : '${_historyRecords.length} записей';

    return _buildInfoSection('История изменений', [
      if (_isLoadingHistory)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator()),
        )
      else
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      latestRecord == null
                          ? Icons.history_outlined
                          : _historyIcon(latestRecord),
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          latestRecord == null
                              ? 'Журнал ещё пуст.'
                              : _historyTitle(latestRecord),
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          latestRecord == null
                              ? 'Как только семья добавит правку, фото или новую связь, здесь появится история изменений.'
                              : _historySubtitle(latestRecord),
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.summarize_outlined, size: 16),
                    label: Text(summaryLabel),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _openHistorySheet,
                    icon: const Icon(Icons.history_outlined, size: 18),
                    label: const Text('Открыть историю'),
                  ),
                ],
              ),
            ],
          ),
        ),
    ]);
  }
}
