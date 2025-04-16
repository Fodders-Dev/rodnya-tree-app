import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/family_tree.dart';
import '../models/family_tree_member.dart';
import '../screens/family_tree/create_tree_screen.dart';
import '../screens/relatives_screen.dart';
import '../providers/tree_provider.dart';
import '../services/profile_service.dart';
import '../models/user_profile.dart';
import 'package:get_it/get_it.dart';
import '../services/invitation_service.dart';
import '../services/local_storage_service.dart';
import '../services/sync_service.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class TreesScreen extends StatefulWidget {
  const TreesScreen({Key? key}) : super(key: key);

  @override
  _TreesScreenState createState() => _TreesScreenState();
}

class _TreesScreenState extends State<TreesScreen> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ProfileService _profileService = ProfileService();
  final InvitationService _invitationService = GetIt.I<InvitationService>();
  late TabController _tabController;
  
  // Переменные для хранения состояния
  List<FamilyTree> _myTrees = [];
  bool _isLoading = false;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    _tabController.addListener(_handleTabSelection); // Используем метод-обработчик
    
    // Загружаем деревья для первой вкладки при инициализации
    _loadUserTrees(); 
  }
  
  @override
  void dispose() {
    _tabController.removeListener(_handleTabSelection); // Удаляем слушателя
    _tabController.dispose();
    super.dispose();
  }
  
  // Метод-обработчик для слушателя
  void _handleTabSelection() {
    // Загружаем деревья только когда выбрана первая вкладка (индекс 0)
    // и когда переход между вкладками завершен (!indexIsChanging)
    if (!_tabController.indexIsChanging && _tabController.index == 0) {
       print("[_TreesScreen] Tab changed to 'Мои деревья', reloading trees...");
       _loadUserTrees(); // Вызываем загрузку/обновление
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Семейные деревья'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Мои деревья'),
            Tab(text: 'Приглашения'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMyTreesTab(),
          _buildInvitationsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToCreateTree,
        child: Icon(Icons.add),
        tooltip: 'Создать семейное дерево',
      ),
    );
  }
  
  Widget _buildMyTreesTab() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      return Center(
        child: Text('Необходимо войти в систему'),
      );
    }
    
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }
    
    if (_myTrees.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.family_restroom,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'У вас пока нет семейных деревьев',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[700],
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _navigateToCreateTree,
              child: Text('Создать новое дерево'),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: _refreshTrees,
      child: ListView.builder(
        padding: EdgeInsets.all(16),
        itemCount: _myTrees.length,
        itemBuilder: (context, index) {
          final tree = _myTrees[index];
          return Card(
            elevation: 2,
            margin: EdgeInsets.only(bottom: 16),
            child: ListTile(
              title: Text(tree.name),
              subtitle: Text(
                tree.description.isEmpty 
                    ? 'Создано: ${tree.createdAt.day}.${tree.createdAt.month}.${tree.createdAt.year}'
                    : tree.description
              ),
              leading: CircleAvatar(
                child: Icon(Icons.account_tree),
              ),
              onTap: () {
                Provider.of<TreeProvider>(context, listen: false)
                    .selectTree(tree.id, tree.name);
                context.go('/relatives');
              },
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildInvitationsTab() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      return Center(
        child: Text('Необходимо войти в систему'),
      );
    }
    
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {});
        return Future.value();
      },
      child: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('tree_members')
            .where('userId', isEqualTo: userId)
            .where('role', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.mail,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'У вас нет приглашений в семейные деревья',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            );
          }
          
          // Получаем список идентификаторов деревьев
          final invitations = snapshot.data!.docs;
          final treeIds = invitations
              .map((doc) => doc['treeId'] as String)
              .toList();
          
          return FutureBuilder<List<DocumentSnapshot>>(
            future: Future.wait(
              treeIds.map((id) => _firestore.collection('family_trees').doc(id).get())
            ),
            builder: (context, treesSnapshot) {
              if (!treesSnapshot.hasData) {
                return Center(child: CircularProgressIndicator());
              }
              
              final trees = treesSnapshot.data!
                  .where((doc) => doc.exists)
                  .map((doc) => FamilyTree.fromFirestore(doc))
                  .toList();
              
              if (trees.isEmpty) {
                return Center(
                  child: Text('Не удалось загрузить приглашения'),
                );
              }
              
              return ListView.builder(
                itemCount: trees.length,
                itemBuilder: (context, index) {
                  final tree = trees[index];
                  final invitation = invitations
                      .firstWhere((doc) => doc['treeId'] == tree.id);
                  final invitationId = invitation.id;
                  
                  return InvitationCard(
                    tree: tree,
                    invitedBy: invitation['addedBy'] as String?,
                    onAccept: () => _handleInvitation(invitationId, true),
                    onDecline: () => _handleInvitation(invitationId, false),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
  
  Future<void> _handleInvitation(String invitationId, bool accept) async {
    try {
      if (accept) {
        // Принять приглашение
        await _firestore
            .collection('tree_members')
            .doc(invitationId)
            .update({
              'role': 'viewer',
              'acceptedAt': FieldValue.serverTimestamp(),
            });
            
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Приглашение принято')),
        );
      } else {
        // Отклонить приглашение
        await _firestore
            .collection('tree_members')
            .doc(invitationId)
            .delete();
            
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Приглашение отклонено')),
        );
      }
    } catch (e) {
      print('Ошибка при обработке приглашения: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Произошла ошибка. Попробуйте еще раз.')),
      );
    }
  }
  
  // --- НОВАЯ РЕАЛИЗАЦИЯ ЗАГРУЗКИ ДЕРЕВЬЕВ --- 
  Future<void> _loadUserTrees() async {
    print('[_loadUserTrees] Method called.');
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      print('[_loadUserTrees] Setting _isLoading = true');
    });
    
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      print('[_loadUserTrees] Error: User not logged in.');
       if (mounted) {
        setState(() {
          _isLoading = false;
           // Можно добавить сообщение об ошибке
        });
       }
      return;
    }
    
    try {
       print('[_loadUserTrees] Загрузка всех деревьев из LocalStorageService...');
       print('[_loadUserTrees] Getting LocalStorageService instance...');
       final localStorageService = GetIt.I<LocalStorageService>();
       print('[_loadUserTrees] Calling localStorageService.getAllTrees()...');
      final cachedTrees = await localStorageService.getAllTrees(); // Получаем из кэша
       print('[_loadUserTrees] Received ${cachedTrees.length} trees from LocalStorageService: ${cachedTrees.map((t) => t.id).toList()}');
       
      if (mounted) {
         setState(() {
            _myTrees = cachedTrees;
           _isLoading = false; // Показываем закэшированные данные
            print('[_loadUserTrees] Inside setState: Setting _myTrees (count: ${cachedTrees.length}) and _isLoading = false');
         });
      }
      
       // --- Фоновая синхронизация (опционально, но рекомендуется) ---
       // Запускаем синхронизацию после отображения кэша, не дожидаясь ее завершения
       print('[_loadUserTrees] Triggering background sync...');
       final syncService = GetIt.I<SyncService>();
       // Используем syncData() для полной синхронизации или 
       // нужен специфичный метод syncTrees(), если он есть.
       // syncService.syncData().then((_) {
       //    print('[_loadUserTrees] Background sync completed. Reloading from cache...');
       //    // После синхронизации можно перезагрузить из кэша для обновления UI,
       //    // если syncData сам не обновляет состояние через провайдеры.
       //    _loadUserTrees(); // Рекурсивный вызов - осторожно! Лучше слушать изменения
       // }).catchError((e) {
       //    print('[_loadUserTrees] Background sync failed: $e');
       // });
       // Пока просто вызываем syncData без ожидания и перезагрузки
       syncService.syncData().catchError((e) {
         print('[_loadUserTrees] Background sync failed: $e');
       });
       // ---------------------------------------------------------
       
    } catch (e, stackTrace) {
       print('[_loadUserTrees] Error loading trees: $e\n$stackTrace');
       FirebaseCrashlytics.instance.recordError(e, stackTrace, reason: 'LoadUserTreesError');
       if (mounted) {
         setState(() {
            _isLoading = false;
            // Показать сообщение об ошибке
         });
       }
    }
  }
  // --- КОНЕЦ НОВОЙ РЕАЛИЗАЦИИ ---

  void _navigateToCreateTree() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateTreeScreen(),
      ),
    ).then((_) {
      _loadUserTrees();
    });
  }

  // --- РЕАЛИЗАЦИЯ REFRESH --- 
  Future<void> _refreshTrees() async {
    print('[_refreshTrees] Pull-to-refresh triggered.');
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      print('[_refreshTrees] Error: User not logged in.');
      return; // Ничего не делаем, если юзера нет
    }
    
    // Показываем индикатор загрузки, если нужно (onRefresh уже показывает)
    // setState(() { _isLoading = true; });
    
    try {
       print('[_refreshTrees] Forcing sync...');
       final syncService = GetIt.I<SyncService>();
       // Запускаем полную синхронизацию и ДОЖИДАЕМСЯ ее
       await syncService.syncData();
       print('[_refreshTrees] Sync completed.');
       
       // После синхронизации перезагружаем данные из кэша (который должен был обновиться)
       await _loadUserTrees();
    } catch (e, stackTrace) {
       print('[_refreshTrees] Error during refresh: $e\n$stackTrace');
       FirebaseCrashlytics.instance.recordError(e, stackTrace, reason: 'RefreshTreesError');
       if (mounted) {
          // Можно показать SnackBar с ошибкой
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Ошибка обновления списка деревьев')),
          );
          // Убедимся, что индикатор загрузки скрыт
          // setState(() { _isLoading = false; });
       }
    }
  }
  // --- КОНЕЦ РЕАЛИЗАЦИИ REFRESH ---
}

class TreeCard extends StatelessWidget {
  final FamilyTree tree;
  final MemberRole role;
  final VoidCallback onTap;
  
  const TreeCard({
    Key? key,
    required this.tree,
    required this.role,
    required this.onTap,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    String roleText;
    IconData roleIcon;
    
    switch (role) {
      case MemberRole.owner:
        roleText = 'Создатель';
        roleIcon = Icons.star;
        break;
      case MemberRole.editor:
        roleText = 'Редактор';
        roleIcon = Icons.edit;
        break;
      case MemberRole.viewer:
        roleText = 'Просмотр';
        roleIcon = Icons.visibility;
        break;
      default:
        roleText = 'Неизвестно';
        roleIcon = Icons.question_mark;
    }
    
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.family_restroom,
                  size: 32,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tree.name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      tree.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey[600],
                      ),
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          roleIcon,
                          size: 16,
                          color: Theme.of(context).primaryColor,
                        ),
                        SizedBox(width: 4),
                        Text(
                          roleText,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                        SizedBox(width: 12),
                        Icon(
                          Icons.people,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        SizedBox(width: 4),
                        Text(
                          '${tree.memberIds.length} ${_getMembersText(tree.memberIds.length)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16),
            ],
          ),
        ),
      ),
    );
  }
  
  String _getMembersText(int count) {
    if (count == 1) return 'участник';
    if (count >= 2 && count <= 4) return 'участника';
    return 'участников';
  }
}

class InvitationCard extends StatelessWidget {
  final FamilyTree tree;
  final String? invitedBy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  
  const InvitationCard({
    Key? key,
    required this.tree,
    this.invitedBy,
    required this.onAccept,
    required this.onDecline,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.family_restroom,
                    size: 28,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tree.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        tree.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Text(
              invitedBy != null
                  ? 'Вас пригласили присоединиться к семейному дереву'
                  : 'Приглашение в семейное дерево',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onDecline,
                  child: Text('Отклонить'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey[700],
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: onAccept,
                  child: Text('Принять'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
} 