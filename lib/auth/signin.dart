import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../layout/dashboard_layout.dart';
import 'login.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({Key? key}) : super(key: key);

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final SupabaseClient supabase = Supabase.instance.client;

  String email = '';
  String fullName = '';
  String phone = '';

  bool isLoading = false;

  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  @override
  void dispose() {
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    if (passwordController.text != confirmPasswordController.text) {
      _showError('Passwords do not match');
      return;
    }

    setState(() => isLoading = true);

    AuthResponse? signUpResponse;
    try {
      signUpResponse = await supabase.auth.signUp(
        email: email,
        password: passwordController.text.trim(),
      );
    } on AuthException catch (e, st) {
      debugPrint('SignUp AuthException: ${e.message} (status=${e.statusCode})\n$st');
      _showError('Sign up failed: ${e.message}');
      if (mounted) setState(() => isLoading = false);
      return;
    } catch (e, st) {
      debugPrint('SignUp error: $e\n$st');
      _showError('Sign up failed: $e');
      if (mounted) setState(() => isLoading = false);
      return;
    }

    final user = signUpResponse.user;
    if (user == null) {
      _showError('Sign up failed: no user returned');
      if (mounted) setState(() => isLoading = false);
      return;
    }

    // Insert admin profile row. Don't fail the whole sign-up if this errors
    // (e.g. RLS) — the auth account was created successfully and we can
    // surface the profile error separately.
    try {
      await supabase.from('admin').insert({
        'user_id': user.id,
        'full_name': fullName,
        'phone': phone,
      });
    } on PostgrestException catch (e, st) {
      debugPrint('admin insert PostgrestException: ${e.message} '
          '(code=${e.code}, details=${e.details})\n$st');
      _showError('Account created, but profile save failed: ${e.message}');
    } catch (e, st) {
      debugPrint('admin insert error: $e\n$st');
      _showError('Account created, but profile save failed: $e');
    }

    // If the project doesn't require email confirmation, signUp returns a
    // session and the user is already authenticated — skip the login step.
    if (signUpResponse.session != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', user.id);
      await prefs.setString('email', email);
      await prefs.setString('role', 'admin');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Welcome! Account created.')),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardLayout()),
      );
      return;
    }

    // Email confirmation required — fall back to the login screen.
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Account created. Check your email to confirm, then log in.'),
        duration: Duration(seconds: 6),
      ),
    );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Admin Sign Up")),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const SizedBox(height: 30),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Full Name'),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Enter your full name' : null,
                  onSaved: (v) => fullName = v!.trim(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Phone (optional)',
                  ),
                  keyboardType: TextInputType.phone,
                  onSaved: (v) => phone = v?.trim() ?? '',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter email';
                    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
                    if (!emailRegex.hasMatch(v)) return 'Enter a valid email';
                    return null;
                  },
                  onSaved: (v) => email = v!.trim(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: passwordController,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  validator: (v) => v == null || v.length < 6
                      ? 'Password too short (min 6 chars)'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: confirmPasswordController,
                  decoration: const InputDecoration(
                    labelText: 'Confirm Password',
                  ),
                  obscureText: true,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Confirm your password';
                    if (v != passwordController.text)
                      return 'Passwords do not match';
                    return null;
                  },
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : handleSignUp,
                    child: isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("Sign Up"),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                    );
                  },
                  child: const Text("Already have an account? Log in"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
