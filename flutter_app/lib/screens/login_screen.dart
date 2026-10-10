import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/http_factory.dart';
import '../core/session.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();

  bool _registering = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final api = context.read<ApiClient>();
    final session = context.read<Session>();

    try {
      final user = _registering
          ? await api.post('/auth/register', queueOnFailure: false, body: {
              'username': _username.text.trim(),
              'display_name': _displayName.text.trim(),
              'password': _password.text,
            })
          : await api.post('/auth/login', queueOnFailure: false, body: {
              'username': _username.text.trim(),
              'password': _password.text,
            });

      if (user is Map) {
        await session.signIn(Map<String, dynamic>.from(user));
      } else {
        setState(() => _error = 'Сервер вернул неожиданный ответ');
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Тёплое пятно за карточкой: ровный чёрный фон — главная примета
      // «сделано на скорую руку». Свет даёт сцене глубину.
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.55),
            radius: 1.1,
            colors: [AppColors.goldWash(0.10), AppColors.bg.withValues(alpha: AppTheme.spec.backdrop.isEmpty ? 1 : 0)],
          ),
        ),
        child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Container(
              padding: const EdgeInsets.fromLTRB(32, 36, 32, 28),
              decoration: BoxDecoration(
                color: AppTheme.spec.backdrop.isEmpty ? AppColors.surface : AppColors.sheet.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(AppRadius.large),
                border: Border.all(color: AppColors.border),
                boxShadow: AppShadow.raised,
              ),
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    height: 84,
                    width: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surfaceHigh,
                      border: Border.all(color: AppColors.goldWash(0.3)),
                      boxShadow: AppShadow.glow(AppColors.gold),
                    ),
                    alignment: Alignment.center,
                    child: const Text('🐒', style: TextStyle(fontSize: 42)),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Monkey App',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  _registering ? 'Создать аккаунт' : 'С возвращением',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textDim, fontSize: 14),
                ),
                const SizedBox(height: 30),
                TextField(
                  controller: _username,
                  autofillHints: const [AutofillHints.username],
                  decoration: const InputDecoration(hintText: 'Логин'),
                  textInputAction: TextInputAction.next,
                ),
                if (_registering) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _displayName,
                    decoration: const InputDecoration(hintText: 'Как тебя показывать'),
                    textInputAction: TextInputAction.next,
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(hintText: 'Пароль'),
                  onSubmitted: (_) => _busy ? null : _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    style: TextStyle(color: AppColors.red, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.bg),
                        )
                      : Text(_registering ? 'Зарегистрироваться' : 'Войти'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _registering = !_registering;
                            _error = null;
                          }),
                  child: Text(_registering ? 'У меня уже есть аккаунт' : 'Создать аккаунт'),
                ),
                // Видно только когда прокси найден. Если сеть вдруг снова
                // отвалится, сразу понятно, через что шло приложение.
                if (activeProxy != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'через прокси $activeProxy',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textDim, fontSize: 11),
                    ),
                  ),
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
