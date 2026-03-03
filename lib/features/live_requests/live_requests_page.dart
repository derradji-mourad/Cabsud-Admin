import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cabsudadminn/features/live_requests/request_details_page.dart';
import 'package:http/http.dart' as http;

import '../../main.dart';
import '../../theme/app_colors.dart';

class ServicesPage extends StatefulWidget {
  const ServicesPage({Key? key}) : super(key: key);

  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  List<dynamic> services = [];
  final AudioPlayer _audioPlayer = AudioPlayer();
  Set<String> _notifiedRequestIds = {};
  bool _isLoading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    fetchServices();
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => fetchServices(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
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
        for (var service in newRequests) {
          _notifiedRequestIds.add(service['id'].toString());
        }
        await _playNotificationSound();
        _showNewRequestDialog();
      }

      if (mounted) {
        setState(() {
          services = response;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching services: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
        backgroundColor: AppColors.secondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.notifications_active,
                color: AppColors.gold,
              ),
            ),
            const SizedBox(width: 14),
            const Text("New Request"),
          ],
        ),
        content: const Text(
          "A new service request has been received.",
          style: TextStyle(color: AppColors.textSecondary),
        ),
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
      final response = await supabase
          .from('services')
          .select()
          .eq('id', id)
          .single();
      await supabase.from('passed_services').insert(response);
      await supabase.from('services').delete().eq('id', id);
      fetchServices();
    } catch (e) {
      print('Error moving to passed service: $e');
    }
  }

  Future<List<Map<String, dynamic>>> fetchAvailableDrivers() async {
    final response = await supabase
        .from('driver')
        .select()
        .eq('isavailable', true);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>?> fetchDriverLocation(String driverId) async {
    final response = await supabase
        .from('drivers_location')
        .select()
        .eq('driver_id', driverId)
        .maybeSingle();
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

      List<Map<String, dynamic>> drivers = await fetchAvailableDrivers();
      if (drivers.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("No available drivers.")));
        return;
      }

      List<Map<String, dynamic>> driversWithDistance = [];
      for (final driver in drivers) {
        final driverLoc = await fetchDriverLocation(driver['id']);
        if (driverLoc == null) continue;

        final driverLat = driverLoc['lat'];
        final driverLng = driverLoc['lng'];

        final distance = Geolocator.distanceBetween(
          pickupLat,
          pickupLng,
          driverLat,
          driverLng,
        );

        driversWithDistance.add({'driver': driver, 'distance': distance});
      }

      if (driversWithDistance.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No drivers with location found.")),
        );
        return;
      }

      driversWithDistance.sort(
        (a, b) => a['distance'].compareTo(b['distance']),
      );

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
                  final distanceKm = (driverData['distance'] / 1000)
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
      print('Error showing driver selection: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Failed to load drivers.")));
    }
  }

  Future<void> _assignDriver(
    Map<String, dynamic> service,
    Map<String, dynamic> driver,
  ) async {
    final supabaseUrl = 'https://utypxmgyfqfwlkpkqrff.supabase.co';
    final edgeFunctionUrl = '$supabaseUrl/functions/v1/send_trip_to_driver';

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
          'apikey':
              'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV0eXB4bWd5ZnFmd2xrcGtxcmZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTAyNDAxMTAsImV4cCI6MjA2NTgxNjExMH0.tkNF11cJ06ZNt0dykFgu1smGEDWuT0Q4LtAmRL6wNZU',
          'Authorization':
              'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV0eXB4bWd5ZnFmd2xrcGtxcmZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTAyNDAxMTAsImV4cCI6MjA2NTgxNjExMH0.tkNF11cJ06ZNt0dykFgu1smGEDWuT0Q4LtAmRL6wNZU',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
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
      print('Error assigning driver: $e');
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
      return Center(
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
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: services.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final s = services[index];
        return _buildRequestCard(s);
      },
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> s) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 280),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Determine sizing based on available width
          final width = constraints.maxWidth;
          final isVerySmall = width < 400;
          final isSmall = width < 600;

          // Adaptive dimensions
          final cardPadding = isVerySmall ? 8.0 : (isSmall ? 12.0 : 16.0);
          final avatarSize = isVerySmall ? 32.0 : 44.0;
          final spacing = isVerySmall ? 6.0 : (isSmall ? 8.0 : 12.0);
          final iconContainerSize = isVerySmall ? 24.0 : 28.0;
          final iconSize = isVerySmall ? 12.0 : 14.0;
          final nameFontSize = isVerySmall ? 13.0 : 15.0;
          final phoneFontSize = isVerySmall ? 11.0 : 13.0;
          final fareFontSize = isVerySmall ? 11.0 : 13.0;
          final tagFontSize = isVerySmall ? 9.0 : 11.0;
          final tagIconSize = isVerySmall ? 10.0 : 12.0;
          final tagPadding = isVerySmall ? 4.0 : 8.0;

          return Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(isVerySmall ? 12 : 16),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.3),
              ),
            ),
            child: Padding(
              padding: EdgeInsets.all(cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Row
                  Row(
                    children: [
                      Container(
                        width: avatarSize,
                        height: avatarSize,
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(
                            isVerySmall ? 8 : 12,
                          ),
                        ),
                        child: Icon(
                          Icons.person,
                          color: AppColors.gold,
                          size: avatarSize * 0.5,
                        ),
                      ),
                      SizedBox(width: spacing),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${s['firstname']} ${s['lastname']}',
                              style: TextStyle(
                                fontSize: nameFontSize,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            if (s['phonenumber'] != null)
                              Text(
                                s['phonenumber'],
                                style: TextStyle(
                                  fontSize: phoneFontSize,
                                  color: AppColors.textMuted,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                          ],
                        ),
                      ),
                      if (s['total_fare'] != null) ...[
                        SizedBox(width: spacing * 0.5),
                        Flexible(
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: isVerySmall ? 50 : (isSmall ? 60 : 80),
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: isVerySmall ? 6 : 10,
                              vertical: isVerySmall ? 4 : 6,
                            ),
                            decoration: BoxDecoration(
                              gradient: AppColors.goldGradient,
                              borderRadius: BorderRadius.circular(
                                isVerySmall ? 6 : 8,
                              ),
                            ),
                            child: Text(
                              '\$${s['total_fare']}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                                fontSize: fareFontSize,
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

                  SizedBox(height: spacing + 4),

                  // Location Info
                  _buildLocationRow(
                    Icons.trip_origin,
                    'Pickup',
                    s['pickuplocation'] ?? 'N/A',
                    AppColors.success,
                    iconContainerSize,
                    iconSize,
                  ),
                  SizedBox(height: spacing - 2),
                  _buildLocationRow(
                    Icons.place,
                    'Drop-off',
                    s['dropofflocation'] ?? 'N/A',
                    AppColors.error,
                    iconContainerSize,
                    iconSize,
                  ),

                  SizedBox(height: spacing + 2),

                  // Tags Row
                  Wrap(
                    spacing: isVerySmall ? 4 : 6,
                    runSpacing: isVerySmall ? 4 : 6,
                    children: [
                      if (s['servicetype'] != null)
                        _buildTag(
                          s['servicetype'],
                          Icons.category_outlined,
                          tagPadding,
                          tagIconSize,
                          tagFontSize,
                          isVerySmall,
                        ),
                      if (s['vehicle_type'] != null)
                        _buildTag(
                          s['vehicle_type'],
                          Icons.directions_car_outlined,
                          tagPadding,
                          tagIconSize,
                          tagFontSize,
                          isVerySmall,
                        ),
                      if (s['datetime'] != null)
                        _buildTag(
                          _formatDate(s['datetime']),
                          Icons.schedule_outlined,
                          tagPadding,
                          tagIconSize,
                          tagFontSize,
                          isVerySmall,
                        ),
                    ],
                  ),

                  SizedBox(height: spacing + 4),

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
                          isVerySmall,
                        ),
                      ),
                      SizedBox(width: isVerySmall ? 4 : 8),
                      Expanded(
                        child: _buildActionButton(
                          'Assign',
                          Icons.local_taxi_outlined,
                          AppColors.gold,
                          () => _showDriverSelectionDialog(s),
                          isVerySmall,
                        ),
                      ),
                      SizedBox(width: isVerySmall ? 4 : 8),
                      Expanded(
                        child: _buildActionButton(
                          'Done',
                          Icons.check_circle_outline,
                          AppColors.success,
                          () {
                            final id = s['id'];
                            if (id != null) moveToPassedService(id);
                          },
                          isVerySmall,
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
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, color: color, size: iconSize),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1,
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
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: iconOnly ? 8 : 10,
            horizontal: iconOnly ? 0 : 4,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: iconOnly ? 18 : 16),
              if (!iconOnly) ...[
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: color,
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
