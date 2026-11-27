import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../backend/interfaces/post_service_interface.dart';
import '../models/post.dart';
import '../theme/app_theme.dart';
import '../utils/user_facing_error.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/post_card.dart';

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({
    super.key,
    required this.postId,
    this.postServiceOverride,
  });

  final String postId;
  final PostServiceInterface? postServiceOverride;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  PostServiceInterface get _postService =>
      widget.postServiceOverride ?? GetIt.I<PostServiceInterface>();

  Post? _post;
  bool _isLoading = true;
  bool _notFound = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPost();
  }

  @override
  void didUpdateWidget(covariant PostDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postId != widget.postId) {
      _loadPost();
    }
  }

  Future<void> _loadPost() async {
    final trimmedId = widget.postId.trim();
    if (trimmedId.isEmpty) {
      setState(() {
        _post = null;
        _isLoading = false;
        _notFound = true;
        _error = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _notFound = false;
      _error = null;
    });

    try {
      final post = await _postService.getPost(trimmedId);
      if (!mounted) return;
      if (post == null) {
        setState(() {
          _post = null;
          _isLoading = false;
          _notFound = true;
        });
      } else {
        setState(() {
          _post = post;
          _isLoading = false;
          _notFound = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = humanizeError(
          e,
          fallback: 'Не удалось загрузить публикацию.',
        );
      });
    }
  }

  void _navigateBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  void _handleDeleted() {
    _navigateBack();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<RodnyaDesignTokens>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('post-detail-back'),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
          onPressed: _navigateBack,
        ),
        title: const Text('Публикация'),
      ),
      body: SafeArea(
        child: _buildBody(tokens),
      ),
    );
  }

  Widget _buildBody(RodnyaDesignTokens tokens) {
    if (_isLoading) {
      return const Center(child: LoadingIndicator());
    }

    if (_notFound) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(tokens.space16),
          child: EmptyStateWidget(
            icon: Icons.article_outlined,
            title: 'Публикация не найдена',
            message:
                'Возможно, автор удалил этот пост или у вас нет к нему доступа.',
            actionLabel: 'Вернуться в ленту',
            onAction: () => context.go('/'),
          ),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(tokens.space16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              EmptyStateWidget(
                icon: Icons.error_outline,
                title: 'Не удалось открыть пост',
                message: _error!,
                actionLabel: 'Повторить',
                onAction: _loadPost,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.go('/'),
                child: const Text('Вернуться в ленту'),
              ),
            ],
          ),
        ),
      );
    }

    final post = _post!;
    return RefreshIndicator(
      onRefresh: _loadPost,
      child: ListView(
        padding: EdgeInsets.all(tokens.space12),
        children: [
          PostCard(
            post: post,
            onUpdated: (updated) {
              if (!mounted) return;
              setState(() => _post = updated);
            },
            onDeleted: _handleDeleted,
          ),
        ],
      ),
    );
  }
}
