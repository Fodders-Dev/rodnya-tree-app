// Profile Phase 2a (2026-05-29): «💡 Идеи» темы-промпт sheet.
//
// Q6 (locked): одноуровневые темы (no sub-prompts на старте). Tap a
// theme → editor inserts a section header + an empty paragraph whose
// placeholder is the prompt question. «Свой раздел» → empty custom
// header the user titles themselves.

import 'package:flutter/material.dart';

class ArticleIdeaPrompt {
  const ArticleIdeaPrompt({
    required this.title,
    required this.prompt,
    this.custom = false,
  });

  /// Section header text inserted into the article.
  final String title;

  /// Question shown as the new paragraph's placeholder.
  final String prompt;

  /// «Свой раздел» — user titles the header themselves.
  final bool custom;
}

const List<ArticleIdeaPrompt> _presets = [
  ArticleIdeaPrompt(
    title: 'Детство',
    prompt: 'Где и когда родился? Каким было детство, каким был дом?',
  ),
  ArticleIdeaPrompt(
    title: 'Семья',
    prompt: 'Расскажите о родителях, братьях и сёстрах.',
  ),
  ArticleIdeaPrompt(
    title: 'Свадьба',
    prompt: 'Как познакомились? Когда и где поженились?',
  ),
  ArticleIdeaPrompt(
    title: 'Работа',
    prompt: 'Кем работал? Чем гордился в своём деле?',
  ),
  ArticleIdeaPrompt(
    title: 'Война',
    prompt: 'Как война коснулась семьи? Что запомнилось из тех лет?',
  ),
  ArticleIdeaPrompt(
    title: 'Характер и увлечения',
    prompt: 'Каким он был человеком? Чем увлекался в свободное время?',
  ),
];

const ArticleIdeaPrompt _customPrompt = ArticleIdeaPrompt(
  title: '',
  prompt: 'О чём этот раздел?',
  custom: true,
);

/// Shows the idea-prompts sheet. Returns the chosen prompt, or null if
/// dismissed.
Future<ArticleIdeaPrompt?> showArticleIdeaPromptsSheet(BuildContext context) {
  return showModalBottomSheet<ArticleIdeaPrompt>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'С чего начать?',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Выберите тему — добавим раздел, а вы расскажете своими словами.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var i = 0; i < _presets.length; i++)
                        _PromptTile(
                          key: Key('article-idea-${_slug(_presets[i].title)}'),
                          prompt: _presets[i],
                          icon: Icons.auto_stories_outlined,
                        ),
                      _PromptTile(
                        key: const Key('article-idea-custom'),
                        prompt: _customPrompt,
                        label: 'Свой раздел',
                        icon: Icons.add_circle_outline_rounded,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

String _slug(String title) =>
    title.toLowerCase().replaceAll(RegExp(r'\s+'), '-');

class _PromptTile extends StatelessWidget {
  const _PromptTile({
    super.key,
    required this.prompt,
    required this.icon,
    this.label,
  });

  final ArticleIdeaPrompt prompt;
  final IconData icon;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(label ?? prompt.title),
      subtitle: prompt.custom ? null : Text(prompt.prompt),
      onTap: () => Navigator.of(context).pop(prompt),
    );
  }
}
