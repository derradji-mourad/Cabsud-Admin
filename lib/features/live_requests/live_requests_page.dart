import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cabsudadminn/features/live_requests/request_details_page.dart';
import 'package:http/http.dart' as http;

import '../../main.dart';

class ServicesPage extends StatefulWidget {
  const ServicesPage({Key? key}) : super(key: key);

  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  List<dynamic> services = [];
  final AudioPlayer _audioPlayer = AudioPlayer();
  int _previousServiceCount = 0;
  Set<String> _notifiedRequestIds = {};

  @override
  void initState() {
    super.initState();
    fetchServices();
    Timer.periodic(Duration(seconds: 10), (_) => fetchServices());
  }

  Future<void> fetchServices() async {
    try {
      final response = await supabase
          .from('services')
          .select()
          .order('datetime', ascending: false);

      final newRequests = response.where((service) {
        final id = service['id']?.toString();
        return id != null && !_notifiedRequestIds.contains(id);
      }).toList();

      if (newRequests.isNotEmpty) {
        // Add these new request IDs to the notified set
        for (var service in newRequests) {
          _notifiedRequestIds.add(service['id'].toString());
        }

        await _playNotificationSound();
        _showNewRequestDialog();
      }

      setState(() {
        services = response;
      });
    } catch (e) {
      print('Error fetching services: $e');
    }
  }
  Future<void> _playNotificationSound() async {
    try {
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.play(AssetSource('notification.mp3'));
    } catch (e) {
      print('Error playing sound: $e');
    }
  }
  void _showNewRequestDialog() {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("New Request"),
        content: const Text("A new service request has been received."),
        actions: [
          TextButton(
            child: const Text("OK"),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }


  Future<void> moveToPassedService(String id) async {
    try {
      final response =
      await supabase.from('services').select().eq('id', id).single();
      await supabase.from('passed_services').insert(response);
      await supabase.from('services').delete().eq('id', id);
      fetchServices();
    } catch (e) {
      print('Error moving to passed service: $e');
    }
  }

  Future<List<Map<String, dynamic>>> fetchAvailableDrivers() async {
    // Fetch drivers with isavailable == true
    final response = await supabase
        .from('driver')
        .select()
        .eq('isavailable', true);
    if (response == null) return [];
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>?> fetchDriverLocation(String driverId) async {
    final response = await supabase
        .from('drivers_location')
        .select()
        .eq('driver_id', driverId)
        .maybeSingle(); // <-- use maybeSingle here
    if (response == null) return null;
    return Map<String, dynamic>.from(response);
  }
  Future<void> _showDriverSelectionDialog(Map<String, dynamic> service) async {
    final pickupAddress = service['pickuplocation'];
    if (pickupAddress == null) return;

    try {
      final pickupLocations = await locationFromAddress(pickupAddress);
      if (pickupLocations.isEmpty) throw Exception("Invalid pickup location");

      final pickupLat = pickupLocations.first.latitude;
      final pickupLng = pickupLocations.first.longitude;

      // Fetch available drivers
      List<Map<String, dynamic>> drivers = await fetchAvailableDrivers();
      if (drivers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No available drivers.")),
        );
        return;
      }

      // For each driver, get their location and calculate distance
      List<Map<String, dynamic>> driversWithDistance = [];
      for (final driver in drivers) {
        final driverLoc = await fetchDriverLocation(driver['id']);
        if (driverLoc == null) continue; // skip if no location

        final driverLat = driverLoc['lat'];
        final driverLng = driverLoc['lng'];

        final distance = Geolocator.distanceBetween(
          pickupLat,
          pickupLng,
          driverLat,
          driverLng,
        );

        driversWithDistance.add({
          'driver': driver,
          'distance': distance,
        });
      }

      if (driversWithDistance.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No drivers with location found.")),
        );
        return;
      }

      // Sort drivers by distance (closest first)
      driversWithDistance.sort((a, b) => a['distance'].compareTo(b['distance']));

      // Show selection dialog
      await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Select Driver to Assign'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: driversWithDistance.length,
                itemBuilder: (context, index) {
                  final driverData = driversWithDistance[index];
                  final driver = driverData['driver'] as Map<String, dynamic>;
                  final distanceKm = (driverData['distance'] / 1000).toStringAsFixed(2);

                  return ListTile(
                    title: Text('${driver['firstname']} ${driver['lastname']}'),
                    subtitle: Text('Distance: $distanceKm km\nPhone: ${driver['phonenumber']}'),
                    trailing: Icon(Icons.local_taxi),
                    onTap: () async {
                      Navigator.of(context).pop(); // close dialog
                      await _assignDriver(service, driver);
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        },
      );
    } catch (e) {
      print('Error showing driver selection: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to load drivers.")),
      );
    }
  }

  Future<void> _assignDriver(Map<String, dynamic> service, Map<String, dynamic> driver) async {
    final supabaseUrl = 'https://utypxmgyfqfwlkpkqrff.supabase.co'; // Replace with your Supabase project URL
    final edgeFunctionUrl = '$supabaseUrl/functions/v1/send_trip_to_driver'; // Your Edge Function URL path

    final body = {
      'driver_id': driver['id'],
      'service_id': service['id'],
      'pickup': service['pickuplocation'],
      'dropoff': service['dropofflocation'],
      'fare': service['total_fare'],
      'customer_name': '${service['firstname']} ${service['lastname']}',
      'status': 'assigned',

    };

    try {
      final response = await http.post(
        Uri.parse(edgeFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
          'apikey': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV0eXB4bWd5ZnFmd2xrcGtxcmZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTAyNDAxMTAsImV4cCI6MjA2NTgxNjExMH0.tkNF11cJ06ZNt0dykFgu1smGEDWuT0Q4LtAmRL6wNZU', // Use anon key or service role key as needed
          'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV0eXB4bWd5ZnFmd2xrcGtxcmZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTAyNDAxMTAsImV4cCI6MjA2NTgxNjExMH0.tkNF11cJ06ZNt0dykFgu1smGEDWuT0Q4LtAmRL6wNZU', // sometimes needed
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Assigned to ${driver['firstname']} ${driver['lastname']}")),
          );
        } else {
          throw Exception(data['error'] ?? 'Unknown error');
        }
      } else {
        throw Exception('Failed to assign driver: ${response.body}');
      }
    } catch (e) {
      print('Error assigning driver: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to assign driver.")),
      );
    }
  }

  Widget _infoText(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Service Requests'),
      ),
      body: services.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: services.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final s = services[index];

          return Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person, size: 20),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${s['firstname']} ${s['lastname']}',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    runSpacing: 4,
                    children: [
                      if (s['email'] != null) _infoText('Email', s['email']),
                      if (s['phonenumber'] != null)
                        _infoText('Phone', s['phonenumber']),
                      if (s['servicetype'] != null)
                        _infoText('Service', s['servicetype']),
                      if (s['vehicle_type'] != null)
                        _infoText('Vehicle', s['vehicle_type']),
                      if (s['pickuplocation'] != null)
                        _infoText('Pickup', s['pickuplocation']),
                      if (s['dropofflocation'] != null)
                        _infoText('Drop-off', s['dropofflocation']),
                      if (s['total_fare'] != null)
                        _infoText('Fare', '\$${s['total_fare']}'),
                      if (s['datetime'] != null) _infoText('Date', s['datetime']),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.end,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.map),
                        label: const Text('View on Map'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => LiveDriverMapPage(
                                pickupLocation: s['pickuplocation'],
                                dropoffLocation: s['dropofflocation'],
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[600],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Mark as Passed'),
                        onPressed: () {
                          final id = s['id'];
                          if (id != null) {
                            moveToPassedService(id);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          backgroundColor: Colors.green[600],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.local_taxi),
                        label: const Text('Assign Driver'),
                        onPressed: () => _showDriverSelectionDialog(s),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}