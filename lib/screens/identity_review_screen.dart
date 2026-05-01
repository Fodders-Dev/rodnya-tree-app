import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/identity_service_interface.dart';
import '../models/identity_claim.dart';
import '../models/merge_proposal.dart';
import '../utils/user_facing_error.dart';

class IdentityReviewScreen extends StatefulWidget {
  const IdentityReviewScreen({super.key});

  @override
  State<IdentityReviewScreen> createState() => _IdentityReviewScreenState();
}

class _IdentityReviewScreenState extends State<IdentityReviewScreen> {
  AuthServiceInterface get _authService => GetIt.I<AuthServiceInterface>();

  IdentityServiceInterface? get _identityService =>
      GetIt.I.isRegistered<IdentityServiceInterface>()
          ? GetIt.I<IdentityServiceInterface>()
          : null;

  bool _isLoading = true;
  bool _isMutating = false;
  bool _publicDiscoverability = false;
  Object? _loadError;
  List<MergeProposal> _mergeProposals = const <MergeProposal>[];
  List<IdentityClaim> _identityClaims = const <IdentityClaim>[];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final service = _identityService;
    if (service == null) {
      setState(() {
        _isLoading = false;
        _mergeProposals = const <MergeProposal>[];
        _identityClaims = const <IdentityClaim>[];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final results = await Future.wait([
        service.getPendingMergeProposals(),
        service.getPendingIdentityClaims(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _mergeProposals = results[0] as List<MergeProposal>;
        _identityClaims = results[1] as List<IdentityClaim>;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _reviewMergeProposal(
    MergeProposal proposal, {
    required bool accept,
  }) async {
    final service = _identityService;
    if (service == null) {
      return;
    }
    setState(() => _isMutating = true);
    try {
      final reviewed = await service.reviewMergeProposal(
        proposal.id,
        accept: accept,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _mergeProposals = _mergeProposals
            .where((entry) => entry.id != proposal.id)
            .toList(growable: false);
        if (reviewed.isPending) {
          _mergeProposals = [..._mergeProposals, reviewed];
        }
      });
      _showMessage(
        accept
            ? 'Голос учтён. Объединение применится после согласия всех ответственных.'
            : 'Совпадение отклонено.',
      );
    } catch (error) {
      _showMessage(describeUserFacingError(
        authService: _authService,
        error: error,
        fallbackMessage: 'Не удалось отправить решение.',
      ));
    } finally {
      if (mounted) {
        setState(() => _isMutating = false);
      }
    }
  }

  Future<void> _reviewIdentityClaim(
    IdentityClaim claim, {
    required bool approve,
  }) async {
    final service = _identityService;
    if (service == null) {
      return;
    }
    setState(() => _isMutating = true);
    try {
      await service.reviewIdentityClaim(claim.id, approve: approve);
      if (!mounted) {
        return;
      }
      setState(() {
        _identityClaims = _identityClaims
            .where((entry) => entry.id != claim.id)
            .toList(growable: false);
      });
      _showMessage(approve ? 'Запрос подтверждён.' : 'Запрос отклонён.');
    } catch (error) {
      _showMessage(describeUserFacingError(
        authService: _authService,
        error: error,
        fallbackMessage: 'Не удалось обновить запрос.',
      ));
    } finally {
      if (mounted) {
        setState(() => _isMutating = false);
      }
    }
  }

  Future<void> _setPublicDiscoverability(bool enabled) async {
    final service = _identityService;
    if (service == null) {
      return;
    }
    setState(() {
      _isMutating = true;
      _publicDiscoverability = enabled;
    });
    try {
      final value = await service.setPublicDiscoverability(enabled);
      if (!mounted) {
        return;
      }
      setState(() => _publicDiscoverability = value);
      _showMessage(
        value
            ? 'Публичный поиск включён только по имени и году рождения.'
            : 'Публичный поиск отключён.',
      );
    } catch (error) {
      if (mounted) {
        setState(() => _publicDiscoverability = !enabled);
      }
      _showMessage(describeUserFacingError(
        authService: _authService,
        error: error,
        fallbackMessage: 'Не удалось обновить публичный поиск.',
      ));
    } finally {
      if (mounted) {
        setState(() => _isMutating = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Совпадения и личность'),
        actions: [
          IconButton(
            onPressed: _isMutating ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          _ReviewStateCard(
            icon: Icons.error_outline,
            title: 'Не удалось загрузить проверки',
            message: 'Обновите экран ещё раз.',
            action: FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ),
        ],
      );
    }

    final hasReviews = _mergeProposals.isNotEmpty || _identityClaims.isNotEmpty;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _PublicDiscoveryCard(
          value: _publicDiscoverability,
          enabled: !_isMutating,
          onChanged: _setPublicDiscoverability,
        ),
        const SizedBox(height: 16),
        Text(
          'Возможные совпадения',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        if (_mergeProposals.isEmpty)
          const _ReviewStateCard(
            icon: Icons.merge_type_outlined,
            title: 'Нет совпадений на проверку',
            message:
                'Когда система найдёт похожие карточки в разных деревьях, они появятся здесь.',
          )
        else
          ..._mergeProposals.map(
            (proposal) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _MergeProposalCard(
                proposal: proposal,
                isMutating: _isMutating,
                onAccept: () => _reviewMergeProposal(
                  proposal,
                  accept: true,
                ),
                onReject: () => _reviewMergeProposal(
                  proposal,
                  accept: false,
                ),
              ),
            ),
          ),
        const SizedBox(height: 18),
        Text(
          'Запросы личности',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        if (_identityClaims.isEmpty)
          const _ReviewStateCard(
            icon: Icons.verified_user_outlined,
            title: 'Нет запросов личности',
            message:
                'Здесь будут запросы на привязку аккаунта к карточке человека.',
          )
        else
          ..._identityClaims.map(
            (claim) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _IdentityClaimCard(
                claim: claim,
                isMutating: _isMutating,
                onApprove: () => _reviewIdentityClaim(claim, approve: true),
                onDeny: () => _reviewIdentityClaim(claim, approve: false),
              ),
            ),
          ),
        if (!hasReviews) ...[
          const SizedBox(height: 10),
          const Text(
            'Ничего не требует решения. Публичный поиск остаётся выключенным, пока вы явно не включите его.',
          ),
        ],
      ],
    );
  }
}

class _PublicDiscoveryCard extends StatelessWidget {
  const _PublicDiscoveryCard({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: SwitchListTile(
        value: value,
        onChanged: enabled ? onChanged : null,
        secondary: Icon(
          Icons.manage_search_outlined,
          color: theme.colorScheme.primary,
        ),
        title: const Text('Разрешить публичный поиск'),
        subtitle: const Text(
          'Показывает только ФИО и год рождения. Фото, точные даты, контакты и дерево не раскрываются.',
        ),
      ),
    );
  }
}

class _MergeProposalCard extends StatelessWidget {
  const _MergeProposalCard({
    required this.proposal,
    required this.isMutating,
    required this.onAccept,
    required this.onReject,
  });

  final MergeProposal proposal;
  final bool isMutating;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.merge_type_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Похоже, это один человек',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text('${(proposal.matchScore * 100).round()}%'),
              ],
            ),
            const SizedBox(height: 12),
            _MergePersonLine(person: proposal.personA),
            const SizedBox(height: 6),
            _MergePersonLine(person: proposal.personB),
            if (proposal.reasons.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                proposal.reasons.join(', '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: isMutating ? null : onAccept,
                  icon: const Icon(Icons.check),
                  label: const Text('Это один человек'),
                ),
                OutlinedButton.icon(
                  onPressed: isMutating ? null : onReject,
                  icon: const Icon(Icons.close),
                  label: const Text('Разные люди'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MergePersonLine extends StatelessWidget {
  const _MergePersonLine({required this.person});

  final MergePersonPreview person;

  @override
  Widget build(BuildContext context) {
    final year = person.birthYear == null ? '' : ' · ${person.birthYear}';
    return Row(
      children: [
        const Icon(Icons.person_outline, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text('${person.name}$year')),
      ],
    );
  }
}

class _IdentityClaimCard extends StatelessWidget {
  const _IdentityClaimCard({
    required this.claim,
    required this.isMutating,
    required this.onApprove,
    required this.onDeny,
  });

  final IdentityClaim claim;
  final bool isMutating;
  final VoidCallback onApprove;
  final VoidCallback onDeny;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Пользователь просит подтвердить карточку',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Карточка: ${claim.personId}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: isMutating ? null : onApprove,
                  icon: const Icon(Icons.check),
                  label: const Text('Подтвердить'),
                ),
                OutlinedButton.icon(
                  onPressed: isMutating ? null : onDeny,
                  icon: const Icon(Icons.close),
                  label: const Text('Отклонить'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewStateCard extends StatelessWidget {
  const _ReviewStateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 10),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 12),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
