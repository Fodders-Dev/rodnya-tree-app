import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';

import '../backend/interfaces/safety_service_interface.dart';
import '../models/user_block_record.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  late final SafetyServiceInterface _safetyService =
      GetIt.I<SafetyServiceInterface>();
  late Future<List<UserBlockRecord>> _blocksFuture = _loadBlocks();

  Future<List<UserBlockRecord>> _loadBlocks() {
    return _safetyService.listBlockedUsers();
  }

  Future<void> _refresh() async {
    final nextFuture = _loadBlocks();
    setState(() {
      _blocksFuture = nextFuture;
    });
    await nextFuture;
  }

  Future<void> _unblock(UserBlockRecord block) async {
    await _safetyService.unblockUser(block.id);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text('${block.blockedUserDisplayName} снова сможет писать вам'),
      ),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Заблокированные пользователи')),
      body: FutureBuilder<List<UserBlockRecord>>(
        future: _blocksFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      'Не удалось загрузить список блокировок',
                      style: theme.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _refresh,
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            );
          }

          final blocks = snapshot.data ?? const <UserBlockRecord>[];
          if (blocks.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shield_outlined, size: 44),
                    const SizedBox(height: 12),
                    Text(
                      'Сейчас здесь пусто',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Если вы заблокируете кого-то из личного чата, пользователь появится в этом списке и вы сможете снять блокировку позже.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemBuilder: (context, index) {
                final block = blocks[index];
                final formattedDate = DateFormat('d MMM yyyy, HH:mm', 'ru')
                    .format(block.createdAt);
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  tileColor: theme.colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  leading: CircleAvatar(
                    backgroundImage: block.blockedUserPhotoUrl != null &&
                            block.blockedUserPhotoUrl!.trim().isNotEmpty
                        ? NetworkImage(block.blockedUserPhotoUrl!.trim())
                        : null,
                    child: block.blockedUserPhotoUrl == null ||
                            block.blockedUserPhotoUrl!.trim().isEmpty
                        ? Text(
                            block.blockedUserDisplayName.isNotEmpty
                                ? block.blockedUserDisplayName[0].toUpperCase()
                                : '?',
                          )
                        : null,
                  ),
                  title: Text(block.blockedUserDisplayName),
                  subtitle: Text(
                    block.reason?.trim().isNotEmpty == true
                        ? 'Причина: ${block.reason} · $formattedDate'
                        : 'Заблокирован: $formattedDate',
                  ),
                  trailing: TextButton(
                    onPressed: () => _unblock(block),
                    child: const Text('Разблокировать'),
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemCount: blocks.length,
            ),
          );
        },
      ),
    );
  }
}
