import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../config/supabase_config.dart';
import '../../theme/app_colors.dart';

class AddDriverPage extends StatefulWidget {
  const AddDriverPage({Key? key}) : super(key: key);

  @override
  State<AddDriverPage> createState() => _AddDriverPageState();
}

class _AddDriverPageState extends State<AddDriverPage> {
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;

  // Form fields
  String firstName = '';
  String lastName = '';
  String phoneNumber = '';
  String email = '';
  String address = '';
  String drivingLicenseNumber = '';
  String contractNumber = '';
  bool isAvailable = true;
  String identifier = '';
  String secretCode = '';

  final String edgeFunctionUrl = SupabaseConfig.addDriverFn;
  final String supabaseApiKey = SupabaseConfig.anonKey;

  Future<void> saveDriver() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _isSubmitting = true);

    final newDriver = {
      "identifier": identifier,
      "secret_code": secretCode,
      "firstname": firstName,
      "lastname": lastName,
      "phonenumber": phoneNumber,
      "email": email,
      "address": address,
      "drivinglicencenumber": drivingLicenseNumber,
      "contractnumber": contractNumber,
      "isavailable": isAvailable,
    };

    try {
      final response = await http.post(
        Uri.parse(edgeFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $supabaseApiKey',
        },
        body: json.encode(newDriver),
      );

      if (response.statusCode == 201) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.success),
                  const SizedBox(width: 12),
                  const Text('Driver added successfully!'),
                ],
              ),
              backgroundColor: AppColors.surface,
            ),
          );
          _formKey.currentState?.reset();
          setState(() => isAvailable = true);
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${response.body}'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Account Section
              _buildSectionHeader(
                'Account Information',
                Icons.account_circle_outlined,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildInputField(
                      label: 'Identifier',
                      icon: Icons.badge_outlined,
                      onSaved: (v) => identifier = v!.trim(),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildInputField(
                      label: 'Secret Code',
                      icon: Icons.lock_outlined,
                      onSaved: (v) => secretCode = v!.trim(),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Required' : null,
                      obscure: true,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Personal Section
              _buildSectionHeader(
                'Personal Information',
                Icons.person_outlined,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildInputField(
                      label: 'First Name',
                      icon: Icons.person_outlined,
                      onSaved: (v) => firstName = v!.trim(),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildInputField(
                      label: 'Last Name',
                      icon: Icons.person_outlined,
                      onSaved: (v) => lastName = v!.trim(),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildInputField(
                      label: 'Phone Number',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      onSaved: (v) => phoneNumber = v!.trim(),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildInputField(
                      label: 'Email',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      onSaved: (v) => email = v!.trim(),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
                        if (!emailRegex.hasMatch(v)) return 'Invalid email';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildInputField(
                label: 'Address',
                icon: Icons.location_on_outlined,
                onSaved: (v) => address = v ?? '',
              ),

              const SizedBox(height: 32),

              // License Section
              _buildSectionHeader(
                'License & Contract',
                Icons.description_outlined,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildInputField(
                      label: 'Driving License Number',
                      icon: Icons.credit_card_outlined,
                      onSaved: (v) => drivingLicenseNumber = v!.trim(),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildInputField(
                      label: 'Contract Number',
                      icon: Icons.article_outlined,
                      onSaved: (v) => contractNumber = v ?? '',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Availability Toggle
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.border.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isAvailable
                            ? AppColors.success.withValues(alpha: 0.15)
                            : AppColors.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isAvailable ? Icons.check_circle : Icons.cancel,
                        color: isAvailable
                            ? AppColors.success
                            : AppColors.error,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Availability Status',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isAvailable
                                ? 'Driver is available for trips'
                                : 'Driver is not available',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: isAvailable,
                      onChanged: (val) => setState(() => isAvailable = val),
                      activeColor: AppColors.success,
                      activeTrackColor: AppColors.success.withValues(
                        alpha: 0.3,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : saveDriver,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.gold.withValues(
                      alpha: 0.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.primary,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_add),
                            SizedBox(width: 10),
                            Text(
                              'Add Driver',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.gold, size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildInputField({
    required String label,
    required IconData icon,
    required FormFieldSetter<String> onSaved,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool obscure = false,
  }) {
    return TextFormField(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: AppColors.surface,
      ),
      validator: validator,
      onSaved: onSaved,
      keyboardType: keyboardType,
      obscureText: obscure,
    );
  }
}
