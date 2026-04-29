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
              Positioned(
                top: 12,
                left: 12,
                child: _buildViewportStatusBar(),
              ),
              Positioned(
                right: 12,
                bottom: 12,
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
            ),
          ),
          ..._buildPersonWidgets(),
          if (widget.isEditMode)
            _buildInlineEditPanel(
              stackWidth: stackWidth,
              stackHeight: stackHeight,
            ),
        ],
      ),
    );
  }
}
