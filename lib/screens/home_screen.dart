import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../services/post_service.dart';
import '../models/post.dart';
import 'create_post_screen.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/tree_provider.dart';
import '../services/event_service.dart';
import '../models/app_event.dart';
import '../widgets/event_card.dart';
import 'package:get_it/get_it.dart';
import '../widgets/post_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();
  late EventService _eventService;
  late PostService _postService;
  List<AppEvent> _upcomingEvents = [];
  bool _isLoadingEvents = true;
  String? _currentTreeId;
  TreeProvider? _treeProviderInstance;

  @override
  void initState() {
    super.initState();
    _eventService = EventService();
    _postService = PostService();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _treeProviderInstance = Provider.of<TreeProvider>(context, listen: false);
      _treeProviderInstance!.addListener(_handleTreeChange);
      _currentTreeId = _treeProviderInstance!.selectedTreeId;
      if (_currentTreeId != null) {
        _loadEvents(_currentTreeId!);
      } else {
        setState(() { _isLoadingEvents = false; });
      }
    });
  }

  @override
  void dispose() {
    _treeProviderInstance?.removeListener(_handleTreeChange);
    super.dispose();
  }

  void _handleTreeChange() {
    if (!mounted) return;
    final newTreeId = _treeProviderInstance?.selectedTreeId;
    if (_currentTreeId != newTreeId) {
      print('HomeScreen: Обнаружено изменение дерева с $_currentTreeId на $newTreeId');
      _currentTreeId = newTreeId;
      if (_currentTreeId != null) {
        _loadEvents(_currentTreeId!);
      } else {
        setState(() {
          _isLoadingEvents = false;
          _upcomingEvents = [];
        });
      }
    }
  }

  Future<void> _loadEvents(String treeId) async {
    if (!mounted) return;
    setState(() {
      _isLoadingEvents = true;
      _upcomingEvents = [];
    });
    try {
      final events = await _eventService.getUpcomingEvents(treeId, limit: 5);
      if (mounted) {
        setState(() {
          _upcomingEvents = events;
          _isLoadingEvents = false;
        });
      }
    } catch (e) {
      print('Ошибка загрузки событий: $e');
      if (mounted) {
        setState(() {
          _isLoadingEvents = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedTreeName = Provider.of<TreeProvider>(context).selectedTreeName;

    return Scaffold(
      appBar: AppBar(
        title: Text(selectedTreeName ?? 'Главная'),
        actions: [
          IconButton(
            icon: Icon(Icons.account_tree_outlined),
            tooltip: 'Выбрать дерево',
            onPressed: () => context.push('/tree'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (_currentTreeId != null) {
            await _loadEvents(_currentTreeId!);
          }
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundImage: _authService.currentUser?.photoURL != null
                          ? NetworkImage(_authService.currentUser!.photoURL!)
                          : null,
                      child: _authService.currentUser?.photoURL == null
                          ? Icon(Icons.person, size: 30, color: Colors.white)
                          : null,
                      backgroundColor: Theme.of(context).primaryColor,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Привет, ${_authService.currentUser?.displayName ?? 'пользователь'}!',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Добро пожаловать в приложение Lineage',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            SliverToBoxAdapter(
              child: _buildStoriesSection(),
            ),
            
            SliverToBoxAdapter(
              child: _buildUpcomingEventsSection(),
            ),
            
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Лента новостей',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.add_circle_outline),
                      onPressed: () async {
                        final result = await Navigator.pushNamed(context, '/post/create');
                        if (result == true) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Публикация создана успешно')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            
            _buildPostsFeed(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          context.push('/post/create');
        },
        tooltip: 'Создать пост',
        child: const Icon(Icons.add_photo_alternate_outlined),
      ),
    );
  }
  
  Widget _buildStoriesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 16, right: 16),
          child: Text(
            'Истории',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        
        SizedBox(height: 8),
        
        SizedBox(
                height: 100,
                child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: 12),
                  scrollDirection: Axis.horizontal,
            itemCount: 10, // Заглушка для демо
                  itemBuilder: (context, index) {
              // Первый элемент - добавление новой истории
                    if (index == 0) {
                return Container(
                  width: 70,
                  margin: EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          children: [
                            Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                          color: Colors.grey[200],
                                shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).primaryColor,
                            width: 2,
                          ),
                              ),
                              child: Icon(
                                Icons.add,
                                color: Theme.of(context).primaryColor,
                                size: 30,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Добавить',
                              style: TextStyle(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      );
              }
              
              // Кружки историй
              return Container(
                width: 70,
                margin: EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          children: [
                            Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.2),
                                shape: BoxShape.circle,
                                border: Border.all(
                          color: Theme.of(context).primaryColor,
                                  width: 2,
                                ),
                        image: DecorationImage(
                          image: NetworkImage(
                            'https://i.pravatar.cc/150?img=${index + 10}',
                          ),
                          fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                      'История ${index}',
                              style: TextStyle(fontSize: 12),
                      maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
              );
            },
          ),
        ),
        
        Divider(),
      ],
    );
  }
  
  Widget _buildUpcomingEventsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Ближайшие события',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        
        _buildEventsSection(),
        
        Divider(),
      ],
    );
  }
  
  Widget _buildEventsSection() {
    if (_isLoadingEvents) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_upcomingEvents.isEmpty && _currentTreeId != null) {
       return Container(
        height: 120,
        alignment: Alignment.center,
        child: Text('Нет предстоящих событий', style: TextStyle(color: Colors.grey)),
      );
    }
     if (_upcomingEvents.isEmpty && _currentTreeId == null) {
       return Container(
        height: 120,
        alignment: Alignment.center,
        child: Text('Выберите дерево для просмотра событий', style: TextStyle(color: Colors.grey)),
      );
    }

    return Container(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10.0),
        itemCount: _upcomingEvents.length,
        itemBuilder: (context, index) {
          final event = _upcomingEvents[index];
          return EventCard(event: event);
        },
      ),
    );
  }
  
  Widget _buildPostsFeed() {
    if (_currentTreeId == null) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 50.0),
          child: Center(child: Text('Выберите дерево, чтобы увидеть ленту', style: TextStyle(color: Colors.grey))),
        ),
      );
    }

    return StreamBuilder<List<Post>>(
      stream: _postService.getPostsStream(_currentTreeId!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SliverToBoxAdapter(
            child: Center(child: Padding(padding: EdgeInsets.all(50.0), child: CircularProgressIndicator())),
          );
        }
        if (snapshot.hasError) {
          print('Ошибка в StreamBuilder постов: ${snapshot.error}');
          return SliverToBoxAdapter(
            child: Center(child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('Ошибка загрузки ленты: ${snapshot.error}', textAlign: TextAlign.center, style: TextStyle(color: Colors.red)),
            )),
          );
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 50.0),
                child: Text('В этом дереве пока нет постов.', style: TextStyle(color: Colors.grey)),
              ),
            ),
          );
        }

        final posts = snapshot.data!;
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              return PostCard(post: posts[index]);
            },
            childCount: posts.length,
          ),
        );
      },
    );
  }
} 