part of '../create_post_screen.dart';

extension _CreatePostSections on _CreatePostScreenState {
  Widget _buildComposeToolDock({required bool compact}) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 24,
        0,
        compact ? 12 : 24,
        compact ? 12 : 18,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: GlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          color: tokens.surfaceStrong.withValues(alpha: 0.94),
          borderColor: tokens.surfaceLine,
          child: Row(
            children: [
              _buildToolButton(
                icon: Icons.add_photo_alternate_outlined,
                label: _selectedMedia.isEmpty
                    ? 'Медиа'
                    : '${_selectedMedia.length}/$kMaxPostMedia',
                active: _selectedMedia.isNotEmpty,
                onPressed: _openMediaPicker,
              ),
              _buildToolButton(
                icon: Icons.group_work_outlined,
                label: 'Кому',
                active: _selectedCircleId != null,
                onPressed: _showAudienceSheet,
              ),
              _buildToolButton(
                icon: Icons.alt_route_outlined,
                label: _isFriendsTree ? 'Круги' : 'Ветки',
                active: _scopeType == TreeContentScopeType.branches,
                onPressed: () {
                  _updateCreatePostState(() {
                    _scopeType = TreeContentScopeType.branches;
                  });
                  _showAudienceSheet();
                },
              ),
              _buildToolButton(
                icon: _isPublic ? Icons.public : Icons.lock_outline,
                label: _isPublic ? 'Публично' : 'Внутри',
                active: _isPublic,
                onPressed: () {
                  _updateCreatePostState(() {
                    _isPublic = !_isPublic;
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final foreground = active ? tokens.accentStrong : tokens.inkSecondary;

    return Expanded(
      child: Material(
        color: active ? tokens.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: foreground, size: 21),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPresetTilesRow(
    ThemeData theme,
    RodnyaDesignTokens tokens,
    StateSetter? sheetSetState,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _audiencePresets.presets.map((preset) {
        final selected = _selectedPresetKey == preset.key;
        final memberCount = preset.personIds.length;
        return InkWell(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          onTap: () => _applyAudiencePreset(preset, sheetSetState),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            constraints: const BoxConstraints(minWidth: 140),
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: selected ? tokens.accentSoft : tokens.surfaceStrong,
              borderRadius: BorderRadius.circular(tokens.radiusMd),
              border: Border.all(
                color: selected ? tokens.accent : tokens.surfaceLine,
                width: selected ? 1.4 : 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  preset.key == 'core_family'
                      ? Icons.diversity_3_outlined
                      : Icons.groups_2_outlined,
                  color: selected ? tokens.accent : tokens.inkSecondary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      preset.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: tokens.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$memberCount ${_memberLabel(memberCount).split(' ').last}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEditorCard({required bool compact}) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return GlassPanel(
      padding: EdgeInsets.all(compact ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAuthorRow(compact: compact),
          const SizedBox(height: 14),
          // Q6: the compact (mobile) editor shows just the audience summary
          // + «Изменить»; the wide layout already has the full audience
          // panel in the side column, so the summary would be redundant.
          if (compact) ...[
            _buildAudienceSummaryRow(),
            const SizedBox(height: 12),
          ],
          // Reference compose textarea is transparent — no border, no bg, just
          // text inside the outer card. Drop the inner DecoratedBox so the
          // input reads like the jsx prototype (placeholder font 17px, fluid
          // line-height 1.45, accent cursor).
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 4 : 6,
              vertical: compact ? 4 : 6,
            ),
            child: TextField(
              controller: _contentController,
              decoration: InputDecoration(
                hintText: 'О чём хотите рассказать родне?',
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isCollapsed: true,
                hintStyle: AppTheme.sans(
                  color: tokens.inkMuted,
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  height: 1.45,
                ),
              ),
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              maxLines: compact ? 9 : 12,
              minLines: compact ? 7 : 10,
              cursorColor: tokens.accent,
              style: AppTheme.sans(
                color: tokens.ink,
                fontSize: 17,
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
          ),
          // Visible media slot. Was previously rendered only when the
          // user had attached something, which made the "Фото"/"Медиа"
          // toolbar button feel disconnected — user said: "не
          // интуитивно понятно где фото то прикладывается". The empty
          // hint card reserves the space and re-opens the picker on
          // tap, so the user can see ahead of time where media will
          // land.
          const SizedBox(height: 12),
          if (_selectedMedia.isEmpty)
            _buildMediaEmptyHint()
          else
            _buildMediaPreviews(),
        ],
      ),
    );
  }

  Widget _buildAuthorRow({required bool compact}) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return Row(
      children: [
        _buildAuthorAvatar(),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _authorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: tokens.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _selectedAudienceDetail,
                maxLines: compact ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.inkSecondary,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: _showAudienceSheet,
          icon: const Icon(Icons.expand_more, size: 18),
          label: Text(_selectedAudienceLabel),
        ),
      ],
    );
  }

  Widget _buildAuthorAvatar() {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final photoUrl = _authService.currentUserPhotoUrl?.trim();

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: tokens.accentSoft,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: tokens.surfaceLine),
      ),
      clipBehavior: Clip.antiAlias,
      child: photoUrl != null && photoUrl.isNotEmpty
          ? Image.network(
              photoUrl,
              fit: BoxFit.cover,
              // Author avatar — the post card's name row already
              // identifies who's posting, so the image itself is
              // decorative for a screen-reader user.
              excludeFromSemantics: true,
              errorBuilder: (_, __, ___) => _buildAuthorInitials(tokens),
            )
          : _buildAuthorInitials(tokens),
    );
  }

  Widget _buildAuthorInitials(RodnyaDesignTokens tokens) {
    return Center(
      child: Text(
        _authorInitials,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: tokens.accentStrong,
              fontWeight: FontWeight.w900,
            ),
      ),
    );
  }

  String get _authorName {
    final displayName = _authService.currentUserDisplayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    final email = _authService.currentUserEmail?.trim();
    if (email != null && email.isNotEmpty) {
      return email.split('@').first;
    }
    return 'Родня';
  }

  String get _authorInitials {
    final words =
        _authorName.split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
    final initials = words
        .take(2)
        .map((word) => String.fromCharCode(word.runes.first).toUpperCase())
        .join();
    return initials.isEmpty ? 'Р' : initials;
  }

  Widget _buildMissingTreeState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: GlassPanel(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Сначала выберите дерево',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Сначала выберите дерево, чтобы было понятно, кому показывать публикацию.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => context.go('/trees'),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Выбрать дерево'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComposeTopbar({
    required ThemeData theme,
    required RodnyaDesignTokens tokens,
  }) {
    // Q1: nothing to publish until there's text or at least one media item.
    final hasContent =
        _contentController.text.trim().isNotEmpty || _selectedMedia.isNotEmpty;
    final canPublish = !_isLoading && _currentTreeId != null && hasContent;
    // Same Android perf bypass as other topbars.
    final useBlur = defaultTargetPlatform != TargetPlatform.android;
    final body = Container(
      decoration: BoxDecoration(
        color: tokens.surface.withValues(
          alpha: theme.brightness == Brightness.dark
              ? (useBlur ? 0.74 : 0.96)
              : (useBlur ? 0.78 : 0.97),
        ),
        border: Border(
          bottom: BorderSide(
            color: tokens.surfaceLine.withValues(alpha: 0.5),
            width: 0.6,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: AppTheme.topbarContentHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 3, 12, 3),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back_rounded, color: tokens.ink),
                  tooltip: 'Назад',
                  onPressed: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  },
                ),
                const SizedBox(width: 4),
                Text(
                  'Новый пост',
                  style: AppTheme.serif(
                    color: tokens.ink,
                    fontSize: AppTheme.tabTitleFontSize,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.22,
                  ),
                ),
                const Spacer(),
                Material(
                  color: canPublish ? tokens.accent : tokens.surfaceLine,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: canPublish ? _createPost : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      child: _isLoading
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    // Детерминированный бар, когда файлов
                                    // несколько и хоть один уже долетел; иначе
                                    // честнее крутилка, чем застывший 0%.
                                    value: _uploadProgress?.value,
                                    color: tokens.accentInk,
                                  ),
                                ),
                                if (_uploadProgressLabel != null) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    _uploadProgressLabel!,
                                    style: AppTheme.sans(
                                      color: tokens.accentInk,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ],
                            )
                          : Text(
                              'Опубликовать',
                              style: AppTheme.sans(
                                color: canPublish
                                    ? tokens.accentInk
                                    : tokens.inkMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!useBlur) return body;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: body,
      ),
    );
  }
}
