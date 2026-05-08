// ignore_for_file: use_build_context_synchronously
// ignore_for_file: library_private_types_in_public_api
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../backend/interfaces/family_tree_service_interface.dart';
import '../../models/family_tree.dart';
import '../../providers/tree_provider.dart';

class CreateTreeScreen extends StatefulWidget {
  const CreateTreeScreen({
    super.key,
    this.initialKind = TreeKind.family,
  });

  final TreeKind initialKind;

  @override
  _CreateTreeScreenState createState() => _CreateTreeScreenState();
}

class _CreateTreeScreenState extends State<CreateTreeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  bool _isLoading = false;
  bool _isPrivate = true; // Значение по умолчанию - приватное дерево
  late TreeKind _treeKind;
  String? _selectedTemplateKey;

  final FamilyTreeServiceInterface _familyTreeService =
      GetIt.I<FamilyTreeServiceInterface>();

  @override
  void initState() {
    super.initState();
    _treeKind = widget.initialKind;
  }

  // Pre-cooked branch ideas. Tap a chip → name + description
  // controllers fill in. The user can edit either field after,
  // we just save them from staring at a blank form. The keys are
  // stable identifiers so we can highlight the active chip
  // without comparing freeform text. Two parallel lists because
  // the friends-tree («Круг») use case has a totally different
  // vocabulary from blood family.
  static const List<_BranchTemplate> _familyTemplates = <_BranchTemplate>[
    _BranchTemplate(
      key: 'maternal',
      label: 'По маминой линии',
      name: 'По маминой линии',
      description: 'Мама и её родня — бабушка с дедом, тёти и дяди, кузены.',
    ),
    _BranchTemplate(
      key: 'paternal',
      label: 'По папиной линии',
      name: 'По папиной линии',
      description: 'Папа и его родня — другая половина моего дерева.',
    ),
    _BranchTemplate(
      key: 'spouse',
      label: 'Семья жены/мужа',
      name: 'Семья жены',
      description: 'Родные супруга — родители, братья и сёстры, племянники.',
    ),
    _BranchTemplate(
      key: 'closeBlood',
      label: 'Кровная родня',
      name: 'Кровная родня',
      description: 'Только кровные родственники, без свойственников.',
    ),
  ];

  static const List<_BranchTemplate> _friendsTemplates = <_BranchTemplate>[
    _BranchTemplate(
      key: 'closeFriends',
      label: 'Близкие друзья',
      name: 'Близкие друзья',
      description: 'Те, кому первому пишу о хороших и плохих новостях.',
    ),
    _BranchTemplate(
      key: 'school',
      label: 'Школа',
      name: 'Школа',
      description: 'Одноклассники и ребята со школьных лет.',
    ),
    _BranchTemplate(
      key: 'uni',
      label: 'Универ',
      name: 'Универ',
      description: 'Однокурсники, преподаватели, студенческая компания.',
    ),
    _BranchTemplate(
      key: 'work',
      label: 'Работа',
      name: 'Работа',
      description: 'Коллеги и партнёры, с которыми поддерживаю общение.',
    ),
  ];

  List<_BranchTemplate> get _activeTemplates =>
      _treeKind == TreeKind.friends ? _friendsTemplates : _familyTemplates;

  void _applyTemplate(_BranchTemplate template) {
    setState(() {
      _selectedTemplateKey = template.key;
      _nameController.text = template.name;
      _descriptionController.text = template.description;
    });
    // Reset cursor positions to the END so the user can keep typing
    // without first pressing → (small UX win, big when they tap a
    // chip and immediately want to extend «По маминой линии» to «По
    // маминой линии Кузнецовых»).
    _nameController.selection = TextSelection.fromPosition(
      TextPosition(offset: _nameController.text.length),
    );
    _descriptionController.selection = TextSelection.fromPosition(
      TextPosition(offset: _descriptionController.text.length),
    );
  }

  void _clearTemplateSelection() {
    if (_selectedTemplateKey != null) {
      setState(() {
        _selectedTemplateKey = null;
      });
    }
  }

  Future<void> _createTree() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final treeId = await _familyTreeService.createTree(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        isPrivate: _isPrivate,
        kind: _treeKind,
      );

      if (mounted) {
        final treeName = _nameController.text.trim();
        if (GetIt.I.isRegistered<TreeProvider>()) {
          await GetIt.I<TreeProvider>().selectTree(
            treeId,
            treeName,
            treeKind: _treeKind,
          );
        }
        final successLabel = _treeKind == TreeKind.friends
            ? 'Дерево друзей создано'
            : 'Семейное дерево создано';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successLabel)));
        final encodedName = Uri.encodeComponent(treeName);
        context.go('/tree/view/$treeId?name=$encodedName');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новая ветка')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'С чего начнём?',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                _treeKind == TreeKind.friends
                    ? 'Введите название круга друзей — потом сможете добавлять и связывать людей.'
                    : 'Введите название ветки — потом сможете добавлять родственников. У каждой ветки своя лента, истории и события.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              SegmentedButton<TreeKind>(
                segments: const [
                  ButtonSegment<TreeKind>(
                    value: TreeKind.family,
                    icon: Icon(Icons.family_restroom),
                    label: Text('Семья'),
                  ),
                  ButtonSegment<TreeKind>(
                    value: TreeKind.friends,
                    icon: Icon(Icons.diversity_3_outlined),
                    label: Text('Друзья'),
                  ),
                ],
                selected: <TreeKind>{_treeKind},
                onSelectionChanged: (selection) {
                  setState(() {
                    _treeKind = selection.first;
                    // Switching kind drops any previous template
                    // pick — the family templates don't make sense
                    // in the friends tab and vice versa.
                    _selectedTemplateKey = null;
                  });
                },
              ),
              const SizedBox(height: 12),
              Text(
                _treeKind == TreeKind.friends
                    ? 'Режим друзей подходит для близкого круга, друзей, коллег и выбранной семьи. Узлы удобнее раскладывать вручную.'
                    : 'Режим семьи лучше подходит для родственных связей и поколений. Ветка — это срез вашего общего графа: «Кровная родня», «Семья жены», «Папина линия» — и у каждой свои истории, посты и события.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              // Pre-cooked template chips. Tap one and the name +
              // description fields below get prefilled with a
              // sensible default — the user can edit either, the
              // chip just saves them from staring at a blank form
              // and inventing a name from scratch. Hidden when
              // the template list is empty (e.g. tomorrow when
              // somebody adds a new tree-kind without templates).
              if (_activeTemplates.isNotEmpty) ...[
                Text(
                  'Шаблоны',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final template in _activeTemplates)
                      ChoiceChip(
                        label: Text(template.label),
                        selected: _selectedTemplateKey == template.key,
                        onSelected: (selected) {
                          if (selected) {
                            _applyTemplate(template);
                          } else {
                            _clearTemplateSelection();
                          }
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: _treeKind == TreeKind.friends
                      ? 'Название круга друзей'
                      : 'Название ветки',
                  hintText: _treeKind == TreeKind.friends
                      ? 'Например: Наш круг'
                      : 'Например: Семья Ивановых, Кровная родня, Папина линия',
                  prefixIcon: Icon(
                    _treeKind == TreeKind.friends
                        ? Icons.diversity_3_outlined
                        : Icons.family_restroom,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return _treeKind == TreeKind.friends
                        ? 'Введите название круга друзей'
                        : 'Введите название ветки';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Описание, если нужно',
                  hintText:
                      'Например: близкие друзья, университет, рабочий круг',
                  prefixIcon: Icon(Icons.description),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 20),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _isPrivate,
                onChanged: (value) {
                  setState(() {
                    _isPrivate = value;
                  });
                },
                title:
                    Text(_isPrivate ? 'Приватная ветка' : 'Публичная ветка'),
                subtitle: Text(
                  _isPrivate
                      ? 'Её увидят только приглашённые участники.'
                      : 'Её можно будет открывать по ссылке.',
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _createTree,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Создать и открыть'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}

/// Pre-cooked branch idea surfaced as a ChoiceChip on the create
/// form. Tapping a chip prefills the name + description controllers
/// — the user can keep editing afterwards, this is just a head
/// start. `key` is a stable identifier for selection state so we
/// can highlight the active chip without comparing freeform text.
class _BranchTemplate {
  const _BranchTemplate({
    required this.key,
    required this.label,
    required this.name,
    required this.description,
  });

  /// Stable identifier used to mark a chip as selected. Survives
  /// renames of the localized `label` / `name` without breaking
  /// the highlight.
  final String key;

  /// Short copy shown on the chip itself.
  final String label;

  /// Default branch name written into the name controller when the
  /// chip is tapped. Often equal to `label`; kept separate so we
  /// can have «Семья жены/мужа» on the chip but seed the safer
  /// «Семья жены» as the actual name.
  final String name;

  /// Default description written into the description controller.
  final String description;
}
