import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/rustore_service.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({Key? key}) : super(key: key);

  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  
  // Контроллеры для полей ввода
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  
  // Дополнительные поля для регистрации
  String? _gender;
  DateTime? _birthDate;
  
  // Состояние формы
  bool _isLogin = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  String? _errorMessage;
  
  // Обработка авторизации/регистрации
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      if (_isLogin) {
        // Вход
        await _authService.loginWithEmail(
          _emailController.text,
          _passwordController.text,
        );
      } else {
        // Регистрация с расширенными данными
        await _authService.registerWithEmail(
          email: _emailController.text,
          password: _passwordController.text,
          name: _nameController.text,
        );
      }
      
      // Проверяем, что пользователь действительно авторизован
      if (_authService.currentUser != null) {
        // Явно перенаправляем пользователя на главную страницу
        if (mounted) {
          // Важно: используем rootNavigator, чтобы избежать проблем с вложенными навигаторами
          Navigator.of(context, rootNavigator: true)
              .pushNamedAndRemoveUntil('/', (route) => false);
          
          // Опционально: Показываем приветственное сообщение
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_isLogin ? 'Вход выполнен успешно!' : 'Регистрация успешна! Добро пожаловать!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Ошибка авторизации: пользователь не найден');
      }
    } on FirebaseAuthException catch (e) {
      String message;
      
      switch (e.code) {
        case 'user-not-found':
          message = 'Пользователь не найден';
          break;
        case 'wrong-password':
          message = 'Неверный пароль';
          break;
        case 'email-already-in-use':
          message = 'Этот email уже используется';
          break;
        case 'weak-password':
          message = 'Слишком простой пароль';
          break;
        case 'invalid-email':
          message = 'Неверный формат email';
          break;
        default:
          message = 'Ошибка: ${e.message}';
      }
      
      setState(() {
        _errorMessage = message;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Произошла ошибка: $e';
        _isLoading = false;
      });
    }
  }
  
  // Вход через Google
  Future<void> _signInWithGoogle() async {
    setState(() {
      _isGoogleLoading = true;
      _errorMessage = null;
    });
    
    try {
      await _authService.signInWithGoogle();
      
      // После успешного входа перенаправляем на главный экран
      if (mounted && _authService.currentUser != null) {
        Navigator.of(context, rootNavigator: true).pushReplacementNamed('/');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Ошибка входа через Google: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
        });
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),
                  
                  // Заголовок
                  Text(
                    _isLogin ? 'Вход в аккаунт' : 'Регистрация',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Подзаголовок
                  Text(
                    _isLogin
                        ? 'Введите свои данные для входа'
                        : 'Создайте свой аккаунт в Lineage',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // Сообщение об ошибке
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red[900]),
                      ),
                    ),
                  
                  // Поле для имени (только при регистрации)
                  if (!_isLogin)
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Ваше имя',
                        prefixIcon: Icon(Icons.person),
                      ),
                      keyboardType: TextInputType.name,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (!_isLogin && (value == null || value.trim().length < 2)) {
                          return 'Имя должно содержать не менее 2 символов';
                        }
                        return null;
                      },
                    ),
                  
                  if (!_isLogin) const SizedBox(height: 16),
                  
                  // Поле для email
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || !value.contains('@') || !value.contains('.')) {
                        return 'Введите корректный email адрес';
                      }
                      return null;
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Поле для пароля
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Пароль',
                      prefixIcon: Icon(Icons.lock),
                    ),
                    obscureText: true,
                    textInputAction: _isLogin ? TextInputAction.done : TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.length < 6) {
                        return 'Пароль должен содержать не менее 6 символов';
                      }
                      return null;
                    },
                  ),
                  
                  const SizedBox(height: 24),
                  
                  if (!_isLogin) ...[
                    // Дополнительные поля для регистрации
                    
                    // Поле для выбора пола
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Пол',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'male', child: Text('Мужской')),
                        DropdownMenuItem(value: 'female', child: Text('Женский')),
                        DropdownMenuItem(value: 'other', child: Text('Другой')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _gender = value;
                        });
                      },
                      validator: (value) {
                        if (!_isLogin && value == null) {
                          return 'Выберите пол';
                        }
                        return null;
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Поле для выбора даты рождения
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _birthDate ?? DateTime(2000),
                          firstDate: DateTime(1900),
                          lastDate: DateTime.now(),
                          helpText: 'Дата рождения',
                        );
                        if (date != null) {
                          setState(() {
                            _birthDate = date;
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Дата рождения',
                          prefixIcon: Icon(Icons.calendar_today),
                          errorText: (!_isLogin && _birthDate == null) ? 'Укажите дату рождения' : null,
                        ),
                        child: Text(
                          _birthDate == null 
                              ? 'Выберите дату рождения' 
                              : DateFormat('dd.MM.yyyy').format(_birthDate!),
                          style: TextStyle(
                            color: _birthDate == null ? Colors.grey : null,
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                  ],
                  
                  // Кнопка входа/регистрации
                  ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_isLogin ? 'Войти' : 'Зарегистрироваться'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Разделитель
                  Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'ИЛИ',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Кнопка входа через Google
                  OutlinedButton.icon(
                    onPressed: _isGoogleLoading ? null : _signInWithGoogle,
                    icon: _isGoogleLoading 
                        ? SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).primaryColor,
                            ),
                          )
                        : Icon(Icons.g_mobiledata, size: 24, color: Colors.red),
                    label: Text('Войти через Google'),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Переключение между входом и регистрацией
                  TextButton(
                    onPressed: _isLoading || _isGoogleLoading
                        ? null
                        : () {
                            setState(() {
                              _isLogin = !_isLogin;
                              _errorMessage = null;
                              
                              // Сбрасываем дополнительные поля при переключении на вход
                              if (_isLogin) {
                                _gender = null;
                                _birthDate = null;
                              }
                            });
                          },
                    child: Text(
                      _isLogin
                          ? 'Нет аккаунта? Зарегистрируйтесь'
                          : 'Уже есть аккаунт? Войдите',
                      style: TextStyle(color: Theme.of(context).primaryColor),
                    ),
                  ),
                  
                  // Ссылка на политику конфиденциальности
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: GestureDetector(
                      onTap: () {
                        // Используем GoRouter для перехода
                        GoRouter.of(context).push('/privacy');
                      },
                      child: Text(
                        'Продолжая, вы соглашаетесь с Политикой конфиденциальности',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                  
                  // Ссылка на восстановление пароля
                  if (_isLogin)
                    TextButton(
                      onPressed: _isLoading ? null : () {
                        Navigator.of(context).pushNamed('/password/reset');
                      },
                      child: Text(
                        'Забыли пароль?',
                        style: TextStyle(color: Theme.of(context).primaryColor),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }
} 