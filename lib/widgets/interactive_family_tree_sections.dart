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
                right: 12,
                top: widget.viewportReservedTop > 96
                    ? widget.viewportReservedTop + 8
                    : 92,
                child: _buildViewportControlDock(),
              ),
              // Small unobtrusive zoom indicator at the BOTTOM of the
              // canvas — replaces the previous "Семья / 250%" pill at
              // the top-left which the user said was overpowering.
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: IgnorePointer(
                  child: Center(child: _buildBottomZoomIndicator()),
                ),
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

  /// Small "75%" pill at the bottom of the canvas. Replaces the
  /// previous top-left "Семья / 250%" panel that was bigger than
  /// the user wanted. Hidden when scale is at the resting 100% to
  /// keep the canvas clean.
  Widget _buildBottomZoomIndicator() {
    final zoomPercent = (_currentScale * 100).round();
    if (zoomPercent == 100) return const SizedBox.shrink();
    final tokens = Theme.of(context).extension<RodnyaDesignTokens>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.surfaceStrong.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: tokens.surfaceLine.withValues(alpha: 0.6),
          width: 0.6,
        ),
      ),
      child: Text(
        '$zoomPercent%',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tokens.inkSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
              fontSize: 11,
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

    // Collapsed state: single chevron-pill that expands on tap. This
    // way the dock doesn't overlap person cards by default — the
    // canvas stays clean. Tap the chevron → animated expand to the
    // full vertical button column. Tap the close pill → collapse
    // back. Same TG / Maps "tools FAB" pattern.
    final expanded = _controlDockExpanded;
    final collapsedToggle = Tooltip(
      message: 'Настройки вида',
      child: Material(
        color: tokens.surfaceStrong.withValues(alpha: 0.92),
        shape: const CircleBorder(),
        elevation: 1.5,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _setControlDockExpanded(!expanded),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              expanded ? Icons.close_rounded : Icons.tune_rounded,
              size: 20,
              color: tokens.accentStrong,
            ),
          ),
        ),
      ),
    );

    if (!expanded) {
      return collapsedToggle;
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.all(6),
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
              icon: Icons.close_rounded,
              tooltip: 'Свернуть',
              onPressed: () => _setControlDockExpanded(false),
            ),
            const SizedBox(height: 4),
            _buildDockButton(
              icon: Icons.add,
              tooltip: 'Увеличить',
              onPressed: () => _zoomBy(1.2),
            ),
            const SizedBox(height: 4),
            _buildDockButton(
              icon: Icons.remove,
              tooltip: 'Уменьшить',
              onPressed: () => _zoomBy(1 / 1.2),
            ),
            const SizedBox(height: 4),
            _buildDockButton(
              icon: Icons.fit_screen_outlined,
              tooltip: 'Вписать дерево',
              onPressed: _fitTreeToViewport,
            ),
            if (currentUserNodeId != null) ...[
              const SizedBox(height: 4),
              _buildDockButton(
                icon: Icons.my_location_outlined,
                tooltip: 'Ко мне',
                onPressed: () => _focusOnPerson(currentUserNodeId),
              ),
            ],
            if (branchRootPersonId != null &&
                branchRootPersonId.isNotEmpty) ...[
              const SizedBox(height: 4),
              _buildDockButton(
                icon: Icons.alt_route_outlined,
                tooltip:
                    widget.showGenerationGuides ? 'К ветке' : 'К кругу',
                onPressed: () => _focusOnPerson(branchRootPersonId),
              ),
              if (widget.onBranchFocusCleared != null) ...[
                const SizedBox(height: 4),
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
          // Tighter button — was 44dp which made the vertical dock
          // ~280dp tall on mobile and overlapped person cards. 38dp
          // satisfies Android's 36dp tap-target floor + reads as a
          // quick action pill rather than a full FAB.
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, size: 18, color: tokens.accentStrong),
          ),
        ),
      ),
    );
  }

}
