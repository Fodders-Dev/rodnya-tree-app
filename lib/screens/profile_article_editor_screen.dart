// Profile Phase 2a (2026-05-29): Telegraph-style article editor.
//
// Minimal, warm, serif (Lora). Block-based native editing — each
// paragraph / header is its own TextField. Debounced per-block auto-save
// against the Phase 1 backend (PATCH per dirty block + baseUpdatedAt for
// the multi-author last-write-wins conflict). «+» inserts at position;
// «💡 Идеи» opens the темы-промпт sheet. Media blocks (photo / audio /
// mention) land in Phase 2b — their toolbar buttons show «Скоро».
//
// Permission: writes hit requireGraphPersonEdit server-side; this screen
// is opened only from edit-capable entry points.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:image_picker/image_picker.dart';

import '../backend/interfaces/profile_article_service_interface.dart';
import '../backend/interfaces/storage_service_interface.dart';
import '../backend/models/profile_article.dart';
import '../widgets/article_idea_prompts_sheet.dart';
import '../widgets/article_photo_block.dart';
import '../widgets/photo_date_picker_sheet.dart';
import '../widgets/article_audio_block.dart';
import '../widgets/audio_record_sheet.dart';
import '../widgets/voice_input_sheet.dart';

class ProfileArticleEditorScreen extends StatefulWidget {
  const ProfileArticleEditorScreen({
    super.key,
    required this.personId,
    this.personName,
    this.personRelation,
    this.personGender,
    this.serviceOverride,
    this.storageOverride,
    this.pickImageOverride,
    this.voiceInputOverride,
    this.audioRecordOverride,
    this.saveDebounce = const Duration(seconds: 5),
  });

  final String personId;
  final String? personName;
  final String? personRelation;

  /// Raw person gender ('male' / 'female' / 'other' / 'unknown' / null)
  /// — tunes идея-prompt wording so verbs agree with the card.
  final String? personGender;

  /// Test seam — production resolves via GetIt.
  final ProfileArticleServiceInterface? serviceOverride;

  /// Test seam — photo upload. Production resolves StorageServiceInterface
  /// via GetIt.
  final StorageServiceInterface? storageOverride;

  /// Test seam — image picking. Production uses ImagePicker.
  final Future<XFile?> Function(ImageSource source)? pickImageOverride;

  /// Test seam — voice input. Production opens showVoiceInputSheet
  /// (speech_to_text, ru_RU). Returns the transcript or null.
  final Future<String?> Function(BuildContext context)? voiceInputOverride;

  /// Test seam — voice recording. Production opens showAudioRecordSheet
  /// (record pkg). Returns the recorded artifact or null.
  final Future<AudioRecordResult?> Function(BuildContext context)?
      audioRecordOverride;

  /// Debounce before a dirty block auto-saves (overridable for tests).
  final Duration saveDebounce;

  @override
  State<ProfileArticleEditorScreen> createState() =>
      _ProfileArticleEditorScreenState();
}

class _ProfileArticleEditorScreenState
    extends State<ProfileArticleEditorScreen> {
  final List<ArticleBlock> _blocks = [];
  final Map<String, TextEditingController> _controllers = {};
  // Quote blocks have a second editable field («— кто сказал»); its
  // controller lives here, keyed by block id, alongside the main one.
  final Map<String, TextEditingController> _attributionControllers = {};
  final Map<String, FocusNode> _focus = {};
  final Map<String, String> _hints = {}; // blockId → placeholder prompt
  final Set<String> _dirty = {};

  Timer? _debounce;
  bool _loading = false;
  bool _hasLoaded = false;
  bool _saving = false;
  bool _conflictNoticed = false;
  bool _photoUploading = false;
  String? _busyBlockId; // photo block with an in-flight replace/date patch
  String? _error;
  DateTime? _lastSavedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final c in _attributionControllers.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  ProfileArticleServiceInterface? _service() {
    if (widget.serviceOverride != null) return widget.serviceOverride;
    if (GetIt.I.isRegistered<ProfileArticleServiceInterface>()) {
      return GetIt.I<ProfileArticleServiceInterface>();
    }
    return null;
  }

  StorageServiceInterface? _storage() {
    if (widget.storageOverride != null) return widget.storageOverride;
    if (GetIt.I.isRegistered<StorageServiceInterface>()) {
      return GetIt.I<StorageServiceInterface>();
    }
    return null;
  }

  Future<void> _load() async {
    final svc = _service();
    if (svc == null) {
      setState(() {
        _hasLoaded = true;
        _error = 'Сервис недоступен';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final article = await svc.getArticle(widget.personId);
      if (!mounted) return;
      setState(() {
        _blocks
          ..clear()
          ..addAll(article.blocks);
        for (final b in _blocks) {
          _bind(b);
        }
        _loading = false;
        _hasLoaded = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasLoaded = true;
        _error = _describe(error);
      });
    }
  }

  String _initialTextFor(ArticleBlock b) {
    if (b.type == 'photo') return b.content['caption']?.toString() ?? '';
    if (b.isHeader) return b.headerText;
    if (b.isQuote) return b.quoteText;
    return b.plainText;
  }

  void _bind(ArticleBlock b) {
    _controllers.putIfAbsent(
      b.id,
      () => TextEditingController(text: _initialTextFor(b)),
    );
    if (b.isQuote) {
      _attributionControllers.putIfAbsent(
        b.id,
        () => TextEditingController(text: b.quoteAttribution ?? ''),
      );
    }
    _focus.putIfAbsent(b.id, () {
      final node = FocusNode();
      node.addListener(() {
        if (!node.hasFocus && _dirty.contains(b.id)) {
          _flush();
        }
      });
      return node;
    });
  }

  void _onChanged(String blockId) {
    _dirty.add(blockId);
    _debounce?.cancel();
    _debounce = Timer(widget.saveDebounce, _flush);
    // Clear the prompt hint once the user starts typing.
    if (_hints.containsKey(blockId)) {
      setState(() => _hints.remove(blockId));
    }
  }

  Future<void> _flush() async {
    _debounce?.cancel();
    final svc = _service();
    if (svc == null || _dirty.isEmpty) return;
    final ids = _dirty.toList(growable: false);
    _dirty.clear();
    if (mounted) setState(() => _saving = true);
    var sawConflict = false;
    for (final id in ids) {
      final idx = _blocks.indexWhere((b) => b.id == id);
      if (idx < 0) continue;
      final block = _blocks[idx];
      final text = _controllers[id]?.text ?? '';
      final Map<String, dynamic> content;
      if (block.type == 'photo') {
        // Only the caption is editable inline; keep url + date metadata.
        content = {
          ...block.content,
          'caption': text.trim().isEmpty ? null : text.trim(),
        };
      } else if (block.isHeader) {
        content = ArticleBlock.headerContent(text, level: block.headerLevel);
      } else if (block.isQuote) {
        content = ArticleBlock.quoteContent(
          text: text,
          attribution: _attributionControllers[id]?.text,
        );
      } else {
        content = ArticleBlock.paragraphContent(text);
      }
      try {
        final result = await svc.updateBlock(
          widget.personId,
          id,
          content: content,
          baseUpdatedAt: block.updatedAt,
        );
        if (!mounted) return;
        _blocks[idx] = result.block;
        if (result.conflict) sawConflict = true;
      } catch (_) {
        _dirty.add(id); // keep for retry
      }
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _lastSavedAt = DateTime.now();
    });
    if (sawConflict && !_conflictNoticed) {
      _conflictNoticed = true;
      _snack(
        'Этот раздел редактировал кто-то ещё — мы сохранили вашу версию, '
        'прежняя осталась в истории.',
      );
    }
  }

  Future<void> _addBlock(
    String type, {
    int? afterIndex,
    String? initialText,
    String? hint,
  }) async {
    final svc = _service();
    if (svc == null) return;
    final text = initialText ?? '';
    final Map<String, dynamic> content;
    switch (type) {
      case 'header':
        content = ArticleBlock.headerContent(text);
        break;
      case 'quote':
        content = ArticleBlock.quoteContent(text: text);
        break;
      case 'divider':
        content = ArticleBlock.dividerContent();
        break;
      default:
        content = ArticleBlock.paragraphContent(text);
    }
    try {
      final block =
          await svc.appendBlock(widget.personId, type: type, content: content);
      if (!mounted) return;
      _bind(block);
      _controllers[block.id]?.text = text;
      setState(() {
        if (afterIndex != null &&
            afterIndex >= 0 &&
            afterIndex < _blocks.length) {
          _blocks.insert(afterIndex + 1, block);
        } else {
          _blocks.add(block);
        }
        if (hint != null && hint.isNotEmpty) _hints[block.id] = hint;
      });
      // Backend appended at end; if we placed it mid-list, persist order.
      if (afterIndex != null && afterIndex < _blocks.length - 2) {
        await svc.reorderBlocks(
          widget.personId,
          _blocks.map((b) => b.id).toList(growable: false),
        );
      }
      // Divider has no editable field — nothing to focus.
      if (type != 'divider') _focus[block.id]?.requestFocus();
    } catch (_) {
      _snack('Не удалось добавить блок');
    }
  }

  // ===== Phase 2b-1: photo blocks =====

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

  // Pick → upload → url. null on cancel or failure (snackbar on failure).
  Future<String?> _pickAndUpload(ImageSource source) async {
    final storage = _storage();
    if (storage == null) {
      _snack('Загрузка фото недоступна');
      return null;
    }
    XFile? file;
    try {
      file = await _pickImage(source);
    } catch (_) {
      _snack('Не удалось открыть фото');
      return null;
    }
    if (file == null) return null;
    if (mounted) setState(() => _photoUploading = true);
    String? url;
    try {
      url = await storage.uploadImage(file, 'article-photos');
    } catch (_) {
      url = null;
    }
    if (mounted) setState(() => _photoUploading = false);
    if (url == null || url.isEmpty) {
      _snack('Не удалось загрузить фото');
      return null;
    }
    return url;
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
              key: const Key('photo-source-camera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Снять на камеру'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              key: const Key('photo-source-gallery'),
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
    final url = await _pickAndUpload(source);
    if (url == null || !mounted) return;
    final svc = _service();
    if (svc == null) return;
    try {
      final block = await svc.appendBlock(
        widget.personId,
        type: 'photo',
        content: {'url': url},
      );
      if (!mounted) return;
      _bind(block);
      setState(() => _blocks.add(block));
    } catch (_) {
      _snack('Не удалось добавить фото');
    }
  }

  Future<void> _replacePhoto(ArticleBlock block) async {
    final source = await _choosePhotoSource();
    if (source == null || !mounted) return;
    final url = await _pickAndUpload(source);
    if (url == null) return;
    await _patchBlockContent(block, {...block.content, 'url': url});
  }

  Future<void> _setPhotoDate(ArticleBlock block) async {
    final result = await showPhotoDatePickerSheet(
      context,
      currentYear: DateTime.now().year,
    );
    if (result == null || !mounted) return;
    await _patchBlockContent(block, {
      ...block.content,
      'dateTaken': result.dateTaken,
      'dateTakenAccuracy': result.accuracy,
    });
  }

  // ===== Phase 2b-2 audio: voice recording (artifact) =====

  // Record → upload → returns the url + duration. null on cancel/failure.
  Future<_AudioUpload?> _recordAndUpload() async {
    final record = widget.audioRecordOverride ?? showAudioRecordSheet;
    final result = await record(context);
    if (result == null || !mounted) return null;
    final storage = _storage();
    if (storage == null) {
      _snack('Загрузка записи недоступна');
      return null;
    }
    setState(() => _photoUploading = true); // shared «загрузка…» indicator
    String? url;
    try {
      final bytes = await result.file.readAsBytes();
      url = await storage.uploadBytes(
        bucket: 'article-audio',
        path: result.file.name,
        fileBytes: bytes,
        fileOptions: FileOptions(contentType: result.mimeType),
      );
    } catch (_) {
      url = null;
    }
    if (mounted) setState(() => _photoUploading = false);
    if (url == null || url.isEmpty) {
      _snack('Не удалось загрузить запись');
      return null;
    }
    return _AudioUpload(url, result.durationSec);
  }

  Future<void> _addAudio() async {
    final res = await _recordAndUpload();
    if (res == null || !mounted) return;
    final svc = _service();
    if (svc == null) return;
    try {
      final block = await svc.appendBlock(
        widget.personId,
        type: 'audio',
        content: ArticleBlock.audioContent(
          url: res.url,
          durationSec: res.durationSec,
        ),
      );
      if (!mounted) return;
      _bind(block);
      setState(() => _blocks.add(block));
    } catch (_) {
      _snack('Не удалось добавить запись');
    }
  }

  Future<void> _replaceAudio(ArticleBlock block) async {
    final res = await _recordAndUpload();
    if (res == null) return;
    await _patchBlockContent(
      block,
      ArticleBlock.audioContent(url: res.url, durationSec: res.durationSec),
    );
  }

  Future<void> _patchBlockContent(
    ArticleBlock block,
    Map<String, dynamic> content,
  ) async {
    final svc = _service();
    if (svc == null) return;
    final idx = _blocks.indexWhere((b) => b.id == block.id);
    if (idx < 0) return;
    setState(() => _busyBlockId = block.id);
    try {
      final result = await svc.updateBlock(
        widget.personId,
        block.id,
        content: content,
        baseUpdatedAt: block.updatedAt,
      );
      if (!mounted) return;
      setState(() {
        _blocks[idx] = result.block;
        _busyBlockId = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busyBlockId = null);
      _snack('Не удалось сохранить');
    }
  }

  Future<void> _deleteBlock(ArticleBlock block) async {
    final svc = _service();
    if (svc == null) return;
    final idx = _blocks.indexWhere((b) => b.id == block.id);
    if (idx < 0) return;
    setState(() => _blocks.removeAt(idx));
    _dirty.remove(block.id);
    _controllers.remove(block.id)?.dispose();
    _attributionControllers.remove(block.id)?.dispose();
    _focus.remove(block.id)?.dispose();
    try {
      await svc.removeBlock(widget.personId, block.id);
    } catch (_) {
      _snack('Не удалось удалить');
    }
  }

  // Text-block delete via the «⋮» menu. Empty block → delete straight
  // away; non-empty → a light confirm so a paragraph isn't lost by a
  // stray tap.
  Future<void> _deleteTextBlock(ArticleBlock block) async {
    final text = _controllers[block.id]?.text.trim() ?? '';
    if (text.isNotEmpty) {
      final confirmed = await _confirmDeleteBlock(_deleteNoun(block));
      if (confirmed != true || !mounted) return;
    }
    await _deleteBlock(block);
  }

  // Accusative noun for the delete dialog / menu label.
  String _deleteNoun(ArticleBlock block) {
    if (block.isHeader) return 'раздел';
    if (block.isQuote) return 'цитату';
    return 'абзац';
  }

  Future<bool?> _confirmDeleteBlock(String noun) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить $noun?'),
        content: const Text('Текст этого блока будет удалён.'),
        actions: [
          TextButton(
            key: const Key('article-delete-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton.tonal(
            key: const Key('article-delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  // Backspace at the start of an empty block → remove it and drop the
  // caret into the previous block. Standard Telegraph/Notion behaviour.
  // Fires only for hardware/web key events (Android soft keyboards
  // don't emit it — that's what the «⋮» menu delete is for).
  KeyEventResult _handleBlockKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    if (index <= 0 || index >= _blocks.length) return KeyEventResult.ignored;
    final block = _blocks[index];
    final controller = _controllers[block.id];
    if (controller == null || controller.text.isNotEmpty) {
      return KeyEventResult.ignored;
    }
    // A quote whose text is empty but still carries an attribution is not
    // "empty" — don't delete it out from under the user.
    if (block.isQuote &&
        (_attributionControllers[block.id]?.text.trim().isNotEmpty ?? false)) {
      return KeyEventResult.ignored;
    }
    final prev = _blocks[index - 1];
    _deleteBlock(block); // local remove is synchronous; backend async
    final prevController = _controllers[prev.id];
    final prevFocus = _focus[prev.id];
    if (prevController != null && prevFocus != null) {
      prevFocus.requestFocus();
      prevController.selection = TextSelection.collapsed(
        offset: prevController.text.length,
      );
    }
    return KeyEventResult.handled;
  }

  Future<void> _openIdeas() async {
    final prompt = await showArticleIdeaPromptsSheet(
      context,
      personGender: widget.personGender,
    );
    if (prompt == null || !mounted) return;
    if (prompt.custom) {
      // Empty section the user titles themselves.
      await _addBlock('header', initialText: '', hint: prompt.prompt);
      return;
    }
    await _addBlock('header', initialText: prompt.title);
    await _addBlock(
      'paragraph',
      afterIndex: _blocks.length - 1,
      hint: prompt.prompt,
    );
  }

  // Phase 2b-2: voice → transcript accelerator. Speak → on-device STT
  // (ru_RU) → the recognized text is appended as an editable paragraph
  // (auto-saved on the same path as typed text). No audio is saved —
  // transcript-only by design. Permission-denied / cancel → no-op (the
  // user can still type).
  Future<void> _addVoiceTranscript() async {
    final transcribe = widget.voiceInputOverride ?? showVoiceInputSheet;
    final text = await transcribe(context);
    if (text == null || text.trim().isEmpty || !mounted) return;
    await _addBlock('paragraph', initialText: text.trim());
  }

  // «Голос» toolbar entry → chooser: dictate (STT → editable text) OR
  // record (save the living voice as a playable artifact).
  Future<void> _openVoiceMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('voice-menu-dictate'),
              leading: const Icon(Icons.keyboard_voice_outlined),
              title: const Text('Надиктовать текст'),
              subtitle: const Text('Речь превратится в текст — можно править'),
              onTap: () => Navigator.of(ctx).pop('dictate'),
            ),
            ListTile(
              key: const Key('voice-menu-record'),
              leading: const Icon(Icons.mic_rounded),
              title: const Text('Записать голос'),
              subtitle: const Text('Сохранить живой голос — можно послушать'),
              onTap: () => Navigator.of(ctx).pop('record'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'dictate') {
      await _addVoiceTranscript();
    } else if (choice == 'record') {
      await _addAudio();
    }
  }

  // «Блок» toolbar entry → compact picker. The bottom toolbar is already
  // at its width limit (4 buttons), so new block types live behind one
  // entry instead of adding more buttons. Раздел kept here (used to be its
  // own button); Цитата / Разделитель are new.
  Future<void> _openBlockMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('block-menu-header'),
              leading: const Icon(Icons.title_rounded),
              title: const Text('Раздел'),
              subtitle: const Text('Заголовок новой части'),
              onTap: () => Navigator.of(ctx).pop('header'),
            ),
            ListTile(
              key: const Key('block-menu-quote'),
              leading: const Icon(Icons.format_quote_rounded),
              title: const Text('Цитата'),
              subtitle: const Text('Чьи-то слова, с автором'),
              onTap: () => Navigator.of(ctx).pop('quote'),
            ),
            ListTile(
              key: const Key('block-menu-divider'),
              leading: const Icon(Icons.horizontal_rule_rounded),
              title: const Text('Разделитель'),
              subtitle: const Text('Тонкая линия между частями'),
              onTap: () => Navigator.of(ctx).pop('divider'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    await _addBlock(choice);
  }

  Future<bool> _onWillPop() async {
    await _flush();
    return true;
  }

  String _describe(Object error) {
    if (error is ProfileArticleException) return error.message;
    return 'Не удалось загрузить биографию';
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // Warm «family album» surface (PROFILE-UX-REDESIGN §8.1) — applied in
  // BOTH themes. Dark mode must NOT fall to pure black: a warm sepia
  // keeps the album feel. Localized to the article surface; does not
  // touch the app theme.
  static const Color _paperLight = Color(0xFFFAF7F2); // кремовый
  // Theme B (device-verified on S20 FE): #1C1814 read as near-black to
  // the eye. #2A211A (RGB 42,33,26) is darker-but-clearly-warm сепия.
  static const Color _paperDark = Color(0xFF2A211A); // тёплый сепия

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final bg = isLight ? _paperLight : _paperDark;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        await _onWillPop();
        if (mounted) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          elevation: 0,
          title: Text(widget.personName ?? 'Биография'),
          actions: [
            TextButton(
              key: const Key('article-done'),
              onPressed: () async {
                final navigator = Navigator.of(context);
                await _flush();
                if (mounted) navigator.pop();
              },
              child: const Text('Готово'),
            ),
          ],
        ),
        body: _buildBody(theme),
        bottomNavigationBar: _hasLoaded && _error == null
            ? _buildToolbar(theme, bg)
            : null,
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading && !_hasLoaded) {
      return const Center(
        key: Key('article-editor-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('article-editor-retry'),
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _buildHeader(theme),
        const SizedBox(height: 16),
        if (_blocks.isEmpty)
          _buildEmpty(theme)
        else
          for (var i = 0; i < _blocks.length; i++) _buildBlockRow(theme, i),
        if (_photoUploading) _buildUploadingRow(theme),
        const SizedBox(height: 8),
        if (_blocks.isNotEmpty) _buildSaveStatus(theme),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final relation = widget.personRelation?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.personName ?? 'Биография',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontFamily: 'Lora',
            fontWeight: FontWeight.w700,
          ),
        ),
        if (relation != null && relation.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            relation,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 4),
        Divider(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ],
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Биография ещё не написана.',
            style: theme.textTheme.titleMedium?.copyWith(
              fontFamily: 'Lora',
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.tonalIcon(
                key: const Key('article-empty-start'),
                onPressed: () => _addBlock('paragraph'),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Начать писать'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('article-empty-ideas'),
                onPressed: _openIdeas,
                icon: const Icon(Icons.lightbulb_outline_rounded, size: 18),
                label: const Text('Идеи'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBlockRow(ThemeData theme, int index) {
    final block = _blocks[index];

    // Phase 2b-1: photo blocks render as an image + caption, not a
    // TextField. The caption reuses the per-block controller.
    if (block.type == 'photo') {
      return ArticlePhotoBlock(
        key: Key('article-block-${block.id}'),
        block: block,
        captionController: _controllers[block.id]!,
        busy: _busyBlockId == block.id,
        onCaptionChanged: () => _onChanged(block.id),
        onSetDate: () => _setPhotoDate(block),
        onReplace: () => _replacePhoto(block),
        onDelete: () => _deleteBlock(block),
      );
    }

    // Phase 2b-2 audio: a saved voice recording — play/pause + duration,
    // with replace/delete in the editor.
    if (block.isAudio) {
      return ArticleAudioBlock(
        key: Key('article-block-${block.id}'),
        block: block,
        busy: _busyBlockId == block.id,
        onReplace: () => _replaceAudio(block),
        onDelete: () => _deleteBlock(block),
      );
    }

    // «Цитата» — quoted words + optional attribution. Edited inline (text
    // mirrors a paragraph; attribution is a second light field).
    if (block.isQuote) {
      return _buildQuoteRow(theme, index, block);
    }

    // «Разделитель» — a thin rule between parts. Not editable; managed via
    // the shared block «⋮» menu (insert / delete).
    if (block.isDivider) {
      return _buildDividerRow(theme, index, block);
    }

    final controller = _controllers[block.id]!;
    final focusNode = _focus[block.id]!;
    final hint = _hints[block.id];

    final TextStyle? style;
    final String fallbackHint;
    if (block.isHeader) {
      style = theme.textTheme.titleLarge?.copyWith(
        fontFamily: 'Lora',
        fontWeight: FontWeight.w700,
        fontSize: block.headerLevel == 1 ? 24 : 20,
      );
      fallbackHint = 'Заголовок раздела';
    } else {
      style = theme.textTheme.bodyLarge?.copyWith(
        fontFamily: 'Lora',
        fontSize: 18,
        height: 1.55,
      );
      fallbackHint = 'Расскажите своими словами…';
    }

    return Padding(
      padding: EdgeInsets.only(top: block.isHeader ? 18 : 6, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            // Focus ancestor (canRequestFocus:false) catches Backspace
            // that bubbles up from the empty TextField → delete-on-empty.
            // Works on web/desktop/hardware kbd; no-ops on Android soft
            // keyboards (which don't emit the key event) — explicit menu
            // delete covers that case.
            child: Focus(
              canRequestFocus: false,
              onKeyEvent: (_, event) => _handleBlockKey(index, event),
              child: TextField(
                key: Key('article-block-${block.id}'),
                controller: controller,
                focusNode: focusNode,
                style: style,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: hint ?? fallbackHint,
                  hintStyle: style?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.6),
                    fontWeight: block.isHeader ? FontWeight.w600 : null,
                  ),
                ),
                onChanged: (_) => _onChanged(block.id),
              ),
            ),
          ),
          // Per-block «⋮» menu — insert below + delete.
          _blockMenu(theme, index, block),
        ],
      ),
    );
  }

  // Shared per-block «⋮» menu (insert paragraph below + delete). Reused by
  // paragraph / header / quote / divider so every block has consistent
  // actions. Divider has no text, so its delete skips the confirm.
  Widget _blockMenu(ThemeData theme, int index, ArticleBlock block) {
    return PopupMenuButton<String>(
      key: Key('article-block-menu-${block.id}'),
      tooltip: 'Действия с блоком',
      padding: EdgeInsets.zero,
      icon: Icon(
        Icons.more_vert_rounded,
        size: 18,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
      ),
      onSelected: (value) {
        switch (value) {
          case 'insert':
            _addBlock('paragraph', afterIndex: index);
            break;
          case 'delete':
            if (block.isDivider) {
              _deleteBlock(block); // nothing to lose — no confirm
            } else {
              _deleteTextBlock(block);
            }
            break;
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'insert',
          child: Text('Добавить абзац ниже'),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Text(
            block.isDivider ? 'Удалить разделитель' : 'Удалить ${_deleteNoun(block)}',
          ),
        ),
      ],
    );
  }

  // «Цитата» row — accent left border, italic serif quote + a lighter
  // attribution field («— …»). Warm theme; reads as a pull-quote.
  Widget _buildQuoteRow(ThemeData theme, int index, ArticleBlock block) {
    final controller = _controllers[block.id]!;
    final focusNode = _focus[block.id]!;
    final attribution = _attributionControllers[block.id]!;
    final quoteStyle = theme.textTheme.bodyLarge?.copyWith(
      fontFamily: 'Lora',
      fontSize: 18,
      height: 1.5,
      fontStyle: FontStyle.italic,
    );
    final attributionStyle = theme.textTheme.bodyMedium?.copyWith(
      fontFamily: 'Lora',
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(left: 14),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: theme.colorScheme.primary.withValues(alpha: 0.55),
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Focus(
                    canRequestFocus: false,
                    onKeyEvent: (_, event) => _handleBlockKey(index, event),
                    child: TextField(
                      key: Key('article-block-${block.id}'),
                      controller: controller,
                      focusNode: focusNode,
                      style: quoteStyle,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Цитата…',
                        hintStyle: quoteStyle?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.6),
                        ),
                      ),
                      onChanged: (_) => _onChanged(block.id),
                    ),
                  ),
                  TextField(
                    key: Key('article-quote-attribution-${block.id}'),
                    controller: attribution,
                    style: attributionStyle,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      prefixText: '— ',
                      prefixStyle: attributionStyle,
                      hintText: 'кто сказал (необязательно)',
                      hintStyle: attributionStyle?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.6),
                      ),
                    ),
                    onChanged: (_) => _onChanged(block.id),
                  ),
                ],
              ),
            ),
          ),
          _blockMenu(theme, index, block),
        ],
      ),
    );
  }

  // «Разделитель» row — a thin warm rule with breathing room, plus the
  // shared «⋮» menu so it can be removed / followed by a new paragraph.
  Widget _buildDividerRow(ThemeData theme, int index, ArticleBlock block) {
    return Padding(
      key: Key('article-block-${block.id}'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Divider(
                key: Key('article-divider-${block.id}'),
                thickness: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
              ),
            ),
          ),
          _blockMenu(theme, index, block),
        ],
      ),
    );
  }

  Widget _buildUploadingRow(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            'Загрузка фото…',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveStatus(ThemeData theme) {
    final String label;
    if (_saving) {
      label = 'Сохранение…';
    } else if (_lastSavedAt != null) {
      label = '✓ Сохранено';
    } else {
      label = 'Автосохранение включено';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        label,
        key: const Key('article-save-status'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildToolbar(ThemeData theme, Color bg) {
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            _toolbarButton(
              theme,
              key: const Key('article-ideas'),
              icon: Icons.lightbulb_outline_rounded,
              label: 'Идеи',
              onTap: _openIdeas,
            ),
            _toolbarButton(
              theme,
              key: const Key('article-add-block'),
              icon: Icons.add_box_outlined,
              label: 'Блок',
              onTap: _openBlockMenu,
            ),
            _toolbarButton(
              theme,
              key: const Key('article-add-photo'),
              icon: Icons.photo_outlined,
              label: 'Фото',
              onTap: _addPhoto,
            ),
            _toolbarButton(
              theme,
              key: const Key('article-add-voice'),
              icon: Icons.mic_none_rounded,
              label: 'Голос',
              onTap: _openVoiceMenu,
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbarButton(
    ThemeData theme, {
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool dimmed = false,
  }) {
    final color = dimmed
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
        : theme.colorScheme.primary;
    // Vertical icon-over-label: gives the label the full slot width so
    // «Раздел» / «Голос» fit on one line on narrow phones (was a
    // horizontal TextButton.icon whose label wrapped). FittedBox is a
    // belt-and-braces guard against very narrow widths.
    return Expanded(
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AudioUpload {
  const _AudioUpload(this.url, this.durationSec);
  final String url;
  final int durationSec;
}
