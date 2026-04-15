import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:country_picker/country_picker.dart';
import 'package:phone_number/phone_number.dart';
import '../models/family_person.dart';
import 'package:get_it/get_it.dart';
import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/profile_service_interface.dart';
import '../backend/models/profile_form_data.dart';
import '../widgets/glass_panel.dart';
import '../widgets/flow_overlays.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cityController = TextEditingController();
  final _maidenNameController = TextEditingController();

  DateTime? _birthDate;
  String? _countryCode;
  String? _countryName;
  String? _profileImageUrl;
  bool _isLoading = false;
  bool _isPhoneVerified = false;
  Gender _gender = Gender.unknown;

  final AuthServiceInterface _authService = GetIt.I<AuthServiceInterface>();
  final ProfileServiceInterface _profileService =
      GetIt.I<ProfileServiceInterface>();

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _middleNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    _maidenNameController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (_authService.currentUserId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: пользователь не авторизован')),
        );
        Navigator.pop(context);
        return;
      }

      final data = await _profileService.getCurrentUserProfileFormData();
      if (!mounted) return;

      // Разделяем displayName на компоненты, если отдельные поля не заполнены
      String displayName = data.displayName;
      List<String> nameParts = displayName.split(' ');

      setState(() {
        // Используем отдельные поля, если они есть
        _firstNameController.text = data.firstName.isNotEmpty
            ? data.firstName
            : (nameParts.isNotEmpty ? nameParts[0] : '');
        _lastNameController.text = data.lastName.isNotEmpty
            ? data.lastName
            : (nameParts.length > 1 ? nameParts.last : '');

        // Если есть отчество в отдельном поле или можно предположить из displayName
        _middleNameController.text = data.middleName.isNotEmpty
            ? data.middleName
            : (nameParts.length > 2
                ? nameParts.sublist(1, nameParts.length - 1).join(' ')
                : '');

        _usernameController.text = data.username;

        _emailController.text = data.email ?? '';
        _phoneController.text = data.phoneNumber;
        _cityController.text = data.city;
        _countryCode = data.countryCode;
        _countryName = data.countryName;
        _profileImageUrl = data.photoUrl;
        _isPhoneVerified = data.isPhoneVerified;

        _gender = data.gender;

        _birthDate = data.birthDate;

        if (_gender == Gender.female) {
          _maidenNameController.text = data.maidenName;
        }
      });
    } catch (e) {
      debugPrint('Ошибка при загрузке данных пользователя: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка при загрузке данных: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      setState(() {
        _isLoading = true;
      });

      try {
        final imageUrl = await _profileService.uploadProfilePhoto(image);
        if (!mounted) return;

        if (imageUrl != null) {
          setState(() {
            _profileImageUrl = imageUrl;
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Не удалось получить URL изображения после загрузки.',
              ),
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки изображения: $e')),
        );
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _pickDate() async {
    final DateTime? pickedDate = await showRodnyaDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(1990),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (pickedDate != null) {
      setState(() {
        _birthDate = pickedDate;
      });
    }
  }

  Future<void> _selectCountry() async {
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      countryListTheme: CountryListThemeData(
        flagSize: 25,
        backgroundColor:
            Theme.of(context).colorScheme.surface.withValues(alpha: 0.98),
        textStyle: TextStyle(
          fontSize: 16,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
        bottomSheetHeight: 560,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28.0),
          topRight: Radius.circular(28.0),
        ),
        inputDecoration: InputDecoration(
          labelText: 'Поиск',
          hintText: 'Страна или код',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Theme.of(context)
              .colorScheme
              .surfaceContainerLowest
              .withValues(alpha: 0.92),
        ),
      ),
      onSelect: (Country country) {
        setState(() {
          _countryCode = country.countryCode;
          _countryName = country.name;
        });
      },
    );
  }

  Future<void> _verifyPhoneNumber() async {
    if (_phoneController.text.isEmpty || _countryCode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Введите номер телефона и выберите страну')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final phoneUtil = PhoneNumberUtil();
      bool isValid = false;

      final phoneNumberWithCode = '+$_countryCode${_phoneController.text}';

      try {
        isValid = await phoneUtil.validate(phoneNumberWithCode);
      } catch (e) {
        isValid = false;
        debugPrint('Ошибка валидации номера: $e');
      }

      if (!isValid) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Неверный формат номера телефона')),
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }

      await _profileService.verifyCurrentUserPhone(
        phoneNumber: _phoneController.text,
        countryCode: _countryCode!,
      );

      if (!mounted) return;
      setState(() {
        _isPhoneVerified = true;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Номер телефона проверен')));
    } catch (e) {
      if (!mounted) return;
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

  Future<void> _saveProfile({String? newPhotoUrl}) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final userId = _authService.currentUserId;
      if (userId == null) throw Exception('Пользователь не авторизован');

      // Создаем displayName из компонентов
      String displayName = [
        _firstNameController.text.trim(),
        _middleNameController.text.trim(),
        _lastNameController.text.trim(),
      ].where((part) => part.isNotEmpty).join(' ');

      await _profileService.saveCurrentUserProfileFormData(
        ProfileFormData(
          userId: userId,
          email: _emailController.text.trim(),
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          middleName: _middleNameController.text.trim(),
          displayName: displayName,
          username: _usernameController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          countryCode: _countryCode,
          countryName: _countryName,
          city: _cityController.text.trim(),
          photoUrl: newPhotoUrl ?? _profileImageUrl,
          isPhoneVerified: _isPhoneVerified,
          gender: _gender,
          maidenName:
              _gender == Gender.female ? _maidenNameController.text.trim() : '',
          birthDate: _birthDate,
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Профиль успешно обновлен')));

      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Ошибка при сохранении профиля: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка при сохранении: $e')));
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
    final dateFormat = DateFormat.yMMMMd('ru');
    final isWide = MediaQuery.of(context).size.width >= 920;

    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildAvatarCard(),
                        const SizedBox(height: 16),
                        if (isWide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildIdentitySection()),
                              const SizedBox(width: 16),
                              Expanded(
                                  child: _buildPersonalSection(dateFormat)),
                            ],
                          )
                        else ...[
                          _buildIdentitySection(),
                          const SizedBox(height: 16),
                          _buildPersonalSection(dateFormat),
                        ],
                        const SizedBox(height: 16),
                        _buildContactsSection(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: _isLoading ? null : _saveProfile,
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('Сохранить'),
        ),
      ),
    );
  }

  Widget _buildAvatarCard() {
    final theme = Theme.of(context);
    return GlassPanel(
      child: Row(
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 42,
                  backgroundImage: _profileImageUrl != null
                      ? NetworkImage(_profileImageUrl!)
                      : null,
                  child: _profileImageUrl == null
                      ? const Icon(Icons.person, size: 42)
                      : null,
                ),
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.camera_alt_outlined,
                    color: theme.colorScheme.onPrimary,
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Фото профиля',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Обновите аватар и основные данные.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: _pickImage,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Фото'),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentitySection() {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionTitle('Основное'),
          const SizedBox(height: 14),
          TextFormField(
            controller: _firstNameController,
            decoration: _inputDecoration('Имя'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Введите имя';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _lastNameController,
            decoration: _inputDecoration('Фамилия'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Введите фамилию';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _middleNameController,
            decoration: _inputDecoration('Отчество'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _usernameController,
            decoration: _inputDecoration('Username'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _emailController,
            readOnly: true,
            decoration: _inputDecoration(
              'Email',
              suffixIcon: const Icon(Icons.lock_outline),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalSection(DateFormat dateFormat) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionTitle('Личное'),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ChoiceChip(
                label: const Text('Мужской'),
                avatar: const Icon(Icons.male, size: 18),
                selected: _gender == Gender.male,
                onSelected: (_) {
                  setState(() {
                    _gender = Gender.male;
                  });
                },
              ),
              ChoiceChip(
                label: const Text('Женский'),
                avatar: const Icon(Icons.female, size: 18),
                selected: _gender == Gender.female,
                onSelected: (_) {
                  setState(() {
                    _gender = Gender.female;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildActionTile(
            icon: Icons.calendar_today_outlined,
            title: 'Дата рождения',
            subtitle: _birthDate != null
                ? dateFormat.format(_birthDate!)
                : 'Не указана',
            onTap: _pickDate,
          ),
          if (_gender == Gender.female) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _maidenNameController,
              decoration: _inputDecoration('Девичья фамилия'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContactsSection() {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionTitle('Контакты'),
          const SizedBox(height: 14),
          _buildActionTile(
            icon: Icons.public_outlined,
            title: 'Страна',
            subtitle: _countryName ?? 'Не указана',
            onTap: _selectCountry,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _cityController,
            decoration: _inputDecoration('Город'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: _inputDecoration(
                    'Телефон',
                    suffixIcon: _isPhoneVerified
                        ? const Icon(Icons.verified, color: Colors.green)
                        : null,
                    prefixText: _countryCode != null ? '+' : null,
                  ),
                ),
              ),
              if (!_isPhoneVerified) ...[
                const SizedBox(width: 10),
                FilledButton.tonal(
                  onPressed: _verifyPhoneNumber,
                  child: const Text('Проверить'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }

  InputDecoration _inputDecoration(
    String label, {
    String? hintText,
    Widget? suffixIcon,
    String? prefixText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      suffixIcon: suffixIcon,
      prefixText: prefixText,
      filled: true,
      fillColor: Theme.of(context)
          .colorScheme
          .surfaceContainerLowest
          .withValues(alpha: 0.88),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
