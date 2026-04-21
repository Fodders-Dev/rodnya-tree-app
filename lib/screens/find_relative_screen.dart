import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend/backend_runtime_config.dart';
import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/profile_service_interface.dart';
import '../models/family_relation.dart';
import '../models/user_profile.dart';
import '../services/app_status_service.dart';
import '../utils/user_facing_error.dart';
import '../widgets/glass_panel.dart';

class FindRelativeScreen extends StatefulWidget {
  const FindRelativeScreen({
    super.key,
    required this.treeId,
    this.initialProfileCode,
  });

  final String treeId;
  final String? initialProfileCode;

  @override
  State<FindRelativeScreen> createState() => _FindRelativeScreenState();
}

class _FindRelativeScreenState extends State<FindRelativeScreen>
    with TickerProviderStateMixin {
  final AuthServiceInterface _authService = GetIt.I<AuthServiceInterface>();
  final FamilyTreeServiceInterface _familyTreeService =
      GetIt.I<FamilyTreeServiceInterface>();
  final ProfileServiceInterface _profileService =
      GetIt.I<ProfileServiceInterface>();
  final AppStatusService _appStatusService = GetIt.I<AppStatusService>();

  late final TabController _tabController;
  final _searchEmailController = TextEditingController();
  final _searchUsernameController = TextEditingController();
  final _searchProfileCodeController = TextEditingController();
  final _inviteLinkController = TextEditingController();

  List<UserProfile> _searchResults = [];
  bool _isLoading = false;
  bool _isInviteLinkOpening = false;
  String? _searchFeedbackMessage;
  bool _searchFailed = false;
  RelationType? _selectedRelation;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        return;
      }
      setState(() {
        _searchResults = [];
        _searchFeedbackMessage = null;
        _searchFailed = false;
      });
    });
    final initialProfileCode = widget.initialProfileCode?.trim() ?? '';
    if (initialProfileCode.isNotEmpty) {
      _searchProfileCodeController.text = initialProfileCode.startsWith('@')
          ? initialProfileCode
          : '@$initialProfileCode';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _tabController.animateTo(2);
        _searchByProfileCode();
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchEmailController.dispose();
    _searchUsernameController.dispose();
    _searchProfileCodeController.dispose();
    _inviteLinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Найти родственника'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Email'),
            Tab(text: 'Никнейм'),
            Tab(text: 'Код'),
            Tab(text: 'Приглашение'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSearchTab(
            controller: _searchEmailController,
            labelText: 'Email пользователя',
            hintText: 'example@mail.ru',
            icon: Icons.email_outlined,
            helperText:
                'Ищите тех, у кого уже есть аккаунт в Родне. Телефон для поиска больше не используется.',
            onSearch: () => _searchByField(
              field: 'email',
              value: _searchEmailController.text.trim(),
              notFoundMessage: 'Пользователь с таким email не найден в Родне.',
            ),
          ),
          _buildSearchTab(
            controller: _searchUsernameController,
            labelText: 'Никнейм пользователя',
            hintText: '@username',
            icon: Icons.alternate_email_outlined,
            helperText:
                'Если человек уже зарегистрирован, проще всего найти его по username.',
            onSearch: () => _searchByField(
              field: 'username',
              value: _searchUsernameController.text.trim(),
              notFoundMessage:
                  'Пользователь с таким никнеймом не найден в Родне.',
            ),
          ),
          _buildSearchTab(
            controller: _searchProfileCodeController,
            labelText: 'Профильный код',
            hintText: '@rodnya-code',
            icon: Icons.qr_code_2_rounded,
            helperText:
                'Профильный код и QR ведут в тот же сценарий, что и username. Это быстрый способ связать родственника именно с этим деревом.',
            onSearch: _searchByProfileCode,
          ),
          _buildInviteTab(),
        ],
      ),
    );
  }

  Future<void> _searchByField({
    required String field,
    required String value,
    required String notFoundMessage,
  }) async {
    final normalizedValue = value.trim();
    if (normalizedValue.isEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
      _searchResults = [];
      _searchFeedbackMessage = null;
      _searchFailed = false;
    });

    try {
      final results = await _profileService.searchUsersByField(
        field: field,
        value: normalizedValue,
        limit: 10,
      );
      final availableResults = await _filterAvailableUsers(results);

      if (!mounted) {
        return;
      }
      setState(() {
        _searchResults = availableResults;
        _isLoading = false;
        _searchFeedbackMessage =
            availableResults.isEmpty ? notFoundMessage : null;
        _searchFailed = false;
      });
    } catch (error) {
      _appStatusService.reportError(
        error,
        fallbackMessage: 'Не удалось выполнить поиск.',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _searchFailed = true;
        _searchFeedbackMessage = describeUserFacingError(
          authService: _authService,
          error: error,
          fallbackMessage: _appStatusService.isOffline
              ? 'Нет соединения. Поиск заработает, когда интернет вернётся.'
              : 'Не удалось выполнить поиск. Попробуйте ещё раз.',
        );
      });
    }
  }

  Future<void> _shareAppLink() async {
    final publicAppUrl = BackendRuntimeConfig.current.publicAppUrl;
    final profileCode = _searchProfileCodeController.text.trim();
    await Share.share(
      'Присоединяйтесь к Родне по ссылке: $publicAppUrl\n\n'
      'Если у вас уже есть аккаунт, меня можно найти по email, username или профильному коду'
      '${profileCode.isEmpty ? '' : ' $profileCode'}. '
      'Если аккаунта ещё нет, откройте invite/claim ссылку или QR.',
    );
  }

  Future<void> _searchByProfileCode() async {
    final rawValue = _searchProfileCodeController.text.trim();
    final normalizedValue = rawValue.replaceFirst('@', '').trim();
    await _searchByField(
      field: 'username',
      value: normalizedValue,
      notFoundMessage:
          'Пользователь с таким профильным кодом не найден в Родне.',
    );
  }

  Future<void> _copyInviteLink() async {
    final publicAppUrl = BackendRuntimeConfig.current.publicAppUrl;
    await Clipboard.setData(ClipboardData(text: publicAppUrl));
    if (!mounted) {
      return;
    }
    _showMessage('Ссылка на Родню скопирована.');
  }

  Future<void> _openInviteOrClaimLink() async {
    final rawValue = _inviteLinkController.text.trim();
    if (rawValue.isEmpty) {
      _showMessage('Вставьте invite или claim ссылку.');
      return;
    }

    setState(() {
      _isInviteLinkOpening = true;
    });

    try {
      Uri? uri = Uri.tryParse(rawValue);
      if (uri == null || (!uri.hasScheme && !rawValue.startsWith('/'))) {
        final baseUri = Uri.parse(BackendRuntimeConfig.current.publicAppUrl);
        uri = baseUri.replace(
          path: rawValue.startsWith('/') ? rawValue : '/$rawValue',
        );
      } else if (!uri.hasScheme && rawValue.startsWith('/')) {
        uri = Uri.parse(rawValue);
      }

      if (!uri.hasScheme && mounted) {
        context.push(uri.toString());
      } else {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.platformDefault,
          webOnlyWindowName: '_self',
        );
        if (!launched) {
          throw Exception('Не удалось открыть ссылку');
        }
      }
    } catch (error) {
      _appStatusService.reportError(
        error,
        fallbackMessage: 'Не удалось открыть ссылку.',
      );
      if (!mounted) {
        return;
      }
      _showMessage(
        describeUserFacingError(
          authService: _authService,
          error: error,
          fallbackMessage:
              'Не удалось открыть ссылку. Проверьте формат и попробуйте ещё раз.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isInviteLinkOpening = false;
        });
      }
    }
  }

  Future<List<UserProfile>> _filterAvailableUsers(
    List<UserProfile> users,
  ) async {
    final currentUserId = _authService.currentUserId;
    final relatives = await _familyTreeService.getRelatives(widget.treeId);
    final existingUserIds = relatives
        .map((person) => person.userId)
        .whereType<String>()
        .where((userId) => userId.isNotEmpty)
        .toSet();

    return users.where((user) {
      if (user.id.isEmpty) {
        return false;
      }
      if (user.id == currentUserId) {
        return false;
      }
      return !existingUserIds.contains(user.id);
    }).toList();
  }

  Future<void> _sendRelationRequest(
    UserProfile user,
    RelationType relationType,
  ) async {
    if (user.id.isEmpty) {
      _showMessage('Информация о пользователе пока недоступна.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final currentUserId = _authService.currentUserId;
      if (currentUserId == null) {
        throw Exception('Вы не авторизованы');
      }

      final hasPendingRequest =
          await _familyTreeService.hasPendingRelationRequest(
        treeId: widget.treeId,
        senderId: currentUserId,
        recipientId: user.id,
      );

      if (!mounted) {
        return;
      }
      if (hasPendingRequest) {
        setState(() {
          _isLoading = false;
        });

        _showMessage('Запрос этому человеку уже отправлен.');
        return;
      }

      await _familyTreeService.sendRelationRequest(
        treeId: widget.treeId,
        recipientId: user.id,
        relationType: relationType,
        message: 'Запрос на подтверждение родственной связи',
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });

      _showMessage('Запрос отправлен.');

      context.pop();
    } catch (error) {
      _appStatusService.reportError(
        error,
        fallbackMessage: 'Не удалось отправить запрос на связь.',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });

      _showMessage(
        describeUserFacingError(
          authService: _authService,
          error: error,
          fallbackMessage: _appStatusService.isOffline
              ? 'Нет соединения. Запрос можно будет отправить, когда интернет вернётся.'
              : 'Не удалось отправить запрос. Попробуйте ещё раз.',
        ),
      );
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

  Widget _buildSearchTab({
    required TextEditingController controller,
    required String labelText,
    required String hintText,
    required IconData icon,
    required String helperText,
    required VoidCallback onSearch,
    String? emptyStateMessage,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            helperText,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: labelText,
              hintText: hintText,
              prefixIcon: Icon(icon),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: onSearch,
              ),
            ),
            keyboardType: labelText.contains('Email')
                ? TextInputType.emailAddress
                : TextInputType.text,
            onSubmitted: (_) => onSearch(),
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            Expanded(
              child: _buildSearchStateCard(
                icon: Icons.sync,
                title: 'Ищем в Родне',
                message:
                    'Проверяем аккаунты по email, username или профильному коду.',
                showProgress: true,
              ),
            )
          else if (_searchResults.isNotEmpty)
            Expanded(
              child: ListView.builder(
                itemCount: _searchResults.length,
                itemBuilder: (context, index) =>
                    _buildUserCard(_searchResults[index]),
              ),
            )
          else if (_searchFeedbackMessage != null)
            Expanded(
              child: _buildSearchStateCard(
                icon: _searchFailed
                    ? (_appStatusService.isOffline
                        ? Icons.cloud_off_outlined
                        : Icons.sync_problem_outlined)
                    : Icons.search_off_outlined,
                title: _searchFailed
                    ? (_appStatusService.isOffline
                        ? 'Нет соединения'
                        : 'Поиск временно недоступен')
                    : 'Совпадений пока нет',
                message: _searchFeedbackMessage!,
                actions: [
                  if (_searchFailed)
                    FilledButton.icon(
                      onPressed: () {
                        _appStatusService.requestRetry();
                        onSearch();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Повторить'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () {
                      controller.clear();
                      setState(() {
                        _searchResults = [];
                        _searchFeedbackMessage = null;
                        _searchFailed = false;
                      });
                    },
                    icon: const Icon(Icons.close),
                    label: const Text('Очистить'),
                  ),
                ],
              ),
            )
          else
            Expanded(
              child: _buildSearchStateCard(
                icon: Icons.person_search_outlined,
                title: 'Найти аккаунт в Родне',
                message: emptyStateMessage ??
                    'Введите email, username или профильный код, чтобы связать уже зарегистрированного родственника с этим деревом.',
                actions: [
                  FilledButton.tonalIcon(
                    onPressed: onSearch,
                    icon: const Icon(Icons.search),
                    label: const Text('Искать'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchStateCard({
    required IconData icon,
    required String title,
    required String message,
    bool showProgress = false,
    List<Widget> actions = const <Widget>[],
  }) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: GlassPanel(
          padding: const EdgeInsets.all(24),
          borderRadius: BorderRadius.circular(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: showProgress
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : Icon(
                        icon,
                        size: 28,
                        color: theme.colorScheme.primary,
                      ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInviteTab() {
    final publicAppUrl = BackendRuntimeConfig.current.publicAppUrl;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Без поиска по телефону',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Теперь доверие строится не на SMS и не на телефонной книге. '
                  'Уже зарегистрированных людей ищите по email, username или профильному коду, '
                  'а для новых используйте invite link, claim link или QR.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Открыть invite или claim ссылку',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Если родственник уже прислал вам invite/claim ссылку или QR, '
                  'вставьте ссылку сюда и откройте её прямо из приложения.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _inviteLinkController,
                  decoration: const InputDecoration(
                    labelText: 'Invite или claim ссылка',
                    hintText: 'https://rodnya-tree.ru/invite?...',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.link_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isInviteLinkOpening
                            ? null
                            : _openInviteOrClaimLink,
                        icon: _isInviteLinkOpening
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.open_in_new_outlined),
                        label: Text(
                          _isInviteLinkOpening
                              ? 'Открываем...'
                              : 'Открыть ссылку',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Профильный код',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Если родственник прислал только короткий код или QR, откройте вкладку "Код" и введите его вручную. QR всегда приводит в этот же сценарий поиска.',
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => _tabController.animateTo(2),
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: const Text('Открыть поиск по коду'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Поделиться Роднёй',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                SelectableText(publicAppUrl),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _copyInviteLink,
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('Скопировать'),
                    ),
                    FilledButton.icon(
                      onPressed: _shareAppLink,
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Поделиться'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Если у родственника нет аккаунта, можно сначала создать его карточку в дереве, а потом уже отправить личную invite-ссылку из этой карточки.',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () =>
                      context.push('/relatives/add/${widget.treeId}'),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Добавить карточку родственника'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUserCard(
    UserProfile user, {
    String? subtitle,
  }) {
    final displayName = user.displayName.isNotEmpty
        ? user.displayName
        : (user.firstName.isNotEmpty
            ? '${user.firstName} ${user.lastName}'.trim()
            : 'Пользователь');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage:
              user.photoURL != null ? NetworkImage(user.photoURL!) : null,
          child: user.photoURL == null
              ? Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                )
              : null,
        ),
        title: Text(displayName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitle != null && subtitle.isNotEmpty) Text(subtitle),
            if (user.email.isNotEmpty) Text(user.email),
            if (user.username.isNotEmpty)
              Text(
                '@${user.username}',
                style: const TextStyle(color: Colors.blue),
              ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.add_circle_outline, color: Colors.green),
          onPressed: () => _showRelationSelectDialog(user),
        ),
      ),
    );
  }

  Widget _buildRelationTypeDropdown() {
    return DropdownButtonFormField<RelationType>(
      initialValue: _selectedRelation,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      hint: const Text('Выберите тип связи'),
      isExpanded: true,
      items: const [
        DropdownMenuItem(value: RelationType.parent, child: Text('Родитель')),
        DropdownMenuItem(value: RelationType.child, child: Text('Ребенок')),
        DropdownMenuItem(value: RelationType.spouse, child: Text('Супруг(а)')),
        DropdownMenuItem(
          value: RelationType.sibling,
          child: Text('Брат/сестра'),
        ),
        DropdownMenuItem(
          value: RelationType.cousin,
          child: Text('Двоюродный брат/сестра'),
        ),
        DropdownMenuItem(value: RelationType.uncle, child: Text('Дядя')),
        DropdownMenuItem(value: RelationType.aunt, child: Text('Тётя')),
        DropdownMenuItem(
          value: RelationType.grandparent,
          child: Text('Бабушка/дедушка'),
        ),
        DropdownMenuItem(
          value: RelationType.grandchild,
          child: Text('Внук/внучка'),
        ),
      ],
      onChanged: (value) {
        setState(() {
          _selectedRelation = value;
        });
      },
    );
  }

  void _showRelationSelectDialog(UserProfile user) {
    setState(() {
      _selectedRelation = null;
    });
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Выберите тип родственной связи'),
        content: _buildRelationTypeDropdown(),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              if (_selectedRelation == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Сначала выберите тип родства'),
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext);
              _sendRelationRequest(user, _selectedRelation!);
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }
}
