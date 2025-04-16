import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:country_picker/country_picker.dart';
import '../models/family_person.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import 'package:go_router/go_router.dart';

class CompleteProfileScreen extends StatefulWidget {
  final UserProfile? initialData;
  final Map<String, bool>? requiredFields;
  
  const CompleteProfileScreen({
    Key? key, 
    this.initialData,
    this.requiredFields,
  }) : super(key: key);
  
  @override
  _CompleteProfileScreenState createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _phoneController = TextEditingController();
  
  Gender _selectedGender = Gender.unknown;
  DateTime? _birthDate;
  String? _selectedCountry;
  String? _countryCode = '+7'; // По умолчанию российский код
  String? _phoneNumber;
  
  bool _isLoading = false;
  
  @override
  void initState() {
    super.initState();
    _loadExistingData();
  }
  
  Future<void> _loadExistingData() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Navigator.pushReplacementNamed(context, '/auth');
        return;
      }
      
      // Загружаем существующие данные пользователя
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      if (doc.exists) {
        final data = doc.data()!;
        
        setState(() {
          // Заполняем поля формы существующими данными
          _firstNameController.text = data['firstName'] ?? '';
          _lastNameController.text = data['lastName'] ?? '';
          _middleNameController.text = data['middleName'] ?? '';
          _usernameController.text = data['username'] ?? '';
          
          if (data['phoneNumber'] != null) {
            // Разделяем номер телефона на код страны и основной номер
            final phoneNumber = data['phoneNumber'] as String;
            if (phoneNumber.startsWith('+')) {
              // Находим первую цифру после + и определяем код страны
              int codeLength = 2; // По умолчанию длина кода 2 символа (+7, +1 и т.д.)
              if (phoneNumber.length > 3) {
                _countryCode = phoneNumber.substring(0, codeLength + 1); // +7, +1, ...
                _phoneController.text = phoneNumber.substring(codeLength + 1);
              } else {
                _phoneController.text = phoneNumber;
              }
            } else {
              _phoneController.text = phoneNumber;
            }
          }
          
          if (data['gender'] != null) {
            _selectedGender = _stringToGender(data['gender']);
          }
          
          if (data['birthDate'] != null) {
            _birthDate = (data['birthDate'] as Timestamp).toDate();
          }
          
          _selectedCountry = data['country'];
        });
      } else {
        // Если документ не существует, используем данные из Firebase Auth
        setState(() {
          _firstNameController.text = user.displayName?.split(' ').first ?? '';
          _lastNameController.text = user.displayName?.split(' ').last ?? '';
          _phoneController.text = user.phoneNumber ?? '';
        });
      }
    } catch (e) {
      print('Error loading user data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при загрузке данных пользователя')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Пользователь не авторизован');
      
      final fullPhoneNumber = _countryCode! + _phoneController.text.trim();
      final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      
      await userDocRef.set({
        'id': user.uid,
        'firstName': _firstNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'middleName': _middleNameController.text.trim(),
        'username': _usernameController.text.trim(),
        'email': user.email,
        'phoneNumber': fullPhoneNumber,
        'gender': _genderToString(_selectedGender),
        'birthDate': _birthDate != null ? Timestamp.fromDate(_birthDate!) : null,
        'country': _selectedCountry ?? 'Россия',
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true));
      
      // Обновляем отображаемое имя в Firebase Auth
      await user.updateDisplayName([
        _firstNameController.text.trim(),
        _lastNameController.text.trim(),
        _middleNameController.text.trim()
      ].where((part) => part.isNotEmpty).join(' '));
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Профиль успешно обновлен')),
      );
      
      // Переходим на главный экран
      if (mounted) {
        context.go('/');
      }
    } catch (e) {
      print('Ошибка при сохранении профиля: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при сохранении профиля: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // Конвертация пола из строки
  Gender _stringToGender(String value) {
    switch (value) {
      case 'male': return Gender.male;
      case 'female': return Gender.female;
      case 'other': return Gender.other;
      default: return Gender.unknown;
    }
  }
  
  // Конвертация пола в строку
  String _genderToString(Gender gender) {
    switch (gender) {
      case Gender.male: return 'male';
      case Gender.female: return 'female';
      case Gender.other: return 'other';
      case Gender.unknown: return 'unknown';
    }
  }
  
  @override
  Widget build(BuildContext context) {
    // Вывод страны и кода на экран для отладки
    print('Selected country: $_selectedCountry, code: $_countryCode');
    
    // Получаем список необходимых полей
    final needsGender = widget.requiredFields == null || 
        widget.requiredFields!['hasGender'] == false;
        
    final needsPhone = widget.requiredFields == null || 
        widget.requiredFields!['hasPhoneNumber'] == false;
        
    final needsUsername = widget.requiredFields == null || 
        widget.requiredFields!['hasUsername'] == false;
        
    return Scaffold(
      appBar: AppBar(
        title: Text('Завершение регистрации'),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Заполните профиль',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 16),
                    
                    // Имя
                    TextFormField(
                      controller: _firstNameController,
                      decoration: InputDecoration(
                        labelText: 'Имя',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                        hintText: 'Введите ваше имя',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Введите имя';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 16),
                    
                    // Фамилия
                    TextFormField(
                      controller: _lastNameController,
                      decoration: InputDecoration(
                        labelText: 'Фамилия',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                        hintText: 'Введите вашу фамилию',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Введите фамилию';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 16),
                    
                    // Отчество (опционально)
                    TextFormField(
                      controller: _middleNameController,
                      decoration: InputDecoration(
                        labelText: 'Отчество (если есть)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                        hintText: 'Введите ваше отчество',
                      ),
                    ),
                    
                    // Username (обязательно)
                    TextFormField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        labelText: 'Имя пользователя (username)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.alternate_email),
                        hintText: 'Введите уникальное имя пользователя',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Введите имя пользователя';
                        }
                        if (value.contains(' ')) { // Проверка на пробелы
                          return 'Имя пользователя не должно содержать пробелов';
                        }
                        // Можно добавить другие проверки (длина, символы)
                        return null;
                      },
                    ),
                    SizedBox(height: 16),
                    
                    // Телефон (обязательно)
                    Row(
                      children: [
                        // Выбор кода страны (можно оставить как есть или улучшить)
                        ElevatedButton(
                          onPressed: _selectCountry,
                          child: Text(_countryCode ?? '+?'),
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _phoneController,
                            decoration: InputDecoration(
                              labelText: 'Номер телефона',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.phone),
                              hintText: 'Введите номер телефона',
                            ),
                            keyboardType: TextInputType.phone,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Введите номер телефона';
                              }
                              // Можно добавить более строгую валидацию номера
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),

                    // Пол (опционально)
                    DropdownButtonFormField<Gender>(
                      value: _selectedGender,
                      decoration: InputDecoration(
                        labelText: 'Пол',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.wc),
                      ),
                      items: Gender.values.map((Gender gender) {
                        String genderText;
                        switch (gender) {
                          case Gender.male: genderText = 'Мужской'; break;
                          case Gender.female: genderText = 'Женский'; break;
                          case Gender.other: genderText = 'Другой'; break;
                          case Gender.unknown: genderText = 'Не указан'; break;
                        }
                        return DropdownMenuItem<Gender>(
                          value: gender,
                          child: Text(genderText),
                        );
                      }).toList(),
                      onChanged: (Gender? newValue) {
                        setState(() {
                          _selectedGender = newValue ?? Gender.unknown;
                        });
                      },
                    ),
                    SizedBox(height: 16),

                    // Дата рождения (опционально)
                    InkWell(
                      onTap: _selectDate,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Дата рождения',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          _birthDate == null
                              ? 'Выберите дату'
                              : DateFormat.yMMMMd('ru').format(_birthDate!),
                        ),
                      ),
                    ),
                    SizedBox(height: 16),

                    // Страна (опционально)
                    _buildCountryPicker(), // Используем существующий виджет выбора страны
                    
                    SizedBox(height: 32),
                    
                    // Кнопка сохранения
                    _isLoading
                      ? Center(child: CircularProgressIndicator())
                      : Center(
                        child: ElevatedButton(
                          onPressed: _saveProfile,
                          child: Text('Сохранить профиль'),
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                            textStyle: TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
  
  Widget _buildCountryPicker() {
    return GestureDetector(
      onTap: _selectCountry,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 15, horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(Icons.flag, color: Colors.grey[700]),
            SizedBox(width: 12),
            Text(_selectedCountry ?? 'Выберите страну'),
            Spacer(),
            Text(_countryCode ?? '+7', style: TextStyle(fontWeight: FontWeight.bold)),
            Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
  
  void _selectCountry() {
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      onSelect: (Country country) {
        setState(() {
          _countryCode = country.phoneCode;
          _selectedCountry = country.name;
        });
      },
    );
  }
  
  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      locale: const Locale('ru', 'RU'),
    );
    
    if (picked != null && picked != _birthDate) {
      setState(() {
        _birthDate = picked;
      });
    }
  }
  
  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _middleNameController.dispose();
    _usernameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
} 