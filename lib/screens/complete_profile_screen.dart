import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/profile_service_interface.dart';
import '../backend/models/profile_form_data.dart';
import '../models/family_person.dart';
import '../models/user_profile.dart';
import '../widgets/flow_overlays.dart';
import '../widgets/glass_panel.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({
    super.key,
    this.initialData,
    this.requiredFields,
  });

  final UserProfile? initialData;
  final Map<String, bool>? requiredFields;

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final AuthServiceInterface _authService = GetIt.I<AuthServiceInterface>();
  final ProfileServiceInterface _profileService =
      GetIt.I<ProfileServiceInterface>();
  final FamilyTreeServiceInterface _familyTreeService =
      GetIt.I<FamilyTreeServiceInterface>();
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _phoneController = TextEditingController();

  Gender _selectedGender = Gender.unknown;
  DateTime? _birthDate;
  String? _selectedCountry;
  String? _countryCode = '+7';

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadExistingData();
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

  Future<void> _loadExistingData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (_authService.currentUserId == null) {
        if (!mounted) return;
        context.go('/login');
        return;
      }

      final data = await _profileService.getCurrentUserProfileFormData();
      if (!mounted) return;

      setState(() {
        _firstNameController.text = data.firstName;
        _lastNameController.text = data.lastName;
        _middleNameController.text = data.middleName;
        _usernameController.text = data.username;
        _selectedGender = data.gender;
        _birthDate = data.birthDate;
        _selectedCountry = data.countryName;

        if (data.phoneNumber.isNotEmpty) {
          final phoneNumber = data.phoneNumber;
          if (phoneNumber.startsWith('+') && phoneNumber.length > 2) {
            final separatorIndex = phoneNumber.length > 11 ? 2 : 1;
            _countryCode = phoneNumber.substring(0, separatorIndex + 1);
            _phoneController.text = phoneNumber.substring(separatorIndex + 1);
          } else {
            _phoneController.text = phoneNumber;
          }
        }
      });
    } catch (e) {
      debugPrint('Error loading user data: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить профиль.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
      final fullPhoneNumber =
          '${_countryCode ?? '+7'}${_phoneController.text.trim()}';
      final currentUserId = _authService.currentUserId;
      if (currentUserId == null) {
        throw Exception('Пользователь не авторизован');
      }

      await _profileService.saveCurrentUserProfileFormData(
        ProfileFormData(
          userId: currentUserId,
          email: _authService.currentUserEmail,
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          middleName: _middleNameController.text.trim(),
          username: _usernameController.text.trim(),
          phoneNumber: fullPhoneNumber,
          gender: _selectedGender,
          birthDate: _birthDate,
          countryName: _selectedCountry ?? 'Россия',
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профиль сохранён.')),
      );
      context.go(await _resolvePostSaveLocation());
    } catch (e) {
      debugPrint('Ошибка при сохранении профиля: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при сохранении профиля: $e')),
      );
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.08),
              theme.colorScheme.surface,
              theme.colorScheme.secondary.withValues(alpha: 0.05),
            ],
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 980;
                  final dateFormat = DateFormat.yMMMd('ru');

                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildHeaderCard(),
                              const SizedBox(height: 16),
                              if (isWide)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: _buildIdentitySection()),
                                    const SizedBox(width: 16),
                                    Expanded(child: _buildContactsSection()),
                                  ],
                                )
                              else ...[
                                _buildIdentitySection(),
                                const SizedBox(height: 16),
                                _buildContactsSection(),
                              ],
                              const SizedBox(height: 16),
                              _buildPersonalSection(dateFormat),
                              const SizedBox(height: 20),
                              FilledButton(
                                onPressed: _isLoading ? null : _saveProfile,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(54),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Сохранить'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    final theme = Theme.of(context);

    return GlassPanel(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.account_circle_outlined,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Почти готово',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Нужны основные данные.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
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
            decoration: _inputDecoration(
              label: 'Имя',
              icon: Icons.person_outline,
            ),
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
            decoration: _inputDecoration(
              label: 'Фамилия',
              icon: Icons.badge_outlined,
            ),
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
            decoration: _inputDecoration(
              label: 'Отчество',
              icon: Icons.person_2_outlined,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _usernameController,
            decoration: _inputDecoration(
              label: 'Username',
              icon: Icons.alternate_email,
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Введите username';
              }
              if (value.contains(' ')) {
                return 'Без пробелов';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildContactsSection() {
    final theme = Theme.of(context);

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionTitle('Контакты'),
          const SizedBox(height: 14),
          _buildActionTile(
            icon: Icons.flag_outlined,
            title: _selectedCountry ?? 'Страна',
            subtitle: _countryCode ?? '+7',
            onTap: _selectCountry,
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest
                  .withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text(
                    _countryCode ?? '+7',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _phoneController,
                    decoration: _inputDecoration(
                      label: 'Телефон',
                      icon: Icons.phone_outlined,
                      noBorder: true,
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Введите телефон';
                      }
                      return null;
                    },
                  ),
                ),
              ],
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
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildGenderChip(
                label: 'Мужской',
                value: Gender.male,
                icon: Icons.male_rounded,
              ),
              _buildGenderChip(
                label: 'Женский',
                value: Gender.female,
                icon: Icons.female_rounded,
              ),
              _buildGenderChip(
                label: 'Не указан',
                value: Gender.unknown,
                icon: Icons.circle_outlined,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildActionTile(
            icon: Icons.calendar_today_outlined,
            title: 'Дата рождения',
            subtitle: _birthDate == null
                ? 'Не указана'
                : dateFormat.format(_birthDate!),
            onTap: _selectDate,
          ),
        ],
      ),
    );
  }

  Widget _buildGenderChip({
    required String label,
    required Gender value,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final isSelected = _selectedGender == value;

    return ChoiceChip(
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          _selectedGender = value;
        });
      },
      avatar: Icon(
        icon,
        size: 18,
        color: isSelected
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurfaceVariant,
      ),
      label: Text(label),
      backgroundColor:
          theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.88),
      selectedColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.92),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      side: BorderSide(
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.2)
            : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
      ),
      labelStyle: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
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
        color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(22),
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

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    bool noBorder = false,
  }) {
    final theme = Theme.of(context);
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor:
          theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.9),
      border: noBorder
          ? InputBorder.none
          : OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide.none,
            ),
      enabledBorder: noBorder
          ? InputBorder.none
          : OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide.none,
            ),
      focusedBorder: noBorder
          ? InputBorder.none
          : OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.35),
              ),
            ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    );
  }

  Future<String> _resolvePostSaveLocation() async {
    try {
      final pendingInvitations =
          await _familyTreeService.getPendingTreeInvitations().first;
      if (pendingInvitations.isNotEmpty) {
        return '/trees?tab=invitations';
      }
    } catch (_) {
      // Do not block navigation after save.
    }
    return '/';
  }

  void _selectCountry() {
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      countryListTheme: CountryListThemeData(
        backgroundColor:
            Theme.of(context).colorScheme.surface.withValues(alpha: 0.98),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        bottomSheetHeight: 560,
        inputDecoration: InputDecoration(
          labelText: 'Поиск',
          hintText: 'Страна или код',
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Theme.of(context)
              .colorScheme
              .surfaceContainerLowest
              .withValues(alpha: 0.9),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      onSelect: (Country country) {
        setState(() {
          _countryCode = '+${country.phoneCode}';
          _selectedCountry = country.name;
        });
      },
    );
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showRodnyaDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (picked != null && picked != _birthDate) {
      setState(() {
        _birthDate = picked;
      });
    }
  }
}
