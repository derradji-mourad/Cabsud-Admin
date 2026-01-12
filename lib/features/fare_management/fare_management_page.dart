import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class FareManagementPage extends StatefulWidget {
  const FareManagementPage({Key? key}) : super(key: key);

  @override
  State<FareManagementPage> createState() => _FareManagementPageState();
}

class _FareManagementPageState extends State<FareManagementPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> fares = [];
  bool isLoading = true;

  final String edgeFunctionUrl =
      'https://utypxmgyfqfwlkpkqrff.supabase.co/functions/v1/modifier-fare';

  @override
  void initState() {
    super.initState();
    fetchFares();
  }

  Future<void> fetchFares() async {
    final response = await supabase
        .from('fare')
        .select('id, category, base_fare, price_per_km, price_per_minute')
        .order('id');

    setState(() {
      fares = List<Map<String, dynamic>>.from(response);
      isLoading = false;
    });
  }

  Future<void> updateFareOnServer(Map<String, dynamic> updatedFare) async {
    final res = await http.post(
      Uri.parse(edgeFunctionUrl),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(updatedFare),
    );

    if (res.statusCode == 200) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fare updated successfully')),
        );
      }
      fetchFares();
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: ${res.body}')),
        );
      }
    }
  }

  void showEditDialog(Map<String, dynamic> fare) {
    final baseFareCtrl =
    TextEditingController(text: fare['base_fare'].toString());
    final perKmCtrl =
    TextEditingController(text: fare['price_per_km'].toString());
    final perMinCtrl =
    TextEditingController(text: fare['price_per_minute'].toString());

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Edit "${fare['category'].toString().toUpperCase()}" Fare'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: baseFareCtrl,
                decoration: const InputDecoration(labelText: 'Base Fare'),
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: perKmCtrl,
                decoration: const InputDecoration(labelText: 'Price per KM'),
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: perMinCtrl,
                decoration: const InputDecoration(labelText: 'Price per Minute'),
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final updated = {
                'id': fare['id'],
                'base_fare': double.tryParse(baseFareCtrl.text) ?? 0.0,
                'price_per_km': double.tryParse(perKmCtrl.text) ?? 0.0,
                'price_per_minute': double.tryParse(perMinCtrl.text) ?? 0.0,
              };
              Navigator.pop(context);
              updateFareOnServer(updated);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget buildFareCard(Map<String, dynamic> fare) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(
          fare['category'].toString().toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6.0),
          child: Text(
            'Base: \$${fare['base_fare']} | KM: \$${fare['price_per_km']} | Min: \$${fare['price_per_minute']}',
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.edit),
          onPressed: () => showEditDialog(fare),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fare Management')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : fares.isEmpty
              ? const Center(child: Text('No fare configurations found.'))
              : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'All Fare Configurations',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: fares.length,
                  itemBuilder: (context, index) {
                    return buildFareCard(fares[index]);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
