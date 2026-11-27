// «Спросить историю» MVP-1 (STORY-REQUEST-MVP1-BRIEF.md §3.4, voice-first
// per PHASE-D-MEMORY-HISTORY-PROPOSAL.md §3.3.4): the addressee's answer
// screen — opened from the `story_request_received` notification or from
// «Мне задали вопрос». One screen, three ways to answer (audio — MVP-1
// has no video, §0.4), plus skip / decline.
//
// Voice-first: recording starts the moment the 72dp mic is tapped, via
// the SAME reused audio_record_sheet.dart the article editor uses (it
// already does listen/re-record/accept internally) — no separate
// «press to talk» step here, matching Phase D's «no press-to-talk, too
// fiddly for elders» note.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/storage_service_interface.dart';
import '../backend/interfaces/story_request_capable_family_tree_service.dart';
import '../models/story_request.dart';
import '../theme/app_theme.dart';
import '../utils/relative_details_route.dart';
import '../utils/user_facing_error.dart';
import '../widgets/audio_record_sheet.dart';

enum _ScreenState { loading, error, terminal, main, thankYou }

class StoryRequestAnswerScreen extends StatefulWidget {
  const StoryRequestAnswerScreen({
    super.key,
    required this.requestId,
    this.serviceOverride,
    this.storageOverride,
    this.audioRecordOverride,
    this.pickImageOverride,
  });

  final String requestId;

  /// Test seam — production resolves via GetIt (casts the registered
  /// FamilyTreeServiceInterface, see discover_relatives_screen.dart for
  /// the same pattern).
  final StoryRequestCapableFamilyTreeService? serviceOverride;

  /// Test seam — photo/audio upload. Production resolves via GetIt.
  final StorageServiceInterface? storageOverride;

  /// Test seam — voice recording. Production opens showAudioRecordSheet,
  /// exactly like profile_article_editor_screen.dart's audioRecordOverride.
  final Future<AudioRecordResult?> Function(BuildContext context)?
      audioRecordOverride;

  /// Test seam — image picking. Production uses ImagePicker.
  final Future<XFile?> Function(ImageSource source)? pickImageOverride;

  @override
  State<StoryRequestAnswerScreen> createState() =>
      _StoryRequestAnswerScreenState();
}

class _StoryRequestAnswerScreenState extends State<StoryRequestAnswerScreen> {
  _ScreenState _state = _ScreenState.loading;
  StoryRequest? _request;
  String? _loadError;
  bool _textMode = false;
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _transcriptController = TextEditingController();
  final TextEditingController _photoCaptionController = TextEditingController();
  bool _submitting = false;
  bool _uploadingAudio = false;
  String? _submitError;
  bool _notAddressee = false;
  String? _audioMediaUrl;
  int? _audioDurationSec;
  XFile? _pickedPhotoFile;
  Uint8List? _pickedPhotoBytes;
  String? _uploadedPhotoUrl;
  StoryRequestAnswerInput? _pendingRetryInput;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _transcriptController.dispose();
    _photoCaptionController.dispose();
    super.dispose();
  }

  bool get _hasAnyDraft =>
      _audioMediaUrl != null ||
      _textController.text.trim().isNotEmpty ||
      _pickedPhotoBytes != null;

  bool get _hasSubmittableDraft =>
      _audioMediaUrl != null ||
      _textController.text.trim().isNotEmpty ||
      _pickedPhotoBytes != null ||
      _uploadedPhotoUrl != null;

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  StoryRequestCapableFamilyTreeService? _service() {
    if (widget.serviceOverride != null) return widget.serviceOverride;
    if (!GetIt.I.isRegistered<FamilyTreeServiceInterface>()) return null;
    final service = GetIt.I<FamilyTreeServiceInterface>();
    return service is StoryRequestCapableFamilyTreeService
        ? service as StoryRequestCapableFamilyTreeService
        : null;
  }

  StorageServiceInterface? _storage() {
    if (widget.storageOverride != null) return widget.storageOverride;
    if (GetIt.I.isRegistered<StorageServiceInterface>()) {
      return GetIt.I<StorageServiceInterface>();
    }
    return null;
  }

  // Вложения person/requester приходят только с GET; ответ на answer/
  // decline — голый запрос. Имена кэшируем при загрузке, иначе экран
  // «Спасибо» после ответа терял имя инициатора.
  String? _cachedRequesterName;
  String? _cachedPersonName;

  String get _requesterName {
    final name =
        (_request?.requester?.displayName ?? _cachedRequesterName)?.trim();
    return (name != null && name.isNotEmpty) ? name : 'Родной человек';
  }

  String get _personName {
    final name = (_request?.person?.displayName ?? _cachedPersonName)?.trim();
    return (name != null && name.isNotEmpty) ? name : 'этого человека';
  }

  Future<void> _load() async {
    final service = _service();
    if (service == null) {
      setState(() {
        _state = _ScreenState.error;
        _loadError = 'Сервис недоступен.';
      });
      return;
    }
    try {
      final request = await service.getStoryRequest(
        requestId: widget.requestId,
      );
      if (!mounted) return;
      if (request == null) {
        setState(() {
          _state = _ScreenState.error;
          _loadError = 'Вопрос не найден — возможно, его уже удалили.';
        });
        return;
      }
      final currentUserId = GetIt.I.isRegistered<AuthServiceInterface>()
          ? GetIt.I<AuthServiceInterface>().currentUserId
          : null;
      final isNotTarget =
          currentUserId != null && request.targetUserId != currentUserId;
      setState(() {
        _request = request;
        _cachedRequesterName =
            request.requester?.displayName ?? _cachedRequesterName;
        _cachedPersonName = request.person?.displayName ?? _cachedPersonName;
        _notAddressee = isNotTarget;
        _state = (!isNotTarget && request.isPending)
            ? _ScreenState.main
            : _ScreenState.terminal;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _ScreenState.error;
        _loadError = humanizeError(e, fallback: 'Не удалось загрузить вопрос.');
      });
    }
  }

  void _closeScreen() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      GoRouter.of(context).go('/');
    }
  }

  Future<void> _submitAnswer(StoryRequestAnswerInput input) async {
    final service = _service();
    if (service == null) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final updated = await service.answerStoryRequest(
        requestId: widget.requestId,
        answer: input,
      );
      if (!mounted) return;
      if (updated == null) {
        setState(() {
          _submitting = false;
          _submitError = 'Не удалось отправить ответ. Попробуйте ещё раз.';
        });
        return;
      }
      setState(() {
        _request = updated;
        _submitting = false;
        _pendingRetryInput = null;
        _audioMediaUrl = null;
        _audioDurationSec = null;
        _uploadedPhotoUrl = null;
        _pickedPhotoFile = null;
        _pickedPhotoBytes = null;
        _state = _ScreenState.thankYou;
      });
    } on StoryRequestError catch (e) {
      if (!mounted) return;
      if (e.statusCode == 409 || e.code == 'NOT_PENDING') {
        setState(() {
          _submitting = false;
          _pendingRetryInput = null;
          _audioMediaUrl = null;
          _audioDurationSec = null;
          _uploadedPhotoUrl = null;
          _pickedPhotoFile = null;
          _pickedPhotoBytes = null;
          _state = _ScreenState.terminal;
        });
        return;
      }
      setState(() {
        _submitting = false;
        _pendingRetryInput = input;
        _submitError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _pendingRetryInput = input;
        _submitError = 'Не удалось отправить ответ. Попробуйте ещё раз.';
      });
    }
  }

  Future<void> _retryPendingUploadSubmit() async {
    final retryInput = _pendingRetryInput;
    if (retryInput == null) return;
    await _submitAnswer(retryInput);
  }

  Future<void> _recordAudio() async {
    final record = widget.audioRecordOverride ??
        (BuildContext ctx) => showAudioRecordSheet(
              ctx,
              confirmLabel: 'Сохранить',
              autoStart: true,
            );
    final result = await record(context);
    if (result == null || !mounted) return;
    final service = _service();
    final storage = _storage();
    if (service == null && storage == null) {
      _snack('Загрузка записи недоступна');
      return;
    }
    setState(() {
      _uploadingAudio = true;
      _submitError = null;
    });
    String? url;
    String? transcript;
    try {
      final bytes = await result.file.readAsBytes();
      if (service != null) {
        final uploaded = await service.uploadStoryRequestMedia(
          requestId: widget.requestId,
          kind: 'audio',
          bytes: bytes,
          contentType: result.mimeType,
        );
        if (uploaded != null) {
          url = uploaded.url;
          transcript = uploaded.transcript;
        }
      }
      if ((url == null || url.isEmpty) && storage != null) {
        final ts = DateTime.now().millisecondsSinceEpoch;
        url = await storage.uploadBytes(
          bucket: 'story-request-audio',
          path: '${widget.requestId}/${ts}_${result.file.name}',
          fileBytes: bytes,
          fileOptions: FileOptions(contentType: result.mimeType),
        );
      }
    } catch (_) {
      url = null;
    }
    if (!mounted) return;
    if (url == null || url.isEmpty) {
      setState(() {
        _uploadingAudio = false;
        _submitError = 'Не удалось сохранить запись. Попробуйте ещё раз.';
      });
      return;
    }
    setState(() {
      _uploadingAudio = false;
      _audioMediaUrl = url;
      _audioDurationSec = result.durationSec;
      if (transcript != null && transcript.isNotEmpty) {
        _transcriptController.text = transcript;
      }
    });
  }

  Future<XFile?> _pickImage(ImageSource source) {
    if (widget.pickImageOverride != null) {
      return widget.pickImageOverride!(source);
    }
    return ImagePicker().pickImage(
      source: source,
      maxWidth: 2048,
      imageQuality: 85,
    );
  }

  Future<ImageSource?> _choosePhotoSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('story-answer-photo-camera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Снять на камеру'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              key: const Key('story-answer-photo-gallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Выбрать из галереи'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addPhoto() async {
    final source = await _choosePhotoSource();
    if (source == null || !mounted) return;
    XFile? file;
    Uint8List? bytes;
    try {
      file = await _pickImage(source);
      if (file != null) {
        bytes = await file.readAsBytes();
      }
    } catch (_) {
      _snack('Не удалось открыть фото');
      return;
    }
    if (file == null || bytes == null || !mounted) return;
    setState(() {
      _submitError = null;
      _pickedPhotoFile = file;
      _pickedPhotoBytes = bytes;
      _uploadedPhotoUrl = null;
    });
  }

  Future<void> _submitCombinedAnswer() async {
    if (!_hasSubmittableDraft || _submitting || _uploadingAudio) return;
    final service = _service();
    final storage = _storage();

    String? photoUrl = _uploadedPhotoUrl;
    if (photoUrl == null && _pickedPhotoFile != null) {
      if (service == null && storage == null) {
        _snack('Загрузка фото недоступна');
        return;
      }
      setState(() {
        _submitting = true;
        _submitError = null;
      });
      try {
        if (service != null && _pickedPhotoBytes != null) {
          final mime = _pickedPhotoFile!.mimeType?.trim();
          final uploaded = await service.uploadStoryRequestMedia(
            requestId: widget.requestId,
            kind: 'photo',
            bytes: _pickedPhotoBytes!,
            contentType: mime != null && mime.isNotEmpty ? mime : 'image/jpeg',
          );
          photoUrl = uploaded?.url;
        }
        if ((photoUrl == null || photoUrl.isEmpty) && storage != null) {
          photoUrl = await storage.uploadImage(
            _pickedPhotoFile!,
            'story-request-photos',
          );
        }
      } catch (_) {
        photoUrl = null;
      }
      if (!mounted) return;
      if (photoUrl == null || photoUrl.isEmpty) {
        setState(() {
          _submitting = false;
          _submitError = 'Не удалось загрузить фото. Попробуйте ещё раз.';
        });
        return;
      }
      _uploadedPhotoUrl = photoUrl;
    }

    final cleanText = _textController.text.trim();
    final cleanCaption = _photoCaptionController.text.trim();
    final cleanTranscript = _transcriptController.text.trim();
    final hasAudio = _audioMediaUrl != null;
    final hasText = cleanText.isNotEmpty;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    final partCount =
        (hasAudio ? 1 : 0) + (hasText ? 1 : 0) + (hasPhoto ? 1 : 0);
    if (partCount == 0) return;

    late final StoryRequestAnswerInput input;
    if (partCount >= 2) {
      input = StoryRequestAnswerInput.combined(
        audio: hasAudio
            ? StoryAudioPart(
                mediaUrl: _audioMediaUrl!,
                durationSec: _audioDurationSec,
                transcript: cleanTranscript.isEmpty ? null : cleanTranscript,
              )
            : null,
        text: hasText ? cleanText : null,
        photo: hasPhoto
            ? StoryPhotoPart(
                mediaUrl: photoUrl,
                caption: cleanCaption.isEmpty ? null : cleanCaption,
              )
            : null,
      );
    } else if (hasAudio) {
      input = StoryRequestAnswerInput.audio(
        mediaUrl: _audioMediaUrl!,
        durationSec: _audioDurationSec ?? 1,
        transcript: cleanTranscript.isEmpty ? null : cleanTranscript,
      );
    } else if (hasText) {
      input = StoryRequestAnswerInput.text(cleanText);
    } else {
      input = StoryRequestAnswerInput.photo(
        mediaUrl: photoUrl!,
        caption: cleanCaption.isEmpty ? null : cleanCaption,
      );
    }
    await _submitAnswer(input);
  }

  Future<void> _confirmDecline() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Не хотите отвечать?'),
        content: Text(
          '$_requesterName не увидит причину — просто узнает, что вопрос закрыт.',
        ),
        actions: [
          TextButton(
            key: const Key('story-answer-decline-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            key: const Key('story-answer-decline-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Не отвечать'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final service = _service();
    if (service == null) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final updated = await service.declineStoryRequest(
        requestId: widget.requestId,
      );
      if (!mounted) return;
      if (updated == null) {
        setState(() {
          _submitting = false;
          _submitError = 'Не получилось отклонить вопрос. Попробуйте ещё раз.';
        });
        return;
      }
      setState(() {
        _submitting = false;
        _request = updated;
        _state = _ScreenState.terminal;
      });
    } on StoryRequestError catch (e) {
      if (!mounted) return;
      if (e.statusCode == 409 || e.code == 'NOT_PENDING') {
        setState(() {
          _submitting = false;
          _state = _ScreenState.terminal;
        });
        return;
      }
      setState(() {
        _submitting = false;
        _submitError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = 'Не получилось отклонить вопрос. Попробуйте ещё раз.';
      });
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _ScreenState.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case _ScreenState.error:
        return _buildError(context);
      case _ScreenState.terminal:
        return _buildTerminal(context);
      case _ScreenState.thankYou:
        return _buildThankYou(context);
      case _ScreenState.main:
        return _buildMain(context);
    }
  }

  Widget _buildError(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 44,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  _loadError ?? 'Не удалось загрузить вопрос.',
                  key: const Key('story-answer-error-message'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('story-answer-error-close'),
                  onPressed: _closeScreen,
                  child: const Text('Закрыть'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTerminal(BuildContext context) {
    final theme = Theme.of(context);
    String message;
    if (_notAddressee) {
      message = 'Ответить на этот вопрос может только адресат.';
    } else {
      switch (_request?.status) {
        case StoryRequestStatus.declined:
          message = 'Хорошо — вопрос закрыт, отвечать не нужно.';
          break;
        case StoryRequestStatus.answered:
          message = 'Вы уже ответили на этот вопрос — спасибо!';
          break;
        case StoryRequestStatus.expired:
          message = 'Срок ответа на этот вопрос истёк.';
          break;
        case StoryRequestStatus.revoked:
          message =
              '$_requesterName отозвал(а) этот вопрос — отвечать не нужно.';
          break;
        default:
          message = 'Этот вопрос уже закрыт.';
      }
    }
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 44,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  key: const Key('story-answer-terminal-message'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('story-answer-terminal-close'),
                  onPressed: _closeScreen,
                  child: const Text('Готово'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThankYou(BuildContext context) {
    final personId = _request?.personId;
    final treeId = _request?.treeId;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.favorite_rounded,
                    size: 44, color: Colors.pink),
                const SizedBox(height: 16),
                Text(
                  'Спасибо! $_requesterName получит вашу историю',
                  key: const Key('story-answer-thankyou-message'),
                  textAlign: TextAlign.center,
                  style:
                      AppTheme.serif(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 24),
                if (personId != null && personId.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('story-answer-thankyou-person'),
                      onPressed: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                        GoRouter.of(context).push(
                          relativeDetailsRoute(personId, treeId: treeId),
                        );
                      },
                      child: Text('К странице $_personName'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMain(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppTheme.tokensOf(context);
    final request = _request!;
    return Scaffold(
      appBar: AppBar(title: const Text('Вопрос от родного')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            children: [
              Text(
                'Спрашивает: $_requesterName\nО ком: $_personName',
                key: const Key('story-answer-context'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '«${request.question.text}»',
                key: const Key('story-answer-question'),
                textAlign: TextAlign.center,
                style: AppTheme.serif(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: tokens.ink,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 26),
              if (!_hasAnyDraft && !_textMode) ...[
                Material(
                  color: tokens.accent,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: InkWell(
                    key: const Key('story-answer-mic'),
                    onTap:
                        (_submitting || _uploadingAudio) ? null : _recordAudio,
                    customBorder: const CircleBorder(),
                    child: const SizedBox(
                      width: 72,
                      height: 72,
                      child: Icon(
                        Icons.mic_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Нажмите и расскажите',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                TextButton.icon(
                  key: const Key('story-answer-text-mode'),
                  onPressed: _submitting
                      ? null
                      : () => setState(() => _textMode = true),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text(
                    'Написать текстом',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
                TextButton.icon(
                  key: const Key('story-answer-photo'),
                  onPressed: _submitting ? null : _addPhoto,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text(
                    'Прислать фото',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ] else
                _buildCombinedComposer(theme),
              const SizedBox(height: 12),
              if (_submitting || _uploadingAudio) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(
                  _uploadingAudio ? 'Загружаем запись…' : 'Сохраняем ответ…',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (_submitError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    children: [
                      Text(
                        _submitError!,
                        key: const Key('story-answer-submit-error'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      if (_pendingRetryInput != null && !_submitting) ...[
                        const SizedBox(height: 8),
                        FilledButton.tonal(
                          key: const Key('story-answer-retry-submit'),
                          onPressed: _retryPendingUploadSubmit,
                          child: const Text('Повторить отправку'),
                        ),
                      ],
                    ],
                  ),
                ),
              TextButton(
                key: const Key('story-answer-skip'),
                onPressed: _submitting ? null : _closeScreen,
                child: const Text(
                  'Пропустить пока',
                  style: TextStyle(fontSize: 16),
                ),
              ),
              TextButton(
                key: const Key('story-answer-decline'),
                onPressed: _submitting ? null : _confirmDecline,
                child: Text(
                  'Не хочу отвечать',
                  style:
                      TextStyle(fontSize: 16, color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCombinedComposer(ThemeData theme) {
    final busy = _submitting || _uploadingAudio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_audioMediaUrl != null) ...[
          Card(
            key: const Key('story-answer-audio-card'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.graphic_eq_rounded),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Голосовой ответ · ${_audioDurationSec ?? 0} сек',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        key: const Key('story-answer-audio-remove'),
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                  _audioMediaUrl = null;
                                  _audioDurationSec = null;
                                  _transcriptController.clear();
                                }),
                        child: const Text('Удалить'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('story-answer-transcript-field'),
                    controller: _transcriptController,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Расшифровка (можно поправить)',
                      hintText: 'Добавьте или уточните текст записи…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_textMode || _textController.text.isNotEmpty) ...[
          TextField(
            key: const Key('story-answer-text-field'),
            controller: _textController,
            autofocus: _audioMediaUrl == null && _pickedPhotoBytes == null,
            minLines: 3,
            maxLines: 8,
            style: const TextStyle(fontSize: 16, height: 1.4),
            decoration: const InputDecoration(
              labelText: 'Текст истории',
              hintText: 'Напишите здесь свою историю…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_pickedPhotoBytes != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(
              _pickedPhotoBytes!,
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('story-answer-photo-caption'),
            controller: _photoCaptionController,
            maxLength: 300,
            decoration: const InputDecoration(
              hintText: 'Подпись к фото (необязательно)…',
              border: OutlineInputBorder(),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('story-answer-photo-cancel'),
              onPressed: busy
                  ? null
                  : () => setState(() {
                        _pickedPhotoFile = null;
                        _pickedPhotoBytes = null;
                        _uploadedPhotoUrl = null;
                        _photoCaptionController.clear();
                      }),
              child: const Text('Убрать фото'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_audioMediaUrl == null)
              OutlinedButton.icon(
                key: const Key('story-answer-mic'),
                onPressed: busy ? null : _recordAudio,
                icon: const Icon(Icons.mic_rounded, size: 18),
                label: const Text('Добавить голос'),
              ),
            if (!_textMode && _textController.text.isEmpty)
              OutlinedButton.icon(
                key: const Key('story-answer-text-mode'),
                onPressed: busy ? null : () => setState(() => _textMode = true),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Добавить текст'),
              ),
            if (_pickedPhotoBytes == null)
              OutlinedButton.icon(
                key: const Key('story-answer-photo'),
                onPressed: busy ? null : _addPhoto,
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Добавить фото'),
              ),
          ],
        ),
        const SizedBox(height: 14),
        FilledButton(
          key: const Key('story-answer-submit'),
          onPressed:
              (!busy && _hasSubmittableDraft) ? _submitCombinedAnswer : null,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Отправить ответ'),
        ),
      ],
    );
  }
}
