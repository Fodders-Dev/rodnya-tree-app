import 'package:flutter/material.dart';

/// Phase 3.4 chunk 4 (PHASE-3.4-UI-PROPOSAL.md §2.4): sensitive
/// contacts section на person card.
///
/// Wireframe (proposal):
/// ```
/// ─── Контакты ─────────────────────────
/// Телефон:    +7 999 1234567   🔒 Видно тебе
/// E-mail:     anna@example.com  🔒 Видно тебе
/// Адрес:      Москва, Невская   🔒 Видно тебе
///
///  ⓘ  Эти поля видны только тебе. Другие
///     родственники их не увидят, даже если
///     карточка открыта всем.
///
///                                  [Изменить]
/// ```
///
/// Видимость:
///   • viewer = owner → section отображается (с values или empty state).
///   • viewer ≠ owner → section полностью скрыта (sensitive
///     attributes отфильтрованы на бекенде Phase 3.2; UI просто не
///     рендерит).
///
/// Edit callback ведёт в существующий profile editor — Save
/// прописывает PUT attributes с category-level gate (только owner
/// может писать contacts; backend reject'ит non-owner с 403).
///
/// Privacy frame: badge «Видно тебе» на каждом поле — explicit
/// signal что это owner-only-всегда, независимо от
/// [`graphPerson.visibility`]. Phase 3.2 enforce'ит это backend-
/// side; UI badge — UX confirmation для owner'а.
class SensitiveContactsSection extends StatelessWidget {
  const SensitiveContactsSection({
    required this.isOwner,
    this.phoneNumber,
    this.email,
    this.addressLine,
    this.onEdit,
    super.key,
  });

  /// Если false — section полностью скрыта. Ответственность caller'а
  /// рассчитать `viewer == effectiveOwner`.
  final bool isOwner;

  final String? phoneNumber;
  final String? email;

  /// Свободная строка — обычно «Город, Страна» либо более точный
  /// адрес. Если null/empty — соответствующая row не показывается
  /// (но empty-state срабатывает только если ВСЕ три пусты).
  final String? addressLine;

  /// Если null — кнопка «Изменить» не показывается (read-only).
  /// Production-call'ом должен быть navigation в profile editor с
  /// pre-filled значениями.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    if (!isOwner) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final phone = _normalize(phoneNumber);
    final mail = _normalize(email);
    final address = _normalize(addressLine);
    final allEmpty = phone == null && mail == null && address == null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Контакты',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.lock_rounded,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (allEmpty)
            _EmptyContactsState(onEdit: onEdit)
          else ...[
            if (phone != null)
              _ContactRow(
                label: 'Телефон',
                value: phone,
                icon: Icons.phone_outlined,
              ),
            if (mail != null)
              _ContactRow(
                label: 'E-mail',
                value: mail,
                icon: Icons.email_outlined,
              ),
            if (address != null)
              _ContactRow(
                label: 'Адрес',
                value: address,
                icon: Icons.location_on_outlined,
              ),
            const SizedBox(height: 8),
            _SensitiveFootnote(),
            if (onEdit != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Изменить'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  static String? _normalize(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 68,
            child: Text(
              '$label:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          const _VisibleToYouBadge(),
        ],
      ),
    );
  }
}

class _VisibleToYouBadge extends StatelessWidget {
  const _VisibleToYouBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message:
          'Видно только тебе. Контакты родственники не видят, даже '
          'если карточка открыта всем.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_rounded,
              size: 12,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 4),
            Text(
              'Видно тебе',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SensitiveFootnote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.6,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Эти поля видны только тебе. Другие родственники их не '
              'увидят, даже если карточка открыта всем.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyContactsState extends StatelessWidget {
  const _EmptyContactsState({required this.onEdit});

  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.5,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Контакты ещё не указаны',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Добавь телефон, e-mail или адрес — их увидишь только ты.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (onEdit != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Добавить'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
