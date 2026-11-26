part of '../create_post_screen.dart';

extension _CreatePostSubmit on _CreatePostScreenState {
  /// Подпись рядом со спиннером публикации: «Загружено 18 из 30».
  /// Для одного файла счётчик не нужен — он не несёт информации.
  String? get _uploadProgressLabel {
    final progress = _uploadProgress;
    if (progress == null || progress.total <= 1) {
      return null;
    }
    switch (progress.stage) {
      case MediaUploadStage.preparing:
        return 'Готовим ${progress.total} фото';
      case MediaUploadStage.uploading:
        return 'Загружено ${progress.completed} из ${progress.total}';
      case MediaUploadStage.publishing:
        return 'Публикуем…';
    }
  }

  /// Rebuilds the composer when the text content changes so the publish
  /// button's enabled state (Q1) tracks the field live.
  void _handleComposerChanged() {
    if (mounted) _updateCreatePostState(() {});
  }

  Future<void> _createPost() async {
    final content = _contentController.text.trim();
    if (content.isEmpty && _selectedMedia.isEmpty) {
      _showMessage('Добавьте текст или хотя бы один файл.');
      return;
    }
    if (_scopeType == TreeContentScopeType.branches &&
        _selectedBranchPersonIds.isEmpty) {
      _showMessage(
        _isFriendsTree
            ? 'Выберите хотя бы один круг для публикации.'
            : 'Выберите хотя бы одну ветку для публикации.',
      );
      return;
    }

    if (_currentTreeId == null) return;

    // Phase 3.4: when the user picked one or more "Опубликовать
    // также в" chips, the post fans out to the primary tree
    // PLUS those branches. When nothing's picked, send `null`
    // so the backend keeps the legacy single-branch default.
    final List<String>? branchIdsForRequest = _additionalBranchIds.isEmpty
        ? null
        : <String>{_currentTreeId!, ..._additionalBranchIds}.toList();

    // Шаг 5 bulk-upload: очередь публикации есть → «Опубликовать» отпускает
    // человека сразу. Пачка грузится в фоне (чип в shell показывает ход),
    // упавшая публикация переживает офлайн и kill приложения и уходит сама.
    // Рефреш ленты придёт через PostsRefreshCoordinator после ACK сервера,
    // поэтому pop без сигнала «обнови сейчас».
    if (GetIt.I.isRegistered<PostPublishQueue>()) {
      // Двойной тап по «Опубликовать» без этого гварда создавал ДВА поста:
      // enqueue асинхронный (Hive-restore внутри), и второй тап успевал
      // пройти валидацию до pop. _isLoading гасит кнопку синхронно.
      _updateCreatePostState(() {
        _isLoading = true;
        _uploadProgress = null;
      });
      try {
        await GetIt.I<PostPublishQueue>().enqueue(
          treeId: _currentTreeId!,
          content: content,
          files: _selectedMedia.map((m) => m.file).toList(),
          isPublic: _isPublic,
          scopeType: _scopeType,
          anchorPersonIds: _selectedBranchPersonIds.toList(),
          circleId: _selectedCircleId,
          branchIds: branchIdsForRequest,
        );
      } catch (error) {
        _appStatusService.reportError(
          error,
          fallbackMessage: 'Не удалось опубликовать запись.',
        );
        if (mounted) {
          _updateCreatePostState(() => _isLoading = false);
        }
        _showMessage('Не удалось опубликовать запись. Попробуйте ещё раз.');
        return;
      }
      if (mounted) {
        context.pop();
      }
      return;
    }

    // Очереди нет (тестовый или деградированный контекст) — публикуем на
    // месте, как раньше: блокирующий прогресс на кнопке.
    _updateCreatePostState(() {
      _isLoading = true;
      _uploadProgress = null;
    });

    try {
      await _postService.createPost(
        treeId: _currentTreeId!,
        content: content,
        // The Post model still surfaces everything as imageUrls — the
        // video items go through the same upload pipe (storage service
        // already handles video MIME) and post_card.dart sniffs the
        // URL extension at render time to pick the right tile.
        images: _selectedMedia.map((m) => m.file).toList(),
        isPublic: _isPublic,
        scopeType: _scopeType,
        anchorPersonIds: _selectedBranchPersonIds.toList(),
        circleId: _selectedCircleId,
        branchIds: branchIdsForRequest,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          _updateCreatePostState(() => _uploadProgress = progress);
        },
      );

      if (mounted) {
        _showMessage('Запись опубликована.');
        context.pop(true); // Return true to signal refresh
      }
    } catch (error) {
      _appStatusService.reportError(
        error,
        fallbackMessage: 'Не удалось опубликовать запись.',
      );
      if (mounted) {
        _updateCreatePostState(() {
          _isLoading = false;
          _uploadProgress = null;
        });
        _showMessage(
          describeUserFacingError(
            authService: _authService,
            error: error,
            fallbackMessage: _appStatusService.isOffline
                ? 'Нет соединения. Проверьте интернет и отправьте запись ещё раз.'
                : 'Не удалось опубликовать запись. Попробуйте ещё раз.',
          ),
        );
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
