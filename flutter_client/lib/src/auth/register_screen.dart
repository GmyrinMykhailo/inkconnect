import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../city/city_catalog.dart';
import '../validators.dart';
import '../widgets/city_autocomplete_field.dart';
import 'auth_styles.dart';
import 'auth_widgets.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    required this.api,
    required this.onRegister,
    required this.onOpenLogin,
    this.errorText,
  });

  final InkConnectApiClient api;
  final Future<void> Function(Map<String, dynamic> payload) onRegister;
  final VoidCallback onOpenLogin;
  final String? errorText;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  final _passwordConfirmFocusNode = FocusNode();
  final _cityController = TextEditingController();
  final _bioController = TextEditingController();
  final _studioController = TextEditingController();

  CityOption? _selectedCity;
  String _role = 'client';
  bool _showCity = false;
  bool _agreementAccepted = false;
  bool _submitting = false;

  bool _usernameChecking = false;
  bool? _usernameAvailable;
  String? _usernameError;
  Timer? _usernameDebounce;
  int _usernameRequestNonce = 0;

  bool _emailChecking = false;
  bool? _emailAvailable;
  String? _emailError;
  Timer? _emailDebounce;
  int _emailRequestNonce = 0;

  bool _phoneChecking = false;
  bool? _phoneAvailable;
  String? _phoneError;
  Timer? _phoneDebounce;
  int _phoneRequestNonce = 0;

  bool _obscurePassword = true;
  bool _obscurePasswordConfirm = true;

  @override
  void initState() {
    super.initState();
    _passwordFocusNode.addListener(_handlePasswordFocusChange);
    _passwordConfirmFocusNode.addListener(_handlePasswordConfirmFocusChange);
  }

  bool get _isMaster => _role == 'master';

  Iterable<String> get _nameValues => [
        _lastNameController.text,
        _firstNameController.text,
        _middleNameController.text,
      ];

  bool get _canSubmit {
    return !_submitting &&
        !_usernameChecking &&
        !_emailChecking &&
        !_phoneChecking &&
        _agreementAccepted &&
        (_usernameAvailable ?? false) &&
        (_emailAvailable ?? false) &&
        (_phoneAvailable ?? false) &&
        isValidEmail(_emailController.text) &&
        isValidPassword(_passwordController.text) &&
        isValidPassword(_passwordConfirmController.text) &&
        _passwordController.text == _passwordConfirmController.text &&
        normalizePhoneDigits(_phoneController.text).length == 10 &&
        _hasSelectedCity &&
        isValidHumanName(_lastNameController.text) &&
        isValidHumanName(_firstNameController.text) &&
        (_middleNameController.text.isEmpty ||
            isValidHumanName(_middleNameController.text)) &&
        hasConsistentNameScript(_nameValues);
  }

  List<String> get _stepTitles => const [
        'Публичный профиль',
        'Личные данные',
        'Контакты и доступ',
        'Роль и профиль',
        'Подтверждение',
      ];

  bool get _profileStepComplete =>
      isValidUsername(_usernameController.text.trim()) &&
      _usernameAvailable == true;

  bool get _personalStepComplete =>
      isValidHumanName(_lastNameController.text) &&
      isValidHumanName(_firstNameController.text) &&
      (_middleNameController.text.isEmpty ||
          isValidHumanName(_middleNameController.text)) &&
      hasConsistentNameScript(_nameValues);

  bool get _contactsStepComplete =>
      isValidEmail(_emailController.text) &&
      _emailAvailable == true &&
      normalizePhoneDigits(_phoneController.text).length == 10 &&
      _phoneAvailable == true &&
      isValidPassword(_passwordController.text) &&
      isValidPassword(_passwordConfirmController.text) &&
      _passwordController.text == _passwordConfirmController.text;

  bool get _roleStepComplete =>
      _role.trim().isNotEmpty && _hasSelectedCity;

  bool get _hasSelectedCity {
    final selected = _selectedCity;
    return selected != null &&
        selected.displayName == _cityController.text.trim();
  }

  bool get _confirmationStepComplete => _agreementAccepted;

  List<bool> get _stepCompletionStates => [
        _profileStepComplete,
        _personalStepComplete,
        _contactsStepComplete,
        _roleStepComplete,
        _confirmationStepComplete,
      ];

  Set<int> get _completedStepIndexes => {
        for (var i = 0; i < _stepCompletionStates.length; i++)
          if (_stepCompletionStates[i]) i,
      };

  int get _activeStepIndex {
    for (var i = 0; i < _stepCompletionStates.length; i++) {
      if (!_stepCompletionStates[i]) {
        return i;
      }
    }
    return _stepCompletionStates.length - 1;
  }

  List<AuthStepItemData> get _stepItems => List.generate(
        _stepTitles.length,
        (index) => AuthStepItemData(
          label: _stepTitles[index],
          status: _completedStepIndexes.contains(index)
              ? AuthStepStatus.completed
              : index == _activeStepIndex
              ? AuthStepStatus.active
              : AuthStepStatus.pending,
        ),
      );

  List<AuthStepItemData> get _tabletStepItems => [
        AuthStepItemData(
          label: 'РџСѓР±Р»РёС‡РЅС‹Р№ РїСЂРѕС„РёР»СЊ',
          status: _stepItems[0].status,
        ),
        AuthStepItemData(
          label: 'Р›РёС‡РЅС‹Рµ РґР°РЅРЅС‹Рµ',
          status: _stepItems[1].status,
        ),
        AuthStepItemData(
          label: 'РљРѕРЅС‚Р°РєС‚С‹',
          status: _stepItems[2].status,
        ),
        AuthStepItemData(
          label: 'Р РѕР»СЊ',
          status: _stepItems[3].status,
        ),
        AuthStepItemData(
          label: 'РџРѕРґС‚РІРµСЂР¶РґРµРЅРёРµ',
          status: _stepItems[4].status,
        ),
      ];

  String? get _usernameStatus {
    if (_usernameChecking) {
      return 'Проверяем доступность никнейма...';
    }
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      return null;
    }
    if (!isValidUsername(username)) {
      return 'Используйте только латинские буквы, цифры и символы . _ -';
    }
    if (_usernameAvailable == true) {
      return 'Никнейм свободен.';
    }
    if (_usernameAvailable == false) {
      return _usernameError?.isNotEmpty == true
          ? _usernameError
          : 'Этот никнейм уже занят.';
    }
    return null;
  }

  bool get _usernameStatusIsError =>
      _usernameStatus != null && _usernameStatus != 'Никнейм свободен.';

  String? get _emailNote {
    final value = _emailController.text.trim();
    if (value.isEmpty) {
      return null;
    }
    if (!isValidEmail(value)) {
      return 'Введите корректный email в латинице, например name@example.com.';
    }
    if (_emailChecking) {
      return 'Проверяем, зарегистрирован ли этот email...';
    }
    if (_emailAvailable == true) {
      return 'Email свободен.';
    }
    if (_emailAvailable == false) {
      return _emailError?.isNotEmpty == true
          ? _emailError
          : 'Пользователь с таким email уже зарегистрирован.';
    }
    return null;
  }

  String? get _phoneNote {
    final value = _phoneController.text;
    if (value.trim().isEmpty) {
      return null;
    }
    if (normalizePhoneDigits(value).length != 10) {
      return 'Введите полный номер: после +7 нужно 10 цифр.';
    }
    if (_phoneChecking) {
      return 'Проверяем, зарегистрирован ли этот телефон...';
    }
    if (_phoneAvailable == true) {
      return 'Телефон свободен.';
    }
    if (_phoneAvailable == false) {
      return _phoneError?.isNotEmpty == true
          ? _phoneError
          : 'Пользователь с таким телефоном уже зарегистрирован.';
    }
    return null;
  }

  String? get _passwordNote {
    final value = _passwordController.text;
    if (value.isEmpty || isValidPassword(value)) {
      return null;
    }
    return 'Пароль: минимум 10 символов, буквы, цифры и спецсимвол, без пробелов в начале и конце.';
  }

  String? get _passwordConfirmNote {
    final value = _passwordConfirmController.text;
    if (value.isEmpty) {
      return null;
    }
    if (!isValidPassword(value)) {
      return 'Подтверждение пароля должно быть не короче 10 символов, содержать буквы, цифры и спецсимвол, без пробелов в начале и конце.';
    }
    if (value != _passwordController.text) {
      return 'Пароли не совпадают.';
    }
    return 'Пароли совпадают.';
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _emailDebounce?.cancel();
    _phoneDebounce?.cancel();
    _passwordFocusNode
      ..removeListener(_handlePasswordFocusChange)
      ..dispose();
    _passwordConfirmFocusNode
      ..removeListener(_handlePasswordConfirmFocusChange)
      ..dispose();
    _usernameController.dispose();
    _lastNameController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    _cityController.dispose();
    _bioController.dispose();
    _studioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 600;
        final tablet = constraints.maxWidth >= 600 && constraints.maxWidth < 1024;

        if (mobile) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 6),
              const AuthBrand(center: true),
              const SizedBox(height: 12),
              _buildMobileProgress(),
              const SizedBox(height: 10),
              _buildRegisterCard(mobile: true),
            ],
          );
        }

        if (tablet) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthBrand(center: true),
                  const SizedBox(height: 22),
                  _buildTabletSteps(),
                  const SizedBox(height: 14),
                  _buildRegisterCard(mobile: false),
                ],
              ),
            ),
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 272,
              child: AuthStepperSidebar(
                title: 'Регистрация',
                subtitle: 'Создайте аккаунт клиента или мастера.',
                items: _stepItems,
              ),
            ),
            const SizedBox(width: 28),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: _buildRegisterCard(mobile: false),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRegisterCard({required bool mobile}) {
    return AuthFormCard(
      padding: EdgeInsets.fromLTRB(
        mobile ? 16 : 34,
        mobile ? 16 : 28,
        mobile ? 16 : 34,
        mobile ? 18 : 28,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AuthHeader(
              title: 'Регистрация',
              subtitle: 'Создайте аккаунт клиента или мастера',
            ),
            if (widget.errorText != null) ...[
              const SizedBox(height: 16),
              AuthErrorBanner(message: widget.errorText!),
            ],
            SizedBox(height: mobile ? 18 : 22),
            _buildPublicProfileSection(mobile: mobile),
            SizedBox(height: mobile ? 14 : 16),
            _buildPersonalDataSection(mobile: mobile),
            SizedBox(height: mobile ? 14 : 16),
            _buildContactSection(mobile: mobile),
            SizedBox(height: mobile ? 14 : 16),
            _buildRoleSection(mobile: mobile),
            SizedBox(height: mobile ? 14 : 16),
            _buildConfirmationSection(context),
            SizedBox(height: mobile ? 18 : 22),
            _buildSubmitButton(),
            const SizedBox(height: 14),
            AuthFooterRow(
              prompt: 'Уже зарегистрированы?',
              actionLabel: 'Войти в систему',
              onPressed: widget.onOpenLogin,
              center: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabletSteps() {
    return AuthStepStrip(
      title: 'Р­С‚Р°РїС‹ СЂРµРіРёСЃС‚СЂР°С†РёРё',
      items: _tabletStepItems,
    );
  }

  Widget _buildMobileProgressRefactored() {
    final stepCount = _stepTitles.length;
    final completedCount = _completedStepIndexes.length;
    final activeIndex = _activeStepIndex;
    final progress = (completedCount == stepCount ? stepCount : activeIndex + 1) /
        stepCount;

    return AuthMobileProgressCard(
      currentStep: activeIndex + 1,
      totalSteps: stepCount,
      title: _stepTitles[activeIndex],
      progress: progress,
    );
  }

  Widget _buildTabletStepsLegacy() {
    final completedIndexes = _completedStepIndexes;
    final activeIndex = _activeStepIndex;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
      decoration: BoxDecoration(
        color: authSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: authOutline.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Этапы регистрации',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: authText,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(_stepTitles.length, (index) {
              final completed = completedIndexes.contains(index);
              final active = index == activeIndex;
              return Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: completed || active ? authAccent : authSurface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: completed || active ? authAccent : authOutline,
                        ),
                      ),
                      child: Icon(
                        completed
                            ? Icons.check_rounded
                            : active
                                ? Icons.radio_button_checked_rounded
                                : Icons.circle_outlined,
                        size: 13,
                        color: completed || active ? Colors.white : authHint,
                      ),
                    ),
                    if (index != _stepTitles.length - 1)
                      Expanded(
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          color: completed
                              ? authAccent.withValues(alpha: 0.38)
                              : authOutline,
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(
              _stepTitles.length,
              (index) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: index == _stepTitles.length - 1 ? 0 : 8,
                  ),
                  child: Text(
                    _stepTitles[index],
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight:
                          index == activeIndex ? FontWeight.w700 : FontWeight.w500,
                      color: completedIndexes.contains(index) || index == activeIndex
                          ? authText
                          : authHint,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileProgress() => _buildMobileProgressRefactored();

  Widget _buildMobileProgressLegacy() {
    final stepCount = _stepTitles.length;
    final completedCount = _completedStepIndexes.length;
    final activeIndex = _activeStepIndex;
    final progress = (completedCount == stepCount ? stepCount : activeIndex + 1) /
        stepCount;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: authSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: authOutline.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Этап ${activeIndex + 1} из $stepCount',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: authAccent,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: progress,
              backgroundColor: authSoftPanel,
              valueColor: const AlwaysStoppedAnimation<Color>(authAccent),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _stepTitles[activeIndex],
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: authText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPublicProfileSection({required bool mobile}) {
    return AuthSectionCard(
      title: 'Публичный профиль',
      child: mobile
          ? AuthFieldBlock(
              field: _buildUsernameField(),
              note: _buildUsernameNote(),
              minNoteHeight: 34,
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: AuthFieldBlock(
                    field: _buildUsernameField(),
                    note: _buildUsernameStatusNote(),
                    minNoteHeight: 34,
                  ),
                ),
                const SizedBox(width: 18),
                const Expanded(
                  flex: 1,
                  child: Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: AuthFieldHint(
                      'Публичное имя, по которому другие пользователи смогут вас находить.',
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPersonalDataSection({required bool mobile}) {
    final fields = [
      AuthFieldBlock(
        field: _buildNameField(
          controller: _lastNameController,
          label: 'Фамилия *',
          hintText: 'Введите фамилию',
        ),
      ),
      AuthFieldBlock(
        field: _buildNameField(
          controller: _firstNameController,
          label: 'Имя *',
          hintText: 'Введите имя',
        ),
      ),
      AuthFieldBlock(
        field: _buildNameField(
          controller: _middleNameController,
          label: 'Отчество',
          hintText: 'Введите отчество',
          required: false,
        ),
      ),
    ];

    return AuthSectionCard(
      title: 'Личные данные',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mobile) ...[
            fields[0],
            const SizedBox(height: 8),
            fields[1],
            const SizedBox(height: 8),
            fields[2],
            const SizedBox(height: 6),
            const AuthFieldHint(
              'ФИО обязательно для регистрации, но это приватные данные. Они не показываются публично другим пользователям.',
            ),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: fields[0]),
                const SizedBox(width: 14),
                Expanded(child: fields[1]),
                const SizedBox(width: 14),
                Expanded(child: fields[2]),
                const SizedBox(width: 16),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: AuthFieldHint(
                      'Эти данные обязательны для регистрации, но не показываются публично.',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContactSection({required bool mobile}) {
    if (mobile) {
      return AuthSectionCard(
        title: 'Контакты и доступ',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AuthFieldBlock(
              field: _buildEmailField(),
              note: _emailNote != null
                  ? AuthFieldHint(
                      _emailNote!,
                      color: _emailAvailable == true ? authSuccess : authError,
                    )
                  : null,
              minNoteHeight: 24,
            ),
            const SizedBox(height: 8),
            AuthFieldBlock(
              field: _buildPhoneField(),
              note: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_phoneNote != null)
                    AuthFieldHint(
                      _phoneNote!,
                      color: _phoneAvailable == true ? authSuccess : authError,
                    ),
                  const SizedBox(height: 4),
                  const AuthFieldHint(
                    'Телефон и email обязательны, но это приватные данные. Они не показываются публично другим пользователям.',
                  ),
                ],
              ),
              minNoteHeight: 52,
            ),
            const SizedBox(height: 8),
            AuthFieldBlock(
              field: _buildPasswordField(),
              note: _passwordNote != null
                  ? AuthFieldHint(_passwordNote!, color: authError)
                  : null,
              minNoteHeight: 24,
            ),
            const SizedBox(height: 8),
            AuthFieldBlock(
              field: _buildPasswordConfirmField(),
              note: _passwordConfirmNote != null
                  ? AuthFieldHint(
                      _passwordConfirmNote!,
                      color: _passwordConfirmNote == 'Пароли совпадают.'
                          ? authSuccess
                          : authError,
                    )
                  : null,
              minNoteHeight: 24,
            ),
          ],
        ),
      );
    }

    return AuthSectionCard(
      title: 'Контакты и доступ',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AuthFieldBlock(
                  field: _buildEmailField(),
                  note: _emailNote != null
                      ? AuthFieldHint(
                          _emailNote!,
                          color: _emailAvailable == true ? authSuccess : authError,
                        )
                      : null,
                  minNoteHeight: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: AuthFieldBlock(
                  field: _buildPasswordField(),
                  note: _passwordNote != null
                      ? AuthFieldHint(_passwordNote!, color: authError)
                      : null,
                  minNoteHeight: 28,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: AuthFieldHint(
                    'Телефон и email обязательны, но это приватные данные. Они не показываются публично другим пользователям.',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AuthFieldBlock(
                  field: _buildPhoneField(),
                  note: _phoneNote != null
                      ? AuthFieldHint(
                          _phoneNote!,
                          color: _phoneAvailable == true ? authSuccess : authError,
                        )
                      : null,
                  minNoteHeight: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: AuthFieldBlock(
                  field: _buildPasswordConfirmField(),
                  note: _passwordConfirmNote != null
                      ? AuthFieldHint(
                          _passwordConfirmNote!,
                          color: _passwordConfirmNote == 'Пароли совпадают.'
                              ? authSuccess
                              : authError,
                        )
                      : null,
                  minNoteHeight: 28,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoleSection({required bool mobile}) {
    final roleCity = _buildResponsivePair(
      mobile: mobile,
      left: AuthFieldBlock(field: _buildRoleField()),
      right: AuthFieldBlock(field: _buildCityField()),
    );

    return AuthSectionCard(
      title: 'Роль и профиль',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          roleCity,
          const SizedBox(height: 10),
          Transform.translate(
            offset: const Offset(-6, 0),
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'Показывать город в профиле',
                style: TextStyle(color: authText),
              ),
              value: _showCity,
              onChanged: (value) {
                setState(() {
                  _showCity = value ?? false;
                });
              },
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _bioController,
            maxLines: 4,
            maxLength: 150,
            decoration: const InputDecoration(
              constraints: BoxConstraints(minHeight: 132),
              labelText: 'О себе',
              hintText: 'Расскажите немного о себе...',
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_isMaster) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _studioController,
              decoration: const InputDecoration(
                labelText: 'Студия или рабочее имя мастера',
                hintText: 'Можно оставить пустым',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConfirmationSection(BuildContext context) {
    return AuthSectionCard(
      title: 'Подтверждение',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Transform.translate(
            offset: const Offset(-6, 0),
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _agreementAccepted,
              onChanged: (value) {
                setState(() {
                  _agreementAccepted = value ?? false;
                });
              },
              title: const Text(
                'Я принимаю пользовательское соглашение и согласен на обработку персональных данных.',
                style: TextStyle(color: authText, fontSize: 14),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ),
          TextButton(
            onPressed: () => _showAgreementDialog(context),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            child: const Text(
              'Открыть текст соглашения',
              style: TextStyle(
                color: authAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _canSubmit ? _submit : null,
        style: authPrimaryButtonStyle(),
        child: _submitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('Зарегистрироваться'),
      ),
    );
  }

  Widget _buildUsernameField() {
    return TextFormField(
      controller: _usernameController,
      decoration: const InputDecoration(
        labelText: 'Ник *',
        hintText: 'Введите ник',
        errorStyle: TextStyle(fontSize: 0, height: 0),
      ),
      onChanged: (value) {
        final normalized = normalizeUsername(value);
        if (normalized != value) {
          _usernameController.value = TextEditingValue(
            text: normalized,
            selection: TextSelection.collapsed(offset: normalized.length),
          );
        }
        setState(() {
          _usernameAvailable = null;
          _usernameError = null;
        });
        _scheduleUsernameCheck();
      },
      onEditingComplete: _checkUsername,
      validator: (value) {
        if (!isValidUsername(value?.trim() ?? '')) {
          return 'Используйте только латинские буквы, цифры и символы . _ -';
        }
        if (_usernameAvailable != true) {
          return 'Подтвердите, что никнейм свободен.';
        }
        return null;
      },
    );
  }

  Widget _buildUsernameNote() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AuthFieldHint(
          'Публичное имя, по которому другие пользователи смогут вас находить.',
        ),
        if (_usernameStatus != null) ...[
          const SizedBox(height: 6),
          AuthFieldHint(
            _usernameStatus!,
            color: _usernameStatusIsError ? authError : authSuccess,
          ),
        ],
      ],
    );
  }

  Widget? _buildUsernameStatusNote() {
    if (_usernameStatus == null) {
      return null;
    }

    return AuthFieldHint(
      _usernameStatus!,
      color: _usernameStatusIsError ? authError : authSuccess,
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      decoration: const InputDecoration(
        labelText: 'Email *',
        hintText: 'Введите email',
        errorStyle: TextStyle(fontSize: 0, height: 0),
      ),
      onChanged: (value) {
        final normalized = normalizeEmail(value);
        if (normalized != value) {
          _emailController.value = TextEditingValue(
            text: normalized,
            selection: TextSelection.collapsed(offset: normalized.length),
          );
        }
        setState(() {
          _emailAvailable = null;
          _emailError = null;
        });
        _scheduleEmailCheck();
      },
      validator: (value) {
        if (!isValidEmail(value?.trim() ?? '')) {
          return 'Введите корректный email в латинице.';
        }
        if (_emailAvailable != true) {
          return 'Подтвердите, что email свободен.';
        }
        return null;
      },
    );
  }

  Widget _buildPhoneField() {
    return TextFormField(
      controller: _phoneController,
      keyboardType: TextInputType.phone,
      decoration: const InputDecoration(
        labelText: 'Телефон *',
        prefixText: '+7 ',
        hintText: '(___) ___-__-__',
        errorStyle: TextStyle(fontSize: 0, height: 0),
      ),
      onChanged: (value) {
        final formatted = formatPhone(value);
        if (formatted != value) {
          _phoneController.value = TextEditingValue(
            text: formatted,
            selection: TextSelection.collapsed(offset: formatted.length),
          );
        }
        setState(() {
          _phoneAvailable = null;
          _phoneError = null;
        });
        _schedulePhoneCheck();
      },
      validator: (value) {
        if (normalizePhoneDigits(value ?? '').length != 10) {
          return 'Введите полный номер: после +7 нужно 10 цифр.';
        }
        if (_phoneAvailable != true) {
          return 'Подтвердите, что телефон свободен.';
        }
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      focusNode: _passwordFocusNode,
      obscureText: _obscurePassword,
      decoration: InputDecoration(
        labelText: 'Пароль *',
        hintText: 'Введите пароль',
        errorStyle: const TextStyle(fontSize: 0, height: 0),
        suffixIcon: IconButton(
          tooltip: _obscurePassword ? 'Показать пароль' : 'Скрыть пароль',
          onPressed: () {
            setState(() {
              _obscurePassword = !_obscurePassword;
            });
          },
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: authHint,
          ),
        ),
      ),
      onChanged: (_) => setState(() {}),
      validator: (value) {
        if (!isValidPassword(value ?? '')) {
          return 'Пароль: минимум 10 символов, буквы, цифры и спецсимвол, без пробелов в начале и конце.';
        }
        return null;
      },
    );
  }

  Widget _buildPasswordConfirmField() {
    return TextFormField(
      controller: _passwordConfirmController,
      focusNode: _passwordConfirmFocusNode,
      obscureText: _obscurePasswordConfirm,
      decoration: InputDecoration(
        labelText: 'Подтверждение пароля *',
        hintText: 'Повторите пароль',
        errorStyle: const TextStyle(fontSize: 0, height: 0),
        suffixIcon: IconButton(
          tooltip: _obscurePasswordConfirm
              ? 'Показать пароль'
              : 'Скрыть пароль',
          onPressed: () {
            setState(() {
              _obscurePasswordConfirm = !_obscurePasswordConfirm;
            });
          },
          icon: Icon(
            _obscurePasswordConfirm
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: authHint,
          ),
        ),
      ),
      onChanged: (_) => setState(() {}),
      validator: (value) {
        if (!isValidPassword(value ?? '')) {
          return 'Подтверждение пароля должно быть не короче 10 символов, содержать буквы, цифры и спецсимвол, без пробелов в начале и конце.';
        }
        if (value != _passwordController.text) {
          return 'Пароли не совпадают.';
        }
        return null;
      },
    );
  }

  Widget _buildRoleField() {
    return DropdownButtonFormField<String>(
      initialValue: _role,
      items: const [
        DropdownMenuItem(value: 'client', child: Text('Клиент')),
        DropdownMenuItem(value: 'master', child: Text('Мастер')),
      ],
      decoration: const InputDecoration(labelText: 'Роль *'),
      onChanged: (value) {
        if (value == null) {
          return;
        }
        setState(() {
          _role = value;
          if (!_isMaster) {
            _studioController.clear();
          }
        });
      },
    );
  }

  Widget _buildCityField() {
    return CityAutocompleteField(
      controller: _cityController,
      selectedOption: _selectedCity,
      isRequired: true,
      labelText: 'Город *',
      hintText: 'Начните вводить город',
      onSelected: (option) {
        _selectedCity = option;
      },
      onChanged: () {
        setState(() {});
      },
    );
  }

  Widget _buildNameField({
    required TextEditingController controller,
    required String label,
    String? hintText,
    bool required = true,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
      ),
      onChanged: (value) {
        final script = currentNameScript(_nameValues);
        final normalized = normalizeName(value, script);
        if (normalized != value) {
          controller.value = TextEditingValue(
            text: normalized,
            selection: TextSelection.collapsed(offset: normalized.length),
          );
        }
        setState(() {});
      },
      validator: (value) {
        final trimmed = value?.trim() ?? '';
        if (required && trimmed.isEmpty) {
          return 'Обязательное поле.';
        }
        if (trimmed.isNotEmpty && !isValidHumanName(trimmed)) {
          return 'Допустимы только русские или английские буквы, пробел и дефис.';
        }
        if (!hasConsistentNameScript(_nameValues)) {
          return 'Все поля ФИО должны быть в одной раскладке.';
        }
        return null;
      },
    );
  }

  Widget _buildResponsivePair({
    required bool mobile,
    required Widget left,
    required Widget right,
  }) {
    if (mobile) {
      return Column(
        children: [
          left,
          const SizedBox(height: 12),
          right,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 14),
        Expanded(child: right),
      ],
    );
  }

  Widget _buildFieldBlockLegacy({
    required Widget field,
    Widget? note,
    double minNoteHeight = 36,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        field,
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: minNoteHeight),
          child: note ?? const SizedBox.shrink(),
        ),
      ],
    );
  }

  void _scheduleUsernameCheck() {
    _usernameDebounce?.cancel();
    final username = _usernameController.text.trim();
    if (!isValidUsername(username)) {
      return;
    }

    _usernameDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        _checkUsername();
      }
    });
  }

  void _scheduleEmailCheck() {
    _emailDebounce?.cancel();
    final email = _emailController.text.trim();
    if (!isValidEmail(email)) {
      return;
    }

    _emailDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        _checkEmail();
      }
    });
  }

  void _schedulePhoneCheck() {
    _phoneDebounce?.cancel();
    if (normalizePhoneDigits(_phoneController.text).length != 10) {
      return;
    }

    _phoneDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        _checkPhone();
      }
    });
  }

  Future<void> _checkUsername() async {
    _usernameDebounce?.cancel();
    final username = _usernameController.text.trim();
    if (!isValidUsername(username)) {
      setState(() {
        _usernameAvailable = false;
        _usernameError = username.isEmpty
            ? null
            : 'Используйте только латинские буквы, цифры и символы . _ -';
      });
      return;
    }

    setState(() {
      _usernameChecking = true;
      _usernameError = null;
    });

    final requestNonce = ++_usernameRequestNonce;

    try {
      final available = await widget.api.isUsernameAvailable(username);
      if (!mounted ||
          requestNonce != _usernameRequestNonce ||
          username != _usernameController.text.trim()) {
        return;
      }
      setState(() {
        _usernameAvailable = available;
        _usernameError = available ? null : 'Этот никнейм уже занят.';
      });
    } on ApiException catch (error) {
      if (!mounted || requestNonce != _usernameRequestNonce) {
        return;
      }
      setState(() {
        _usernameAvailable = false;
        _usernameError = error.message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _usernameChecking = false;
        });
      }
    }
  }

  Future<void> _checkEmail() async {
    _emailDebounce?.cancel();
    final email = _emailController.text.trim();
    if (!isValidEmail(email)) {
      setState(() {
        _emailAvailable = false;
        _emailError = email.isEmpty
            ? null
            : 'Введите корректный email в латинице, например name@example.com.';
      });
      return;
    }

    setState(() {
      _emailChecking = true;
      _emailError = null;
    });

    final requestNonce = ++_emailRequestNonce;

    try {
      final available = await widget.api.isEmailAvailable(email);
      if (!mounted ||
          requestNonce != _emailRequestNonce ||
          email != _emailController.text.trim()) {
        return;
      }
      setState(() {
        _emailAvailable = available;
        _emailError = available
            ? null
            : 'Пользователь с таким email уже зарегистрирован.';
      });
    } on ApiException catch (error) {
      if (!mounted || requestNonce != _emailRequestNonce) {
        return;
      }
      setState(() {
        _emailAvailable = false;
        _emailError = error.message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _emailChecking = false;
        });
      }
    }
  }

  Future<void> _checkPhone() async {
    _phoneDebounce?.cancel();
    final digits = normalizePhoneDigits(_phoneController.text);
    if (digits.length != 10) {
      setState(() {
        _phoneAvailable = false;
        _phoneError = digits.isEmpty
            ? null
            : 'Введите полный номер: после +7 нужно 10 цифр.';
      });
      return;
    }

    final normalizedPhone = '+7$digits';
    setState(() {
      _phoneChecking = true;
      _phoneError = null;
    });

    final requestNonce = ++_phoneRequestNonce;

    try {
      final available = await widget.api.isPhoneAvailable(normalizedPhone);
      if (!mounted ||
          requestNonce != _phoneRequestNonce ||
          digits != normalizePhoneDigits(_phoneController.text)) {
        return;
      }
      setState(() {
        _phoneAvailable = available;
        _phoneError = available
            ? null
            : 'Пользователь с таким телефоном уже зарегистрирован.';
      });
    } on ApiException catch (error) {
      if (!mounted || requestNonce != _phoneRequestNonce) {
        return;
      }
      setState(() {
        _phoneAvailable = false;
        _phoneError = error.message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _phoneChecking = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    await _checkUsername();
    await _checkEmail();
    await _checkPhone();
    if (!_formKey.currentState!.validate() || !_canSubmit) {
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      await widget.onRegister({
        'username': _usernameController.text.trim(),
        'email': _emailController.text.trim(),
        'password': _passwordController.text,
        'password_confirm': _passwordConfirmController.text,
        'role': _role,
        'last_name': _lastNameController.text.trim(),
        'first_name': _firstNameController.text.trim(),
        'middle_name': _middleNameController.text.trim(),
        'phone': '+7${normalizePhoneDigits(_phoneController.text)}',
        'city': _cityController.text.trim(),
        'show_city_in_profile': _showCity,
        'bio': _bioController.text.trim(),
        'studio_name': _studioController.text.trim(),
        'agreement_accepted': _agreementAccepted,
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _showAgreementDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Пользовательское соглашение'),
          content: const SingleChildScrollView(
            child: Text(
              'Это текущий технический вариант документа для регистрации в InkConnect. '
              'Согласие нужно для создания учетной записи, авторизации, отображения профиля и тестирования бизнес-логики проекта. '
              'Полный placeholder-документ также доступен на backend по пути /static/docs/user-agreement.html.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Закрыть'),
            ),
          ],
        );
      },
    );
  }

  void _handlePasswordFocusChange() {
    if (!_passwordFocusNode.hasFocus && !_obscurePassword && mounted) {
      setState(() {
        _obscurePassword = true;
      });
    }
  }

  void _handlePasswordConfirmFocusChange() {
    if (!_passwordConfirmFocusNode.hasFocus &&
        !_obscurePasswordConfirm &&
        mounted) {
      setState(() {
        _obscurePasswordConfirm = true;
      });
    }
  }
}
