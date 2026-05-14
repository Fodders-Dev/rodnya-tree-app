import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../backend/interfaces/family_tree_service_interface.dart';
import '../../backend/interfaces/onboarding_capable_family_tree_service.dart';
import '../../backend/models/onboarding_state.dart';
import '../../providers/onboarding_controller.dart';
import '../../providers/tree_provider.dart';

/// Phase 6 chunk 2 (PHASE-6-PROPOSAL.md §2.1): onboarding wizard
/// entry. 4 linear screens — welcome / profile / relatives / finish.
///
/// Router guard ([app_router_guards.dart] decides /onboarding vs
/// /tree based on `OnboardingState.completed` либо existing-user
/// detection).
class OnboardingWizardScreen extends StatefulWidget {
  const OnboardingWizardScreen({super.key});

  @override
  State<OnboardingWizardScreen> createState() =>
      _OnboardingWizardScreenState();
}

class _OnboardingWizardScreenState extends State<OnboardingWizardScreen> {
  late final OnboardingController _controller;

  @override
  void initState() {
    super.initState();
    final service = GetIt.I<FamilyTreeServiceInterface>();
    _controller = OnboardingController(
      service: service is OnboardingCapableFamilyTreeService
          ? service as OnboardingCapableFamilyTreeService
          : null,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<OnboardingController>.value(
      value: _controller,
      child: Consumer<OnboardingController>(
        builder: (context, controller, _) {
          if (controller.isLoading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (!controller.isCapable) {
            // Backend не capable — wizard skipped. Defensive landing
            // (router guard normally redirect'нёт раньше).
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) context.go('/tree');
            });
            return const SizedBox.shrink();
          }
          if (controller.completed) {
            // Already done — defensive redirect.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _selectCreatedTree(controller.state.treeId);
                context.go('/tree');
              }
            });
            return const SizedBox.shrink();
          }
          return Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              title: _WizardStepIndicator(step: controller.currentStep),
              elevation: 0,
            ),
            body: SafeArea(
              child: _buildStep(controller),
            ),
          );
        },
      ),
    );
  }

  void _selectCreatedTree(String? treeId) {
    if (treeId == null || treeId.isEmpty) return;
    final treeProvider = Provider.of<TreeProvider>(context, listen: false);
    treeProvider.selectTree(treeId, 'Моя семья');
  }

  Widget _buildStep(OnboardingController controller) {
    switch (controller.currentStep) {
      case OnboardingStep.welcome:
        return _WelcomeStep(controller: controller);
      case OnboardingStep.profile:
        return _ProfileStep(controller: controller);
      case OnboardingStep.relatives:
        return _RelativesStep(controller: controller);
      case OnboardingStep.finish:
        return _FinishStep(
          controller: controller,
          onFinish: () async {
            final ok = await controller.submit();
            if (!mounted) return;
            if (ok) {
              _selectCreatedTree(controller.state.treeId);
              context.go('/tree');
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(controller.error ?? 'Не удалось сохранить'),
                ),
              );
            }
          },
        );
      case OnboardingStep.done:
        // Same path as completed=true defensive redirect.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _selectCreatedTree(controller.state.treeId);
            context.go('/tree');
          }
        });
        return const SizedBox.shrink();
    }
  }
}

// ── Step indicator ────────────────────────────────────────────────

class _WizardStepIndicator extends StatelessWidget {
  const _WizardStepIndicator({required this.step});

  final OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    if (step == OnboardingStep.done) return const SizedBox.shrink();
    final stepLabels = const ['Старт', 'О вас', 'Семья', 'Готово'];
    final index = step.stepIndex.clamp(0, 3);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (i) {
        final isCurrent = i == index;
        final isPast = i < index;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCurrent
                  ? Theme.of(context).colorScheme.primary
                  : isPast
                      ? Theme.of(context).colorScheme.primary.withValues(
                          alpha: 0.5,
                        )
                      : Theme.of(context).colorScheme.surfaceContainerHigh,
            ),
          ),
        );
      })
        ..add(Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Text(
            stepLabels[index],
            style: Theme.of(context).textTheme.titleSmall,
          ),
        )),
    );
  }
}

// ── Step 1: Welcome ───────────────────────────────────────────────

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({required this.controller});

  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          Center(
            child: Icon(
              Icons.account_tree_rounded,
              size: 96,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Добро пожаловать в Родню',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Соберите семейное дерево вместе с родственниками и\n'
            'найдите дальних родных через цепочку знакомых.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          FilledButton(
            onPressed: () => controller.setStep(OnboardingStep.profile),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Начать', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step 2: Profile ───────────────────────────────────────────────

class _ProfileStep extends StatefulWidget {
  const _ProfileStep({required this.controller});

  final OnboardingController controller;

  @override
  State<_ProfileStep> createState() => _ProfileStepState();
}

class _ProfileStepState extends State<_ProfileStep> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.controller.profileName);
    _nameController.addListener(() {
      widget.controller.setProfileName(_nameController.text);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Расскажите о себе',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Это будет ваша карточка в дереве.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Имя и фамилия',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 16),
          Text(
            'Пол (необязательно)',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          SegmentedButton<String?>(
            segments: const [
              ButtonSegment<String?>(value: 'male', label: Text('Муж')),
              ButtonSegment<String?>(value: 'female', label: Text('Жен')),
              ButtonSegment<String?>(value: null, label: Text('Не указ.')),
            ],
            selected: <String?>{controller.profileGender},
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) {
                controller.setProfileGender(selection.first);
              }
            },
            emptySelectionAllowed: true,
          ),
          const Spacer(),
          Row(
            children: [
              TextButton(
                onPressed: () => controller.setStep(OnboardingStep.welcome),
                child: const Text('Назад'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: controller.profileStepValid
                    ? () => controller.setStep(OnboardingStep.relatives)
                    : null,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('Далее'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Step 3: First relatives ──────────────────────────────────────

class _RelativesStep extends StatelessWidget {
  const _RelativesStep({required this.controller});

  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Добавьте близких',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Дерево с 2-3 людьми помогает быстрее найти родню. '
            'Можно пропустить и добавить позже.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: controller.relatives.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _RelativeSlot(
                  index: index,
                  controller: controller,
                );
              },
            ),
          ),
          if (controller.relatives.length < 5)
            TextButton.icon(
              onPressed: controller.addRelativeSlot,
              icon: const Icon(Icons.add),
              label: const Text('Добавить ещё'),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: () => controller.setStep(OnboardingStep.profile),
                child: const Text('Назад'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => controller.setStep(OnboardingStep.finish),
                child: const Text('Пропустить'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => controller.setStep(OnboardingStep.finish),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('Далее'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RelativeSlot extends StatefulWidget {
  const _RelativeSlot({required this.index, required this.controller});

  final int index;
  final OnboardingController controller;

  @override
  State<_RelativeSlot> createState() => _RelativeSlotState();
}

class _RelativeSlotState extends State<_RelativeSlot> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    final draft = widget.controller.relatives[widget.index];
    _nameController = TextEditingController(text: draft.name);
    _nameController.addListener(() {
      widget.controller.setRelativeName(widget.index, _nameController.text);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.controller.relatives[widget.index];
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<OnboardingRelationToMe>(
              initialValue: draft.relationToMe,
              decoration: const InputDecoration(
                labelText: 'Кто это?',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: OnboardingRelationToMe.values
                  .map(
                    (r) => DropdownMenuItem<OnboardingRelationToMe>(
                      value: r,
                      child: Text(r.russianLabel),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  widget.controller.setRelativeRelation(widget.index, value),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Имя и фамилия',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            if (widget.controller.relatives.length > 1)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => widget.controller
                      .removeRelativeSlot(widget.index),
                  icon: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  label: Text(
                    'Убрать',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Step 4: Finish ────────────────────────────────────────────────

class _FinishStep extends StatelessWidget {
  const _FinishStep({required this.controller, required this.onFinish});

  final OnboardingController controller;
  final Future<void> Function() onFinish;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final validRelativeCount =
        controller.relatives.where((r) => r.isValid).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          Center(
            child: Icon(
              Icons.check_circle_outline,
              size: 96,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            validRelativeCount > 0
                ? 'Готово — соберём дерево'
                : 'Готово — начнём с пустого дерева',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            validRelativeCount > 0
                ? 'Создадим вашу карточку и $validRelativeCount '
                    '${_relativeCountLabel(validRelativeCount)} в дереве.'
                : 'Создадим только вашу карточку. Родственников '
                    'добавите позже из дерева.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          if (controller.isSubmitting)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            FilledButton(
              onPressed: onFinish,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Открыть дерево',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
          TextButton(
            onPressed: () => controller.setStep(OnboardingStep.relatives),
            child: const Text('Назад'),
          ),
        ],
      ),
    );
  }

  static String _relativeCountLabel(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'родственника';
    if ([2, 3, 4].contains(mod10) && ![12, 13, 14].contains(mod100)) {
      return 'родственников';
    }
    return 'родственников';
  }
}
