import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_profile.dart';
import '../models/family_relation.dart';
import '../services/family_service.dart';

class FindRelativeScreen extends StatefulWidget {
  final String treeId;
  
  const FindRelativeScreen({Key? key, required this.treeId}) : super(key: key);
  
  @override
  _FindRelativeScreenState createState() => _FindRelativeScreenState();
}

class _FindRelativeScreenState extends State<FindRelativeScreen> with TickerProviderStateMixin {
  final _searchController = TextEditingController();
  List<UserProfile> _searchResults = [];
  bool _isLoading = false;
  RelationType? _selectedRelation;
  late TabController _tabController;
  final _searchEmailController = TextEditingController();
  final _searchPhoneController = TextEditingController();
  final _searchUsernameController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    _searchEmailController.dispose();
    _searchPhoneController.dispose();
    _searchUsernameController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Найти родственника'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Email'),
            Tab(text: 'Телефон'),
            Tab(text: 'Никнейм'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEmailSearchTab(),
          _buildPhoneSearchTab(),
          _buildUsernameSearchTab(),
        ],
      ),
    );
  }
  
  Future<void> _searchByEmail() async {
    final email = _searchEmailController.text.trim();
    if (email.isEmpty) return;
    
    setState(() {
      _isLoading = true;
      _searchResults = [];
    });
    
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      
      if (querySnapshot.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Пользователь с таким email не найден')),
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }
      
      final doc = querySnapshot.docs.first;
      final userProfile = UserProfile.fromFirestore(doc);
      
      // Проверяем, не является ли этот пользователь нами самими
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser?.uid == userProfile.id) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Вы не можете добавить себя в качестве родственника')),
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }
      
      // Проверяем, не является ли этот пользователь уже родственником
      final relationsQuery = await FirebaseFirestore.instance
          .collection('family_relations')
          .where('treeId', isEqualTo: widget.treeId)
          .where('person1Id', isEqualTo: currentUser?.uid)
          .where('person2Id', isEqualTo: userProfile.id)
          .get();
      
      if (relationsQuery.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Этот пользователь уже добавлен в ваши родственники')),
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }
      
      setState(() {
        _searchResults = [userProfile];
        _isLoading = false;
      });
    } catch (e) {
      print('Ошибка при поиске пользователя: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Произошла ошибка при поиске: $e')),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _searchByPhone() async {
    final phone = _searchPhoneController.text.trim();
    if (phone.isEmpty) return;
    
    _searchUser({'field': 'phoneNumber', 'value': phone});
  }
  
  Future<void> _searchByUsername() async {
    final username = _searchUsernameController.text.trim();
    if (username.isEmpty) return;
    
    _searchUser({'field': 'username', 'value': username});
  }
  
  Future<void> _searchUser(Map<String, String> query) async {
    setState(() {
      _isLoading = true;
      _searchResults = [];
    });
    
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where(query['field']!, isEqualTo: query['value'])
          .get();
      
      final results = querySnapshot.docs
          .map((doc) => UserProfile.fromFirestore(doc))
          .toList();
      
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    } catch (e) {
      print('Ошибка поиска: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка поиска: $e')),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _sendRelationRequest(UserProfile user, RelationType relationType) async {
    if (user == null || user.id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: информация о пользователе недоступна')),
      );
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('Вы не авторизованы');
      
      // Проверяем, не отправлен ли запрос уже
      final existingRequestsQuery = await FirebaseFirestore.instance
          .collection('relation_requests')
          .where('treeId', isEqualTo: widget.treeId)
          .where('senderId', isEqualTo: currentUser.uid)
          .where('recipientId', isEqualTo: user.id)
          .get();
      
      if (existingRequestsQuery.docs.isNotEmpty) {
        setState(() {
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Запрос этому пользователю уже отправлен')),
        );
        return;
      }
      
      await FamilyService().sendRelationRequest(
        treeId: widget.treeId,
        recipientId: user.id,
        relationType: relationType,
        message: 'Запрос на подтверждение родственной связи',
      );
      
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Запрос успешно отправлен')),
      );
      
      Navigator.pop(context);
      
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Widget _buildUserCard(UserProfile user) {
    if (user == null) {
      return SizedBox.shrink();
    }
    
    final String displayName = user.displayName.isNotEmpty 
        ? user.displayName 
        : (user.firstName.isNotEmpty ? '${user.firstName} ${user.lastName}' : 'Пользователь');
    
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage: user.photoURL != null ? NetworkImage(user.photoURL!) : null,
          child: user.photoURL == null 
              ? Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?')
              : null,
        ),
        title: Text(displayName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (user.email != null && user.email!.isNotEmpty)
              Text(user.email!),
            if (user.username != null && user.username!.isNotEmpty)
              Text('@${user.username}', style: TextStyle(color: Colors.blue)),
          ],
        ),
        trailing: IconButton(
          icon: Icon(Icons.add_circle_outline, color: Colors.green),
          onPressed: () => _showRelationSelectDialog(user),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          SizedBox(width: 8),
          Text(text),
        ],
      ),
    );
  }

  Widget _buildEmailSearchTab() {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _searchEmailController,
            decoration: InputDecoration(
              labelText: 'Email пользователя',
              hintText: 'example@mail.ru',
              prefixIcon: Icon(Icons.email),
              border: OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(Icons.search),
                onPressed: _searchByEmail,
              ),
            ),
            keyboardType: TextInputType.emailAddress,
            onSubmitted: (_) => _searchByEmail(),
          ),
          SizedBox(height: 16),
          if (_isLoading)
            Center(child: CircularProgressIndicator())
          else if (_searchResults.isNotEmpty)
            Expanded(
              child: ListView.builder(
                itemCount: _searchResults.length,
                itemBuilder: (context, index) => _buildUserCard(_searchResults[index]),
              ),
            )
          else if (_searchEmailController.text.isNotEmpty)
            Expanded(
              child: Center(child: Text('Пользователь не найден')),
            )
        ],
      ),
    );
  }
  
  Widget _buildPhoneSearchTab() {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _searchPhoneController,
            decoration: InputDecoration(
              labelText: 'Телефон пользователя',
              hintText: '+7XXXXXXXXXX',
              prefixIcon: Icon(Icons.phone),
              border: OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(Icons.search),
                onPressed: _searchByPhone,
              ),
            ),
            keyboardType: TextInputType.phone,
            onSubmitted: (_) => _searchByPhone(),
          ),
          SizedBox(height: 16),
          if (_isLoading)
            Center(child: CircularProgressIndicator())
          else if (_searchResults.isNotEmpty)
            Expanded(
              child: ListView.builder(
                itemCount: _searchResults.length,
                itemBuilder: (context, index) => _buildUserCard(_searchResults[index]),
              ),
            )
          else if (_searchPhoneController.text.isNotEmpty)
            Expanded(
              child: Center(child: Text('Пользователь не найден')),
            )
        ],
      ),
    );
  }
  
  Widget _buildUsernameSearchTab() {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _searchUsernameController,
            decoration: InputDecoration(
              labelText: 'Никнейм пользователя',
              hintText: '@username',
              prefixIcon: Icon(Icons.person),
              border: OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(Icons.search),
                onPressed: _searchByUsername,
              ),
            ),
            onSubmitted: (_) => _searchByUsername(),
          ),
          SizedBox(height: 16),
          if (_isLoading)
            Center(child: CircularProgressIndicator())
          else if (_searchResults.isNotEmpty)
            Expanded(
              child: ListView.builder(
                itemCount: _searchResults.length,
                itemBuilder: (context, index) => _buildUserCard(_searchResults[index]),
              ),
            )
          else if (_searchUsernameController.text.isNotEmpty)
            Expanded(
              child: Center(child: Text('Пользователь не найден')),
            )
        ],
      ),
    );
  }
  
  Widget _buildRelationTypeDropdown() {
    return DropdownButtonFormField<RelationType>(
      value: _selectedRelation,
      decoration: InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      hint: Text('Выберите тип связи'),
      isExpanded: true,
      items: [
        DropdownMenuItem(
          value: RelationType.parent,
          child: Text('Родитель'),
        ),
        DropdownMenuItem(
          value: RelationType.child,
          child: Text('Ребенок'),
        ),
        DropdownMenuItem(
          value: RelationType.spouse,
          child: Text('Супруг(а)'),
        ),
        DropdownMenuItem(
          value: RelationType.sibling,
          child: Text('Брат/сестра'),
        ),
        DropdownMenuItem(
          value: RelationType.cousin,
          child: Text('Двоюродный брат/сестра'),
        ),
        DropdownMenuItem(
          value: RelationType.uncle,
          child: Text('Дядя'),
        ),
        DropdownMenuItem(
          value: RelationType.aunt,
          child: Text('Тётя'),
        ),
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Выберите тип родственной связи'),
        content: _buildRelationTypeDropdown(),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена'),
          ),
          TextButton(
            onPressed: () => _sendRelationRequest(user, _selectedRelation!),
            child: Text('Добавить'),
          ),
        ],
      ),
    );
  }

  Future<List<UserProfile>> _searchUsersByEmail(String email) async {
    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(10)
          .get();
          
      print('Найдено ${snapshot.docs.length} пользователей по email: $email');
          
      List<UserProfile> results = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        print('Данные пользователя: $data');
        
        results.add(UserProfile.create(
          id: doc.id,
          email: data['email'] ?? '',
          displayName: data['displayName'] ?? '',
          firstName: data['firstName'] ?? '',
          lastName: data['lastName'] ?? '',
          middleName: data['middleName'] ?? '',
          username: data['username'] ?? '',
          photoURL: data['photoURL'],
          phoneNumber: data['phoneNumber'] ?? '',
        ));
      }
      
      return results;
    } catch (e) {
      print('Ошибка при поиске пользователей по email: $e');
      return [];
    }
  }
} 