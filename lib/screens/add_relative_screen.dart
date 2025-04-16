import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/family_person.dart';
import '../services/family_service.dart';
import '../models/family_relation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../widgets/loading_indicator.dart';
import 'package:get_it/get_it.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';

class AddRelativeScreen extends StatefulWidget {
  final String treeId;
  final FamilyPerson? person;
  final FamilyPerson? relatedTo;
  final bool isEditing;
  final RelationType? predefinedRelation;

  const AddRelativeScreen({
    Key? key,
    required this.treeId,
    this.person,
    this.relatedTo,
    this.isEditing = false,
    this.predefinedRelation,
  }) : super(key: key);

  @override
  _AddRelativeScreenState createState() => _AddRelativeScreenState();
}

class _AddRelativeScreenState extends State<AddRelativeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _familyService = GetIt.I<FamilyService>();
  final _authService = AuthService();
  final _profileService = ProfileService();
  
  // Контроллеры для полей формы
  final _lastNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _maidenNameController = TextEditingController();
  final _birthPlaceController = TextEditingController();
  final _notesController = TextEditingController();
  
  // Состояние формы
  DateTime? _birthDate;
  DateTime? _deathDate;
  Gender? _selectedGender;
  RelationType? _selectedRelationType;
  RelationType? _relationType;
  RelationType? _initialRelationType;
  Gender _gender = Gender.unknown; // Пол текущего пользователя
  bool _isLoading = false;
  
  // Переменные для контекста из дерева
  FamilyPerson? _contextPerson;
  RelationType? _contextRelationType;
  bool _isLoadingContext = false;
  
  @override
  void initState() {
    super.initState();
    _loadUserGender();
    
    // Если редактируем существующего человека, заполняем форму его данными
    if (widget.isEditing && widget.person != null) {
      final nameParts = widget.person!.name.split(' ');
      String lastName = '';
      String firstName = '';
      String? middleName;
      if (nameParts.length >= 1) lastName = nameParts[0];
      if (nameParts.length >= 2) firstName = nameParts[1];
      if (nameParts.length >= 3) middleName = nameParts.sublist(2).join(' ');
      // -------------------------------------------------------------------
      _lastNameController.text = lastName;
      _firstNameController.text = firstName;
      _middleNameController.text = middleName ?? '';
      _maidenNameController.text = widget.person!.maidenName ?? '';
      _birthPlaceController.text = widget.person!.birthPlace ?? '';
      _notesController.text = widget.person!.notes ?? '';
      _selectedGender = widget.person!.gender;
      _birthDate = widget.person!.birthDate;
      _deathDate = widget.person!.deathDate;
      
      // Загружаем текущий тип отношения (правильно)
      _loadCurrentRelationType();
    }
    
    // Если добавляем к существующему родственнику, но не редактируем
    if (widget.relatedTo != null && !widget.isEditing) {
       // Используем predefinedRelation, если он есть
       if (widget.predefinedRelation != null) {
          setState(() {
            _selectedRelationType = widget.predefinedRelation;
            // Опционально: можно попытаться угадать пол на основе связи,
            // но это может быть не всегда точно (например, для spouse/sibling).
            // Пока оставим пол неопределенным.
            _selectedGender = null; 
          });
       } else {
          // Если predefinedRelation нет, предлагаем тип по умолчанию (например, ребенок)
          _loadRelationType(); // Старая логика для RelationType по умолчанию
       }
    }

    // Обновляем виджет связи при изменении имени/фамилии или пола
    _firstNameController.addListener(_updateRelationshipWidget);
    _lastNameController.addListener(_updateRelationshipWidget);

    // Сначала проверяем контекст из GoRouter
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final extra = GoRouterState.of(context).extra;
      print("AddRelativeScreen initState: extra = $extra"); // Отладка
      if (extra is Map<String, dynamic> &&
          extra.containsKey('contextPersonId') &&
          extra.containsKey('relationType')) {
        final String contextPersonId = extra['contextPersonId'];
        final RelationType relationType = extra['relationType'];
        print("AddRelativeScreen initState: Found context from tree. Person ID: $contextPersonId, Relation: $relationType"); // Отладка
        _loadContextPerson(contextPersonId, relationType);
      } else if (widget.relatedTo != null) {
        // Используем relatedTo и predefinedRelation, если они переданы (из Details)
        print("AddRelativeScreen initState: Using relatedTo from widget: ${widget.relatedTo!.id}"); // Отладка
        _selectedRelationType = widget.predefinedRelation;
        // Предзаполнение пола на основе predefinedRelation и пола relatedTo
        _prefillGenderBasedOnRelation(widget.relatedTo!, widget.predefinedRelation);
      } else {
        // Добавление родственника к текущему пользователю
        print("AddRelativeScreen initState: Adding relative to current user."); // Отладка
        // Оставляем _selectedRelationType = null, пользователь выберет сам
      }
    });
  }
  
  void _updateRelationshipWidget() {
    // Перерисовываем виджет связи, чтобы обновить имя "Новый родственник"
    setState(() {});
  }
  
  Future<void> _pickDate(bool isBirthDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isBirthDate 
          ? (_birthDate ?? DateTime.now()) 
          : (_deathDate ?? DateTime.now()),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      locale: const Locale('ru', 'RU'),
    );
    
    if (picked != null) {
      setState(() {
        if (isBirthDate) {
          _birthDate = picked;
        } else {
          _deathDate = picked;
        }
      });
    }
  }
  
  Future<void> _loadRelation() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || widget.person == null) return;
      
      final relationSnapshot = await FirebaseFirestore.instance
          .collection('family_relations')
          .where('treeId', isEqualTo: widget.treeId)
          .where('person1Id', isEqualTo: user.uid)
          .where('person2Id', isEqualTo: widget.person!.id)
          .get();
      
      if (relationSnapshot.docs.isNotEmpty) {
        final relation = relationSnapshot.docs.first.data();
        setState(() {
          _relationType = RelationType.values.firstWhere(
            (type) => type.toString() == relation['relation1to2'],
            orElse: () => RelationType.other,
          );
        });
      }
    } catch (e) {
      print('Ошибка при загрузке родственной связи: $e');
    }
  }
  
  Future<void> _savePerson() async {
    if (_formKey.currentState!.validate()) {
    setState(() {
      _isLoading = true;
    });
    
    try {
        // Создаем объект с данными из формы
        final Map<String, dynamic> personData = {
          'firstName': _firstNameController.text.trim(),
          'lastName': _lastNameController.text.trim(),
          'middleName': _middleNameController.text.trim(),
          'gender': _selectedGender != null ? _genderToString(_selectedGender!) : 'unknown',
          'birthPlace': _birthPlaceController.text.trim(),
          'notes': _notesController.text.trim(),
        };
        
        // Добавляем даты, если они указаны
        if (_birthDate != null) {
          personData['birthDate'] = Timestamp.fromDate(_birthDate!);
        }
        
        if (_deathDate != null) {
          personData['deathDate'] = Timestamp.fromDate(_deathDate!);
        }
        
        // Добавляем девичью фамилию для женщин
        if (_selectedGender == Gender.female && _maidenNameController.text.isNotEmpty) {
          personData['maidenName'] = _maidenNameController.text.trim();
        }

        // Если редактируем существующего человека
        if (widget.isEditing) {
          if (widget.person != null) {
            // 1. Обновляем данные самого человека
            print('Сохранение редактирования: ID=${widget.person!.id}');
            print('Значение _selectedGender перед сохранением: $_selectedGender');
            print('Данные для сохранения (personData): $personData');
            await _familyService.updateRelative(widget.person!.id, personData);

            // 2. Обновляем связь, если она изменилась
            final userId = FirebaseAuth.instance.currentUser?.uid;
            if (userId != null && 
                _selectedRelationType != null && 
                _selectedRelationType != RelationType.other &&
                _selectedRelationType != _initialRelationType) 
            {
              print('Обновляем связь: ${_selectedRelationType} между ${widget.person!.id} и $userId');
              try {
                // Вызываем addRelation с позиционными аргументами
                await _familyService.addRelation(
                  widget.treeId,
                  widget.person!.id, // Редактируемый человек
                  userId,             // Текущий пользователь
                  _selectedRelationType!, // Новое отношение person1 -> person2
                );
                // Обновляем _initialRelationType после успешного сохранения
                _initialRelationType = _selectedRelationType;
                print('Связь успешно обновлена.');
              } catch (e) {
                 print('Ошибка при обновлении связи: $e');
                 if (mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(content: Text('Не удалось обновить связь: $e')),
                   );
                 }
                 // Не выходим из функции, так как данные человека могли обновиться
              }
            } else if (_selectedRelationType == _initialRelationType) {
               print('Связь не изменилась, обновление не требуется.');
            } else {
               print('Связь не выбрана или не изменилась, обновление связи не выполняется.');
            }

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Информация о родственнике обновлена')),
              );
            }
          } else {
             if (mounted) {
               ScaffoldMessenger.of(context).showSnackBar(
                 SnackBar(content: Text('Ошибка: Не удалось определить ID редактируемого родственника')),
               );
             }
             return; // Выходим, если некого редактировать
          }
        } else {
          // 2. Добавление нового родственника
          // addRelative теперь принимает только treeId и personData
          final newPersonId = await _familyService.addRelative(widget.treeId, personData);

          // Получаем ID текущего пользователя
          final userId = FirebaseAuth.instance.currentUser?.uid;
          if (userId == null) {
            throw Exception('Не удалось получить ID текущего пользователя.');
          }

          // Получаем выбранный тип отношения
          final relationType = _getRelationType();

          // Проверяем, что тип отношения выбран
          if (relationType != RelationType.other) {
            // Определяем ID второго человека в связи (КОГО связываем с новым)
            final String person2Id;
            if (_contextPerson != null) {
               person2Id = _contextPerson!.id; // Приоритет: контекст из дерева
            } else if (widget.relatedTo != null) {
               person2Id = widget.relatedTo!.id; // Приоритет: переданный relatedTo
            } else {
               person2Id = userId; // По умолчанию: текущий пользователь
            }
            
            // Если добавляем не к себе и не к текущему пользователю,
            // то создаем связь между новым человеком и тем, к кому добавляли (или с пользователем)
            if (newPersonId != person2Id) {
              try {
                // Создаем основную связь (например, newPersonId -> relationType -> person2Id)
                await _familyService.createRelation(
                  treeId: widget.treeId,
                  person1Id: newPersonId,
                  person2Id: person2Id,
                  relation1to2: relationType,
                  isConfirmed: true, 
                );
                print('Основная связь создана: $newPersonId ($relationType) -> $person2Id');

                // --- Автоматическое доопределение связей --- 
                if (relationType == RelationType.parent) {
                  // Если ДОБАВИЛИ РОДИТЕЛЯ (newPersonId) к ребенку (person2Id)
                  await _familyService.checkAndCreateSpouseRelationIfNeeded(widget.treeId, person2Id, newPersonId);
                  // TODO: Добавить вызов для создания связи дедушка/бабушка-внук/внучка

                } else if (relationType == RelationType.child) {
                  // Если ДОБАВИЛИ РЕБЕНКА (newPersonId) к родителю (person2Id)
                  // --- NEW: Проверяем, есть ли супруг у родителя, к которому добавили ребенка --- 
                  final String parentId = person2Id; // Родитель, к которому добавили
                  final String childId = newPersonId; // Добавленный ребенок

                  final spouseId = await _familyService.findSpouseId(widget.treeId, parentId);
                  print('Проверка супруга для родителя $parentId: найден spouseId = $spouseId');

                  if (mounted && spouseId != null) { // Проверяем mounted перед асинхронными операциями
                     // Загружаем данные родителя, супруга и ребенка для диалога
                     FamilyPerson? parentPerson = await _familyService.getPersonById(widget.treeId, parentId); // Нужен метод getPersonById
                     FamilyPerson? spousePerson = await _familyService.getPersonById(widget.treeId, spouseId); 
                     FamilyPerson? childPerson = await _familyService.getPersonById(widget.treeId, childId);

                     if (mounted && parentPerson != null && spousePerson != null && childPerson != null) { // Проверяем mounted снова
                        // Показываем диалог
                        bool? confirmSecondParent = await showDialog<bool>(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              title: Text('Подтвердить второго родителя?'),
                              content: Text('Является ли ${spousePerson.name} (${_getRelationNameForDialog(RelationType.spouse, spousePerson.gender)}) для ${parentPerson.name}) также родителем для ${childPerson.name}?'),
                              actions: <Widget>[
                                TextButton(
                                  child: Text('Нет'),
                                  onPressed: () {
                                    Navigator.of(context).pop(false); // Возвращаем false
                                  },
                                ),
                                TextButton(
                                  child: Text('Да'),
                                  onPressed: () {
                                    Navigator.of(context).pop(true); // Возвращаем true
                                  },
                                ),
                              ],
                            );
                          },
                        );

                        print('Результат диалога подтверждения второго родителя: $confirmSecondParent');

                        // Если пользователь подтвердил, создаем вторую связь
                        if (confirmSecondParent == true) {
                           print('Создание второй родительской связи: $spouseId (parent) -> $childId');
                           try {
                              await _familyService.createRelation(
                                 treeId: widget.treeId,
                                 person1Id: spouseId,
                                 person2Id: childId,
                                 relation1to2: RelationType.parent,
                                 isConfirmed: true,
                               );
                              print('Вторая родительская связь успешно создана.');
                           } catch (e) {
                              print('Ошибка создания второй родительской связи: $e');
                              if (mounted) {
                                 ScaffoldMessenger.of(context).showSnackBar(
                                   SnackBar(content: Text('Не удалось создать связь с ${spousePerson.name}: $e')),
                                 );
                              }
                           }
                        }
                     } else {
                        print('Не удалось загрузить данные для диалога подтверждения второго родителя.');
                     }
                  }
                  // --- END NEW --- 

                } else if (relationType == RelationType.sibling) {
                  // Если ДОБАВИЛИ СИБЛИНГА (newPersonId) к другому сиблингу (person2Id)
                  await _familyService.checkAndCreateParentSiblingRelations(widget.treeId, person2Id, newPersonId);
                }
                // --- Конец автоматического доопределения --- 

              } catch (e) {
                print("Ошибка создания связи: $e");
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Не удалось создать связь: $e'))
                  );
                }
              }
            } else {
              print("Попытка создать связь человека с самим собой проигнорирована.");
            }
          } else {
             print("Тип отношения не выбран или 'other', связь не создается.");
             // Опционально: показать сообщение пользователю
          }
        }

        // Закрываем экран в любом случае (успешное добавление или редактирование)
        if (mounted) {
          Navigator.pop(context, true); // Возвращаем true для обновления предыдущего экрана
        }

    } on FirebaseException catch (e) { // Ловим Firebase ошибки
        print('Firebase ошибка при сохранении: ${e.code} - ${e.message}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка Firestore: ${e.message}')),
          );
        }
    } catch (e) {
        print('Ошибка при сохранении: $e');
        if (mounted) { // Проверяем mounted перед показом SnackBar
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Произошла ошибка: $e')),
          );
        }
      } finally {
        if (mounted) { // Проверяем mounted перед setState
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }
  
  RelationType _getCorrespondingRelation(RelationType relationType) {
    switch (relationType) {
      case RelationType.parent:
        return RelationType.child;
      case RelationType.child:
        return RelationType.parent;
      case RelationType.spouse:
        return RelationType.spouse;
      case RelationType.sibling:
        return RelationType.sibling;
      case RelationType.cousin:
        return RelationType.cousin;
      case RelationType.uncle:
        return RelationType.nephew;
      case RelationType.aunt:
        return RelationType.nephew;
      case RelationType.nephew:
        return _gender == Gender.male ? RelationType.uncle : RelationType.aunt;
      case RelationType.grandparent:
        return RelationType.grandchild;
      case RelationType.grandchild:
        return RelationType.grandparent;
      case RelationType.other:
      default:
        return RelationType.other;
    }
  }
  
  RelationType _getReverseRelationType(RelationType relationType) {
    switch (relationType) {
      case RelationType.parent: return RelationType.child;
      case RelationType.child: return RelationType.parent;
      case RelationType.spouse: return RelationType.spouse;
      case RelationType.sibling: return RelationType.sibling;
      default: return RelationType.other;
    }
  }
  
  List<DropdownMenuItem<RelationType>> _getRelationTypeItems(Gender? anchorGender) {
    // Используем статический метод из FamilyRelation для получения и фильтрации связей
    return FamilyRelation.getAvailableRelationTypes(anchorGender)
        .map((type) => DropdownMenuItem(
              value: type,
              // Используем статический метод для получения описания
              // Передаем пол *нового* человека (_selectedGender)
              child: Text(FamilyRelation.getRelationDescription(type, _selectedGender)),
            ))
        .toList();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing 
          ? 'Редактирование родственника' 
          : widget.relatedTo != null 
            ? 'Добавление родственника к ${widget.relatedTo!.name}' 
            : 'Добавление родственника'),
        actions: [
          if (widget.isEditing)
            IconButton(
              icon: Icon(Icons.person_add),
              tooltip: 'Добавить родственника',
              onPressed: () {
                _showAddRelativeDialog();
              },
            ),
          if (widget.isEditing)
            IconButton(
              icon: Icon(Icons.delete),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Удаление родственника'),
                    content: Text('Вы уверены, что хотите удалить этого родственника?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Отмена'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _deletePerson();
                        },
                        child: Text('Удалить', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    // Контекстная информация о том, что делает пользователь
                    if (!widget.isEditing)
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.blue.shade100),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                              Row(
                                children: [
                                  Icon(Icons.info_outline, color: Colors.blue),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      widget.relatedTo != null
                                          ? 'Вы добавляете родственника к ${widget.relatedTo!.name}'
                                          : 'Вы добавляете нового родственника в свое семейное древо',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      SizedBox(height: 8),
                              Text(
                                widget.relatedTo != null
                                    ? 'Заполните информацию о родственнике и укажите, кем он является для ${widget.relatedTo!.name}'
                                    : 'Заполните информацию о родственнике и укажите, кем он является для вас',
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                        ),
                      ),
                    
                    SizedBox(height: 24),
                    
                    // Основная информация
                    Text(
                      'Основная информация',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    SizedBox(height: 16),
                    
                    // Фамилия
                      TextFormField(
                        controller: _lastNameController,
                        decoration: InputDecoration(
                          labelText: 'Фамилия',
                          border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Пожалуйста, введите фамилию';
                          }
                          return null;
                        },
                      ),
                    SizedBox(height: 16),
                    
                    // Имя
                      TextFormField(
                        controller: _firstNameController,
                        decoration: InputDecoration(
                          labelText: 'Имя',
                          border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Пожалуйста, введите имя';
                          }
                          return null;
                        },
                      ),
                    SizedBox(height: 16),
                    
                    // Отчество
                      TextFormField(
                        controller: _middleNameController,
                        decoration: InputDecoration(
                        labelText: 'Отчество',
                          border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    SizedBox(height: 24),
                    
                    // Пол
                    Text(
                      'Пол',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<Gender>(
                          title: Text('Мужской'),
                          value: Gender.male,
                          groupValue: _selectedGender,
                            onChanged: (value) {
                            print('RadioListTile onChanged: выбрано $value (был $_selectedGender)');
                            setState(() {
                              _selectedGender = value;
                            });
                          },
                            activeColor: Colors.blue,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: _selectedGender == Gender.male 
                                  ? Colors.blue 
                                  : Colors.grey.shade300,
                                width: _selectedGender == Gender.male ? 2 : 1,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 16),
                      Expanded(
                        child: RadioListTile<Gender>(
                          title: Text('Женский'),
                          value: Gender.female,
                          groupValue: _selectedGender,
                            onChanged: (value) {
                            print('RadioListTile onChanged: выбрано $value (был $_selectedGender)');
                            setState(() {
                              _selectedGender = value;
                            });
                          },
                            activeColor: Colors.pink,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: _selectedGender == Gender.female 
                                  ? Colors.pink 
                                  : Colors.grey.shade300,
                                width: _selectedGender == Gender.female ? 2 : 1,
                              ),
                            ),
                        ),
                      ),
                    ],
                  ),
                    SizedBox(height: 24),
                    
                    // Девичья фамилия (только для женщин)
                    if (_selectedGender == Gender.female)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _maidenNameController,
                            decoration: InputDecoration(
                              labelText: 'Девичья фамилия',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.person_outline),
                              helperText: 'Фамилия до замужества',
                            ),
                          ),
                          SizedBox(height: 24),
                        ],
                      ),
                    
                    // Даты
                    Text(
                      'Даты жизни',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    SizedBox(height: 16),
                  
                  // Дата рождения
                    InkWell(
                      onTap: () => _pickDate(true),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Дата рождения',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.cake),
                        ),
                        child: Text(
                          _birthDate != null
                              ? DateFormat('dd.MM.yyyy').format(_birthDate!)
                              : 'Выберите дату',
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  
                    // Дата смерти
                    InkWell(
                      onTap: () => _pickDate(false),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Дата смерти',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.event),
                          helperText: 'Оставьте пустым, если человек жив',
                        ),
                        child: Text(
                          _deathDate != null
                              ? DateFormat('dd.MM.yyyy').format(_deathDate!)
                              : 'Не указано',
                        ),
                      ),
                    ),
                    SizedBox(height: 24),
                    
                    // Дополнительная информация
                    Text(
                      'Дополнительная информация',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  SizedBox(height: 16),
                  
                  // Место рождения
                  TextFormField(
                    controller: _birthPlaceController,
                    decoration: InputDecoration(
                      labelText: 'Место рождения',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.location_on),
                    ),
                  ),
                  SizedBox(height: 16),
                  
                    // Заметки
                  TextFormField(
                    controller: _notesController,
                    decoration: InputDecoration(
                        labelText: 'Заметки',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.note),
                        helperText: 'Дополнительная информация о человеке',
                    ),
                    maxLines: 3,
                  ),
                    SizedBox(height: 24),
                    
                    // Виджет выбора родственной связи
                    _buildRelationshipSelector(),
                    SizedBox(height: 24),
                    
                    // Кнопка сохранения
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _savePerson,
                        child: Text(
                          widget.isEditing ? 'Сохранить изменения' : 'Добавить родственника',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                    SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }
  
  @override
  void dispose() {
    _lastNameController.removeListener(_updateRelationshipWidget);
    _firstNameController.removeListener(_updateRelationshipWidget);
    _middleNameController.dispose();
    _maidenNameController.dispose();
    _birthPlaceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Widget _buildRelationshipSelector() {
    // Используем _contextPerson если он есть, иначе widget.relatedTo
    final FamilyPerson? anchorPerson = _contextPerson ?? widget.relatedTo;
    final bool addingFromContext = _contextPerson != null;
    final bool isEditingMode = widget.isEditing;
    final bool isAddingToSelf = anchorPerson == null && !isEditingMode;

    // Определяем пол опорного человека (или текущего пользователя)
    final Gender? anchorGender = anchorPerson?.gender ?? _gender; // Используем _gender если anchorPerson null

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Родственная связь',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        SizedBox(height: 16),
        
        // ---- Виджет связи с КОНКРЕТНЫМ человеком (контекстным или relatedTo) ----
        if (anchorPerson != null)
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.blue.shade200, width: 1),
            ),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.family_restroom, color: Colors.blue),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          // Отображаем имя опорного человека
                          'Связь с ${anchorPerson.name}',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  Divider(height: 24),
                  Row(
                    children: [
                      // Блок существующего родственника (anchorPerson)
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade300),
                          ),
                          child: Column(
                            children: [
                              CircleAvatar(
                                backgroundColor: anchorPerson.gender == Gender.male
                                    ? Colors.blue.shade100
                                    : Colors.pink.shade100,
                                radius: 24,
                                child: Icon(
                                  Icons.person,
                                  color: anchorPerson.gender == Gender.male
                                      ? Colors.blue
                                      : Colors.pink,
                                  size: 32,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                anchorPerson.name,
                                style: TextStyle(fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Существующий родственник', 
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(Icons.arrow_back, color: Colors.grey),
                            SizedBox(height: 4),
                            // Выпадающий список связей
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              // Если добавляем из контекста дерева, связь нередактируема
                              child: addingFromContext
                                  ? Text(
                                      FamilyRelation.getRelationDescription(
                                          _contextRelationType!, // Связь от anchor к новому
                                          _selectedGender // Пол нового
                                      ),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber.shade900,
                                      ),
                                    )
                                  : DropdownButton<RelationType>(
                                value: _selectedRelationType,
                                underline: SizedBox(),
                                hint: Text('Выберите'),
                                      // Передаем пол *нового* человека (_selectedGender)
                                      items: _getRelationTypeItems(_selectedGender),
                                onChanged: (newValue) {
                                  setState(() {
                                    _selectedRelationType = newValue;
                                          // Предзаполняем пол нового, если возможно
                                          _prefillGenderBasedOnRelation(anchorPerson, newValue);
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Блок нового родственника
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade300),
                          ),
                          child: Column(
                            children: [
                              CircleAvatar(
                                backgroundColor: _selectedGender == Gender.male
                                    ? Colors.blue.shade100
                                    : _selectedGender == Gender.female
                                        ? Colors.pink.shade100
                                        : Colors.grey.shade100,
                                radius: 24,
                                child: Icon(
                                  Icons.person_add,
                                  color: _selectedGender == Gender.male
                                      ? Colors.blue
                                      : _selectedGender == Gender.female
                                          ? Colors.pink
                                          : Colors.grey,
                                  size: 32,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                _firstNameController.text.isEmpty &&
                                        _lastNameController.text.isEmpty
                                ? 'Новый родственник' 
                                    : '${_lastNameController.text} ${_firstNameController.text}'
                                        .trim(),
                                style: TextStyle(fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Добавляемый человек', 
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Text(
                    addingFromContext
                        ? 'Добавляем ${(_getRelationTypeDescription(_contextRelationType!)).toLowerCase()} для ${anchorPerson.name}'
                        : 'Выберите, кем является новый человек для ${anchorPerson.name}',
                    style: TextStyle(fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          
        SizedBox(height: 24),
        
        // ---- Виджет связи с ТЕКУЩИМ ПОЛЬЗОВАТЕЛЕМ (если нет anchorPerson ИЛИ режим редактирования) ----
        if (anchorPerson == null || isEditingMode)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isAddingToSelf
                 ? 'Кем этот человек является для вас?'
                 : 'Кем этот человек является для вас (в режиме редактирования)?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              DropdownButtonFormField<RelationType>(
                value: _selectedRelationType,
                decoration: InputDecoration(
                  labelText: 'Родственная связь с вами',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.family_restroom),
                ),
                // Передаем пол ТЕКУЩЕГО пользователя для фильтрации
                items: _getRelationTypeItems(_gender), // Используем _gender
                onChanged: (newValue) {
                  setState(() {
                    _selectedRelationType = newValue;
                    // Предзаполняем пол нового на основе связи с пользователем
                    // Создаем временный объект FamilyPerson для текущего пользователя
                    final currentUserAsPerson = FamilyPerson(
                      id: FirebaseAuth.instance.currentUser?.uid ?? '',
                      treeId: widget.treeId,
                      name: 'Вы', // Имя не так важно здесь
                      gender: _gender ?? Gender.unknown,
                      isAlive: true, // Предполагаем
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                    );
                     _prefillGenderBasedOnRelation(currentUserAsPerson, newValue);
                  });
                },
                validator: (value) {
                   // Валидация нужна только если добавляем к себе
                  if (isAddingToSelf && value == null) {
                    return 'Пожалуйста, выберите родственную связь';
                  }
                  return null;
                },
              ),
               SizedBox(height: 24), // Добавим отступ
            ],
          ),
      ],
    );
  }

  // Обновляем _getRelationTypeDescription для использования FamilyRelation
  String _getRelationTypeDescription(RelationType type) {
    // Используем пол НОВОГО человека (_selectedGender)
    return FamilyRelation.getRelationDescription(type, _selectedGender);
  }

  Future<void> _deletePerson() async {
    if (widget.person == null) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Удаляем человека и все его связи
      await _familyService.deleteRelative(widget.treeId, widget.person!.id);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Родственник удален')),
      );
      
      Navigator.pop(context, true);
    } catch (e) {
      print('Ошибка при удалении: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при удалении: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUserGender() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;
      
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      
      if (userDoc.exists && userDoc.data()?['gender'] != null) {
        final genderStr = userDoc.data()!['gender'];
        setState(() {
          if (genderStr == 'male') {
            _gender = Gender.male;
          } else if (genderStr == 'female') {
            _gender = Gender.female;
          }
        });
      }
    } catch (e) {
      print('Ошибка при загрузке пола пользователя: $e');
    }
  }
  
  Future<void> _loadRelationType() async {
    if (widget.relatedTo == null) return;
    
    try {
      // Если есть начальный тип отношения, используем его
      if (widget.predefinedRelation != null) {
        setState(() {
          _selectedRelationType = widget.predefinedRelation;
          
          // Автоматически определяем пол на основе выбранной связи
          if (_selectedRelationType == RelationType.spouse) {
            // Для супруга/супруги определяем противоположный пол
            _selectedGender = widget.relatedTo!.gender == Gender.male ? 
              Gender.female : Gender.male;
          } else {
            // Для других типов связей не предполагаем конкретный пол
            _selectedGender = null;
          }
        });
      } else if (widget.relatedTo != null) {
        // Если нет начального типа отношения, предлагаем наиболее вероятный
        setState(() {
          // По умолчанию предлагаем "ребенок" для добавления к родственнику
          _selectedRelationType = RelationType.child;
          
          // Автоматически определяем пол на основе выбранной связи
          // Для ребенка не предполагаем конкретный пол
          _selectedGender = null;
        });
      }
    } catch (e) {
      print('Ошибка при загрузке типа отношения: $e');
    }
  }

  // Метод для загрузки текущего типа отношения при редактировании
  Future<void> _loadCurrentRelationType() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || widget.person == null || !widget.isEditing) return;

    try {
      // Получаем отношение пользователя к редактируемому человеку
      final relationUserToPerson = await _familyService.getRelationToUser(
        widget.treeId,
        widget.person!.id, // ID редактируемого человека
      );
      
      // Получаем обратное отношение (редактируемого человека к пользователю)
      final relationPersonToUser = FamilyRelation.getMirrorRelation(relationUserToPerson);
      
      print('Загружен текущий тип отношения (от ${widget.person!.id} к ${user.uid}): $relationPersonToUser');
      
      if (mounted) {
        setState(() {
          _selectedRelationType = relationPersonToUser; 
          _initialRelationType = relationPersonToUser; // Сохраняем для сравнения
        });
      }
    } catch (e) {
      print('Ошибка при загрузке типа текущего отношения: $e');
      if (mounted) {
         setState(() {
           _selectedRelationType = RelationType.other; // Ставим other в случае ошибки
           _initialRelationType = RelationType.other;
         });
      }
    }
  }

  // Метод для показа диалога добавления родственника
  void _showAddRelativeDialog() {
    if (widget.person == null) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Добавить родственника'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Кого вы хотите добавить для ${widget.person!.name}?'),
            SizedBox(height: 15),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _navigateToAddRelative(RelationType.parent);
              },
              child: Text('Родителя'),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 40),
              ),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _navigateToAddRelative(RelationType.child);
              },
              child: Text('Ребенка'),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 40),
              ),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _navigateToAddRelative(RelationType.spouse);
              },
              child: Text('Супруга/Супругу'),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 40),
              ),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _navigateToAddRelative(RelationType.sibling);
              },
              child: Text('Брата/Сестру'),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 40),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена'),
          ),
        ],
      ),
    );
  }
  
  // Метод для перехода на экран добавления родственника
  void _navigateToAddRelative(RelationType relationType) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddRelativeScreen(
          treeId: widget.treeId,
          relatedTo: widget.person,
          predefinedRelation: relationType,
        ),
      ),
    ).then((success) {
      if (success == true) {
        // Показываем сообщение об успешном добавлении
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Родственник успешно добавлен'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    });
  }

  // Вспомогательный метод для преобразования Gender в строку
  String _genderToString(Gender gender) {
    switch (gender) {
      case Gender.male: return 'male';
      case Gender.female: return 'female';
      case Gender.other: return 'other';
      case Gender.unknown: return 'unknown';
    }
  }

  // Добавляем недостающий метод
  RelationType _getRelationType() {
    return _selectedRelationType ?? RelationType.other;
  }

  // Загрузка данных Person из контекста дерева
  Future<void> _loadContextPerson(String personId, RelationType relationType) async {
    if (!mounted) return;
    setState(() {
      _isLoadingContext = true;
      _contextRelationType = relationType;
      _selectedRelationType = relationType; // Сразу выбираем отношение
    });
    print("AddRelativeScreen _loadContextPerson: Loading person $personId"); // Отладка
    try {
      final person = await _familyService.getPersonById(widget.treeId, personId);
      if (!mounted) return;
      setState(() {
        _contextPerson = person;
        _isLoadingContext = false;
        // Предзаполнение пола на основе relationType и пола _contextPerson
        _prefillGenderBasedOnRelation(_contextPerson!, _contextRelationType);
      });
      print("AddRelativeScreen _loadContextPerson: Loaded person ${_contextPerson?.name}"); // Отладка
    } catch (e) {
      print('Ошибка при загрузке Person из контекста: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingContext = false;
        // TODO: Показать ошибку пользователю?
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось загрузить данные родственника для контекста.')),
      );
    }
  }

  // Предзаполнение пола на основе существующего родственника и типа связи
  void _prefillGenderBasedOnRelation(FamilyPerson anchorPerson, RelationType? relation) {
     if (relation == null) return;

     Gender? prefilledGender;
     // Логика определения пола нового родственника
     switch (relation) {
        case RelationType.parent:
        case RelationType.child:
        case RelationType.sibling:
        case RelationType.grandparent:
        case RelationType.grandchild:
        // Для этих связей пол не очевиден
          prefilledGender = null;
          break;
        case RelationType.spouse:
        case RelationType.partner: // Добавлено
        case RelationType.ex_spouse: // Добавлено
        case RelationType.ex_partner: // Добавлено
        // Пол противоположный
          prefilledGender = (anchorPerson.gender == Gender.male) ? Gender.female : Gender.male;
          break;
       // Для других типов (friend, colleague, other) пол не определяем
       default:
         prefilledGender = null;
     }

     // Устанавливаем только если пол еще не выбран
     if (_selectedGender == null && prefilledGender != null) {
        print("AddRelativeScreen _prefillGenderBasedOnRelation: Pre-filling gender to $prefilledGender based on relation $relation and anchor person gender ${anchorPerson.gender}"); // Отладка
        setState(() {
           _selectedGender = prefilledGender;
        });
     }
  }

  // Вспомогательный метод для получения названия связи для диалога
  String _getRelationNameForDialog(RelationType type, Gender? gender) {
    return FamilyRelation.getRelationName(type, gender); 
  }
} 