// Profile Phase 2a (2026-05-29): «💡 Идеи» темы-промпт sheet.
//
// Q6 (locked): одноуровневые темы (no sub-prompts на старте). Tap a
// theme → editor inserts a section header + an empty paragraph whose
// placeholder is the prompt question. «Свой раздел» → empty custom
// header the user titles themselves.
//
// Gender agreement (2026-05-29): prompt questions reference the person
// in 3rd person, so gendered verbs (родился / работал / он был) must
// agree with the card's gender. genderForm picks the form; for
// unknown / other we use a clean noun-based neutral reformulation
// rather than «родился(ась)» скобки. Section titles are nouns — no
// agreement needed.

import 'package:flutter/material.dart';

/// Picks a gender-agreeing string. `gender` is the raw person gender
/// ('male' / 'female' / 'other' / 'unknown' / null). female → feminine,
/// male → masculine; everything else → neutral (or masculine if no
/// neutral form was supplied).
String genderForm(
  String? gender, {
  required String masculine,
  required String feminine,
  String? neutral,
}) {
  switch (gender) {
    case 'female':
      return feminine;
    case 'male':
      return masculine;
    default:
      return neutral ?? masculine;
  }
}

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

// Built per-gender so the prompt questions agree with the card. Titles
// are gender-neutral nouns. Семья / Свадьба / Война carry no person-
// gendered verb (plural / inanimate-subject agreement) — same string
// for everyone; only Детство / Работа / Характер vary.
List<ArticleIdeaPrompt> _presetsFor(String? gender) => [
      ArticleIdeaPrompt(
        title: 'Детство',
        prompt: genderForm(
          gender,
          masculine: 'Где и когда родился? Каким было детство, каким был дом?',
          feminine: 'Где и когда родилась? Каким было детство, каким был дом?',
          neutral: 'Место и год рождения. Каким было детство, каким был дом?',
        ),
      ),
      const ArticleIdeaPrompt(
        title: 'Семья',
        prompt: 'Расскажите о родителях, братьях и сёстрах.',
      ),
      const ArticleIdeaPrompt(
        title: 'Свадьба',
        prompt: 'Как познакомились? Когда и где поженились?',
      ),
      ArticleIdeaPrompt(
        title: 'Работа',
        prompt: genderForm(
          gender,
          masculine: 'Кем работал? Чем гордился в своём деле?',
          feminine: 'Кем работала? Чем гордилась в своём деле?',
          neutral: 'Работа и призвание. Что приносило гордость в своём деле?',
        ),
      ),
      const ArticleIdeaPrompt(
        title: 'Война',
        prompt: 'Как война коснулась семьи? Что запомнилось из тех лет?',
      ),
      ArticleIdeaPrompt(
        title: 'Характер и увлечения',
        prompt: genderForm(
          gender,
          masculine: 'Каким он был? Чем увлекался в свободное время?',
          feminine: 'Какой она была? Чем увлекалась в свободное время?',
          neutral: 'Что за человек? Какие были увлечения в свободное время?',
        ),
      ),
    ];

const ArticleIdeaPrompt _customPrompt = ArticleIdeaPrompt(
  title: '',
  prompt: 'О чём этот раздел?',
  custom: true,
);

/// Shows the idea-prompts sheet. `personGender` ('male' / 'female' /
/// 'other' / 'unknown' / null) tunes the prompt wording. Returns the
/// chosen prompt, or null if dismissed.
Future<ArticleIdeaPrompt?> showArticleIdeaPromptsSheet(
  BuildContext context, {
  String? personGender,
}) {
  final presets = _presetsFor(personGender);
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
                      for (var i = 0; i < presets.length; i++)
                        _PromptTile(
                          key: Key('article-idea-${_slug(presets[i].title)}'),
                          prompt: presets[i],
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
