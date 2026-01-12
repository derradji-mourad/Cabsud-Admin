import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class RequestHistoryPage extends StatefulWidget {
  const RequestHistoryPage({Key? key}) : super(key: key);

  @override
  State<RequestHistoryPage> createState() => _RequestHistoryPageState();
}

class _RequestHistoryPageState extends State<RequestHistoryPage> {
  List<Map<String, dynamic>> history = [];
  bool loading = true;
  String errorMessage = '';

  final String passedServicesUrl =
      'https://utypxmgyfqfwlkpkqrff.supabase.co/functions/v1/get-passed-services';

  final String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV0eXB4bWd5ZnFmd2xrcGtxcmZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTAyNDAxMTAsImV4cCI6MjA2NTgxNjExMH0.tkNF11cJ06ZNt0dykFgu1smGEDWuT0Q4LtAmRL6wNZU';

  @override
  void initState() {
    super.initState();
    fetchPassedServices();
  }

  Future<void> fetchPassedServices() async {
    setState(() {
      loading = true;
      errorMessage = '';
    });

    try {
      final response = await http.get(
        Uri.parse(passedServicesUrl),
        headers: {
          'Authorization': 'Bearer $supabaseAnonKey',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          history = List<Map<String, dynamic>>.from(data);
          loading = false;
        });
      } else {
        setState(() {
          errorMessage = 'Failed to load history. Status: ${response.statusCode}';
          loading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error: $e';
        loading = false;
      });
    }
  }

  Widget _historyCard(Map<String, dynamic> item) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${item['firstname']} ${item['lastname']}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (item['total_fare'] != null)
              _infoRow('Fare', '\$${item['total_fare']}'),
            _infoRow('Status', 'Completed'),
            if (item['datetime'] != null)
              _infoRow('Date', item['datetime'].toString().split('T').first),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchPassedServices,
            tooltip: 'Refresh',
          )
        ],
      ),
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : errorMessage.isNotEmpty
            ? Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              errorMessage,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
        )
            : history.isEmpty
            ? const Center(
          child: Text(
            'No history found.',
            style: TextStyle(fontSize: 16),
          ),
        )
            : ListView.builder(
          itemCount: history.length,
          padding: const EdgeInsets.only(bottom: 12),
          itemBuilder: (context, index) {
            return _historyCard(history[index]);
          },
        ),
      ),
    );
  }
}
