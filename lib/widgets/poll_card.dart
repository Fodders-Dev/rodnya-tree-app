// Phase E5b: feed card for an «Опрос» (Poll). Mirrors GatheringCard's
// shell (author header, type badge, photos via FeedMediaGallery) and its
// optimistic-update pattern, swapping the RSVP row for option bars: each
// option is a tappable bar with a percent fill by votes, my pick
// highlighted. Single-choice replaces my vote; multi toggles.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';

import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/poll_service_interface.dart';
import '../models/poll.dart';
import '../models/post.dart' show TreeContentScopeType;
import '../theme/app_theme.dart';
import '../utils/date_parser.dart';
import '../utils/user_facing_error.dart';
import 'feed_media_gallery.dart';
import 'media_lightbox.dart';
import 'safe_delete_confirmation_dialog.dart';

class PollCard extends StatefulWidget {
  const PollCard({
    super.key,
    required this.poll,
    this.serviceOverride,
    this.currentUserId,
    this.onDeleted,
    this.onUpdated,
    this.canModerateDelete = false,
  });

  final Poll poll;

  /// Test seams — production resolves these via GetIt.
  final PollServiceInterface? serviceOverride;
  final String? currentUserId;
  final VoidCallback? onDeleted;
  final ValueChanged<Poll>? onUpdated;
  final bool canModerateDelete;

  @override
  State<PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<PollCard> {
  late Poll _poll = widget.poll;
  bool _submitting = false;

  @override
  void didUpdateWidget(covariant PollCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.poll != widget.poll) {
      _poll = widget.poll;
    }
  }

  PollServiceInterface? get _service =>
      widget.serviceOverride ??
      (GetIt.I.isRegistered<PollServiceInterface>()
          ? GetIt.I<PollServiceInterface>()
          : null);

  String? get _currentUserId =>
      widget.currentUserId ??
      (GetIt.I.isRegistered<AuthServiceInterface>()
          ? GetIt.I<AuthServiceInterface>().currentUserId
          : null);

  // Optimistic local upsert of my vote row (mirrors GatheringCard._respond).
  Poll _withMyVote(Poll p, String myId, List<String> optionIds) {
    final next = <Map<String, dynamic>>[
      for (final r in p.responses)
        if (r['userId']?.toString() != myId) Map<String, dynamic>.from(r),
      {'userId': myId, 'optionIds': optionIds},
    ];
    return p.copyWith(responses: next);
  }

  Future<void> _vote(String optionId) async {
    final service = _service;
    final myId = _currentUserId;
    if (service == null || myId == null || _submitting || _poll.isClosed) {
      return;
    }

    final previous = _poll;
    final current = previous.myVotedOptionIds(myId).toSet();
    final Set<String> next;
    if (previous.allowMultiple) {
      next = {...current};
      if (next.contains(optionId)) {
        next.remove(optionId);
      } else {
        next.add(optionId);
      }
      if (next.isEmpty) {
        await _withdrawVote();
        return;
      }
    } else {
      if (current.length == 1 && current.contains(optionId)) {
        await _withdrawVote();
        return;
      }
      next = {optionId};
    }
    final nextIds = next.toList();

    setState(() {
      _poll = _withMyVote(previous, myId, nextIds);
      _submitting = true;
    });
    try {
      final updated = await service.vote(previous.id, nextIds);
      if (!mounted) return;
      setState(() {
        _poll = updated;
        _submitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _poll = previous; // revert
        _submitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить голос')),
      );
    }
  }

  Poll _withoutMyVote(Poll p, String myId) {
    final next = <Map<String, dynamic>>[
      for (final r in p.responses)
        if (r['userId']?.toString() != myId) Map<String, dynamic>.from(r),
    ];
    return p.copyWith(responses: next);
  }

  Future<void> _withdrawVote() async {
    final service = _service;
    final myId = _currentUserId;
    if (service == null || myId == null || _submitting || _poll.isClosed) {
      return;
    }
    final previous = _poll;
    setState(() {
      _poll = _withoutMyVote(previous, myId);
      _submitting = true;
    });
    try {
      final updated = await service.withdrawVote(previous.id);
      if (!mounted) return;
      setState(() {
        _poll = updated;
        _submitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _poll = previous;
        _submitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось снять голос')),
      );
    }
  }

  Future<void> _editPoll() async {
    final service = _service;
    if (service == null) return;
    final result = await showDialog<_PollEditResult>(
      context: context,
      builder: (_) => _PollEditDialog(
        initialQuestion: _poll.question,
        initialClosesAt: _poll.closesAt,
      ),
    );
    if (result == null || !mounted) return;

    try {
      final updated = await service.updatePoll(
        pollId: _poll.id,
        question: result.question,
        closesAt: result.clearClosesAt ? null : result.closesAt,
        clearClosesAt: result.clearClosesAt,
      );
      if (!mounted) return;
      setState(() => _poll = updated);
      widget.onUpdated?.call(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Опрос обновлён')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            humanizeError(e, fallback: 'Не удалось обновить опрос.'),
          ),
        ),
      );
    }
  }

  Future<void> _closePollEarly() async {
    final service = _service;
    if (service == null || _poll.isClosed) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Завершить опрос досрочно?'),
        content: const Text(
          'Новые голоса перестанут приниматься, результаты останутся видны.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const Key('poll-close-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Завершить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final updated = await service.updatePoll(
        pollId: _poll.id,
        closeNow: true,
      );
      if (!mounted) return;
      setState(() => _poll = updated);
      widget.onUpdated?.call(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Опрос завершён')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            humanizeError(e, fallback: 'Не удалось завершить опрос.'),
          ),
        ),
      );
    }
  }

  Future<void> _deletePoll() async {
    final service = _service;
    if (service == null) return;
    final confirmed = await showSafeDeleteConfirmation(
      context,
      title: 'Удалить опрос?',
      body: 'Опрос и все голоса исчезнут у всех участников семьи.',
    );
    if (!confirmed || !mounted) return;
    try {
      await service.deletePoll(_poll.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Опрос удалён')),
      );
      widget.onDeleted?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            humanizeError(e, fallback: 'Не удалось удалить опрос.'),
          ),
        ),
      );
    }
  }

  // Плотность (чанк 24): было padding: EdgeInsets.all(16) на весь
  // контейнер (16dp сверху и снизу впустую) — теперь локальный паддинг
  // на секцию (12 по бокам), как у GatheringCard/PostCard (чанки 24/20).
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return Container(
      key: Key('poll-card-${_poll.id}'),
      margin: EdgeInsets.only(bottom: tokens.space8),
      decoration: BoxDecoration(
        color: tokens.surfaceStrong,
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        border: Border.all(color: tokens.surfaceLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Плотность (чанк 24): вертикаль шапки 4/4 (было бы 8/8, как у
          // GatheringCard) — карточка опроса несёт 3 варианта под собой
          // и должна уложиться в ≤260dp целиком, бюджет плотнее.
          Padding(
            padding: EdgeInsets.fromLTRB(tokens.space12, 4, tokens.space8, 4),
            child: _buildHeader(theme, tokens),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
                tokens.space12, 0, tokens.space12, tokens.space4),
            child: Text(
              _poll.question,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.serif(
                color: tokens.ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
          if (_poll.renderableImageUrls.isNotEmpty) _buildPhotos(),
          Padding(
            padding: EdgeInsets.fromLTRB(
                tokens.space12, 0, tokens.space12, tokens.space8),
            child: _buildOptions(theme, tokens),
          ),
        ],
      ),
    );
  }

  // Плотность (чанк 24): шапка ≤56dp — тот же приём, что у GatheringCard:
  // дата публикации и аудитория объединены в одну строку метаданных
  // вместо отдельной строки-даты.
  Widget _buildHeader(ThemeData theme, RodnyaDesignTokens tokens) {
    final isAuthor = _currentUserId != null && _currentUserId == _poll.authorId;
    final canManage = isAuthor || widget.canModerateDelete;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAvatar(theme, tokens),
        SizedBox(width: tokens.space8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _poll.authorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.sans(
                  color: tokens.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 2),
              DefaultTextStyle.merge(
                style: AppTheme.sans(
                  color: tokens.inkMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        DateFormat('d MMMM', 'ru')
                            .format(toLocalForDisplay(_poll.createdAt)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('·'),
                    const SizedBox(width: 6),
                    Icon(_audienceIcon, size: 13, color: tokens.inkMuted),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _audienceLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: tokens.space8),
        _buildTypeBadge(theme, tokens),
        if (canManage) ...[
          const SizedBox(width: 2),
          SizedBox(
            width: 32,
            height: 32,
            child: PopupMenuButton<String>(
              key: Key('poll-menu-${_poll.id}'),
              padding: EdgeInsets.zero,
              iconSize: 18,
              icon: Icon(
                Icons.more_horiz_rounded,
                color: tokens.inkMuted,
                size: 18,
              ),
              onSelected: (value) {
                if (value == 'edit') {
                  _editPoll();
                } else if (value == 'close') {
                  _closePollEarly();
                } else if (value == 'delete') {
                  _deletePoll();
                }
              },
              itemBuilder: (_) => [
                if (isAuthor)
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 20),
                        SizedBox(width: 8),
                        Text('Редактировать'),
                      ],
                    ),
                  ),
                if (!_poll.isClosed)
                  const PopupMenuItem(
                    value: 'close',
                    child: Row(
                      children: [
                        Icon(Icons.lock_clock_outlined, size: 20),
                        SizedBox(width: 8),
                        Text('Завершить опрос'),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Text('Удалить', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String get _audienceLabel =>
      _poll.scopeType == TreeContentScopeType.branches ? 'Ветки' : 'Семья';

  IconData get _audienceIcon => _poll.scopeType == TreeContentScopeType.branches
      ? Icons.alt_route
      : Icons.eco_outlined;

  Widget _buildAvatar(ThemeData theme, RodnyaDesignTokens tokens) {
    final photo = _poll.renderableAuthorPhotoUrl;
    return Container(
      width: 40,
      height: 40,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tokens.accentSoft,
        shape: BoxShape.circle,
        border: Border.all(color: tokens.surfaceLine),
      ),
      child: photo != null && photo.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: photo,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _buildInitials(theme, tokens),
            )
          : _buildInitials(theme, tokens),
    );
  }

  Widget _buildInitials(ThemeData theme, RodnyaDesignTokens tokens) {
    final name = _poll.authorName.trim();
    final initial = name.isEmpty ? 'Р' : String.fromCharCode(name.runes.first);
    return Center(
      child: Text(
        initial.toUpperCase(),
        style: theme.textTheme.titleSmall?.copyWith(
          color: tokens.accent,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildTypeBadge(ThemeData theme, RodnyaDesignTokens tokens) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tokens.accentSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart_rounded, size: 14, color: tokens.accent),
          const SizedBox(width: 4),
          Text(
            'Опрос',
            style: theme.textTheme.labelSmall?.copyWith(
              color: tokens.accent,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotos() {
    final images = _poll.renderableImageUrls;
    return FeedMediaGallery(
      imageUrls: images,
      caption: _poll.question,
      captionPrefix: 'Фото опроса',
      // Плотность (чанк 24): контейнер больше не паддит всё целиком —
      // дефолтный инсет галереи (space12 бока+низ) не задваивается.
      onTap: (index) {
        MediaLightbox.show(
          context,
          items: [
            for (final url in images) MediaLightboxItem(imageUrl: url),
          ],
          initialIndex: index,
        );
      },
    );
  }

  // Плотность (чанк 24): «N голосов · до …» одной строкой 13sp — было
  // bodySmall (без явного размера) и без даты закрытия вовсе (closesAt
  // нигде не отображался, хотя модель его несёт).
  Widget _buildOptions(ThemeData theme, RodnyaDesignTokens tokens) {
    final total = _poll.totalVoters;
    final myVotes = _poll.myVotedOptionIds(_currentUserId).toSet();
    final closesAt = _poll.closesAt;
    final options = _poll.options;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Плотность (чанк 24): зазор МЕЖДУ строками (4dp), а не паддинг
        // «снизу у каждой» (было tokens.space8 на КАЖДЫЙ вариант,
        // включая последний, — лишние 8dp перед строкой голосов). Три
        // варианта по 44dp держат бюджет ≤260dp карточки.
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) SizedBox(height: tokens.space4),
          _buildOptionBar(theme, tokens, options[i], myVotes, total),
        ],
        SizedBox(height: tokens.space4),
        Row(
          children: [
            Expanded(
              child: Text(
                key: const Key('poll-vote-count'),
                '$total ${_votesWord(total)}'
                '${_poll.allowMultiple ? ' · можно несколько' : ''}'
                '${_poll.isClosed ? ' · Опрос завершён' : (closesAt != null ? ' · до ${DateFormat('d MMMM', 'ru').format(closesAt)}' : '')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.sans(
                  color: tokens.inkMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (!_poll.isClosed && myVotes.isNotEmpty)
              InkWell(
                key: Key('poll-withdraw-vote-${_poll.id}'),
                onTap: _submitting ? null : _withdrawVote,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    'Снять голос',
                    style: AppTheme.sans(
                      color: tokens.accent,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildOptionBar(
    ThemeData theme,
    RodnyaDesignTokens tokens,
    PollOption option,
    Set<String> myVotes,
    int total,
  ) {
    final votes = _poll.votesFor(option.id);
    final fraction = total == 0 ? 0.0 : votes / total;
    final percent = (fraction * 100).round();
    final selected = myVotes.contains(option.id);
    final radius = BorderRadius.circular(tokens.radiusSm);

    // Плотность (чанк 24): зазор между строками теперь ставит вызывающий
    // _buildOptions (SizedBox между элементами) — эта функция больше не
    // несёт собственный нижний отступ (см. комментарий там).
    return InkWell(
      key: Key('poll-option-${option.id}'),
      borderRadius: radius,
      onTap: (_submitting || _poll.isClosed) ? null : () => _vote(option.id),
      child: SizedBox(
        height: 44,
        child: Stack(
          children: [
            // Track.
            Container(
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: radius,
                border: Border.all(
                  color: selected ? tokens.accent : tokens.surfaceLine,
                  width: selected ? 1.4 : 1,
                ),
              ),
            ),
            // Percent fill.
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fraction.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: selected
                        ? tokens.accent.withValues(alpha: 0.22)
                        : tokens.accentSoft,
                    borderRadius: radius,
                  ),
                ),
              ),
            ),
            // Label + percent.
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? (_poll.allowMultiple
                              ? Icons.check_box_rounded
                              : Icons.radio_button_checked)
                          : (_poll.allowMultiple
                              ? Icons.check_box_outline_blank_rounded
                              : Icons.radio_button_unchecked),
                      size: 18,
                      color: selected ? tokens.accent : tokens.inkMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        option.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // Плотность (чанк 24): 16sp явно (было bodyMedium
                        // без гарантии ≥16sp) — вариант ответа это контент.
                        style: AppTheme.sans(
                          color: tokens.ink,
                          fontSize: 16,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$percent%',
                      // Плотность (чанк 24): 14sp явно (было labelMedium
                      // ≈12sp).
                      style: AppTheme.sans(
                        color: tokens.inkMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _votesWord(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod10 == 1 && mod100 != 11) return 'голос';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return 'голоса';
    }
    return 'голосов';
  }
}

class _PollEditResult {
  const _PollEditResult({
    required this.question,
    required this.closesAt,
    required this.clearClosesAt,
  });

  final String question;
  final DateTime? closesAt;
  final bool clearClosesAt;
}

class _PollEditDialog extends StatefulWidget {
  const _PollEditDialog({
    required this.initialQuestion,
    required this.initialClosesAt,
  });

  final String initialQuestion;
  final DateTime? initialClosesAt;

  @override
  State<_PollEditDialog> createState() => _PollEditDialogState();
}

class _PollEditDialogState extends State<_PollEditDialog> {
  late final TextEditingController _questionController =
      TextEditingController(text: widget.initialQuestion);
  late DateTime? _selectedClosesAt = widget.initialClosesAt;
  bool _clearClosesAt = false;
  String? _errorText;

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Редактировать опрос'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('poll-edit-question-field'),
            controller: _questionController,
            minLines: 1,
            maxLines: 4,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Вопрос',
              errorText: _errorText,
            ),
            onChanged: (_) {
              if (_errorText != null) {
                setState(() => _errorText = null);
              }
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _selectedClosesAt == null
                      ? 'Без даты завершения'
                      : 'До ${DateFormat('d MMMM yyyy', 'ru').format(toLocalForDisplay(_selectedClosesAt!))}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedClosesAt != null &&
                            _selectedClosesAt!.isAfter(now)
                        ? _selectedClosesAt!
                        : now.add(const Duration(days: 7)),
                    firstDate: now,
                    lastDate: now.add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() {
                      _selectedClosesAt = DateTime(
                        picked.year,
                        picked.month,
                        picked.day,
                        23,
                        59,
                      );
                      _clearClosesAt = false;
                    });
                  }
                },
                child: const Text('Срок'),
              ),
              if (_selectedClosesAt != null)
                IconButton(
                  tooltip: 'Убрать срок',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    setState(() {
                      _selectedClosesAt = null;
                      _clearClosesAt = true;
                    });
                  },
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const Key('poll-edit-save-button'),
          onPressed: () {
            final trimmed = _questionController.text.trim();
            if (trimmed.isEmpty) {
              setState(() => _errorText = 'Введите вопрос опроса');
              return;
            }
            Navigator.of(context).pop(
              _PollEditResult(
                question: trimmed,
                closesAt: _selectedClosesAt,
                clearClosesAt: _clearClosesAt,
              ),
            );
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
