import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings_store.dart';
import '../state/session.dart';
import 'widgets/common.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  late final _serverController = TextEditingController(text: ref.read(settingsStoreProvider).serverUrl);
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  late bool _showServer = _serverController.text.isEmpty;
  bool _obscure = true;
  bool _submitting = false;

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      setState(() => _showServer = true);
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref
          .read(sessionProvider.notifier)
          .login(
            serverUrl: _serverController.text,
            username: _usernameController.text,
            password: _passwordController.text,
          );
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Form(
              key: _formKey,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.restaurant, size: 64, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 8),
                    Text(
                      'Warique',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(labelText: 'Usuario', prefixIcon: Icon(Icons.person)),
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      validator: (value) => (value ?? '').trim().isEmpty ? 'Ingresa tu usuario' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      validator: (value) => (value ?? '').isEmpty ? 'Ingresa tu contraseña' : null,
                    ),
                    const SizedBox(height: 8),
                    if (_showServer)
                      TextFormField(
                        controller: _serverController,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Servidor',
                          hintText: '192.168.1.50:3000',
                          prefixIcon: Icon(Icons.dns),
                        ),
                        validator: validateServerUrl,
                      )
                    else
                      TextButton.icon(
                        onPressed: () => setState(() => _showServer = true),
                        icon: const Icon(Icons.dns, size: 18),
                        label: Text('Servidor: ${_serverController.text}'),
                      ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      child: _submitting
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Ingresar'),
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
