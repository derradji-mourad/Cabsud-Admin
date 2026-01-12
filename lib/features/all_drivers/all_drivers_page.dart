import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class DriversPage extends StatefulWidget {
  const DriversPage({Key? key}) : super(key: key);

  @override
  State<DriversPage> createState() => _DriversPageState();
}

class _DriversPageState extends State<DriversPage> {
  List<dynamic> drivers = [];
  bool isLoading = true;
  String? error;

  final String supabaseEdgeUrl =
      'https://utypxmgyfqfwlkpkqrff.supabase.co/functions/v1/get-drivers';

  final String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV0eXB4bWd5ZnFmd2xrcGtxcmZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTAyNDAxMTAsImV4cCI6MjA2NTgxNjExMH0.tkNF11cJ06ZNt0dykFgu1smGEDWuT0Q4LtAmRL6wNZU'; // Use secure storage in production

  @override
  void initState() {
    super.initState();
    fetchDrivers();
  }

  Future<void> fetchDrivers() async {
    try {
      final response = await http.get(
        Uri.parse(supabaseEdgeUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $supabaseAnonKey',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          drivers = data['drivers'];
          isLoading = false;
        });
      } else {
        setState(() {
          error = 'Failed to load drivers (${response.statusCode})';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = 'Error: $e';
        isLoading = false;
      });
    }
  }

  Widget buildDriverCard(Map<String, dynamic> driver) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${driver['firstname'] ?? ''} ${driver['lastname'] ?? ''}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              runSpacing: 4,
              children: [
                Text('📧 Email: ${driver['email'] ?? 'N/A'}'),
                Text('📞 Phone: ${driver['phonenumber'] ?? 'N/A'}'),
                if (driver['address'] != null) Text('🏠 Address: ${driver['address']}'),
                if (driver['drivinglicencenumber'] != null)
                  Text('🪪 License: ${driver['drivinglicencenumber']}'),
                if (driver['contractnumber'] != null)
                  Text('📄 Contract #: ${driver['contractnumber']}'),
                Text('🆔 Identifier: ${driver['identifier'] ?? 'N/A'}'),
                Text('✅ Available: ${driver['isavailable'] == true ? 'Yes' : 'No'}'),
                Text('🕒 Created At: ${driver['created_at'] ?? 'N/A'}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('All Drivers')),
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : error != null
            ? Center(child: Text(error!))
            : RefreshIndicator(
          onRefresh: fetchDrivers,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: drivers.length,
            itemBuilder: (context, index) {
              return buildDriverCard(drivers[index]);
            },
          ),
        ),
      ),
    );
  }
}
