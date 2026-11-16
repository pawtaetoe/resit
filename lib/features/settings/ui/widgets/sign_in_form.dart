import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The student ID and password fields. The screen owns the controllers and
/// [formKey], and validates and submits the form.
class SignInForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController usernameController;
  final TextEditingController passwordController;

  /// A sign-in is running: the fields are disabled.
  final bool busy;

  /// Changing the saved login rather than signing in for the first time.
  final bool editing;

  /// A password is saved, so it may be left blank while [editing].
  final bool hasPassword;

  final bool showPassword;
  final VoidCallback onToggleShowPassword;
  final VoidCallback onSubmit;

  const SignInForm({
    super.key,
    required this.formKey,
    required this.usernameController,
    required this.passwordController,
    required this.busy,
    required this.editing,
    required this.hasPassword,
    required this.showPassword,
    required this.onToggleShowPassword,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Form(
        key: formKey,
        child: Column(
          children: [
            TextFormField(
              controller: usernameController,
              enabled: !busy,
              decoration: const InputDecoration(
                labelText: 'Student ID',
                hintText: 'e.g. 2100000',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
              inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your student ID' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: passwordController,
              enabled: !busy,
              obscureText: !showPassword,
              enableIMEPersonalizedLearning: false,
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: editing && hasPassword ? 'Leave blank to keep your saved password' : null,
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: showPassword ? 'Hide password' : 'Show password',
                  icon: Icon(showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: onToggleShowPassword,
                ),
              ),
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => onSubmit(),
              validator: (v) => (v == null || v.isEmpty) && !(editing && hasPassword) ? 'Enter your password' : null,
            ),
          ],
        ),
      ),
    );
  }
}
