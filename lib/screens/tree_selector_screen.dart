import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// Убираем импорт TreeViewScreen, так как переход будет в другое место
// import 'tree_view_screen.dart'; 
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/tree_provider.dart';

class TreeSelectorScreen extends StatefulWidget {
  const TreeSelectorScreen({Key? key}) : super(key: key);

  @override
  _TreeSelectorScreenState createState() => _TreeSelectorScreenState();
}

class _TreeSelectorScreenState extends State<TreeSelectorScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  List<Map<String, dynamic>> _userTrees = [];
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadUserTrees();
  }

  Future<void> _loadUserTrees() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) {
        throw Exception('Пользователь не авторизован');
      }

      final membershipSnapshot = await _firestore
          .collection('tree_members')
          .where('userId', isEqualTo: userId)
          .where('role', whereIn: ['owner', 'editor', 'viewer'])
          .get();

      List<String> treeIds = membershipSnapshot.docs.map((doc) => doc['treeId'] as String).toList();
      
      if (treeIds.isEmpty) {
         if (mounted) {
            setState(() {
              _userTrees = [];
              _isLoading = false;
            });
          }
        return;
      }
      
      List<Map<String, dynamic>> trees = [];
      for (var i = 0; i < treeIds.length; i += 10) {
         final chunkIds = treeIds.sublist(i, i + 10 > treeIds.length ? treeIds.length : i + 10);
         final treesSnapshot = await _firestore
             .collection('family_trees')
             .where(FieldPath.documentId, whereIn: chunkIds)
             .get();
         
         for (var treeDoc in treesSnapshot.docs) {
           if (treeDoc.exists) {
              trees.add({
                'id': treeDoc.id,
                'name': treeDoc['name'] ?? 'Без названия',
                'createdAt': treeDoc['createdAt'], 
              });
           }
         }
      }

      if (mounted) {
        setState(() {
          trees.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
          _userTrees = trees;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Ошибка загрузки деревьев: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Не удалось загрузить список деревьев.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Выберите дерево'),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
             ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Text(_errorMessage, textAlign: TextAlign.center),
                 ))
             : _userTrees.isEmpty
                 ? _buildEmptyState()
                 : _buildTreeList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
       child: Padding(
           padding: const EdgeInsets.all(20.0),
           child: Column(
             mainAxisAlignment: MainAxisAlignment.center,
             children: [
               Icon(
                 Icons.account_tree,
                 size: 80,
                 color: Colors.grey[400],
               ),
               SizedBox(height: 16),
               Text(
                 'У вас нет семейных деревьев',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
               ),
               SizedBox(height: 8),
               Text(
                 'Создайте новое дерево или примите приглашение',
                 textAlign: TextAlign.center,
                 style: TextStyle(color: Colors.grey[600]),
               ),
               SizedBox(height: 16),
               ElevatedButton.icon(
                 icon: Icon(Icons.add),
                 label: Text('Создать дерево'),
                 onPressed: () {
                   context.push('/trees/create').then((result) {
                     if (result == true) {
                       _loadUserTrees();
                     }
                   });
                 },
               ),
             ],
           ),
         ),
    );
  }

  Widget _buildTreeList() {
    final treeProvider = Provider.of<TreeProvider>(context, listen: false);
    return ListView.builder(
      itemCount: _userTrees.length,
      itemBuilder: (context, index) {
        final tree = _userTrees[index];
        final treeId = tree['id'] as String;
        final treeName = tree['name'] as String;
        
        return Card(
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).primaryColor,
              child: Icon(Icons.account_tree, color: Colors.white),
            ),
            title: Text(treeName),
            subtitle: Text('Нажмите для просмотра'),
            onTap: () {
              print('[TreeSelectorScreen] Selecting tree: $treeId ($treeName)');
              treeProvider.selectTree(treeId, treeName);

              print('[TreeSelectorScreen] Pushing to /tree/view/$treeId');
              context.push('/tree/view/$treeId');
            },
          ),
        );
      },
    );
  }
} 