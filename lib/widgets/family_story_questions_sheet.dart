import 'package:flutter/material.dart';

import '../models/family_story_question.dart';

enum FamilyStoryQuestionActionType {
  share,
  saveAnswer,
}

class FamilyStoryQuestionAction {
  const FamilyStoryQuestionAction({
    required this.type,
    required this.question,
  });

  final FamilyStoryQuestionActionType type;
  final FamilyStoryQuestion question;
}

Future<FamilyStoryQuestionAction?> showFamilyStoryQuestionsSheet(
  BuildContext context, {
  required String personName,
  String? relation,
}) {
  return showModalBottomSheet<FamilyStoryQuestionAction>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _FamilyStoryQuestionsSheet(
      personName: personName,
      relation: relation,
    ),
  );
}

class _FamilyStoryQuestionsSheet extends StatefulWidget {
  const _FamilyStoryQuestionsSheet({
    required this.personName,
    this.relation,
  });

  final String personName;
  final String? relation;

  @override
  State<_FamilyStoryQuestionsSheet> createState() =>
      _FamilyStoryQuestionsSheetState();
}

class _FamilyStoryQuestionsSheetState
    extends State<_FamilyStoryQuestionsSheet> {
  FamilyStoryQuestion _selected = familyStoryQuestions.first;

  @override
  Widget build(BuildContext context) {
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
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
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
