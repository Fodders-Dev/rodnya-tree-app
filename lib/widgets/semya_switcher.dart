import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../backend/models/semya.dart';
import '../providers/semya_list_controller.dart';
import '../screens/semya_details_screen.dart';

/// Phase B Ship FE1: семя switcher widget.
///
/// Visual design:
/// * Compact pill в app bar showing current семя name + chevron
/// * Tap → bottom sheet с full list (selection radio rows)
/// * Empty state — «У вас пока нет семьи» plain text
/// * «Создать семью» button — disabled placeholder в Ship FE1, wired
///   к navigation/dialog в Ship FE2
///
/// Wiring:
/// * Reads SemyaListController via Provider.of (либо
///   ListenableBuilder если caller wraps explicitly)
/// * Auto-loads на first mount if controller hasn't loaded yet
/// * Refresh swipe gesture deferred — Ship FE9-10 auto-refresh
///   integration
class SemyaSwitcher extends StatefulWidget {
  const SemyaSwitcher({
    super.key,
    this.compact = false,
  });

  /// Compact mode shows только current name + chevron, no role chip.
  /// Used когда space tight (e.g. nested в other widget).
  final bool compact;

  @override
  State<SemyaSwitcher> createState() => _SemyaSwitcherState();
}

class _SemyaSwitcherState extends State<SemyaSwitcher> {
  bool _initialLoadRequested = false;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SemyaListController>();

    if (!controller.hasLoaded && !_initialLoadRequested) {
      _initialLoadRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Best-effort initial load. Errors surfaced via controller
        // errorMessage; no need to await here.
        controller.loadInitial();
      });
    }

    if (!controller.isCapable) {
      // Backend doesn't expose Phase B caps — render nothing. Legacy
      // tree provider stays in charge. UI invisible на pre-Phase-B
      // installs.
      return const SizedBox.shrink();
    }

    if (controller.isLoading && !controller.hasLoaded) {
      return const _LoadingPill();
    }

    if (controller.semyi.isEmpty) {
      return _EmptyPill(
        onTapCreate: () => _showSheet(context, controller),
      );
    }

    final selected = controller.selectedSemya ?? controller.semyi.first;
    return _SwitcherPill(
      label: selected.name,
      compact: widget.compact,
      onTap: () => _showSheet(context, controller),
    );
  }

  Future<void> _showSheet(
    BuildContext context,
    SemyaListController controller,
  ) async {
    // Sheet может outlive context if user navigates away — capture
    // controller reference now чтобы избежать use-after-unmount.
    final captured = controller;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return _SemyaListSheet(controller: captured);
      },
    );
  }
}

class _SwitcherPill extends StatelessWidget {
  const _SwitcherPill({
    required this.label,
    required this.onTap,
    required this.compact,
  });

  final String label;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.family_restroom,
                size: compact ? 16 : 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingPill extends StatelessWidget {
  const _LoadingPill();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: SizedBox(
        height: 14,
        width: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _EmptyPill extends StatelessWidget {
  const _EmptyPill({required this.onTapCreate});

  final VoidCallback onTapCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTapCreate,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Создать семью',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SemyaListSheet extends StatelessWidget {
  const _SemyaListSheet({required this.controller});

  final SemyaListController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final selectedId = controller.selectedSemyaId;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Text(
                    'Мои семьи',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (controller.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      controller.errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                if (controller.semyi.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Text('У вас пока нет семьи.'),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: controller.semyi.length,
                      itemBuilder: (context, index) {
                        final semya = controller.semyi[index];
                        final isSelected = semya.id == selectedId;
                        return _SemyaTile(
                          semya: semya,
                          isSelected: isSelected,
                          onTap: () async {
                            await controller.selectSemya(semya.id);
                            if (context.mounted) {
                              Navigator.of(context).maybePop();
                            }
                          },
                        );
                      },
                    ),
                  ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: OutlinedButton.icon(
                    onPressed: null, // Ship FE2 wires create flow
                    icon: const Icon(Icons.add),
                    label: const Text('Создать семью'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Text(
                    'Создание семьи появится в следующем обновлении.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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
}

class _SemyaTile extends StatelessWidget {
  const _SemyaTile({
    required this.semya,
    required this.isSelected,
    required this.onTap,
  });

  final Semya semya;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(
        isSelected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_unchecked_rounded,
        color: isSelected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(semya.name),
      subtitle: semya.description != null && semya.description!.isNotEmpty
          ? Text(
              semya.description!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      onTap: onTap,
      // Ship FE2 (2026-05-26): trailing info button opens details screen
      // (members list + owner-only management placeholders). Tap row
      // itself остаётся selection action (existing FE1 behavior).
      trailing: IconButton(
        key: Key('semya-details-${semya.id}'),
        tooltip: 'Подробнее',
        icon: Icon(
          Icons.info_outline_rounded,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        onPressed: () {
          Navigator.of(context).maybePop();
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(
              builder: (_) => SemyaDetailsScreen(semyaId: semya.id),
            ),
          );
        },
      ),
    );
  }
}
