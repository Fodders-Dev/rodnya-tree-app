part of '../interactive_family_tree.dart';

/// keep the friction low. They can fill in details by tapping the
/// new card after it lands on the canvas.
class _BlankCardDialog extends StatefulWidget {
  const _BlankCardDialog();

  @override
  State<_BlankCardDialog> createState() => _BlankCardDialogState();
}

class _BlankCardDialogState extends State<_BlankCardDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  Gender _selectedGender = Gender.unknown;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  String _genderToWireString(Gender gender) {
    switch (gender) {
      case Gender.male:
        return 'male';
      case Gender.female:
        return 'female';
      default:
        return 'unknown';
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    Navigator.of(context).pop(<String, dynamic>{
      'firstName': firstName,
      if (lastName.isNotEmpty) 'lastName': lastName,
      'gender': _genderToWireString(_selectedGender),
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.person_add_alt_1_rounded,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Новый человек',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Сначала добавьте карточку, потом соедините её с другими длинным нажатием.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _firstNameController,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Имя',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Введите имя';
                    }
                    if (value.trim().length > 120) {
                      return 'Имя слишком длинное';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _lastNameController,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _save(),
                  decoration: const InputDecoration(
                    labelText: 'Фамилия (необязательно)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value != null && value.trim().length > 120) {
                      return 'Фамилия слишком длинная';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Пол',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                _BlankCardGenderRow(
                  selected: _selectedGender,
                  onChanged: (gender) =>
                      setState(() => _selectedGender = gender),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Отмена'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Добавить'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BlankCardGenderRow extends StatelessWidget {
  const _BlankCardGenderRow({
    required this.selected,
    required this.onChanged,
  });

  final Gender selected;
  final ValueChanged<Gender> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        _option(theme, Gender.male, 'Мужской', Icons.male_rounded),
        const SizedBox(width: 8),
        _option(theme, Gender.female, 'Женский', Icons.female_rounded),
        const SizedBox(width: 8),
        _option(theme, Gender.unknown, 'Не указан', Icons.help_outline_rounded),
      ],
    );
  }

  Widget _option(ThemeData theme, Gender gender, String label, IconData icon) {
    final isActive = selected == gender;
    final scheme = theme.colorScheme;
    return Expanded(
      child: Semantics(
        button: true,
        label: '$label, ${isActive ? "выбран" : "не выбран"}',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onChanged(gender),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              color: isActive
                  ? scheme.primaryContainer.withValues(alpha: 0.85)
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive
                    ? scheme.primary
                    : scheme.outlineVariant.withValues(alpha: 0.5),
                width: isActive ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: isActive ? scheme.primary : scheme.onSurfaceVariant,
                  size: 22,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Voltage-indicator dot — small accent-colored 💡 chip on cards
/// where the cross-tree matcher found candidates the user hasn't
/// linked or dismissed yet. Visual is intentionally subtle:
/// passive nudge, not an alert. Tap → popover with suggestion
/// list (host responsibility).
///
/// Why "voltage indicator" — the user described the feel they
