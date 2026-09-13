import 'package:flutter/material.dart';

import '../backend/interfaces/story_request_capable_family_tree_service.dart';
import '../models/family_story_question.dart';
import '../models/story_request.dart';

enum FamilyStoryQuestionActionType {
  share,
  saveAnswer,
  requestSent,
}

class FamilyStoryQuestionAction {
  const FamilyStoryQuestionAction({
    required this.type,
    required this.question,
    this.request,
  });

  final FamilyStoryQuestionActionType type;
  final FamilyStoryQuestion question;

  /// Populated only for [FamilyStoryQuestionActionType.requestSent] —
  /// lets the caller refresh the person page's «ждём ответа» status line
  /// right away instead of waiting for the next reload.
  final StoryRequest? request;
}

/// One candidate addressee for the «Кого спросить» step (MVP-1 §0.1 —
/// only tree members with an account; a guest link is MVP-2).
class FamilyStoryAskTarget {
  const FamilyStoryAskTarget({
    required this.userId,
    required this.displayName,
    this.photoUrl,
    this.isHero = false,
  });

  final String userId;
  final String displayName;
  final String? photoUrl;

  /// True when this target IS the person being asked about — «сама
  /// бабушка» has her own account and answers about herself.
  final bool isHero;
}

Future<FamilyStoryQuestionAction?> showFamilyStoryQuestionsSheet(
  BuildContext context, {
  required String personName,
  String? relation,
  // MVP-1 «Спросить историю» (STORY-REQUEST-MVP1-BRIEF.md §3.3): when the
  // backend can create story-requests AND there is at least one addressee
  // with an account, the sheet gains a «Кого спросить» step that sends an
  // in-app request instead of only offering system share. Leaving these
  // unset (or an empty askTargets) reproduces the pre-MVP-1 sheet byte
  // for byte — just the two original buttons, no new step.
  StoryRequestCapableFamilyTreeService? storyRequestService,
  String? treeId,
  String? personId,
  List<FamilyStoryAskTarget> askTargets = const <FamilyStoryAskTarget>[],
}) {
  return showModalBottomSheet<FamilyStoryQuestionAction>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _FamilyStoryQuestionsSheet(
      personName: personName,
      relation: relation,
      storyRequestService: storyRequestService,
      treeId: treeId,
      personId: personId,
      askTargets: askTargets,
    ),
  );
}

enum _Step { question, target }

class _FamilyStoryQuestionsSheet extends StatefulWidget {
  const _FamilyStoryQuestionsSheet({
    required this.personName,
    this.relation,
    this.storyRequestService,
    this.treeId,
    this.personId,
    this.askTargets = const <FamilyStoryAskTarget>[],
  });

  final String personName;
  final String? relation;
  final StoryRequestCapableFamilyTreeService? storyRequestService;
  final String? treeId;
  final String? personId;
  final List<FamilyStoryAskTarget> askTargets;

  @override
  State<_FamilyStoryQuestionsSheet> createState() =>
      _FamilyStoryQuestionsSheetState();
}

class _FamilyStoryQuestionsSheetState
    extends State<_FamilyStoryQuestionsSheet> {
  FamilyStoryQuestion _selected = familyStoryQuestions.first;
  _Step _step = _Step.question;
  String? _selectedTargetUserId;
  bool _sending = false;
  String? _sendError;

  bool get _canRequest =>
      widget.storyRequestService != null &&
      (widget.treeId ?? '').isNotEmpty &&
      (widget.personId ?? '').isNotEmpty &&
      widget.askTargets.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return _step == _Step.target
        ? _buildTargetStep(context)
        : _buildQuestionStep(context);
  }

  Widget _buildQuestionStep(BuildContext context) {
    final theme = Theme.of(context);
    final message = buildFamilyStoryShareMessage(
      question: _selected,
      personName: widget.personName,
      relation: widget.relation,
    );
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.88,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Спросить историю',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontFamily: 'Lora',
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Выберите вопрос. Родня подготовит сообщение, а ответ '
                'можно сохранить в карточке человека.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView.separated(
                  itemCount: familyStoryQuestions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final question = familyStoryQuestions[index];
                    return _QuestionTile(
                      question: question,
                      selected: question.id == _selected.id,
                      onTap: () => setState(() => _selected = question),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              _MessagePreview(message: message),
              const SizedBox(height: 12),
              if (_canRequest) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('family-story-ask-in-app'),
                    onPressed: () => setState(() => _step = _Step.target),
                    icon: const Icon(Icons.forum_outlined, size: 18),
                    label: const Text('Спросить в Родне'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: _canRequest
                    ? OutlinedButton.icon(
                        key: const Key('family-story-share-question'),
                        onPressed: () => Navigator.of(context).pop(
                          FamilyStoryQuestionAction(
                            type: FamilyStoryQuestionActionType.share,
                            question: _selected,
                          ),
                        ),
                        icon: const Icon(Icons.ios_share_outlined, size: 18),
                        label: const Text('Поделиться текстом'),
                      )
                    : FilledButton.icon(
                        key: const Key('family-story-share-question'),
                        onPressed: () => Navigator.of(context).pop(
                          FamilyStoryQuestionAction(
                            type: FamilyStoryQuestionActionType.share,
                            question: _selected,
                          ),
                        ),
                        icon: const Icon(Icons.ios_share_outlined, size: 18),
                        label: const Text('Отправить вопрос'),
                      ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('family-story-save-answer'),
                  onPressed: () => Navigator.of(context).pop(
                    FamilyStoryQuestionAction(
                      type: FamilyStoryQuestionActionType.saveAnswer,
                      question: _selected,
                    ),
                  ),
                  icon: const Icon(Icons.auto_stories_outlined, size: 18),
                  label: const Text('Сохранить ответ'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTargetStep(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.82,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    key: const Key('family-story-target-back'),
                    onPressed: _sending
                        ? null
                        : () => setState(() => _step = _Step.question),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Text(
                      'Кого спросить?',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontFamily: 'Lora',
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                child: Text(
                  '«${_selected.question}»',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                    height: 1.3,
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: widget.askTargets.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final target = widget.askTargets[index];
                    final selected = target.userId == _selectedTargetUserId;
                    return _TargetTile(
                      target: target,
                      selected: selected,
                      onTap: _sending
                          ? null
                          : () => setState(
                              () => _selectedTargetUserId = target.userId),
                    );
                  },
                ),
              ),
              if (_sendError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _sendError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('family-story-send-request'),
                  onPressed: (_selectedTargetUserId == null || _sending)
                      ? null
                      : _sendRequest,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(_sending ? 'Отправляем…' : 'Отправить'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendRequest() async {
    final service = widget.storyRequestService;
    final treeId = widget.treeId;
    final personId = widget.personId;
    final targetUserId = _selectedTargetUserId;
    if (service == null ||
        treeId == null ||
        personId == null ||
        targetUserId == null) {
      return;
    }
    final target = widget.askTargets.firstWhere(
      (t) => t.userId == targetUserId,
      orElse: () => widget.askTargets.first,
    );
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      final created = await service.createStoryRequest(
        treeId: treeId,
        personId: personId,
        targetUserId: targetUserId,
        question: StoryRequestQuestion(
          text: _selected.question,
          sourceQuestionId: _selected.id,
        ),
      );
      if (!mounted) return;
      if (created == null) {
        setState(() {
          _sending = false;
          _sendError = 'Не удалось отправить вопрос. Попробуйте ещё раз.';
        });
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${target.displayName} получит ваш вопрос')),
      );
      Navigator.of(context).pop(
        FamilyStoryQuestionAction(
          type: FamilyStoryQuestionActionType.requestSent,
          question: _selected,
          request: created,
        ),
      );
    } on StoryRequestError catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sendError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sendError = 'Не удалось отправить вопрос. Попробуйте ещё раз.';
      });
    }
  }
}

class _TargetTile extends StatelessWidget {
  const _TargetTile({
    required this.target,
    required this.selected,
    required this.onTap,
  });

  final FamilyStoryAskTarget target;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Material(
      color: selected
          ? primary.withValues(alpha: 0.1)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: Key('family-story-target-${target.userId}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: primary.withValues(alpha: 0.14),
                backgroundImage: (target.photoUrl != null &&
                        target.photoUrl!.isNotEmpty)
                    ? NetworkImage(target.photoUrl!)
                    : null,
                child: (target.photoUrl == null || target.photoUrl!.isEmpty)
                    ? Text(
                        target.displayName.isNotEmpty
                            ? target.displayName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                // Gender-aware «Сама Лида» / «Сам Артём» is composed by the
                // caller (it knows FamilyPerson.gender) — see
                // _buildStoryAskTargets in relative_details_screen_sections
                // .dart. This widget stays dumb: just renders the label.
                child: Text(
                  target.displayName,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? primary : theme.colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuestionTile extends StatelessWidget {
  const _QuestionTile({
    required this.question,
    required this.selected,
    required this.onTap,
  });

  final FamilyStoryQuestion question;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Material(
      color: selected
          ? primary.withValues(alpha: 0.1)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: Key('family-story-question-${question.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? primary : theme.colorScheme.onSurfaceVariant,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      question.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      question.question,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      question.context,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessagePreview extends StatelessWidget {
  const _MessagePreview({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.16),
        ),
      ),
      child: Text(
        message,
        maxLines: 5,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
      ),
    );
  }
}
