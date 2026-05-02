import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/identity_service_interface.dart';
import '../models/identity_claim.dart';
import '../models/merge_proposal.dart';
import '../theme/app_theme.dart';
import '../utils/user_facing_error.dart';
import '../widgets/glass_panel.dart';

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
      _showMessage(
        describeUserFacingError(
          authService: _authService,
          error: error,
          fallbackMessage: 'Не удалось отправить решение.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isMutating = false);
      }
    }
  }

  void _postponeMergeProposal(MergeProposal proposal) {
    if (_mergeProposals.length > 1) {
      setState(() {
        _mergeProposals = [
          ..._mergeProposals.where((entry) => entry.id != proposal.id),
          proposal,
        ];
      });
    }
    _showMessage('Оставили совпадение на потом.');
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
      _showMessage(
        describeUserFacingError(
          authService: _authService,
          error: error,
          fallbackMessage: 'Не удалось обновить запрос.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isMutating = false);
      }
    }
  }

  void _postponeIdentityClaim() {
    _showMessage('Запрос останется в списке до вашего решения.');
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
      _showMessage(
        describeUserFacingError(
          authService: _authService,
          error: error,
          fallbackMessage: 'Не удалось обновить публичный поиск.',
        ),
      );
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

  void _leaveScreen() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    try {
      context.go('/');
    } catch (_) {
      // Widget tests can host the screen without GoRouter.
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPending = _mergeProposals.length + _identityClaims.length;

    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Container(
          decoration: BoxDecoration(
            color: tokens.surfaceStrong.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.86 : 0.90,
            ),
            border: Border(
              bottom: BorderSide(color: tokens.surfaceLine, width: 0.7),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                IconButton(
                  onPressed: _leaveScreen,
                  icon: Icon(Icons.arrow_back_rounded, color: tokens.ink),
                  tooltip: 'Назад',
                ),
                const SizedBox(width: 4),
                Text(
                  'Один человек?',
                  style: AppTheme.serif(
                    color: tokens.ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.18,
                  ),
                ),
                const Spacer(),
                if (totalPending > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: tokens.warmSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$totalPending на проверку',
                      style: AppTheme.sans(
                        color: tokens.warm,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                Material(
                  color: tokens.surfaceStrong,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: tokens.surfaceLine),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: InkWell(
                    onTap: _isMutating ? null : _load,
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 38,
                      height: 38,
                      child: Icon(
                        Icons.refresh_rounded,
                        size: 19,
                        color: tokens.ink,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: const [
          _ReviewStateCard(
            icon: Icons.sync,
            title: 'Загружаем проверки',
            message: 'Ищем совпадения и запросы, которые ждут вашего решения.',
            showProgress: true,
          ),
        ],
      );
    }
    if (_loadError != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          _ReviewStateCard(
            icon: Icons.error_outline,
            title: 'Не удалось загрузить проверки',
            message: 'Обновите экран ещё раз. Данные не изменялись.',
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            isWide ? 28 : 16,
            isWide ? 22 : 14,
            isWide ? 28 : 16,
            34,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isWide ? 1040 : 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ReviewSummaryCard(
                      mergeCount: _mergeProposals.length,
                      claimCount: _identityClaims.length,
                    ),
                    const SizedBox(height: 14),
                    if (_mergeProposals.isEmpty)
                      _ReviewStateCard(
                        icon: Icons.merge_type_outlined,
                        title: 'Нет совпадений на проверку',
                        message: hasReviews
                            ? 'Сейчас остались только запросы личности.'
                            : 'Когда система найдёт похожие карточки в разных деревьях, они появятся здесь.',
                      )
                    else
                      ..._mergeProposals.map(
                        (proposal) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _MergeProposalComparisonCard(
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
                            onLater: () => _postponeMergeProposal(proposal),
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    _PublicDiscoveryCard(
                      value: _publicDiscoverability,
                      enabled: !_isMutating,
                      onChanged: _setPublicDiscoverability,
                    ),
                    const SizedBox(height: 16),
                    _SectionTitle(
                      title: 'Запросы личности',
                      trailing: _identityClaims.isEmpty
                          ? null
                          : '${_identityClaims.length} на проверку',
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
                            onApprove: () =>
                                _reviewIdentityClaim(claim, approve: true),
                            onDeny: () =>
                                _reviewIdentityClaim(claim, approve: false),
                            onLater: _postponeIdentityClaim,
                          ),
                        ),
                      ),
                    if (!hasReviews) ...[
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _leaveScreen,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Вернуться назад'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ReviewSummaryCard extends StatelessWidget {
  const _ReviewSummaryCard({
    required this.mergeCount,
    required this.claimCount,
  });

  final int mergeCount;
  final int claimCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = _tokens(context);
    final total = mergeCount + claimCount;
    final title = total == 0
        ? 'Ничего не требует решения'
        : total == 1
            ? '1 проверка ждёт решения'
            : '$total проверок ждут решения';

    return GlassPanel(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(tokens.radiusLg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: tokens.accentSoft,
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
            child: Icon(Icons.auto_awesome, color: tokens.accentStrong),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: tokens.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Мы показываем только безопасные признаки: имя, год рождения и доступный вам контекст. Решение всегда остаётся за вами.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.inkSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
    final tokens = _tokens(context);
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      borderRadius: BorderRadius.circular(tokens.radiusMd),
      color: tokens.surfaceStrong.withValues(alpha: 0.86),
      child: SwitchListTile.adaptive(
        value: value,
        onChanged: enabled ? onChanged : null,
        contentPadding: EdgeInsets.zero,
        secondary: Icon(
          Icons.manage_search_outlined,
          color: tokens.accentStrong,
        ),
        title: const Text('Публичный поиск'),
        subtitle: const Text(
          'Раскрывает только ФИО и год рождения. Фото, точные даты, контакты и дерево не показываются.',
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    this.trailing,
  });

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = _tokens(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: tokens.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (trailing != null) _MetaPill(label: trailing!),
      ],
    );
  }
}

class _MergeProposalComparisonCard extends StatelessWidget {
  const _MergeProposalComparisonCard({
    required this.proposal,
    required this.isMutating,
    required this.onAccept,
    required this.onReject,
    required this.onLater,
  });

  final MergeProposal proposal;
  final bool isMutating;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final tokens = _tokens(context);
    final confidencePercent = _confidencePercent(proposal);
    final rows = _comparisonRows(proposal);

    return GlassPanel(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(tokens.radiusLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ConfidenceHeader(
            proposal: proposal,
            confidencePercent: confidencePercent,
          ),
          const SizedBox(height: 16),
          _PersonPairPreview(proposal: proposal),
          const SizedBox(height: 18),
          _MatchSignals(reasons: proposal.reasons),
          const SizedBox(height: 12),
          _ComparisonTable(rows: rows),
          const SizedBox(height: 14),
          const _PrivacyNote(
            message:
                'После объединения будут связаны только доступные вам ветки и карточки. Приватные заметки, чужие комментарии, точные даты и внутренние id не раскрываются.',
          ),
          const SizedBox(height: 16),
          _MergeActions(
            isMutating: isMutating,
            onAccept: onAccept,
            onReject: onReject,
            onLater: onLater,
          ),
        ],
      ),
    );
  }

  int _confidencePercent(MergeProposal proposal) {
    final raw = (proposal.matchScore * 100).round();
    return raw.clamp(0, 100).toInt();
  }

  List<_ComparisonRowData> _comparisonRows(MergeProposal proposal) {
    final personA = proposal.personA;
    final personB = proposal.personB;
    final sameName = _normalize(personA.name) == _normalize(personB.name);
    final sameYear = personA.birthYear != null &&
        personB.birthYear != null &&
        personA.birthYear == personB.birthYear;

    return [
      _ComparisonRowData(
        label: 'Имя',
        left: personA.name,
        right: personB.name,
        tone: sameName ? _MatchTone.match : _MatchTone.maybe,
      ),
      _ComparisonRowData(
        label: 'Год рождения',
        left: personA.birthYear ?? 'не указан',
        right: personB.birthYear ?? 'не указан',
        tone: sameYear ? _MatchTone.match : _MatchTone.neutral,
      ),
      _ComparisonRowData(
        label: 'Контекст',
        left: personA.contextLabel ?? 'доступный контекст',
        right: personB.contextLabel ?? 'доступный контекст',
        tone: _MatchTone.neutral,
      ),
    ];
  }

  String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}

class _ConfidenceHeader extends StatelessWidget {
  const _ConfidenceHeader({
    required this.proposal,
    required this.confidencePercent,
  });

  final MergeProposal proposal;
  final int confidencePercent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = _tokens(context);
    final signalCount = proposal.reasons.isEmpty ? 1 : proposal.reasons.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome, color: tokens.accentStrong, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Совпадение по $signalCount признакам',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: tokens.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              '$confidencePercent%',
              style: theme.textTheme.titleSmall?.copyWith(
                color: tokens.accentStrong,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 7,
            value: confidencePercent / 100,
            backgroundColor: tokens.surface,
            color: confidencePercent >= 80 ? tokens.accent : tokens.warm,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                _confidenceText(proposal),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.inkSecondary,
                  height: 1.3,
                ),
              ),
            ),
            if (proposal.requiredReviewCount > 0) ...[
              const SizedBox(width: 10),
              _MetaPill(
                label:
                    '${proposal.reviewCount}/${proposal.requiredReviewCount} согласовано',
              ),
            ],
          ],
        ),
      ],
    );
  }

  String _confidenceText(MergeProposal proposal) {
    final confidence = proposal.confidence.toLowerCase();
    final String label;
    switch (confidence) {
      case 'high':
        label = 'высокая уверенность';
        break;
      case 'low':
        label = 'низкая уверенность';
        break;
      default:
        label = 'средняя уверенность';
    }
    return 'У системы $label. Обычно объединяем при 80% и выше, но решение подтверждает человек.';
  }
}

class _PersonPairPreview extends StatelessWidget {
  const _PersonPairPreview({required this.proposal});

  final MergeProposal proposal;

  @override
  Widget build(BuildContext context) {
    final tokens = _tokens(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _PersonCompareCard(
            person: proposal.personA,
            accent: tokens.accent,
          ),
        ),
        SizedBox(
          width: 42,
          child: Center(
            child: Icon(Icons.merge_type, color: tokens.inkMuted),
          ),
        ),
        Expanded(
          child: _PersonCompareCard(
            person: proposal.personB,
            accent: tokens.warm,
          ),
        ),
      ],
    );
  }
}

class _PersonCompareCard extends StatelessWidget {
  const _PersonCompareCard({
    required this.person,
    required this.accent,
  });

  final MergePersonPreview person;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = _tokens(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: tokens.surfaceLine),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(tokens.radiusSm),
              ),
              child: Center(
                child: Text(
                  _initials(person.name),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              person.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                color: tokens.ink,
                fontWeight: FontWeight.w900,
                height: 1.18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              person.contextLabel ?? 'Контекст скрыт настройками доступа',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.inkMuted,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 10),
            _SafeFactLine(
              icon: Icons.cake_outlined,
              label: person.birthYear == null
                  ? 'год рождения не указан'
                  : 'год ${person.birthYear}',
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final words = name.split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
    final value = words
        .take(2)
        .map((word) => String.fromCharCode(word.runes.first).toUpperCase())
        .join();
    return value.isEmpty ? '?' : value;
  }
}

class _SafeFactLine extends StatelessWidget {
  const _SafeFactLine({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = _tokens(context);
    return Row(
      children: [
        Icon(icon, size: 15, color: tokens.inkMuted),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tokens.inkSecondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }
}

class _MatchSignals extends StatelessWidget {
  const _MatchSignals({required this.reasons});

  final List<String> reasons;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = _tokens(context);
    final safeReasons = reasons.isEmpty
        ? const ['Система нашла похожие безопасные признаки']
        : reasons.take(6).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Что совпадает',
          style: theme.textTheme.titleSmall?.copyWith(
            color: tokens.ink,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final reason in safeReasons)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.accentSoft,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: tokens.surfaceLine),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, size: 14, color: tokens.accentStrong),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          reason,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: tokens.accentStrong,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable({required this.rows});

  final List<_ComparisonRowData> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = _tokens(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: tokens.surfaceLine),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        child: Column(
          children: [
            for (var index = 0; index < rows.length; index++) ...[
              _ComparisonRow(data: rows[index]),
              if (index != rows.length - 1)
                Divider(height: 1, color: tokens.surfaceLine),
            ],
          ],
        ),
      ),
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({required this.data});

  final _ComparisonRowData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = _tokens(context);
    final Color statusColor;
    final IconData statusIcon;
    switch (data.tone) {
      case _MatchTone.match:
        statusColor = tokens.accentStrong;
        statusIcon = Icons.check;
        break;
      case _MatchTone.maybe:
        statusColor = tokens.warm;
        statusIcon = Icons.warning_amber_rounded;
        break;
      case _MatchTone.neutral:
        statusColor = tokens.inkMuted;
        statusIcon = Icons.more_horiz;
        break;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 540;
        if (compact) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        data.label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: tokens.inkMuted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Icon(statusIcon, color: statusColor, size: 16),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  data.left,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: tokens.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  data.right,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: tokens.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 118,
                child: Text(
                  data.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: tokens.inkMuted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(child: _ComparisonValue(value: data.left)),
              SizedBox(
                width: 34,
                child: Icon(statusIcon, color: statusColor, size: 16),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _ComparisonValue(value: data.right, alignRight: true),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ComparisonValue extends StatelessWidget {
  const _ComparisonValue({
    required this.value,
    this.alignRight = false,
  });

  final String value;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final tokens = _tokens(context);
    return Text(
      value,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: alignRight ? TextAlign.right : TextAlign.left,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: tokens.ink,
            fontWeight: FontWeight.w800,
            height: 1.25,
          ),
    );
  }
}

class _MergeActions extends StatelessWidget {
  const _MergeActions({
    required this.isMutating,
    required this.onAccept,
    required this.onReject,
    required this.onLater,
  });

  final bool isMutating;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final tokens = _tokens(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: isMutating ? null : onAccept,
          icon: const Icon(Icons.merge_type),
          label: const Text('Это один человек — объединить'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: isMutating ? null : onReject,
          icon: const Icon(Icons.close),
          label: const Text('Разные люди'),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: isMutating ? null : onLater,
          style: TextButton.styleFrom(foregroundColor: tokens.inkMuted),
          child: const Text('Решу позже'),
        ),
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
    required this.onLater,
  });

  final IdentityClaim claim;
  final bool isMutating;
  final VoidCallback onApprove;
  final VoidCallback onDeny;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = _tokens(context);
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(tokens.radiusLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: tokens.accentSoft,
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
                child: Icon(
                  Icons.verified_user_outlined,
                  color: tokens.accentStrong,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Запрос на привязку личности',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: tokens.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Пользователь просит связать аккаунт с карточкой человека. Внутренние id, reviewer ids и дерево здесь не раскрываются.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.inkSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _PrivacyNote(
            message:
                'Подтверждайте только если уверены по семейному каналу связи. Отклонение не удаляет карточку человека.',
          ),
          const SizedBox(height: 14),
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
              TextButton(
                onPressed: isMutating ? null : onLater,
                child: const Text('Позже'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = _tokens(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surfaceStrong.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.surfaceLine),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, color: tokens.accentStrong, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.inkSecondary,
                  height: 1.4,
                ),
              ),
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
    this.showProgress = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = _tokens(context);
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      borderRadius: BorderRadius.circular(tokens.radiusLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: tokens.accentStrong),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: tokens.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (showProgress)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tokens.accentStrong,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.inkSecondary,
              height: 1.35,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            action!,
          ],
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = _tokens(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.accentSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.surfaceLine),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: tokens.accentStrong,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

enum _MatchTone { match, maybe, neutral }

class _ComparisonRowData {
  const _ComparisonRowData({
    required this.label,
    required this.left,
    required this.right,
    required this.tone,
  });

  final String label;
  final String left;
  final String right;
  final _MatchTone tone;
}

RodnyaDesignTokens _tokens(BuildContext context) {
  final theme = Theme.of(context);
  return theme.extension<RodnyaDesignTokens>() ??
      (theme.brightness == Brightness.dark
          ? RodnyaDesignTokens.dark
          : RodnyaDesignTokens.light);
}
