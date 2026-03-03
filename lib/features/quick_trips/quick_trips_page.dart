import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import '../../theme/app_colors.dart';
import '../../main.dart'; // navigatorKey

class QuickTripsPage extends StatefulWidget {
  const QuickTripsPage({super.key});

  @override
  State<QuickTripsPage> createState() => _QuickTripsPageState();
}

class _QuickTripsPageState extends State<QuickTripsPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  List<Map<String, dynamic>> quickTrips = [];
  bool _isLoading = true;
  Timer? _pollingTimer;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Set<String> _notifiedTripIds = {};

  // For driver assignment
  List<Map<String, dynamic>> _availableDrivers = [];
  bool _isLoadingDrivers = false;

  @override
  void initState() {
    super.initState();
    fetchQuickTrips();
    // Poll every 10 seconds
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => fetchQuickTrips(),
    );
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> fetchQuickTrips() async {
    try {
      final response = await supabase
          .from('quick_trips')
          .select()
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      final newTrips = (response as List).where((trip) {
        final id = trip['id'].toString();
        return !_notifiedTripIds.contains(id);
      }).toList();

      if (newTrips.isNotEmpty) {
        for (var trip in newTrips) {
          _notifiedTripIds.add(trip['id'].toString());
        }
        await _playNotificationSound();
        _showNewQuickTripDialog();
      }

      if (mounted) {
        setState(() {
          quickTrips = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching quick trips: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _playNotificationSound() async {
    try {
      await _audioPlayer.play(AssetSource('notification.mp3'));
    } catch (e) {
      debugPrint("Error playing sound: $e");
    }
  }

  void _showNewQuickTripDialog() {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.secondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.flash_on_rounded, color: Colors.orange),
            ),
            const SizedBox(width: 14),
            const Text("New Quick Trip!"),
          ],
        ),
        content: const Text(
          "A new quick trip request has arrived.",
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            child: const Text("View"),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchAvailableDrivers() async {
    setState(() => _isLoadingDrivers = true);
    try {
      final response = await supabase
          .from('driver')
          .select('id, firstname, lastname, isavailable')
          .eq('isavailable', true);

      if (mounted) {
        setState(() {
          _availableDrivers = List<Map<String, dynamic>>.from(response);
          _isLoadingDrivers = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching drivers: $e');
      if (mounted) {
        setState(() => _isLoadingDrivers = false);
      }
    }
  }

  Future<void> _assignDriver(
    Map<String, dynamic> trip,
    Map<String, dynamic> driver,
  ) async {
    final supabaseUrl = 'https://utypxmgyfqfwlkpkqrff.supabase.co';
    final edgeFunctionUrl = '$supabaseUrl/functions/v1/assign_quick_trip';

    try {
      final response = await http.post(
        Uri.parse(edgeFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
          'apikey':
              'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV0eXB4bWd5ZnFmd2xrcGtxcmZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTAyNDAxMTAsImV4cCI6MjA2NTgxNjExMH0.tkNF11cJ06ZNt0dykFgu1smGEDWuT0Q4LtAmRL6wNZU',
          'Authorization':
              'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV0eXB4bWd5ZnFmd2xrcGtxcmZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTAyNDAxMTAsImV4cCI6MjA2NTgxNjExMH0.tkNF11cJ06ZNt0dykFgu1smGEDWuT0Q4LtAmRL6wNZU',
        },
        body: jsonEncode({
          'driver_id': driver['id'],
          'quick_trip_id': trip['id'],
        }),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "Assigned to ${driver['firstname']} ${driver['lastname']}",
              ),
              backgroundColor: Colors.green,
            ),
          );
          // Refresh list to remove the assigned trip
          fetchQuickTrips();
        }
      } else {
        throw Exception('Failed to assign: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error assigning driver: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to assign driver.")),
        );
      }
    }
  }

  void _showDriverSelectionDialog(Map<String, dynamic> trip) {
    _fetchAvailableDrivers();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.secondary,
        title: const Text("Assign Driver"),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: _isLoadingDrivers
              ? const Center(child: CircularProgressIndicator())
              : _availableDrivers.isEmpty
              ? const Center(
                  child: Text(
                    "No available drivers",
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : ListView.builder(
                  itemCount: _availableDrivers.length,
                  itemBuilder: (context, index) {
                    final driver = _availableDrivers[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.primary,
                        child: Icon(Icons.person, color: AppColors.textPrimary),
                      ),
                      title: Text(
                        "${driver['firstname']} ${driver['lastname']}",
                        style: const TextStyle(color: AppColors.textPrimary),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _assignDriver(trip, driver);
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (quickTrips.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.flash_off_rounded,
              size: 64,
              color: AppColors.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              "No Quick Trips Pending",
              style: TextStyle(color: AppColors.textSecondary, fontSize: 18),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: quickTrips.length,
      itemBuilder: (context, index) {
        final trip = quickTrips[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          color: AppColors.secondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Colors.orange.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.flash_on_rounded,
                        color: Colors.orange,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        trip['passenger_name'] ?? 'Unknown',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      "\$${trip['price']?.toString() ?? '0'}",
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Divider(color: AppColors.border, height: 24),
                _buildInfoRow(
                  Icons.trip_origin,
                  "From",
                  trip['pickup_address'] ?? '',
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  Icons.location_on,
                  "To",
                  trip['dropoff_address'] ?? '',
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildTag(
                      Icons.directions_car,
                      trip['car_type'] ?? 'Standard',
                    ),
                    const SizedBox(width: 8),
                    _buildTag(
                      Icons.payment,
                      trip['payment_method'] ?? 'cash',
                      isPayment: true,
                    ),
                    const SizedBox(width: 8),
                    _buildTag(Icons.timer, "${trip['duration_min'] ?? 0} min"),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _showDriverSelectionDialog(trip),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      "Assign Driver",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.textSecondary, size: 16),
        const SizedBox(width: 8),
        Text(
          "$label: ",
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildTag(IconData icon, String text, {bool isPayment = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPayment
              ? Colors.green.withValues(alpha: 0.3)
              : AppColors.textSecondary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isPayment ? Colors.green : AppColors.textSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            text.toUpperCase(),
            style: TextStyle(
              color: isPayment ? Colors.green : AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
