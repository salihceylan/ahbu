import 'package:ahbu/models/user_role.dart';
import 'package:ahbu/services/auth_service.dart';
import 'package:ahbu/styles/app_colors.dart';
import 'package:ahbu/styles/app_decorations.dart';
import 'package:flutter/material.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.authService});

  final AuthService authService;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const List<UserRole> _allowedRoles = <UserRole>[
    UserRole.siteManager,
    UserRole.apartmentOwner,
  ];

  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final List<TextEditingController> _codeControllers =
      List<TextEditingController>.generate(4, (_) => TextEditingController());
  final List<FocusNode> _codeFocusNodes =
      List<FocusNode>.generate(4, (_) => FocusNode());

  UserRole _selectedRole = UserRole.siteManager;
  bool _isLoginMode = true;
  bool _isVerificationMode = false;
  bool _isLoading = false;
  String? _pendingVerificationEmail;

  bool get _canRegister => _selectedRole == UserRole.siteManager;
  bool get _isRegisterMode => !_isLoginMode && !_isVerificationMode;

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _identifierController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    for (final controller in _codeControllers) {
      controller.dispose();
    }
    for (final node in _codeFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _resetToLogin() {
    setState(() {
      _isVerificationMode = false;
      _isLoginMode = true;
      _pendingVerificationEmail = null;
    });
    for (final controller in _codeControllers) {
      controller.clear();
    }
  }

  Future<void> _submit() async {
    if (_isVerificationMode) {
      await _submitVerification();
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _isLoading = true);

    String? error;
    if (_isLoginMode) {
      error = await widget.authService.login(
        identifier: _identifierController.text.trim().toLowerCase(),
        password: _passwordController.text.trim(),
        role: _selectedRole,
      );
    } else {
      final (pendingEmail, registerError) =
          await widget.authService.registerSiteManager(
        fullName: _fullNameController.text.trim(),
        email: _identifierController.text.trim().toLowerCase(),
        password: _passwordController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
      );
      error = registerError;
      if (registerError == null && pendingEmail != null) {
        _pendingVerificationEmail = pendingEmail;
      }
    }

    if (!mounted) {
      return;
    }

    setState(() => _isLoading = false);
    if (error != null) {
      _showMessage(error);
      return;
    }

    if (_isRegisterMode && _pendingVerificationEmail != null) {
      setState(() => _isVerificationMode = true);
      _showMessage('Dogrulama kodu e-posta adresinize gonderildi.');
    }
  }

  Future<void> _submitVerification() async {
    final email = (_pendingVerificationEmail ?? '').trim().toLowerCase();
    final code = _codeControllers.map((controller) => controller.text.trim()).join();
    if (email.isEmpty || !RegExp(r'^\d{4}$').hasMatch(code)) {
      _showMessage('4 haneli kodu eksiksiz girin.');
      return;
    }

    setState(() => _isLoading = true);
    final error = await widget.authService.verifySiteManagerEmail(
      email: email,
      code: code,
    );

    if (!mounted) {
      return;
    }

    setState(() => _isLoading = false);
    if (error != null) {
      _showMessage(error);
      return;
    }

    _resetToLogin();
    _showMessage(
      'E-posta dogrulandi. Abonelik talebiniz sirket onayina gonderildi.',
    );
  }

  Future<void> _resendCode() async {
    final email = (_pendingVerificationEmail ?? '').trim().toLowerCase();
    if (email.isEmpty) {
      return;
    }

    setState(() => _isLoading = true);
    final error = await widget.authService.resendSiteManagerCode(email: email);

    if (!mounted) {
      return;
    }

    setState(() => _isLoading = false);
    if (error != null) {
      _showMessage(error);
      return;
    }
    _showMessage('Yeni kod gonderildi.');
  }

  void _handleRoleChanged(UserRole role) {
    setState(() {
      _selectedRole = role;
      if (role == UserRole.apartmentOwner) {
        _isLoginMode = true;
        _isVerificationMode = false;
        _pendingVerificationEmail = null;
      }
    });
  }

  Widget _buildVerificationDigits() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List<Widget>.generate(4, (index) {
        return SizedBox(
          width: 56,
          child: TextFormField(
            controller: _codeControllers[index],
            focusNode: _codeFocusNodes[index],
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 1,
            decoration: const InputDecoration(counterText: ''),
            onChanged: (value) {
              if (value.length == 1 && index < _codeFocusNodes.length - 1) {
                _codeFocusNodes[index + 1].requestFocus();
              }
              if (value.isEmpty && index > 0) {
                _codeFocusNodes[index - 1].requestFocus();
              }
            },
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final identifierLabel = _isLoginMode && _selectedRole == UserRole.apartmentOwner
        ? 'Kullanici Adi'
        : 'E-posta';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isVerificationMode
              ? 'E-posta Dogrulama'
              : (_isLoginMode ? 'Uyelik Girisi' : 'Site Yoneticisi Kaydi'),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              decoration: AppDecorations.glassCard,
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: _BrandLogo(size: 88)),
                    const SizedBox(height: 14),
                    Text(
                      _isVerificationMode
                          ? '4 haneli kodu girin'
                          : (_isLoginMode
                                ? 'Rol secip giris yapin'
                                : 'Site yoneticisi hesabinizi olusturun'),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isVerificationMode
                          ? 'Kod: ${_pendingVerificationEmail ?? ''}'
                          : (_canRegister
                                ? 'Site yoneticileri kayit olabilir. Daire aboneleri yonetici tarafindan tanimlanir.'
                                : 'Daire aboneleri sadece kendilerine verilen kullanici adi ve sifreyle giris yapar.'),
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 20),
                    if (!_isVerificationMode) ...[
                      if (_isRegisterMode) ...[
                        TextFormField(
                          controller: _fullNameController,
                          decoration: const InputDecoration(labelText: 'Ad Soyad'),
                          validator: (value) {
                            if (_isRegisterMode && (value ?? '').trim().length < 3) {
                              return 'Ad Soyad en az 3 karakter olmali.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Telefon Numarasi',
                          ),
                          validator: (value) {
                            if (!_isRegisterMode) {
                              return null;
                            }
                            final text = (value ?? '').trim();
                            if (text.isEmpty) {
                              return 'Telefon numarasi zorunlu.';
                            }
                            if (!RegExp(r'^\+?[0-9()\-\s]{10,20}$').hasMatch(text)) {
                              return 'Gecerli bir telefon numarasi girin.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      DropdownButtonFormField<UserRole>(
                        initialValue: _selectedRole,
                        decoration: const InputDecoration(labelText: 'Rol'),
                        items: _allowedRoles
                            .map(
                              (role) => DropdownMenuItem<UserRole>(
                                value: role,
                                child: Text(role.label),
                              ),
                            )
                            .toList(),
                        onChanged: (role) {
                          if (role != null) {
                            _handleRoleChanged(role);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _identifierController,
                        keyboardType: _selectedRole == UserRole.apartmentOwner &&
                                _isLoginMode
                            ? TextInputType.text
                            : TextInputType.emailAddress,
                        decoration: InputDecoration(labelText: identifierLabel),
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.isEmpty) {
                            return '$identifierLabel zorunlu.';
                          }
                          if (!(_selectedRole == UserRole.apartmentOwner && _isLoginMode) &&
                              !text.contains('@')) {
                            return 'Gecerli bir e-posta girin.';
                          }
                          if (_selectedRole == UserRole.apartmentOwner &&
                              _isLoginMode &&
                              text.length < 3) {
                            return 'Kullanici adi en az 3 karakter olmali.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: 'Sifre'),
                        validator: (value) {
                          if ((value ?? '').trim().length < 6) {
                            return 'Sifre en az 6 karakter olmali.';
                          }
                          return null;
                        },
                      ),
                      if (_isRegisterMode) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: true,
                          decoration: const InputDecoration(labelText: 'Sifre Tekrar'),
                          validator: (value) {
                            if ((value ?? '').trim() !=
                                _passwordController.text.trim()) {
                              return 'Sifreler ayni olmali.';
                            }
                            return null;
                          },
                        ),
                      ],
                    ] else ...[
                      _buildVerificationDigits(),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
                        child: Text(
                          _isVerificationMode
                              ? 'Kodu Gonder'
                              : (_isLoginMode ? 'Giris Yap' : 'Kayit Ol'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_isVerificationMode) ...[
                      TextButton(
                        onPressed: _isLoading ? null : _resendCode,
                        child: const Text('Kodu Tekrar Gonder'),
                      ),
                      TextButton(
                        onPressed: _isLoading ? null : _resetToLogin,
                        child: const Text('Giris ekranina don'),
                      ),
                    ] else if (_canRegister) ...[
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                setState(() {
                                  _isLoginMode = !_isLoginMode;
                                });
                              },
                        child: Text(
                          _isLoginMode
                              ? 'Site yoneticisi kaydi olustur'
                              : 'Zaten hesabim var, giris yap',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandLogo extends StatelessWidget {
  const _BrandLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(shape: BoxShape.circle),
      child: ClipOval(
        child: SizedBox.expand(
          child: Transform.scale(
            scale: 1.18,
            child: Image.asset('assets/images/app_logo.png', fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }
}
