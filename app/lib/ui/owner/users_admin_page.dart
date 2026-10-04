import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/admin.dart';
import '../../models/user.dart';
import '../../state/admin.dart';
import '../../state/session.dart';
import '../widgets/common.dart';
import '../widgets/text_controllers.dart';
import 'admin_widgets.dart';

const _passwordMin = 8; // backend: CreateUserDto / ResetPasswordDto
final _usernamePattern = RegExp(r'^[a-z0-9._-]{3,50}$');

String? validatePassword(String? value) {
  final text = value ?? '';
  if (text.length < _passwordMin) return 'Mínimo $_passwordMin caracteres';
  if (text.length > 72) return 'Máximo 72 caracteres';
  return null;
}

class UsersAdminPage extends ConsumerWidget {
  const UsersAdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(staffUsersProvider);
    final me = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Usuarios')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          if (await _showCreateDialog(context, ref)) ref.invalidate(staffUsersProvider);
        },
        icon: const Icon(Icons.person_add),
        label: const Text('Nuevo usuario'),
      ),
      body: switch (users) {
        AsyncValue(value: final list?) => ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            for (final user in list)
              ListTile(
                leading: CircleAvatar(
                  child: Icon(switch (user.role) {
                    Role.owner => Icons.store,
                    Role.waiter => Icons.room_service,
                    Role.kitchen => Icons.soup_kitchen,
                  }),
                ),
                title: Row(
                  children: [
                    Flexible(child: Text(user.fullName)),
                    if (user.id == me.id) const InactiveTag('tú'),
                    if (!user.isActive) const InactiveTag('desactivado'),
                  ],
                ),
                subtitle: Text('${user.username} · ${user.role.label}'),
                onTap: () async {
                  if (await _showEditDialog(context, ref, user, isSelf: user.id == me.id)) {
                    ref.invalidate(staffUsersProvider);
                  }
                },
              ),
          ],
        ),
        AsyncError(:final error) => ErrorRetryView(
          error: error,
          onRetry: () => ref.invalidate(staffUsersProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

Future<bool> _showCreateDialog(BuildContext context, WidgetRef ref) async {
  var role = Role.waiter;
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => WithTextControllers(
      initialTexts: const [null, null, null],
      builder: (_, controllers) => StatefulBuilder(
        builder: (dialogContext, setState) {
          final [fullName, username, password] = controllers;
          return FormDialog(
            title: 'Nuevo usuario',
            onSave: () => runSaving(
              dialogContext,
              () => ref
                  .read(adminRepositoryProvider)
                  .createUser(
                    fullName: fullName.text,
                    username: username.text,
                    password: password.text,
                    role: role,
                  ),
              success: 'Usuario ${username.text.trim().toLowerCase()} creado. Entrégale su clave en persona.',
            ),
            children: [
              TextFormField(
                controller: fullName,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre completo'),
                validator: requiredText,
              ),
              TextFormField(
                controller: username,
                decoration: const InputDecoration(
                  labelText: 'Usuario',
                  helperText: 'Minúsculas, sin espacios. Ej.: rosa',
                ),
                validator: (value) => _usernamePattern.hasMatch((value ?? '').trim().toLowerCase())
                    ? null
                    : '3 a 50: minúsculas, números, ".", "_" o "-"',
              ),
              TextFormField(
                controller: password,
                decoration: const InputDecoration(labelText: 'Clave inicial'),
                validator: validatePassword,
              ),
              DropdownButtonFormField<Role>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Rol'),
                items: [for (final r in Role.values) DropdownMenuItem(value: r, child: Text(r.label))],
                onChanged: (value) => setState(() => role = value ?? role),
              ),
            ],
          );
        },
      ),
    ),
  );
  return saved ?? false;
}

Future<bool> _showEditDialog(
  BuildContext context,
  WidgetRef ref,
  StaffUser user, {
  required bool isSelf,
}) async {
  var role = user.role;
  var isActive = user.isActive;
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => WithTextControllers(
      initialTexts: [user.fullName],
      builder: (_, controllers) => StatefulBuilder(
        builder: (dialogContext, setState) {
          final fullName = controllers.single;
          return FormDialog(
            title: user.username,
            onSave: () => runSaving(
              dialogContext,
              () => ref
                  .read(adminRepositoryProvider)
                  .updateUser(
                    user.id,
                    fullName: fullName.text,
                    role: role == user.role ? null : role,
                    isActive: isActive == user.isActive ? null : isActive,
                  ),
            ),
            children: [
              TextFormField(
                controller: fullName,
                decoration: const InputDecoration(labelText: 'Nombre completo'),
                validator: requiredText,
              ),
              DropdownButtonFormField<Role>(
                initialValue: role,
                decoration: InputDecoration(
                  labelText: 'Rol',
                  helperText: isSelf ? 'No puedes quitarte el rol de dueño' : null,
                ),
                items: [for (final r in Role.values) DropdownMenuItem(value: r, child: Text(r.label))],
                onChanged: isSelf ? null : (value) => setState(() => role = value ?? role),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Puede ingresar'),
                subtitle: Text(
                  isSelf
                      ? 'No puedes desactivar tu propia cuenta'
                      : 'Al desactivarlo se cierra su sesión de inmediato',
                ),
                value: isActive,
                onChanged: isSelf ? null : (value) => setState(() => isActive = value),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _showResetPasswordDialog(dialogContext, ref, user),
                  icon: const Icon(Icons.key),
                  label: const Text('Restablecer clave'),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
  return saved ?? false;
}

Future<void> _showResetPasswordDialog(BuildContext context, WidgetRef ref, StaffUser user) async {
  await showDialog<bool>(
    context: context,
    builder: (_) => WithTextControllers(
      initialTexts: const [null],
      builder: (dialogContext, controllers) {
        final password = controllers.single;
        return FormDialog(
          title: 'Nueva clave para ${user.username}',
          onSave: () => runSaving(
            dialogContext,
            () => ref.read(adminRepositoryProvider).resetPassword(user.id, password.text),
            success: 'Clave actualizada. Entrégasela en persona.',
          ),
          children: [
            TextFormField(
              controller: password,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nueva clave'),
              validator: validatePassword,
            ),
          ],
        );
      },
    ),
  );
}

/// Any role: change your own password (needs the current one).
Future<void> showChangeOwnPasswordDialog(BuildContext context, WidgetRef ref) async {
  await showDialog<bool>(
    context: context,
    builder: (_) => WithTextControllers(
      initialTexts: const [null, null, null],
      builder: (dialogContext, controllers) {
        final [current, next, repeat] = controllers;
        return FormDialog(
          title: 'Cambiar mi contraseña',
          onSave: () => runSaving(
            dialogContext,
            () => ref.read(authRepositoryProvider).changeOwnPassword(current.text, next.text),
            success: 'Contraseña actualizada',
          ),
          children: [
            TextFormField(
              controller: current,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Contraseña actual'),
              validator: (value) => (value ?? '').isEmpty ? 'Obligatorio' : null,
            ),
            TextFormField(
              controller: next,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Nueva contraseña'),
              validator: validatePassword,
            ),
            TextFormField(
              controller: repeat,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Repite la nueva contraseña'),
              validator: (value) => value == next.text ? null : 'No coincide',
            ),
          ],
        );
      },
    ),
  );
}
