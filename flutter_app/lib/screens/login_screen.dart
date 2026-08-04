import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
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
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('🐒', style: TextStyle(fontSize: 52), textAlign: TextAlign.center),
                const SizedBox(height: 14),
                const Text(
                  'Monkey App',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _registering ? 'Создать аккаунт' : 'С возвращением',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textDim, fontSize: 14),
                ),
                const SizedBox(height: 28),
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
                    style: const TextStyle(color: AppColors.red, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
