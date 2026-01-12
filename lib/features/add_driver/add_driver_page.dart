import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class AddDriverPage extends StatefulWidget {
  const AddDriverPage({Key? key}) : super(key: key);

  @override
  State<AddDriverPage> createState() => _AddDriverPageState();
}

class _AddDriverPageState extends State<AddDriverPage> {
  final _formKey = GlobalKey<FormState>();

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

  final String edgeFunctionUrl =
      'https://utypxmgyfqfwlkpkqrff.supabase.co/functions/v1/add-driver';

  final String supabaseApiKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV0eXB4bWd5ZnFmd2xrcGtxcmZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTAyNDAxMTAsImV4cCI6MjA2NTgxNjExMH0.tkNF11cJ06ZNt0dykFgu1smGEDWuT0Q4LtAmRL6wNZU'; // Store securely in prod!

  Future<void> saveDriver() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

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
            const SnackBar(content: Text('Driver added successfully!')),
          );
          _formKey.currentState?.reset();
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${response.body}')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Widget _buildInputField({
    required String label,
    required FormFieldSetter<String> onSaved,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: TextFormField(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: validator,
        onSaved: onSaved,
        keyboardType: keyboardType,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Driver')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                _buildInputField(
                  label: 'Identifier',
                  onSaved: (v) => identifier = v!.trim(),
                  validator: (v) => v == null || v.isEmpty ? 'Enter identifier' : null,
                ),
                _buildInputField(
                  label: 'Secret Code',
                  onSaved: (v) => secretCode = v!.trim(),
                  validator: (v) => v == null || v.isEmpty ? 'Enter secret code' : null,
                ),
                _buildInputField(
                  label: 'First Name',
                  onSaved: (v) => firstName = v!.trim(),
                  validator: (v) => v == null || v.isEmpty ? 'Enter first name' : null,
                ),
                _buildInputField(
                  label: 'Last Name',
                  onSaved: (v) => lastName = v!.trim(),
                  validator: (v) => v == null || v.isEmpty ? 'Enter last name' : null,
                ),
                _buildInputField(
                  label: 'Phone Number',
                  keyboardType: TextInputType.phone,
                  onSaved: (v) => phoneNumber = v!.trim(),
                  validator: (v) => v == null || v.isEmpty ? 'Enter phone number' : null,
                ),
                _buildInputField(
                  label: 'Email',
                  keyboardType: TextInputType.emailAddress,
                  onSaved: (v) => email = v!.trim(),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter email';
                    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
                    if (!emailRegex.hasMatch(v)) return 'Enter valid email';
                    return null;
                  },
                ),
                _buildInputField(
                  label: 'Address',
                  onSaved: (v) => address = v ?? '',
                ),
                _buildInputField(
                  label: 'Driving License Number',
                  onSaved: (v) => drivingLicenseNumber = v!.trim(),
                  validator: (v) => v == null || v.isEmpty ? 'Enter license number' : null,
                ),
                _buildInputField(
                  label: 'Contract Number',
                  onSaved: (v) => contractNumber = v ?? '',
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  title: const Text('Available'),
                  value: isAvailable,
                  onChanged: (val) => setState(() => isAvailable = val),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: saveDriver,
                    icon: const Icon(Icons.save),
                    label: const Text('Save Driver'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
