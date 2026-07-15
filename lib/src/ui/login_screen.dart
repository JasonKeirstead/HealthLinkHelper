import 'package:flutter/material.dart';

import '../auth/auth_api.dart';
import '../auth/auth_controller.dart';

/// Native email/password login with 2FA. (SSO is intentionally unsupported:
/// Google blocks embedded-WebView OAuth and won't issue tokens to an
/// unregistered native client — see reverse-engineering notes.)
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});
  final AuthController auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _pin = TextEditingController();
  bool _remember = true;
  bool _busy = false;
  String? _error;
  TwoFactorChallenge? _challenge;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() => _run(() async {
        final result = await widget.auth.signInWithPassword(
          _email.text.trim(),
          _password.text,
          rememberMe: _remember,
        );
        if (result.needsTwoFactor) {
          final c = result.challenge!;
          await widget.auth.requestTwoFactor(c.ref, c.primaryMethod ?? 'EMAIL');
          setState(() => _challenge = c);
        }
        // On plain success the AuthGate rebuilds into the app automatically.
      });

  Future<void> _confirm() => _run(() async {
        await widget.auth.confirmTwoFactor(
          _challenge!.ref,
          _pin.text.trim(),
          rememberMe: _remember,
        );
      });

  Future<void> _resend() => _run(() async {
        final c = _challenge!;
        await widget.auth.requestTwoFactor(c.ref, c.primaryMethod ?? 'EMAIL');
      });

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('401') || s.contains('rejected')) return 'Incorrect email or password.';
    return s.replaceFirst(RegExp(r'^\w+Exception:?\s*'), '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _challenge == null ? _credentials() : _twoFactor(),
          ),
        ),
      ),
    );
  }

  Widget _credentials() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('HealthLink', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('Sign in with your TELUS Health Connect account.',
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 24),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.username],
          decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => _busy ? null : _signIn(),
          decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Checkbox(value: _remember, onChanged: (v) => setState(() => _remember = v ?? true)),
            const Text('Keep me signed in'),
          ],
        ),
        if (_error != null) _ErrorText(_error!),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy ? null : _signIn,
          child: _busy ? const _Spinner() : const Text('Sign in'),
        ),
      ],
    );
  }

  Widget _twoFactor() {
    final c = _challenge!;
    final dest = c.maskedEmail ?? c.primaryMethod ?? 'your device';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Enter your code', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('We sent a one-time code to $dest.',
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 24),
        TextField(
          controller: _pin,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          onSubmitted: (_) => _busy ? null : _confirm(),
          decoration: const InputDecoration(labelText: 'Code', border: OutlineInputBorder()),
        ),
        if (_error != null) _ErrorText(_error!),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _confirm,
          child: _busy ? const _Spinner() : const Text('Verify'),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: _busy ? null : _resend, child: const Text('Resend code')),
        TextButton(
          onPressed: _busy ? null : () => setState(() => _challenge = null),
          child: const Text('Back'),
        ),
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => const SizedBox(
      height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2));
}
