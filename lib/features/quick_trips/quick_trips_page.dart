import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../config/supabase_config.dart';
import '../../theme/app_colors.dart';

class QuickTripsPage extends StatefulWidget {
  const QuickTripsPage({super.key});

  @override
  State<QuickTripsPage> createState() => _QuickTripsPageState();
}

class _QuickTripsPageState extends State<QuickTripsPage>
    with WidgetsBindingObserver {
  static const Duration _refreshInterval = Duration(seconds: 30);

  final SupabaseClient supabase = Supabase.instance.client;
  List<Map<String, dynamic>> quickTrips = [];
  bool _isLoading = true;
  RealtimeChannel? _channel;
  Timer? _refreshTimer;

  // For driver assignment
  List<Map<String, dynamic>> _availableDrivers = [];
  bool _isLoadingDrivers = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInitial();
    _subscribeToQuickTrips();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _loadInitial());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    if (_channel != null) supabase.removeChannel(_channel!);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadInitial();
    }
  }

  void _subscribeToQuickTrips() {
    _channel = supabase.channel('quick_trips_realtime')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'quick_trips',
        callback: _handleInsert,
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'quick_trips',
        callback: _handleUpdate,
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'quick_trips',
        callback: _handleDelete,
      )
      ..subscribe();
  }

  Future<void> _loadInitial() async {
    try {
      final response = await supabase
          .from('quick_trips')
          .select()
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(response);

      if (list.isNotEmpty) {
        debugPrint('quick_trips row keys: ${list.first.keys.toList()}');
      }

      if (mounted) {
        setState(() {
          quickTrips = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching quick trips: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleInsert(PostgresChangePayload payload) {
    final record = payload.newRecord;
    if (record.isEmpty) return;
    final id = record['id']?.toString();
    if (id == null) return;
    // Only show pending trips in this list.
    if (record['status'] != 'pending') return;

    if (mounted) {
      setState(() {
        quickTrips = [record, ..._removeById(quickTrips, id)];
      });
    }
  }

  void _handleUpdate(PostgresChangePayload payload) {
    final record = payload.newRecord;
    if (record.isEmpty) return;
    final id = record['id']?.toString();
    if (id == null) return;
    if (!mounted) return;

    // If the trip is no longer pending, remove it from the visible list.
    if (record['status'] != 'pending') {
      setState(() => quickTrips = _removeById(quickTrips, id));
      return;
    }

    final next = <Map<String, dynamic>>[];
    var replaced = false;
    for (final t in quickTrips) {
      if (t['id']?.toString() == id) {
        next.add(record);
        replaced = true;
      } else {
        next.add(t);
      }
    }
    if (!replaced) next.insert(0, record);
    setState(() => quickTrips = next);
  }

  void _handleDelete(PostgresChangePayload payload) {
    final record = payload.oldRecord;
    if (record.isEmpty) return;
    final id = record['id']?.toString();
    if (id == null) return;
    if (!mounted) return;
    setState(() => quickTrips = _removeById(quickTrips, id));
  }

  List<Map<String, dynamic>> _removeById(
    List<Map<String, dynamic>> list,
    String id,
  ) {
    return [
      for (final t in list)
        if (t['id']?.toString() != id) t,
    ];
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
    try {
      final response = await http.post(
        Uri.parse(SupabaseConfig.assignQuickTripFn),
        headers: {
          'Content-Type': 'application/json',
          'apikey': SupabaseConfig.anonKey,
          'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
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
          // Realtime UPDATE event will remove this trip from the list once
          // its status flips off "pending".
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
      return RefreshIndicator(
        onRefresh: _loadInitial,
        color: AppColors.gold,
        backgroundColor: AppColors.surface,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
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
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadInitial,
      color: AppColors.gold,
      backgroundColor: AppColors.surface,
      child: ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
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
                  crossAxisAlignment: CrossAxisAlignment.center,
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            trip['passenger_name'] ?? 'Unknown',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          if (_extractPhone(trip).isNotEmpty) ...[
                            const SizedBox(height: 6),
                            _buildPhonePill(_extractPhone(trip)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "€${trip['price']?.toString() ?? '0'}",
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
      ),
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

  String _extractPhone(Map<String, dynamic> trip) {
    const candidates = [
      'passenger_phone',
      'phone',
      'phonenumber',
      'phone_number',
      'passenger_phonenumber',
      'passenger_phone_number',
      'contact',
      'contact_phone',
    ];
    for (final k in candidates) {
      final v = trip[k];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }
    return '';
  }

  Widget _buildPhonePill(String phone) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => _callPhone(phone),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.success.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.phone, size: 14, color: AppColors.success),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  phone,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _callPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      final ok = await launchUrl(uri);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open dialer')),
        );
      }
    } catch (e) {
      debugPrint('Could not launch dialer: $e');
    }
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
