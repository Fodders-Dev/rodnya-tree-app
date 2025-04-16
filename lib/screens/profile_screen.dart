import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart'; // Импортируем Provider
import '../models/user_profile.dart';
import '../models/profile_note.dart'; // Импортируем модель заметки
import '../services/auth_service.dart';
import '../services/family_service.dart';
import '../services/profile_service.dart'; // Импортируем сервис профиля
import '../providers/tree_provider.dart'; // Импортируем TreeProvider
import 'dart:async'; // Для Future
import 'package:get_it/get_it.dart';

// Примерный виджет для отображения статистики (можно вынести в отдельный файл)
class _ProfileStatItem extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileStatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(color: Colors.grey),
        ),
      ],
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  final FamilyService _familyService = GetIt.I<FamilyService>();
  final ProfileService _profileService = ProfileService(); // Добавляем сервис профиля
  UserProfile? _userProfile;
  String? _currentUserId; // Храним ID текущего пользователя
  int _treeCount = 0;
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("Пользователь не авторизован");
      }
      _currentUserId = user.uid; // Сохраняем ID

      // Загружаем профиль пользователя ИСПОЛЬЗУЯ СЕРВИС
      _userProfile = await _profileService.getUserProfile(_currentUserId!);
      if (_userProfile == null) {
         throw Exception("Профиль пользователя не найден");
      }

      // Загружаем количество деревьев
      final trees = await _familyService.getUserTrees();
      _treeCount = trees.length;

    } catch (e) {
       if (mounted) {
         setState(() {
           _errorMessage = 'Ошибка загрузки данных: $e';
         });
       }
      print('Ошибка при загрузке данных пользователя: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Функция для показа диалога добавления/редактирования заметки
  void _showAddEditNoteDialog({ProfileNote? note}) {
    final _titleController = TextEditingController(text: note?.title ?? '');
    final _contentController = TextEditingController(text: note?.content ?? '');
    final _formKey = GlobalKey<FormState>();
    final bool isEditing = note != null;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isEditing ? 'Редактировать заметку' : 'Добавить заметку'),
          content: Form(
            key: _formKey,
            child: SingleChildScrollView( // Добавим прокрутку на случай длинного контента
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _titleController,
                    decoration: InputDecoration(labelText: 'Заголовок'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Пожалуйста, введите заголовок';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 16),
                  TextFormField(
                    controller: _contentController,
                    decoration: InputDecoration(
                      labelText: 'Содержание',
                      alignLabelWithHint: true, // Выравниваем метку по верху
                    ),
                    maxLines: 5, // Больше строк для удобства
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Пожалуйста, введите содержание';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
             if (isEditing) // Кнопка удаления только при редактировании
              TextButton(
                child: Text('Удалить', style: TextStyle(color: Colors.red)),
                onPressed: () async {
                  // Запрос подтверждения перед удалением
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('Подтверждение'),
                      content: Text('Вы уверены, что хотите удалить эту заметку?'),
                      actions: [
                        TextButton(
                          child: Text('Отмена'),
                          onPressed: () => Navigator.of(context).pop(false),
                        ),
                        TextButton(
                          child: Text('Удалить'),
                          onPressed: () => Navigator.of(context).pop(true),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true && _currentUserId != null) {
                    try {
                      await _profileService.deleteProfileNote(_currentUserId!, note.id);
                      Navigator.of(context).pop(); // Закрываем диалог редактирования
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Заметка удалена')));
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Ошибка удаления: $e')));
                    }
                  }
                },
              ),
            TextButton(
              child: Text('Отмена'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text(isEditing ? 'Сохранить' : 'Добавить'),
              onPressed: () async {
                if (_formKey.currentState!.validate() && _currentUserId != null) {
                  try {
                    if (isEditing) {
                      // Создаем обновленную заметку (со старым id и createdAt)
                      final updatedNote = ProfileNote(
                        id: note.id,
                        title: _titleController.text,
                        content: _contentController.text,
                        createdAt: note.createdAt, // Сохраняем исходную дату создания
                      );
                      await _profileService.updateProfileNote(_currentUserId!, updatedNote);
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Заметка обновлена')));
                    } else {
                      await _profileService.addProfileNote(
                          _currentUserId!, _titleController.text, _contentController.text);
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Заметка добавлена')));
                    }
                    Navigator.of(context).pop(); // Закрываем диалог
                  } catch (e) {
                     ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Ошибка сохранения: $e')));
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Получаем TreeProvider, НЕ слушаем изменения здесь, только для нажатия кнопки
    final treeProvider = Provider.of<TreeProvider>(context, listen: false);
    final selectedTreeId = treeProvider.selectedTreeId;

    return Scaffold(
      appBar: AppBar(
        title: Text(_userProfile?.displayName ?? 'Профиль'),
        leading: IconButton(
           icon: Icon(Icons.arrow_back),
           onPressed: () {
             if (context.canPop()) {
               context.pop();
             } else {
               context.go('/'); 
             }
           },
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'settings') {
                context.push('/profile/settings');
              } else if (value == 'about') {
                 context.push('/profile/about');
              } else if (value == 'logout') {
                _authService.signOut();
              }
            },
            itemBuilder: (BuildContext context) {
              return [
                PopupMenuItem<String>(
                  value: 'settings',
                  child: Text('Настройки'),
                ),
                PopupMenuItem<String>(
                  value: 'about',
                  child: Text('О приложении'),
                ),
                PopupMenuItem<String>(
                  value: 'logout',
                  child: Text('Выйти'),
                ),
              ];
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(child: Padding( // Добавим отступы для ошибки
                  padding: const EdgeInsets.all(16.0),
                  child: Text(_errorMessage, textAlign: TextAlign.center),
                ))
              : _userProfile == null || _currentUserId == null // Проверяем и userId
                  ? Center(child: Text('Не удалось загрузить профиль.'))
                  : RefreshIndicator(
                      onRefresh: _loadUserData,
                      child: CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                children: [
                                  CircleAvatar(
                                    radius: 50,
                                    backgroundImage: _userProfile!.photoURL != null
                                        ? NetworkImage(_userProfile!.photoURL!)
                                        : null,
                                    child: _userProfile!.photoURL == null
                                        ? Icon(Icons.person, size: 50)
                                        : null,
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    _userProfile!.displayName ?? 'Имя не указано',
                                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                  ),
                                  SizedBox(height: 4),
                                  if ((_userProfile!.city != null && _userProfile!.city!.isNotEmpty) || 
                                      (_userProfile!.country != null && _userProfile!.country!.isNotEmpty))
                                     Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.location_on, size: 16, color: Colors.grey),
                                          SizedBox(width: 4),
                                          Text(
                                            '${_userProfile!.city ?? ''}${(_userProfile!.city != null && _userProfile!.city!.isNotEmpty && _userProfile!.country != null && _userProfile!.country!.isNotEmpty) ? ', ' : ''}${_userProfile!.country ?? ''}',
                                            style: TextStyle(color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                  SizedBox(height: 16),
                                  // Статистика
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      _ProfileStatItem(label: 'Постов', value: '0'),
                                      _ProfileStatItem(label: 'Родственники', value: '0'),
                                      _ProfileStatItem(label: 'Деревья', value: _treeCount.toString()),
                                    ],
                                  ),
                                  SizedBox(height: 24),
                                  // Кнопки
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: () {
                                            // Получаем ID выбранного дерева из провайдера
                                            final currentSelectedTreeId = treeProvider.selectedTreeId;
                                            
                                            if (currentSelectedTreeId == null) {
                                               // Показываем сообщение, если дерево не выбрано
                                             ScaffoldMessenger.of(context).showSnackBar(
                                                 SnackBar(
                                                   content: Text('Сначала выберите активное дерево на вкладке "Дерево" или "Родные"'),
                                                   action: SnackBarAction(
                                                     label: 'Выбрать',
                                                     onPressed: () => context.go('/tree'), // Предлагаем перейти к выбору
                                                   ),
                                                 ),
                                               );
                                            } else {
                                               // Переходим на новый экран
                                               context.push('/profile/offline_profiles');
                                            }
                                          },
                                          child: Text('Ваши профили'),
                                        ),
                                      ),
                                      SizedBox(width: 16),
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: () => context.push('/profile/edit'),
                                          child: Text('Редактировать'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // --- НАЧАЛО: Секция для заметок ---
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 0), // Уменьшим нижний отступ
                            sliver: SliverToBoxAdapter(
                               child: Row( // Используем Row для заголовка и кнопки
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                       Text(
                                         'Заметки',
                                         style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                       ),
                                       IconButton(
                                         icon: Icon(Icons.add_circle_outline),
                                         tooltip: 'Добавить заметку',
                                         onPressed: () => _showAddEditNoteDialog(), // Вызываем диалог добавления
                                       ),
                                    ],
                                  ),
                            ),
                          ),
                           // Используем StreamBuilder для отображения заметок
                           StreamBuilder<List<ProfileNote>>(
                             stream: _profileService.getProfileNotesStream(_currentUserId!),
                             builder: (context, snapshot) {
                               if (snapshot.connectionState == ConnectionState.waiting) {
                                 // Показываем индикатор загрузки только для секции заметок
                                 return SliverToBoxAdapter(
                                   child: Padding(
                                     padding: const EdgeInsets.all(16.0),
                                     child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                   ),
                                 );
                               }
                               if (snapshot.hasError) {
                                 return SliverToBoxAdapter(
                                   child: Padding(
                                     padding: const EdgeInsets.all(16.0),
                                     child: Text('Ошибка загрузки заметок: ${snapshot.error}'),
                                   ),
                                 );
                               }
                               if (!snapshot.hasData || snapshot.data!.isEmpty) {
                                 return SliverToBoxAdapter(
                                   child: Padding(
                                     padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 40.0), // Добавим отступы
                                     child: Center(
                                       child: Text(
                                        'У вас пока нет заметок. Нажмите "+", чтобы добавить первую.',
                                         textAlign: TextAlign.center,
                                         style: TextStyle(color: Colors.grey),
                                         ),
                                     ),
                                   ),
                                 );
                               }

                               final notes = snapshot.data!;

                               // Используем SliverGrid для отображения заметок
                               return SliverPadding(
                                 padding: const EdgeInsets.all(16.0),
                                 sliver: SliverGrid(
                                   gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                                     maxCrossAxisExtent: 200.0, // Макс. ширина элемента
                                     mainAxisSpacing: 10.0,
                                     crossAxisSpacing: 10.0,
                                     childAspectRatio: 1.0, // Делаем карточки квадратными
                                   ),
                                   delegate: SliverChildBuilderDelegate(
                                     (BuildContext context, int index) {
                                       final note = notes[index];
                                       return InkWell( // Делаем карточку кликабельной
                                         onTap: () => _showAddEditNoteDialog(note: note), // Открываем диалог редактирования
                                         child: Card(
                                           elevation: 2,
                                           child: Padding(
                                             padding: const EdgeInsets.all(12.0),
                                             child: Column(
                                               crossAxisAlignment: CrossAxisAlignment.start,
                                               children: [
                                                 Text(
                                                   note.title,
                                                   style: TextStyle(fontWeight: FontWeight.bold),
                                                   maxLines: 1,
                                                   overflow: TextOverflow.ellipsis,
                                                 ),
                                                 SizedBox(height: 8),
                                                 Expanded(
                                                   child: Text(
                                                     note.content,
                                                     style: TextStyle(color: Colors.grey[700]),
                                                     overflow: TextOverflow.ellipsis, // Обрезаем длинный текст
                                                     maxLines: 4, // Ограничиваем количество строк
                                     ),
                                   ),
                                ],
                               ),
                            ),
                                         ),
                                       );
                                     },
                                     childCount: notes.length,
                                   ),
                                 ),
                               );
                             },
                          ),
                          // --- КОНЕЦ: Секция для заметок ---
                        ],
                      ),
                    ),
    );
  }
} 