// ignore_for_file: library_private_types_in_public_api
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/profile_service_interface.dart';
import '../models/family_person.dart';
import '../models/family_relation.dart';
import '../models/relation_request.dart';
import '../models/user_profile.dart';
import '../utils/photo_url.dart';

class RelationRequestsScreen extends StatefulWidget {
  final String treeId;

  const RelationRequestsScreen({super.key, required this.treeId});

  @override
  _RelationRequestsScreenState createState() => _RelationRequestsScreenState();
}

class _RelationRequestsScreenState extends State<RelationRequestsScreen> {
  final AuthServiceInterface _authService = GetIt.I<AuthServiceInterface>();
  final FamilyTreeServiceInterface _familyService =
      GetIt.I<FamilyTreeServiceInterface>();
  final ProfileServiceInterface _profileService =
      GetIt.I<ProfileServiceInterface>();

  List<RelationRequest> _incomingRequests = [];
  List<RelationRequest> _outgoingRequests = [];
  Map<String, UserProfile?> _userProfiles = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRequests();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final focusNode = FocusNode();
      FocusScope.of(context).requestFocus(focusNode);
      focusNode.addListener(() {
        if (focusNode.hasFocus) {
          _loadRequests();
        }
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent ?? false) {
      _loadRequests();
    }
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (_authService.currentUserId == null) {
        setState(() {
          _error = 'Пользователь не авторизован';
          _isLoading = false;
        });
        return;
      }

      final results = await Future.wait([
        _familyService.getPendingRelationRequests(treeId: widget.treeId),
        _familyService.getSentRelationRequests(treeId: widget.treeId),
      ]);
      final incoming = results[0];
      final outgoing = results[1];
      final profileIds = <String>{
        ...incoming.map((r) => r.senderId),
        ...outgoing.map((r) => r.recipientId),
      };
      final profiles = <String, UserProfile?>{};
      for (final userId in profileIds) {
        try {
          profiles[userId] = await _profileService.getUserProfile(userId);
        } catch (e) {
          debugPrint('Ошибка загрузки профиля $userId: $e');
          profiles[userId] = null;
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _incomingRequests = incoming;
        _outgoingRequests = outgoing;
        _userProfiles = profiles;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Ошибка при загрузке запросов: $e');
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Ошибка при загрузке запросов: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _cancelOutgoingRequest(RelationRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Отменить запрос?'),
        content: const Text(
          'Получатель больше не увидит этот запрос на подтверждение родства.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Оставить'),
          ),
          FilledButton(
            key: const Key('relation-request-cancel-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Отменить запрос'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
    });
    try {
      await _familyService.cancelRelationRequest(request.id);
      await _loadRequests();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Запрос отменён')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось отменить запрос: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _respondToRequest(String requestId, RequestStatus status) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _familyService.respondToRelationRequest(
        requestId: requestId,
        response: status,
      );

      await _loadRequests();

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == RequestStatus.accepted
                ? 'Запрос принят'
                : 'Запрос отклонен',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Ошибка при обработке запроса: $e');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Запросы на родство'),
          bottom: TabBar(
            tabs: [
              Tab(
                key: const Key('relation-requests-incoming-tab'),
                text: 'Входящие (${_incomingRequests.length})',
              ),
              Tab(
                key: const Key('relation-requests-outgoing-tab'),
                text: 'Отправленные (${_outgoingRequests.length})',
              ),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text(
                          'Произошла ошибка',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(_error!, textAlign: TextAlign.center),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadRequests,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  )
                : TabBarView(
                    children: [
                      _buildIncomingTab(context),
                      _buildOutgoingTab(context),
                    ],
                  ),
      ),
    );
  }

  Widget _buildIncomingTab(BuildContext context) {
    if (_incomingRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Нет входящих запросов',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 6),
            const Text(
              'Когда кто-то пригласит вас в свое дерево,\nзапросы появятся здесь',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _incomingRequests.length,
      itemBuilder: (context, index) {
        final request = _incomingRequests[index];
        final senderProfile = _userProfiles[request.senderId];
        final avatarImage = buildAvatarImageProvider(senderProfile?.photoURL);

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundImage: avatarImage,
                      child:
                          avatarImage == null ? const Icon(Icons.person) : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            senderProfile?.displayName ??
                                'Неизвестный пользователь',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            'Хочет добавить вас как: ${FamilyRelation.getRelationName(request.getRecipientToSender(), Gender.unknown)}',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (request.message != null && request.message!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(request.message!),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => _respondToRequest(
                        request.id,
                        RequestStatus.rejected,
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey[700],
                      ),
                      child: const Text('Отклонить'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => _respondToRequest(
                        request.id,
                        RequestStatus.accepted,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Принять'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOutgoingTab(BuildContext context) {
    if (_outgoingRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.outbox_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Нет отправленных запросов',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 6),
            const Text(
              'Запросы на подтверждение родства,\nкоторые ждут ответа получателя, появятся здесь',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _outgoingRequests.length,
      itemBuilder: (context, index) {
        final request = _outgoingRequests[index];
        final recipientProfile = _userProfiles[request.recipientId];
        final avatarImage =
            buildAvatarImageProvider(recipientProfile?.photoURL);

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundImage: avatarImage,
                      child:
                          avatarImage == null ? const Icon(Icons.person) : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            recipientProfile?.displayName ?? 'Родственник',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            'Роль: ${FamilyRelation.getRelationName(request.senderToRecipient, Gender.unknown)}',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (request.message != null && request.message!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(request.message!),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      key: Key('relation-request-cancel-${request.id}'),
                      onPressed: () => _cancelOutgoingRequest(request),
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('Отменить запрос'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
