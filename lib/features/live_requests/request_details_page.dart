import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../config/supabase_config.dart';
import '../../theme/app_colors.dart';

class LiveDriverMapPage extends StatefulWidget {
  final String? pickupLocation;
  final String? dropoffLocation;

  const LiveDriverMapPage({
    super.key,
    this.pickupLocation,
    this.dropoffLocation,
  });

  @override
  State<LiveDriverMapPage> createState() => _LiveDriverMapPageState();
}

class _LiveDriverMapPageState extends State<LiveDriverMapPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  GoogleMapController? _mapController;
  LatLng? _currentUserLocation;

  final Map<String, Marker> _driverMarkers = {};
  Marker? _pickupMarker;
  Marker? _dropoffMarker;
  Polyline? _routePolyline;

  // Pre-computed merged set so build() doesn't allocate a fresh Set every frame.
  Set<Marker> _allMarkers = const <Marker>{};
  Set<Polyline> _allPolylines = const <Polyline>{};

  RealtimeChannel? _channel;
  BitmapDescriptor? _cachedCarIcon;
  bool _isLoading = true;

  // Route metadata (Directions API legs[0]).
  String? _routeDistanceText;
  String? _routeDurationText;

  // Cached LatLngs so the "fit bounds" button can recenter without re-geocoding.
  LatLng? _pickupLatLng;
  LatLng? _dropoffLatLng;

  // Custom dark map style loaded from assets/map_style.json.
  String? _mapStyle;

  bool get _hasRoute =>
      widget.pickupLocation != null && widget.dropoffLocation != null;

  @override
  void initState() {
    super.initState();
    _initializeMap();
  }

  Future<void> _initializeMap() async {
    // Run independent setup in parallel — style, drivers, and user location
    // don't depend on each other.
    await Future.wait([
      _loadMapStyle(),
      _getUserLocation(),
      _loadInitialDrivers(),
    ]);
    _subscribeToDriverUpdates();

    if (_hasRoute) {
      await _handlePickupAndDropoff(
        widget.pickupLocation!,
        widget.dropoffLocation!,
      );
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMapStyle() async {
    try {
      _mapStyle = await rootBundle.loadString('assets/map_style.json');
    } catch (e) {
      debugPrint('Could not load map style: $e');
    }
  }

  Future<void> _getUserLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
    }

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    if (mounted) {
      setState(() {
        _currentUserLocation = LatLng(position.latitude, position.longitude);
      });
    }
  }

  Future<void> _loadInitialDrivers() async {
    try {
      final response = await supabase
          .from('drivers_location')
          .select()
          .eq('is_available', true)
          .order('updated_at', ascending: false);

      _updateDriverMarkers(response);
    } catch (e) {
      debugPrint("Error loading drivers: $e");
    }
  }

  void _rebuildMarkerSet() {
    _allMarkers = {
      ..._driverMarkers.values,
      if (_pickupMarker != null) _pickupMarker!,
      if (_dropoffMarker != null) _dropoffMarker!,
    };
  }

  void _rebuildPolylineSet() {
    _allPolylines = {if (_routePolyline != null) _routePolyline!};
  }

  Future<void> _subscribeToDriverUpdates() async {
    _channel = supabase.channel('driver_location_changes');

    _channel?.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'drivers_location',
      callback: (payload) {
        final record = payload.newRecord;
        if (record.isNotEmpty) {
          _updateSingleDriverMarker(record);
        } else {
          _loadInitialDrivers();
        }
      },
    );

    _channel?.subscribe();
  }

  Future<BitmapDescriptor> _getCarIcon() async {
    _cachedCarIcon ??= await BitmapDescriptor.asset(
      const ImageConfiguration(size: Size(48, 48)),
      'assets/car.png',
    );
    return _cachedCarIcon!;
  }

  void _updateDriverMarkers(List<dynamic> drivers) async {
    final carIcon = await _getCarIcon();
    final Map<String, Marker> newMarkers = {};

    for (var driver in drivers) {
      final id = driver['id'].toString();
      final lat = driver['lat'];
      final lng = driver['lng'];
      final name = driver['name'] ?? 'Available Driver';

      newMarkers[id] = Marker(
        markerId: MarkerId(id),
        position: LatLng(lat, lng),
        infoWindow: InfoWindow(title: name),
        icon: carIcon,
      );
    }

    if (mounted) {
      setState(() {
        _driverMarkers
          ..clear()
          ..addAll(newMarkers);
        _rebuildMarkerSet();
      });
    }
  }

  Future<void> _updateSingleDriverMarker(Map<String, dynamic> driver) async {
    if (!mounted) return;
    final id = driver['id']?.toString();
    if (id == null) return;

    if (driver['is_available'] != true) {
      if (_driverMarkers.containsKey(id)) {
        setState(() {
          _driverMarkers.remove(id);
          _rebuildMarkerSet();
        });
      }
      return;
    }

    final lat = driver['lat'];
    final lng = driver['lng'];
    if (lat == null || lng == null) return;

    final carIcon = await _getCarIcon();
    if (!mounted) return;

    setState(() {
      _driverMarkers[id] = Marker(
        markerId: MarkerId(id),
        position: LatLng((lat as num).toDouble(), (lng as num).toDouble()),
        infoWindow: InfoWindow(title: driver['name'] ?? 'Available Driver'),
        icon: carIcon,
      );
      _rebuildMarkerSet();
    });
  }

  Future<void> _handlePickupAndDropoff(
    String pickupAddress,
    String dropoffAddress,
  ) async {
    try {
      final results = await Future.wait([
        locationFromAddress(pickupAddress),
        locationFromAddress(dropoffAddress),
      ]);

      final pickupLocations = results[0];
      final dropoffLocations = results[1];

      if (pickupLocations.isNotEmpty && dropoffLocations.isNotEmpty) {
        final pickupLatLng = LatLng(
          pickupLocations.first.latitude,
          pickupLocations.first.longitude,
        );
        final dropoffLatLng = LatLng(
          dropoffLocations.first.latitude,
          dropoffLocations.first.longitude,
        );

        _pickupLatLng = pickupLatLng;
        _dropoffLatLng = dropoffLatLng;

        final iconResults = await Future.wait([
          BitmapDescriptor.asset(
            const ImageConfiguration(size: Size(48, 48)),
            'assets/pickup_pin.png',
          ),
          BitmapDescriptor.asset(
            const ImageConfiguration(size: Size(48, 48)),
            'assets/dropoff_pin.png',
          ),
        ]);

        if (mounted) {
          setState(() {
            _pickupMarker = Marker(
              markerId: const MarkerId('pickup'),
              position: pickupLatLng,
              infoWindow: const InfoWindow(title: 'Pickup'),
              icon: iconResults[0],
            );
            _dropoffMarker = Marker(
              markerId: const MarkerId('dropoff'),
              position: dropoffLatLng,
              infoWindow: const InfoWindow(title: 'Drop-off'),
              icon: iconResults[1],
            );
            _rebuildMarkerSet();
          });
        }

        await Future.delayed(const Duration(milliseconds: 500));
        _fitBoundsToRoute();
        await _drawRoutePolyline(pickupLatLng, dropoffLatLng);
      }
    } catch (e) {
      debugPrint('Error geocoding pickup/dropoff: $e');
    }
  }

  void _fitBoundsToRoute() {
    if (_pickupLatLng == null || _dropoffLatLng == null) return;
    final p = _pickupLatLng!;
    final d = _dropoffLatLng!;
    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(
            p.latitude < d.latitude ? p.latitude : d.latitude,
            p.longitude < d.longitude ? p.longitude : d.longitude,
          ),
          northeast: LatLng(
            p.latitude > d.latitude ? p.latitude : d.latitude,
            p.longitude > d.longitude ? p.longitude : d.longitude,
          ),
        ),
        100,
      ),
    );
  }

  Future<void> _drawRoutePolyline(LatLng origin, LatLng destination) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=${origin.latitude},${origin.longitude}'
      '&destination=${destination.latitude},${destination.longitude}'
      '&key=${SupabaseConfig.googleMapsApiKey}',
    );

    try {
      final response = await http.get(url);
      final data = json.decode(response.body);

      if (data['status'] == 'OK') {
        final route = data['routes'][0];
        final points = route['overview_polyline']['points'];
        final List<LatLng> routeCoords = _decodePolyline(points);

        // Pull distance + duration from the first leg of the route.
        String? distanceText;
        String? durationText;
        final legs = route['legs'];
        if (legs is List && legs.isNotEmpty) {
          distanceText = legs[0]['distance']?['text']?.toString();
          durationText = legs[0]['duration']?['text']?.toString();
        }

        if (mounted) {
          setState(() {
            _routePolyline = Polyline(
              polylineId: const PolylineId('route'),
              color: AppColors.gold,
              width: 6,
              points: routeCoords,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              jointType: JointType.round,
            );
            _rebuildPolylineSet();
            _routeDistanceText = distanceText;
            _routeDurationText = durationText;
          });
        }
      } else {
        debugPrint('Directions API error: ${data['status']}');
      }
    } catch (e) {
      debugPrint('Failed to fetch directions: $e');
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> polyline = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dLat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dLng;

      polyline.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return polyline;
  }

  @override
  void dispose() {
    if (_channel != null) {
      supabase.removeChannel(_channel!);
      _channel = null;
    }
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _currentUserLocation == null) {
      return _buildLoadingScreen();
    }

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Stack(
        children: [
          // Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentUserLocation!,
              zoom: 14,
            ),
            style: _mapStyle,
            markers: _allMarkers,
            polylines: _allPolylines,
            onMapCreated: (controller) => _mapController = controller,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
          ),

          // Top overlay: back button + (optional) route info card
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _buildPillButton(
                        icon: Icons.arrow_back,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const Spacer(),
                      _buildOnlineBadge(),
                    ],
                  ),
                  if (_hasRoute) ...[
                    const SizedBox(height: 12),
                    _buildRouteCard(),
                  ],
                ],
              ),
            ),
          ),

          // Right-side map controls
          Positioned(
            right: 16,
            bottom: 32,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildMapButton(Icons.add, () {
                    _mapController?.animateCamera(CameraUpdate.zoomIn());
                  }),
                  const SizedBox(height: 8),
                  _buildMapButton(Icons.remove, () {
                    _mapController?.animateCamera(CameraUpdate.zoomOut());
                  }),
                  const SizedBox(height: 8),
                  _buildMapButton(Icons.my_location, () {
                    if (_currentUserLocation != null) {
                      _mapController?.animateCamera(
                        CameraUpdate.newLatLng(_currentUserLocation!),
                      );
                    }
                  }),
                  if (_hasRoute) ...[
                    const SizedBox(height: 8),
                    _buildMapButton(
                      Icons.center_focus_strong,
                      _fitBoundsToRoute,
                      tint: AppColors.gold,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 12,
                left: 16,
                child: _buildPillButton(
                  icon: Icons.arrow_back,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: AppColors.gold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: AppColors.gold.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Icon(
                        Icons.map_outlined,
                        size: 40,
                        color: AppColors.gold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        color: AppColors.gold,
                        strokeWidth: 2.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Loading map...',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Fetching drivers and route',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOnlineBadge() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: AppColors.success.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.success.withValues(alpha: 0.6),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_driverMarkers.length} online',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRouteCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.gold.withValues(alpha: 0.25),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _routeWaypoint(
                color: AppColors.success,
                label: 'PICKUP',
                value: widget.pickupLocation ?? '—',
              ),
              Padding(
                padding: const EdgeInsets.only(left: 5, top: 4, bottom: 4),
                child: Column(
                  children: List.generate(
                    4,
                    (i) => Container(
                      width: 2,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 1),
                      color: AppColors.border.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
              _routeWaypoint(
                color: AppColors.error,
                label: 'DROP-OFF',
                value: widget.dropoffLocation ?? '—',
              ),
              if (_routeDistanceText != null || _routeDurationText != null) ...[
                const SizedBox(height: 14),
                Container(
                  height: 1,
                  color: AppColors.border.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (_routeDistanceText != null)
                      Expanded(
                        child: _routeStat(
                          icon: Icons.straighten,
                          label: 'Distance',
                          value: _routeDistanceText!,
                        ),
                      ),
                    if (_routeDurationText != null)
                      Expanded(
                        child: _routeStat(
                          icon: Icons.schedule,
                          label: 'Duration',
                          value: _routeDurationText!,
                        ),
                      ),
                    Expanded(
                      child: _routeStat(
                        icon: Icons.local_taxi,
                        label: 'Drivers',
                        value: '${_driverMarkers.length}',
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: _openInExternalMaps,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        gradient: AppColors.goldGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.directions,
                            color: AppColors.primary,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Open in Maps',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openInExternalMaps() async {
    if (_pickupLatLng == null || _dropoffLatLng == null) return;
    final origin = _pickupLatLng!;
    final dest = _dropoffLatLng!;
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _MapAppPicker(
        isIOS: isIOS,
        onSelected: (app) async {
          Navigator.of(context).pop();
          await _launchMapApp(app, origin, dest);
        },
      ),
    );
  }

  Future<void> _launchMapApp(
    _MapApp app,
    LatLng origin,
    LatLng dest,
  ) async {
    final oLat = origin.latitude;
    final oLng = origin.longitude;
    final dLat = dest.latitude;
    final dLng = dest.longitude;

    Uri uri;
    switch (app) {
      case _MapApp.googleMaps:
        uri = Uri.parse(
          'https://www.google.com/maps/dir/?api=1'
          '&origin=$oLat,$oLng'
          '&destination=$dLat,$dLng'
          '&travelmode=driving',
        );
        break;
      case _MapApp.waze:
        // Waze accepts only the destination; navigation starts from current
        // position automatically.
        uri = Uri.parse(
          'https://waze.com/ul?ll=$dLat%2C$dLng&navigate=yes',
        );
        break;
      case _MapApp.appleMaps:
        uri = Uri.parse(
          'http://maps.apple.com/?saddr=$oLat,$oLng&daddr=$dLat,$dLng&dirflg=d',
        );
        break;
      case _MapApp.systemChooser:
        // Android system chooser — every installed map app that handles geo:
        // appears in the picker.
        uri = Uri.parse(
          'geo:$dLat,$dLng?q=$dLat,$dLng(${Uri.encodeComponent(widget.dropoffLocation ?? "Drop-off")})',
        );
        break;
    }

    try {
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open that app.')),
        );
      }
    } catch (e) {
      debugPrint('Failed to launch map app: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open that app.')),
        );
      }
    }
  }

  Widget _routeWaypoint({
    required Color color,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.6),
                blurRadius: 6,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
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

  Widget _routeStat({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: AppColors.gold),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildPillButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.border.withValues(alpha: 0.4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: AppColors.textPrimary, size: 20),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapButton(
    IconData icon,
    VoidCallback onPressed, {
    Color? tint,
  }) {
    final iconColor = tint ?? AppColors.textPrimary;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: tint != null
                  ? tint.withValues(alpha: 0.4)
                  : AppColors.border.withValues(alpha: 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
      ),
    );
  }
}

enum _MapApp { googleMaps, waze, appleMaps, systemChooser }

class _MapAppPicker extends StatelessWidget {
  final bool isIOS;
  final ValueChanged<_MapApp> onSelected;

  const _MapAppPicker({required this.isIOS, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                'Open with',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _option(
              label: 'Google Maps',
              subtitle: 'Pickup → Drop-off',
              icon: Icons.map_outlined,
              tint: AppColors.success,
              onTap: () => onSelected(_MapApp.googleMaps),
            ),
            _option(
              label: 'Waze',
              subtitle: 'Navigate to drop-off',
              icon: Icons.navigation_outlined,
              tint: AppColors.info,
              onTap: () => onSelected(_MapApp.waze),
            ),
            if (isIOS)
              _option(
                label: 'Apple Maps',
                subtitle: 'Pickup → Drop-off',
                icon: Icons.location_on_outlined,
                tint: AppColors.textSecondary,
                onTap: () => onSelected(_MapApp.appleMaps),
              )
            else
              _option(
                label: 'Other apps…',
                subtitle: 'Pick from installed map apps',
                icon: Icons.apps,
                tint: AppColors.gold,
                onTap: () => onSelected(_MapApp.systemChooser),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _option({
    required String label,
    required String subtitle,
    required IconData icon,
    required Color tint,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: tint.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Icon(icon, color: tint),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
