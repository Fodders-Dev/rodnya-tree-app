// «Спросить историю» MVP-1 (STORY-REQUEST-MVP1-BRIEF.md §3.6): for the
// INITIATOR only, a status line above «Семейные истории» tracking their
// own open questions about this person — «Ждём ответа: {имя} · Отозвать».
// Read-only viewers and the addressee never see this (it's the asker's
// own bookkeeping, not a public thing on the card).
//
// The contract has no personId filter on GET /v1/me/story-requests
// (§1 — role + status only), so this fetches the initiator's pending
// issued requests and filters by personId client-side; the list is
// small (a handful of open asks per person, ever) so this is cheap.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';

import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/story_request_capable_family_tree_service.dart';
import '../models/story_request.dart';

class StoryRequestStatusLine extends StatefulWidget {
  const StoryRequestStatusLine({
    super.key,
    required this.personId,
    this.serviceOverride,
    this.authServiceOverride,
  });

  final String personId;

  /// Test seam — production resolves via GetIt (and hides itself when
  /// the registered service doesn't implement the capability).
  final StoryRequestCapableFamilyTreeService? serviceOverride;
  final AuthServiceInterface? authServiceOverride;

  @override
  State<StoryRequestStatusLine> createState() => _StoryRequestStatusLineState();
}

class _StoryRequestStatusLineState extends State<StoryRequestStatusLine> {
  bool _loaded = false;
  List<StoryRequest> _pendingForPerson = const <StoryRequest>[];
  final Set<String> _revoking = <String>{};

  StoryRequestCapableFamilyTreeService? _service() {
    if (widget.serviceOverride != null) return widget.serviceOverride;
    // Production registers ONE FamilyTreeServiceInterface singleton — new
    // capabilities are additive `implements`, not separate GetIt
    // registrations (see discover_relatives_screen.dart for the same
    // pattern with KinshipCheckCapableFamilyTreeService).
    if (!GetIt.I.isRegistered<FamilyTreeServiceInterface>()) return null;
    final service = GetIt.I<FamilyTreeServiceInterface>();
    return service is StoryRequestCapableFamilyTreeService
        ? service as StoryRequestCapableFamilyTreeService
        : null;
  }

  AuthServiceInterface? _auth() {
    if (widget.authServiceOverride != null) return widget.authServiceOverride;
    if (GetIt.I.isRegistered<AuthServiceInterface>()) {
      return GetIt.I<AuthServiceInterface>();
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final service = _service();
    final currentUserId = _auth()?.currentUserId;
    if (service == null || currentUserId == null) {
      if (mounted) setState(() => _loaded = true);
      return;
    }
    try {
      final issued = await service.listStoryRequests(
        role: 'issued',
        status: StoryRequestStatus.pending,
      );
      if (!mounted) return;
      setState(() {
        _pendingForPerson = issued
            .where((r) =>
                r.personId == widget.personId &&
                r.requesterUserId == currentUserId)
            .toList(growable: false);
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _edit(StoryRequest request) async {
    final service = _service();
    if (service == null || _revoking.contains(request.id)) return;
    final edited = await showDialog<_EditedStoryRequestValues>(
      context: context,
      builder: (_) => _EditStoryRequestDialog(
        initialQuestionText: request.question.text,
        showTargetName: request.isPublicLink,
        initialTargetName: request.targetName ?? '',
      ),
    );
    if (edited == null || !mounted) return;
    setState(() => _revoking.add(request.id));
    try {
      final updated = await service.updateStoryRequest(
        requestId: request.id,
        questionText: edited.questionText,
        targetName: request.isPublicLink ? edited.targetName : null,
      );
      if (!mounted) return;
      if (updated == null) {
        setState(() => _revoking.remove(request.id));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось обновить вопрос. Попробуйте ещё раз.'),
          ),
        );
        return;
      }
      setState(() {
        _revoking.remove(request.id);
        _pendingForPerson = _pendingForPerson
            .map((r) => r.id == request.id ? updated : r)
            .toList(growable: false);
      });
    } on StoryRequestError catch (e) {
      if (!mounted) return;
      setState(() => _revoking.remove(request.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _revoking.remove(request.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось обновить вопрос. Попробуйте ещё раз.'),
        ),
      );
    }
  }

  Future<void> _revoke(StoryRequest request) async {
    final service = _service();
    if (service == null || _revoking.contains(request.id)) return;
    setState(() => _revoking.add(request.id));
    try {
      final updated = await service.revokeStoryRequest(requestId: request.id);
      if (!mounted) return;
      if (updated == null) {
        setState(() => _revoking.remove(request.id));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось отозвать вопрос. Попробуйте ещё раз.'),
          ),
        );
        return;
      }
      setState(() {
        _revoking.remove(request.id);
        if (!updated.isPending) {
          _pendingForPerson =
              _pendingForPerson.where((r) => r.id != request.id).toList();
        }
      });
    } on StoryRequestError catch (e) {
      if (!mounted) return;
      setState(() => _revoking.remove(request.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _revoking.remove(request.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось отозвать вопрос. Попробуйте ещё раз.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _pendingForPerson.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      key: const Key('story-request-status-line'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final request in _pendingForPerson)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.hourglass_top_rounded,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          request.isPublicLink
                              ? _publicLinkStatusText(request)
                              : 'Ждём ответа: ${_targetName(request)}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (request.isPublicLink &&
                          (request.shareUrl ?? '').isNotEmpty &&
                          !_revoking.contains(request.id))
                        TextButton(
                          key: Key('story-request-copy-${request.id}'),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: request.shareUrl!),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Ссылка скопирована'),
                              ),
                            );
                          },
                          child: const Text('Скопировать'),
                        ),
                      if (!_revoking.contains(request.id))
                        TextButton(
                          key: Key('story-request-edit-${request.id}'),
                          onPressed: () => _edit(request),
                          child: const Text('Изменить'),
                        ),
                      _revoking.contains(request.id)
                          ? const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : TextButton(
                              key: Key('story-request-revoke-${request.id}'),
                              onPressed: () => _revoke(request),
                              child: const Text('Отозвать'),
                            ),
                    ],
                  ),
                  if (request.question.text.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 22),
                      child: Text(
                        '«${request.question.text.trim()}»',
                        key: Key('story-request-question-${request.id}'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _targetName(StoryRequest request) {
    final name = request.target?.displayName?.trim();
    return (name != null && name.isNotEmpty) ? name : 'родного';
  }

  String _publicLinkStatusText(StoryRequest request) {
    final name = request.targetName?.trim();
    if (name != null && name.isNotEmpty) {
      return 'Ждём ответа по ссылке: $name';
    }
    return 'Ждём ответа по ссылке';
  }
}

class _EditedStoryRequestValues {
  const _EditedStoryRequestValues({
    required this.questionText,
    this.targetName,
  });

  final String questionText;
  final String? targetName;
}

class _EditStoryRequestDialog extends StatefulWidget {
  const _EditStoryRequestDialog({
    required this.initialQuestionText,
    required this.showTargetName,
    required this.initialTargetName,
  });

  final String initialQuestionText;
  final bool showTargetName;
  final String initialTargetName;

  @override
  State<_EditStoryRequestDialog> createState() =>
      _EditStoryRequestDialogState();
}

class _EditStoryRequestDialogState extends State<_EditStoryRequestDialog> {
  late final TextEditingController _questionController;
  late final TextEditingController _targetController;

  @override
  void initState() {
    super.initState();
    _questionController =
        TextEditingController(text: widget.initialQuestionText);
    _targetController = TextEditingController(text: widget.initialTargetName);
  }

  @override
  void dispose() {
    _questionController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trimmedLen = _questionController.text.trim().length;
    final canSave = trimmedLen >= 3 && trimmedLen <= 500;
    return AlertDialog(
      title: const Text('Изменить вопрос'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('story-request-edit-question-field'),
            controller: _questionController,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Текст вопроса',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (widget.showTargetName) ...[
            const SizedBox(height: 10),
            TextField(
              key: const Key('story-request-edit-target-field'),
              controller: _targetController,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Кому ссылка (необязательно)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const Key('story-request-edit-save'),
          onPressed: canSave
              ? () => Navigator.of(context).pop(
                    _EditedStoryRequestValues(
                      questionText: _questionController.text.trim(),
                      targetName: widget.showTargetName
                          ? _targetController.text.trim()
                          : null,
                    ),
                  )
              : null,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
