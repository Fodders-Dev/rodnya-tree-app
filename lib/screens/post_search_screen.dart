import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../backend/interfaces/post_service_interface.dart';
import '../models/post.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/post_card.dart';
import '../widgets/post_card_shimmer.dart';

/// Substring search across post content + author name within the
/// active tree. Backend tokenises the query (Russian-locale lowercase,
/// up to 8 terms) and AND-matches against the post haystack — so
/// "детский сад" only finds posts containing both terms.
///
/// Debounced 320ms while typing so each keystroke doesn't hammer the
/// API. Empty input returns [Найти посты] hint state, no-results
/// returns the standard [EmptyStateWidget].
class PostSearchScreen extends StatefulWidget {
  const PostSearchScreen({super.key});

  @override
  State<PostSearchScreen> createState() => _PostSearchScreenState();
}

class _PostSearchScreenState extends State<PostSearchScreen> {
  final PostServiceInterface _postService = GetIt.I<PostServiceInterface>();
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  String _query = '';
  bool _loading = false;
  Object? _error;
  List<Post> _results = const <Post>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = const <Post>[];
        _loading = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 320), () {
      _runSearch(trimmed);
    });
  }

  Future<void> _runSearch(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Audience-mode search: hit the index across every branch
      // the viewer belongs to instead of narrowing to the active
      // BranchSwitcher selection. Mirror of the home feed default
      // — for the same reason: typing «свадьба» should find the
      // post regardless of which branch the user happens to have
      // selected when they remembered they wanted to look it up.
      final posts = await _postService.searchPosts(
        query: query,
      );
      if (!mounted || _query.trim() != query) return;
      setState(() {
        _results = posts;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return Scaffold(
      backgroundColor: tokens.bgBase,
      appBar: AppBar(
        backgroundColor: tokens.bgBase,
        elevation: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Поиск по постам',
            border: InputBorder.none,
            isDense: true,
            hintStyle: theme.textTheme.titleMedium?.copyWith(
              color: tokens.inkSecondary,
            ),
          ),
          style: theme.textTheme.titleMedium,
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Очистить',
              onPressed: () {
                _controller.clear();
                _onChanged('');
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _buildBody(theme, tokens),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, RodnyaDesignTokens tokens) {
    if (_query.trim().isEmpty) {
      return EmptyStateWidget(
        icon: Icons.search,
        title: 'Найти пост',
        message: 'Введите слово из поста или имя автора. '
            'Например: «зоопарк», «бабушка», «свадьба».',
      );
    }
    if (_loading && _results.isEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: 3,
        itemBuilder: (_, __) => const PostCardShimmer(),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 48, color: tokens.inkSecondary),
            const SizedBox(height: 12),
            Text(
              'Не удалось выполнить поиск: $_error',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.inkSecondary,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => _runSearch(_query.trim()),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Повторить'),
            ),
          ],
        ),
      );
    }
    if (_results.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.search_off,
        title: 'Ничего не нашли',
        message: 'Попробуйте другое слово или уберите часть запроса.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        return PostCard(post: _results[index]);
      },
    );
  }
}
