part of 'home_screen.dart';

class _HomeFeedEmptyViewState {
  const _HomeFeedEmptyViewState({
    required this.title,
    required this.message,
    required this.icon,
    this.actionLabel,
  });

  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
}

extension _HomeScreenSections on _HomeScreenState {
  _HomeFeedEmptyViewState get _feedEmptyViewState {
    if (_postsUnavailable) {
      return const _HomeFeedEmptyViewState(
        title: 'Лента недоступна',
        message: 'Обновите позже.',
        icon: Icons.cloud_off_outlined,
        actionLabel: 'Обновить',
      );
    }

    return const _HomeFeedEmptyViewState(
      title: 'Лента пуста',
      message: 'Новый пост можно создать из верхней кнопки.',
      icon: Icons.post_add_outlined,
    );
  }

  Future<void> _handleFeedEmptyAction() async {
    if (!_postsUnavailable) {
      return;
    }
    await _refreshCurrentPosts();
  }

  Future<void> _refreshCurrentPosts() async {
    final treeId = _currentTreeId;
    if (treeId == null) {
      return;
    }
    await _loadPosts(treeId);
  }

  double _eventCardWidthFor(BoxConstraints constraints) {
    final availableWidth = constraints.maxWidth;
    if (!availableWidth.isFinite || availableWidth <= 0) {
      return 220;
    }
    if (availableWidth < 360) {
      return (availableWidth - 8).clamp(176.0, 220.0);
    }
    if (availableWidth < 520) {
      return (availableWidth * 0.72).clamp(196.0, 236.0);
    }
    if (availableWidth < 760) {
      return (availableWidth * 0.46).clamp(210.0, 248.0);
    }
    return 232;
  }
}
