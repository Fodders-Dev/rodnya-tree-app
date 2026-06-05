// Phase E2c/E3b: feed card for a «Встреча» (Gathering). Mirrors PostCard's
// visual language (author header, audience chip, body) — no likes /
// comments / media. Phase E3b lights up the RSVP row (Да / Может / Нет)
// with an optimistic update, an optional headcount stepper, and a public
// tally, mirroring the post like/reaction toggle pattern.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';

import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/gathering_service_interface.dart';
import '../models/gathering.dart';
import '../models/post.dart' show TreeContentScopeType;
import '../theme/app_theme.dart';
import 'feed_media_gallery.dart';
import 'media_lightbox.dart';

class GatheringCard extends StatefulWidget {
  const GatheringCard({
    super.key,
    required this.gathering,
    this.serviceOverride,
    this.currentUserId,
  });

  final Gathering gathering;

  /// Test seams — production resolves these via GetIt.
  final GatheringServiceInterface? serviceOverride;
  final String? currentUserId;

  @override
  State<GatheringCard> createState() => _GatheringCardState();
}

class _GatheringCardState extends State<GatheringCard> {
  late Gathering _gathering = widget.gathering;
  late int _myHeadcount;
  bool _submitting = false;

  GatheringServiceInterface? get _service =>
      widget.serviceOverride ??
      (GetIt.I.isRegistered<GatheringServiceInterface>()
          ? GetIt.I<GatheringServiceInterface>()
          : null);

  String? get _currentUserId =>
      widget.currentUserId ??
      (GetIt.I.isRegistered<AuthServiceInterface>()
          ? GetIt.I<AuthServiceInterface>().currentUserId
          : null);

  @override
  void initState() {
    super.initState();
    _myHeadcount = _gathering.headcountFor(_currentUserId);
  }

  // Optimistic local upsert of my RSVP row (mirrors the post like toggle:
  // mutate now, reconcile/revert when the server answers).
  Gathering _withMyRsvp(
      Gathering g, String myId, String status, int headcount) {
    final next = <Map<String, dynamic>>[
      for (final r in g.rsvps)
        if (r['userId']?.toString() != myId) Map<String, dynamic>.from(r),
      {
        'userId': myId,
        'status': status,
        'headcount': status == 'yes' ? headcount : 0,
        'note': null,
        'respondedAt': null,
      },
    ];
    return g.copyWith(rsvps: next);
  }

  Future<void> _respond(String status) async {
    final service = _service;
    final myId = _currentUserId;
    if (service == null || myId == null || _submitting) return;

    final previous = _gathering;
    final headcount = status == 'yes' ? _myHeadcount : 0;
    setState(() {
      _gathering = _withMyRsvp(previous, myId, status, headcount);
      _submitting = true;
    });
    try {
      final updated =
          await service.setRsvp(previous.id, status, headcount: headcount);
      if (!mounted) return;
      setState(() {
        _gathering = updated;
        _myHeadcount = updated.headcountFor(myId);
        _submitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _gathering = previous; // revert
        _myHeadcount = previous.headcountFor(myId);
        _submitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить ответ')),
      );
    }
  }

  void _changeHeadcount(int delta) {
    final next = (_myHeadcount + delta).clamp(0, 99);
    if (next == _myHeadcount) return;
    setState(() => _myHeadcount = next);
    _respond('yes'); // persist the new headcount
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return Container(
      key: Key('gathering-card-${_gathering.id}'),
      margin: EdgeInsets.only(bottom: tokens.space12),
      padding: EdgeInsets.all(tokens.space16),
      decoration: BoxDecoration(
        color: tokens.surfaceStrong,
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        border: Border.all(color: tokens.surfaceLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(theme, tokens),
          SizedBox(height: tokens.space12),
          _buildBody(theme, tokens),
          if (_gathering.renderableImageUrls.isNotEmpty) ...[
            SizedBox(height: tokens.space12),
            _buildPhotos(tokens),
          ],
          SizedBox(height: tokens.space12),
          _buildRsvp(theme, tokens),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, RodnyaDesignTokens tokens) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAvatar(theme, tokens),
        SizedBox(width: tokens.space8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _gathering.authorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: tokens.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatPosted(_gathering.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.inkMuted,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: tokens.space8),
        _buildTypeBadge(theme, tokens),
      ],
    );
  }

  Widget _buildAvatar(ThemeData theme, RodnyaDesignTokens tokens) {
    final photo = _gathering.renderableAuthorPhotoUrl;
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
    final name = _gathering.authorName.trim();
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
          Icon(Icons.event_outlined, size: 14, color: tokens.accent),
          const SizedBox(width: 4),
          Text(
            'Встреча',
            style: theme.textTheme.labelSmall?.copyWith(
              color: tokens.accent,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme, RodnyaDesignTokens tokens) {
    final description = _gathering.description?.trim() ?? '';
    final place = _gathering.place?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _gathering.title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontFamily: 'Lora',
            fontWeight: FontWeight.w700,
            color: tokens.ink,
            height: 1.2,
          ),
        ),
        SizedBox(height: tokens.space8),
        _buildInfoRow(theme, tokens, Icons.schedule_outlined, _formatWhen()),
        if (place.isNotEmpty) ...[
          SizedBox(height: tokens.space4),
          _buildInfoRow(theme, tokens, Icons.place_outlined, place),
        ],
        SizedBox(height: tokens.space8),
        _buildAudienceChip(theme, tokens),
        if (description.isNotEmpty) ...[
          SizedBox(height: tokens.space12),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.ink,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoRow(
    ThemeData theme,
    RodnyaDesignTokens tokens,
    IconData icon,
    String text,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: tokens.accent),
        SizedBox(width: tokens.space8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAudienceChip(ThemeData theme, RodnyaDesignTokens tokens) {
    final label = _gathering.scopeType == TreeContentScopeType.branches
        ? 'Отдельные ветки'
        : 'Вся семья';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.group_outlined, size: 13, color: tokens.inkMuted),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: tokens.inkMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotos(RodnyaDesignTokens tokens) {
    final images = _gathering.renderableImageUrls;
    return FeedMediaGallery(
      imageUrls: images,
      caption: _gathering.title,
      captionPrefix: 'Фото встречи',
      // The card already pads its content (space16) — render edge-to-edge
      // within it instead of double-insetting.
      padding: EdgeInsets.zero,
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

  // ── RSVP (Phase E3b) ──

  Widget _buildRsvp(ThemeData theme, RodnyaDesignTokens tokens) {
    final myStatus = _gathering.myRsvpStatus(_currentUserId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildRsvpButton(theme, tokens, 'yes', 'Пойду', myStatus),
            SizedBox(width: tokens.space8),
            _buildRsvpButton(theme, tokens, 'maybe', 'Может', myStatus),
            SizedBox(width: tokens.space8),
            _buildRsvpButton(theme, tokens, 'no', 'Не пойду', myStatus),
          ],
        ),
        if (myStatus == 'yes') ...[
          SizedBox(height: tokens.space8),
          _buildHeadcountStepper(theme, tokens),
        ],
        SizedBox(height: tokens.space8),
        Text(
          key: const Key('gathering-rsvp-tally'),
          'Пойдут: ${_gathering.goingCount} · '
          'Может: ${_gathering.maybeCount} · '
          'Нет: ${_gathering.notGoingCount}',
          style: theme.textTheme.bodySmall?.copyWith(color: tokens.inkMuted),
        ),
      ],
    );
  }

  Widget _buildRsvpButton(
    ThemeData theme,
    RodnyaDesignTokens tokens,
    String status,
    String label,
    String? myStatus,
  ) {
    final selected = myStatus == status;
    return Expanded(
      child: Material(
        color: selected ? tokens.accent : tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        child: InkWell(
          key: Key('gathering-rsvp-$status'),
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          onTap: _submitting ? null : () => _respond(status),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              border: Border.all(
                color: selected ? tokens.accent : tokens.surfaceLine,
              ),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: selected ? tokens.accentInk : tokens.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeadcountStepper(ThemeData theme, RodnyaDesignTokens tokens) {
    return Row(
      children: [
        Expanded(
          child: Text(
            _myHeadcount == 0
                ? 'Приду один'
                : '+$_myHeadcount ${_peopleWord(_myHeadcount)} со мной',
            style: theme.textTheme.bodySmall?.copyWith(color: tokens.ink),
          ),
        ),
        IconButton(
          key: const Key('gathering-headcount-dec'),
          visualDensity: VisualDensity.compact,
          onPressed: _submitting || _myHeadcount == 0
              ? null
              : () => _changeHeadcount(-1),
          icon: const Icon(Icons.remove_circle_outline, size: 20),
        ),
        Text('$_myHeadcount', style: theme.textTheme.titleSmall),
        IconButton(
          key: const Key('gathering-headcount-inc'),
          visualDensity: VisualDensity.compact,
          onPressed: _submitting ? null : () => _changeHeadcount(1),
          icon: const Icon(Icons.add_circle_outline, size: 20),
        ),
      ],
    );
  }

  String _peopleWord(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod10 == 1 && mod100 != 11) return 'человек';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return 'человека';
    }
    return 'человек';
  }

  String _formatWhen() {
    final pattern = _gathering.isAllDay ? 'd MMMM y' : 'd MMMM y, HH:mm';
    final start = DateFormat(pattern, 'ru').format(_gathering.startAt);
    final end = _gathering.endAt;
    if (end == null) return start;
    final sameDay = end.year == _gathering.startAt.year &&
        end.month == _gathering.startAt.month &&
        end.day == _gathering.startAt.day;
    final endLabel = _gathering.isAllDay
        ? DateFormat('d MMMM y', 'ru').format(end)
        : sameDay
            ? DateFormat('HH:mm', 'ru').format(end)
            : DateFormat('d MMMM y, HH:mm', 'ru').format(end);
    return '$start — $endLabel';
  }

  String _formatPosted(DateTime createdAt) {
    return DateFormat('d MMMM', 'ru').format(createdAt);
  }
}
