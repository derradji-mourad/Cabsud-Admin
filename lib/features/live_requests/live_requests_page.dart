import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cabsudadminn/features/live_requests/request_details_page.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../config/supabase_config.dart';
import '../../theme/app_colors.dart';

class ServicesPage extends StatefulWidget {
  const ServicesPage({Key? key}) : super(key: key);

  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage>
    with WidgetsBindingObserver {
  static const Duration _refreshInterval = Duration(seconds: 30);

  final SupabaseClient supabase = Supabase.instance.client;
  List<Map<String, dynamic>> services = [];
  bool _isLoading = true;
  RealtimeChannel? _channel;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInitial();
    _subscribeToServices();
    // Background fallback refresh in case realtime drops events.
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

  void _subscribeToServices() {
    _channel = supabase.channel('services_realtime')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'services',
        callback: _handleInsert,
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'services',
        callback: _handleUpdate,
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'services',
        callback: _handleDelete,
      )
      ..subscribe();
  }

  Future<void> _loadInitial() async {
    try {
      final response = await supabase
          .from('services')
          .select()
          .order('datetime', ascending: false);

      final list = List<Map<String, dynamic>>.from(response);

      if (mounted) {
        setState(() {
          services = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching services: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleInsert(PostgresChangePayload payload) {
    final record = payload.newRecord;
    if (record.isEmpty) return;
    final id = record['id']?.toString();
    if (id == null) return;

    if (mounted) {
      setState(() {
        services = [record, ..._removeById(services, id)];
      });
    }
  }

  void _handleUpdate(PostgresChangePayload payload) {
    final record = payload.newRecord;
    if (record.isEmpty) return;
    final id = record['id']?.toString();
    if (id == null) return;

    if (!mounted) return;
    final next = <Map<String, dynamic>>[];
    var replaced = false;
    for (final s in services) {
      if (s['id']?.toString() == id) {
        next.add(record);
        replaced = true;
      } else {
        next.add(s);
      }
    }
    if (!replaced) next.insert(0, record);
    setState(() => services = next);
  }

  void _handleDelete(PostgresChangePayload payload) {
    final record = payload.oldRecord;
    if (record.isEmpty) return;
    final id = record['id']?.toString();
    if (id == null) return;

    if (!mounted) return;
    setState(() => services = _removeById(services, id));
  }

  List<Map<String, dynamic>> _removeById(
    List<Map<String, dynamic>> list,
    String id,
  ) {
    return [
      for (final s in list)
        if (s['id']?.toString() != id) s,
    ];
  }

  Future<void> moveToPassedService(String id) async {
    try {
      final response = await supabase
          .from('services')
          .select()
          .eq('id', id)
          .single();
      await supabase.from('passed_services').insert(response);
      await supabase.from('services').delete().eq('id', id);
      // Realtime DELETE event will remove the row from local state.
    } catch (e) {
      debugPrint('Error moving to passed service: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAvailableDrivers() async {
    final response = await supabase
        .from('driver')
        .select()
        .eq('isavailable', true);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, Map<String, dynamic>>> _fetchDriverLocations(
    List<dynamic> driverIds,
  ) async {
    if (driverIds.isEmpty) return const {};
    final response = await supabase
        .from('drivers_location')
        .select()
        .inFilter('driver_id', driverIds);

    return {
      for (final loc in response)
        if (loc['driver_id'] != null)
          loc['driver_id'].toString(): Map<String, dynamic>.from(loc as Map),
    };
  }

  Future<void> _showDriverSelectionDialog(Map<String, dynamic> service) async {
    final pickupAddress = service['pickuplocation'];
    if (pickupAddress == null) return;

    try {
      final pickupLocations = await locationFromAddress(pickupAddress);
      if (pickupLocations.isEmpty) throw Exception("Invalid pickup location");

      final pickupLat = pickupLocations.first.latitude;
      final pickupLng = pickupLocations.first.longitude;

      final drivers = await _fetchAvailableDrivers();
      if (drivers.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("No available drivers.")));
        return;
      }

      // Single batched query instead of one round-trip per driver.
      final driverIds = drivers.map((d) => d['id']).toList();
      final locationsByDriverId = await _fetchDriverLocations(driverIds);

      final driversWithDistance = <Map<String, dynamic>>[];
      for (final driver in drivers) {
        final loc = locationsByDriverId[driver['id'].toString()];
        if (loc == null || loc['lat'] == null || loc['lng'] == null) continue;
        final distance = Geolocator.distanceBetween(
          pickupLat,
          pickupLng,
          (loc['lat'] as num).toDouble(),
          (loc['lng'] as num).toDouble(),
        );
        driversWithDistance.add({'driver': driver, 'distance': distance});
      }

      if (driversWithDistance.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No drivers with location found.")),
        );
        return;
      }

      driversWithDistance.sort(
        (a, b) =>
            (a['distance'] as double).compareTo(b['distance'] as double),
      );

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: AppColors.secondary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.local_taxi, color: AppColors.info),
                ),
                const SizedBox(width: 14),
                const Text('Select Driver'),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: driversWithDistance.length,
                itemBuilder: (context, index) {
                  final driverData = driversWithDistance[index];
                  final driver = driverData['driver'] as Map<String, dynamic>;
                  final distanceKm = ((driverData['distance'] as double) / 1000)
                      .toStringAsFixed(2);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.border.withValues(alpha: 0.3),
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.person, color: AppColors.gold),
                      ),
                      title: Text(
                        '${driver['firstname']} ${driver['lastname']}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '$distanceKm km away',
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                      onTap: () async {
                        Navigator.of(context).pop();
                        await _assignDriver(service, driver);
                      },
                    ),
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
      debugPrint('Error showing driver selection: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Failed to load drivers.")));
    }
  }

  Future<void> _assignDriver(
    Map<String, dynamic> service,
    Map<String, dynamic> driver,
  ) async {
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
        Uri.parse(SupabaseConfig.sendTripToDriverFn),
        headers: {
          'Content-Type': 'application/json',
          'apikey': SupabaseConfig.anonKey,
          'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.success),
                  const SizedBox(width: 12),
                  Text(
                    "Assigned to ${driver['firstname']} ${driver['lastname']}",
                  ),
                ],
              ),
              backgroundColor: AppColors.surface,
            ),
          );
        } else {
          throw Exception(data['error'] ?? 'Unknown error');
        }
      } else {
        throw Exception('Failed to assign driver: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error assigning driver: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Failed to assign driver.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }

    if (services.isEmpty) {
      // Scrollable so RefreshIndicator can be triggered on the empty state.
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
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppColors.surface.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.inbox_outlined,
                          size: 64,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'No pending requests',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'New requests will appear here automatically',
                        style: TextStyle(color: AppColors.textMuted),
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

    // Compute breakpoint dimensions ONCE per layout instead of per list item.
    return LayoutBuilder(
      builder: (context, constraints) {
        final dims = _CardDims.fromWidth(constraints.maxWidth);
        return RefreshIndicator(
          onRefresh: _loadInitial,
          color: AppColors.gold,
          backgroundColor: AppColors.surface,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: services.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              return _buildRequestCard(services[index], dims);
            },
          ),
        );
      },
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> s, _CardDims d) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 280),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(d.isVerySmall ? 12 : 16),
          border: Border.all(
            color: AppColors.border.withValues(alpha: 0.3),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(d.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  Container(
                    width: d.avatarSize,
                    height: d.avatarSize,
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(
                        d.isVerySmall ? 8 : 12,
                      ),
                    ),
                    child: Icon(
                      Icons.person,
                      color: AppColors.gold,
                      size: d.avatarSize * 0.5,
                    ),
                  ),
                  SizedBox(width: d.spacing),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${s['firstname']} ${s['lastname']}',
                          style: TextStyle(
                            fontSize: d.nameFontSize,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        if (s['phonenumber'] != null) ...[
                          const SizedBox(height: 4),
                          _buildPhonePill(
                            s['phonenumber'].toString(),
                            d.phoneFontSize,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (s['total_fare'] != null) ...[
                    SizedBox(width: d.spacing * 0.5),
                    Flexible(
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: d.isVerySmall ? 50 : (d.isSmall ? 60 : 80),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: d.isVerySmall ? 6 : 10,
                          vertical: d.isVerySmall ? 4 : 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: AppColors.goldGradient,
                          borderRadius: BorderRadius.circular(
                            d.isVerySmall ? 6 : 8,
                          ),
                        ),
                        child: Text(
                          '€${s['total_fare']}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                            fontSize: d.fareFontSize,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              SizedBox(height: d.spacing + 4),

              // Location Info
              _buildLocationRow(
                Icons.trip_origin,
                'Pickup',
                s['pickuplocation'] ?? 'N/A',
                AppColors.success,
                d.iconContainerSize,
                d.iconSize,
              ),
              SizedBox(height: d.spacing - 2),
              _buildLocationRow(
                Icons.place,
                'Drop-off',
                s['dropofflocation'] ?? 'N/A',
                AppColors.error,
                d.iconContainerSize,
                d.iconSize,
              ),

              SizedBox(height: d.spacing + 2),

              // Tags Row
              Wrap(
                spacing: d.isVerySmall ? 4 : 6,
                runSpacing: d.isVerySmall ? 4 : 6,
                children: [
                  if (s['servicetype'] != null)
                    _buildTag(
                      s['servicetype'],
                      Icons.category_outlined,
                      d.tagPadding,
                      d.tagIconSize,
                      d.tagFontSize,
                      d.isVerySmall,
                    ),
                  if (s['vehicle_type'] != null)
                    _buildTag(
                      s['vehicle_type'],
                      Icons.directions_car_outlined,
                      d.tagPadding,
                      d.tagIconSize,
                      d.tagFontSize,
                      d.isVerySmall,
                    ),
                  if (s['datetime'] != null)
                    _buildTag(
                      _formatDate(s['datetime']),
                      Icons.schedule_outlined,
                      d.tagPadding,
                      d.tagIconSize,
                      d.tagFontSize,
                      d.isVerySmall,
                    ),
                ],
              ),

              SizedBox(height: d.spacing + 4),

              // Action Buttons Row
              Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      'Map',
                      Icons.map_outlined,
                      AppColors.info,
                      () {
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
                      d.isVerySmall,
                    ),
                  ),
                  SizedBox(width: d.isVerySmall ? 4 : 8),
                  Expanded(
                    child: _buildActionButton(
                      'Assign',
                      Icons.local_taxi_outlined,
                      AppColors.gold,
                      () => _showDriverSelectionDialog(s),
                      d.isVerySmall,
                    ),
                  ),
                  SizedBox(width: d.isVerySmall ? 4 : 8),
                  Expanded(
                    child: _buildActionButton(
                      'Done',
                      Icons.check_circle_outline,
                      AppColors.success,
                      () {
                        final id = s['id'];
                        if (id != null) moveToPassedService(id.toString());
                      },
                      d.isVerySmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhonePill(String phone, double fontSize) {
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
              Icon(Icons.phone, size: fontSize, color: AppColors.success),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  phone,
                  style: TextStyle(
                    fontSize: fontSize,
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

  Widget _buildLocationRow(
    IconData icon,
    String label,
    String value,
    Color color,
    double containerSize,
    double iconSize,
  ) {
    return Row(
      children: [
        Container(
          width: containerSize,
          height: containerSize,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: iconSize),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTag(
    String text,
    IconData icon,
    double padding,
    double iconSize,
    double fontSize,
    bool hideIcon,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: padding,
        vertical: padding * 0.5,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!hideIcon) ...[
            Icon(icon, size: iconSize, color: AppColors.textMuted),
            SizedBox(width: padding * 0.5),
          ],
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: fontSize,
                color: AppColors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
    bool iconOnly,
  ) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: iconOnly ? 12 : 13,
            horizontal: iconOnly ? 0 : 6,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: iconOnly ? 22 : 18),
              if (!iconOnly) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: color,
                      letterSpacing: 0.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String datetime) {
    try {
      final dt = DateTime.parse(datetime);
      return '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return datetime;
    }
  }
}

class _CardDims {
  final bool isVerySmall;
  final bool isSmall;
  final double cardPadding;
  final double avatarSize;
  final double spacing;
  final double iconContainerSize;
  final double iconSize;
  final double nameFontSize;
  final double phoneFontSize;
  final double fareFontSize;
  final double tagFontSize;
  final double tagIconSize;
  final double tagPadding;

  const _CardDims({
    required this.isVerySmall,
    required this.isSmall,
    required this.cardPadding,
    required this.avatarSize,
    required this.spacing,
    required this.iconContainerSize,
    required this.iconSize,
    required this.nameFontSize,
    required this.phoneFontSize,
    required this.fareFontSize,
    required this.tagFontSize,
    required this.tagIconSize,
    required this.tagPadding,
  });

  factory _CardDims.fromWidth(double width) {
    final isVerySmall = width < 400;
    final isSmall = width < 600;
    return _CardDims(
      isVerySmall: isVerySmall,
      isSmall: isSmall,
      cardPadding: isVerySmall ? 12.0 : (isSmall ? 16.0 : 20.0),
      avatarSize: isVerySmall ? 44.0 : 52.0,
      spacing: isVerySmall ? 10.0 : (isSmall ? 12.0 : 14.0),
      iconContainerSize: isVerySmall ? 30.0 : 34.0,
      iconSize: isVerySmall ? 16.0 : 18.0,
      nameFontSize: isVerySmall ? 16.0 : 18.0,
      phoneFontSize: isVerySmall ? 14.0 : 15.0,
      fareFontSize: isVerySmall ? 14.0 : 16.0,
      tagFontSize: isVerySmall ? 11.0 : 13.0,
      tagIconSize: isVerySmall ? 12.0 : 14.0,
      tagPadding: isVerySmall ? 6.0 : 10.0,
    );
  }
}
