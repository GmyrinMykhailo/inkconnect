import 'package:flutter/material.dart';

import '../validators.dart';
import 'auth_styles.dart';
import 'auth_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.onLogin,
    required this.onOpenRegister,
    this.errorText,
    this.successText,
  });

  final Future<void> Function(String email, String password) onLogin;
  final VoidCallback onOpenRegister;
  final String? errorText;
  final String? successText;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();

  bool _submitting = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _passwordFocusNode.addListener(_handlePasswordFocusChange);
  }

  String? get _emailNote {
    final value = _emailController.text.trim();
    if (value.isEmpty || isValidEmail(value)) {
      return null;
    }
    return 'Введите корректный email в латинице, например name@example.com.';
  }

  bool get _canSubmit =>
      isValidEmail(_emailController.text) &&
      _passwordController.text.isNotEmpty &&
      !_submitting;

  @override
  void dispose() {
    _passwordFocusNode
      ..removeListener(_handlePasswordFocusChange)
      ..dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 600;
        final tablet = constraints.maxWidth >= 600 && constraints.maxWidth < 1024;

        if (mobile) {
          return _buildMobileLayout();
        }

        if (tablet) {
          return _buildTabletLayout();
        }

        return SizedBox(
          height: 648,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: const AuthHeroPanel(
                    title: 'Платформа\nдля мастеров\nи клиентов',
                    subtitle:
                        'Чистый цифровой контур для записи, поиска мастеров и сопровождения процедур.',
                    items: [
                      AuthHeroItemData(
                        icon: Icons.search_rounded,
                        title: 'Поиск мастера',
                        subtitle:
                            'Находите мастеров по стилю, городу и специализации.',
                      ),
                      AuthHeroItemData(
                        icon: Icons.event_note_rounded,
                        title: 'Запись на процедуру',
                        subtitle:
                            'Удобная запись онлайн в несколько кликов.',
                      ),
                      AuthHeroItemData(
                        icon: Icons.verified_user_outlined,
                        title: 'Журнал ухода',
                        subtitle:
                            'Защищённый журнал ухода после процедуры.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 44),
              SizedBox(
                width: 560,
                child: Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: AuthFormCard(
                    padding: const EdgeInsets.fromLTRB(42, 42, 42, 34),
                    child: _buildForm(centerFooter: false),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        const AuthBrand(center: true),
        const SizedBox(height: 18),
        AuthFormCard(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
          child: _buildForm(centerFooter: true),
        ),
      ],
    );
  }

  Widget _buildTabletLayout() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AuthBrand(center: true),
            const SizedBox(height: 18),
            AuthFormCard(
              padding: const EdgeInsets.fromLTRB(34, 30, 34, 26),
              child: _buildForm(centerFooter: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm({required bool centerFooter}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AuthHeader(
          title: 'Вход',
          subtitle: 'Введите email и пароль для входа в систему',
        ),
        if (widget.errorText != null) ...[
          const SizedBox(height: 18),
          AuthErrorBanner(message: widget.errorText!),
        ] else if (widget.successText != null) ...[
          const SizedBox(height: 18),
          AuthSuccessBanner(message: widget.successText!),
        ],
        const SizedBox(height: 22),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AuthFieldBlock(
                field: TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'Введите email',
                  ),
                  onChanged: (value) {
                    final normalized = normalizeEmail(value);
                    if (normalized != value) {
                      _emailController.value = TextEditingValue(
                        text: normalized,
                        selection: TextSelection.collapsed(
                          offset: normalized.length,
                        ),
                      );
                    }
                    setState(() {});
                  },
                  validator: (value) {
                    if (!isValidEmail(value?.trim() ?? '')) {
                      return 'Введите корректный email в латинице, например name@example.com.';
                    }
                    return null;
                  },
                ),
                note: _emailNote != null
                    ? AuthFieldHint(_emailNote!, color: authError)
                    : null,
              ),
              const SizedBox(height: 14),
              AuthFieldBlock(
                field: TextFormField(
                  controller: _passwordController,
                  focusNode: _passwordFocusNode,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Пароль',
                    hintText: 'Введите пароль',
                    suffixIcon: IconButton(
                      tooltip: _obscurePassword
                          ? 'Показать пароль'
                          : 'Скрыть пароль',
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
                    if ((value ?? '').isEmpty) {
                      return 'Введите пароль.';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
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
                      : const Text('Войти'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AuthFooterRow(
          prompt: 'Нет аккаунта?',
          actionLabel: 'Создать учетную запись',
          onPressed: widget.onOpenRegister,
          center: centerFooter,
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      await widget.onLogin(
        _emailController.text.trim(),
        _passwordController.text,
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  void _handlePasswordFocusChange() {
    if (!_passwordFocusNode.hasFocus && !_obscurePassword && mounted) {
      setState(() {
        _obscurePassword = true;
      });
    }
  }
}
