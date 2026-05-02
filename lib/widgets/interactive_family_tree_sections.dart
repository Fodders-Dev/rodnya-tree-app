part of 'interactive_family_tree.dart';

extension _InteractiveFamilyTreeSections on _InteractiveFamilyTreeState {
  Widget _buildInteractiveTreeSurface({
    required BuildContext context,
    required double stackWidth,
    required double stackHeight,
    required double interactionBoundary,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          _syncViewportSize(Size(constraints.maxWidth, constraints.maxHeight));

          return Stack(
            clipBehavior: Clip.none,
            children: [
              _buildInteractiveCanvas(
                stackWidth: stackWidth,
                stackHeight: stackHeight,
                interactionBoundary: interactionBoundary,
              ),
              // Position canvas-internal overlays below the floating chrome
              // (toolbar + sidebar context column on mobile). The chrome
              // height is captured by `viewportReservedTop`; we sit the
              // overlay just under it so it never lives under the
              // toolbar pill.
              Positioned(
                top: widget.viewportReservedTop > 96
                    ? widget.viewportReservedTop + 8
                    : 12,
                left: 12,
                child: _buildViewportStatusBar(),
              ),
              Positioned(
                right: 12,
                top: widget.viewportReservedTop > 96
                    ? widget.viewportReservedTop + 8
                    : 92,
                child: _buildViewportControlDock(),
              ),
            ],
          );
        },
      ),
    );
  }

  void _syncViewportSize(Size viewportSize) {
    if (_viewportSize == viewportSize) {
      return;
    }
    _viewportSize = viewportSize;
    _hasAppliedViewportFit = false;
    _scheduleViewportFit();
  }

  Widget _buildInteractiveCanvas({
    required double stackWidth,
    required double stackHeight,
    required double interactionBoundary,
  }) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.equal): () => _zoomBy(1.2),
        const SingleActivator(LogicalKeyboardKey.numpadAdd): () => _zoomBy(1.2),
        const SingleActivator(LogicalKeyboardKey.minus): () => _zoomBy(1 / 1.2),
        const SingleActivator(LogicalKeyboardKey.numpadSubtract): () =>
            _zoomBy(1 / 1.2),
        const SingleActivator(LogicalKeyboardKey.digit0): () =>
            _fitTreeToViewport(),
      },
      child: Focus(
        autofocus: true,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onDoubleTap: _fitTreeToViewport,
          child: InteractiveViewer(
            transformationController: _transformationController,
            constrained: false,
            clipBehavior: Clip.none,
            boundaryMargin: EdgeInsets.all(interactionBoundary),
            panAxis: PanAxis.free,
            panEnabled: _draggingPersonId == null,
            scaleEnabled: true,
            trackpadScrollCausesScale: true,
            minScale: 0.08,
            maxScale: 3.5,
            child: _buildTreeContent(
              stackWidth: stackWidth,
              stackHeight: stackHeight,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTreeContent({
    required double stackWidth,
    required double stackHeight,
  }) {
    final tokens = Theme.of(context).extension<RodnyaDesignTokens>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    return SizedBox(
      width: stackWidth,
      height: stackHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (widget.showGenerationGuides)
            ..._buildGenerationGuideWidgets(stackWidth: stackWidth),
          CustomPaint(
            size: Size(stackWidth, stackHeight),
            painter: FamilyTreePainter(
              nodePositions,
              connections,
              graphSnapshot: widget.graphSnapshot,
              relations: widget.relations,
              lineColor: tokens.inkSecondary,
              mutedLineColor: tokens.inkMuted,
              spouseColor: tokens.warm,
              junctionColor: tokens.inkSecondary,
            ),
          ),
          if ((widget.selectedPersonId ?? '').isNotEmpty)
            CustomPaint(
              size: Size(stackWidth, stackHeight),
              painter: _SelectedTreePathPainter(
                nodePositions: nodePositions,
                relations: widget.relations,
                selectedPersonId: widget.selectedPersonId!,
                // Reference uses accent (deep teal/green) for active path
                // highlights — switch from warm so it reads as "selected"
                // rather than "warning".
                accent: tokens.accent,
              ),
            ),
          ..._buildPersonWidgets(),
          if (widget.isEditMode && widget.showInlineEditPanel)
            _buildInlineEditPanel(
              stackWidth: stackWidth,
              stackHeight: stackHeight,
            ),
        ],
      ),
    );
  }

  Widget _buildViewportStatusBar() {
    final tokens = Theme.of(context).extension<RodnyaDesignTokens>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final zoomPercent = (_currentScale * 100).round();
    // Stat duplication cleanup: people/relations counts already render in
    // the screen-level toolbar AND the "Карта рода" sidebar, so the canvas
    // overlay only keeps what's actually canvas-local — the tree-vs-circle
    // mode chip and the live zoom level.
    final chips = <Widget>[
      _buildOverlayChip(
        icon: widget.showGenerationGuides
            ? Icons.account_tree_outlined
            : Icons.diversity_3_outlined,
        label: widget.showGenerationGuides ? 'Семья' : 'Друзья',
        highlighted: true,
      ),
      _buildOverlayChip(
        icon: Icons.zoom_in_map_outlined,
        label: '$zoomPercent%',
      ),
    ];

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: min((_viewportSize?.width ?? 640) - 24, 640),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: tokens.surfaceStrong.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(
              color: tokens.surfaceLine.withValues(alpha: 0.9),
            ),
            boxShadow: tokens.panelShadow(
              Theme.of(context).brightness,
              floating: true,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                chips[i],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewportControlDock() {
    final tokens = Theme.of(context).extension<RodnyaDesignTokens>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final currentUserNodeId = _findCurrentUserNodeId();
    final branchRootPersonId = widget.branchRootPersonId;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: tokens.surfaceStrong.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(
          color: tokens.surfaceLine.withValues(alpha: 0.9),
        ),
        boxShadow: tokens.panelShadow(
          Theme.of(context).brightness,
          floating: true,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDockButton(
            icon: Icons.add,
            tooltip: 'Увеличить',
            onPressed: () => _zoomBy(1.2),
          ),
          const SizedBox(height: 6),
          _buildDockButton(
            icon: Icons.remove,
            tooltip: 'Уменьшить',
            onPressed: () => _zoomBy(1 / 1.2),
          ),
          const SizedBox(height: 6),
          _buildDockButton(
            icon: Icons.fit_screen_outlined,
            tooltip: 'Вписать дерево',
            onPressed: _fitTreeToViewport,
          ),
          if (currentUserNodeId != null) ...[
            const SizedBox(height: 6),
            _buildDockButton(
              icon: Icons.my_location_outlined,
              tooltip: 'Ко мне',
              onPressed: () => _focusOnPerson(currentUserNodeId),
            ),
          ],
          if (branchRootPersonId != null && branchRootPersonId.isNotEmpty) ...[
            const SizedBox(height: 6),
            _buildDockButton(
              icon: Icons.alt_route_outlined,
              tooltip: widget.showGenerationGuides ? 'К ветке' : 'К кругу',
              onPressed: () => _focusOnPerson(branchRootPersonId),
            ),
            if (widget.onBranchFocusCleared != null) ...[
              const SizedBox(height: 6),
              _buildDockButton(
                icon: Icons.clear_all,
                tooltip: widget.showGenerationGuides
                    ? 'Сбросить ветку'
                    : 'Сбросить круг',
                onPressed: widget.onBranchFocusCleared!,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildDockButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    final tokens = Theme.of(context).extension<RodnyaDesignTokens>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: tokens.surface.withValues(alpha: 0.96),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: tokens.accentStrong),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayChip({
    required IconData icon,
    required String label,
    bool highlighted = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<RodnyaDesignTokens>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlighted ? tokens.accentSoft : tokens.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: highlighted ? tokens.accent : tokens.surfaceLine,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color:
                      highlighted ? tokens.accentStrong : colorScheme.onSurface,
                ),
          ),
        ],
      ),
    );
  }
}
