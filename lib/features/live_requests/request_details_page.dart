import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;

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

  RealtimeChannel? _channel;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeMap();
  }

  Future<void> _initializeMap() async {
    await _getUserLocation();
    await _loadInitialDrivers();
    _subscribeToDriverUpdates();

    if (widget.pickupLocation != null && widget.dropoffLocation != null) {
      await _handlePickupAndDropoff(
        widget.pickupLocation!,
        widget.dropoffLocation!,
      );
    }

    if (mounted) {
      setState(() => _isLoading = false);
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
      print("Error loading drivers: $e");
    }
  }

  Future<void> _subscribeToDriverUpdates() async {
    _channel = supabase.channel('driver_location_changes');

    _channel?.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'drivers_location',
      callback: (payload) {
        _loadInitialDrivers();
      },
    );

    _channel?.subscribe();
  }

  void _updateDriverMarkers(List<dynamic> drivers) async {
    final Map<String, Marker> newMarkers = {};

    final carIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(48, 48)),
      'assets/car.png',
    );

    for (var driver in drivers) {
      final id = driver['id'].toString();
      final lat = driver['lat'];
      final lng = driver['lng'];
      final name = driver['name'] ?? 'Available Driver';

      final marker = Marker(
        markerId: MarkerId(id),
        position: LatLng(lat, lng),
        infoWindow: InfoWindow(title: name),
        icon: carIcon,
      );

      newMarkers[id] = marker;
    }

    if (mounted) {
      setState(() {
        _driverMarkers
          ..clear()
          ..addAll(newMarkers);
      });
    }
  }

  Future<void> _handlePickupAndDropoff(
    String pickupAddress,
    String dropoffAddress,
  ) async {
    try {
      List<Location> pickupLocations = await locationFromAddress(pickupAddress);
      List<Location> dropoffLocations = await locationFromAddress(
        dropoffAddress,
      );

      if (pickupLocations.isNotEmpty && dropoffLocations.isNotEmpty) {
        LatLng pickupLatLng = LatLng(
          pickupLocations.first.latitude,
          pickupLocations.first.longitude,
        );
        LatLng dropoffLatLng = LatLng(
          dropoffLocations.first.latitude,
          dropoffLocations.first.longitude,
        );

        final pickupIcon = await BitmapDescriptor.fromAssetImage(
          const ImageConfiguration(size: Size(48, 48)),
          'assets/pickup_pin.png',
        );
        final dropoffIcon = await BitmapDescriptor.fromAssetImage(
          const ImageConfiguration(size: Size(48, 48)),
          'assets/dropoff_pin.png',
        );

        if (mounted) {
          setState(() {
            _pickupMarker = Marker(
              markerId: const MarkerId('pickup'),
              position: pickupLatLng,
              infoWindow: const InfoWindow(title: 'Pickup'),
              icon: pickupIcon,
            );
            _dropoffMarker = Marker(
              markerId: const MarkerId('dropoff'),
              position: dropoffLatLng,
              infoWindow: const InfoWindow(title: 'Drop-off'),
              icon: dropoffIcon,
            );
          });
        }

        await Future.delayed(const Duration(milliseconds: 500));
        _mapController?.animateCamera(
          CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(
                pickupLatLng.latitude < dropoffLatLng.latitude
                    ? pickupLatLng.latitude
                    : dropoffLatLng.latitude,
                pickupLatLng.longitude < dropoffLatLng.longitude
                    ? pickupLatLng.longitude
                    : dropoffLatLng.longitude,
              ),
              northeast: LatLng(
                pickupLatLng.latitude > dropoffLatLng.latitude
                    ? pickupLatLng.latitude
                    : dropoffLatLng.latitude,
                pickupLatLng.longitude > dropoffLatLng.longitude
                    ? pickupLatLng.longitude
                    : dropoffLatLng.longitude,
              ),
            ),
            100,
          ),
        );

        await _drawRoutePolyline(pickupLatLng, dropoffLatLng);
      }
    } catch (e) {
      print('Error geocoding pickup/dropoff: $e');
    }
  }

  Future<void> _drawRoutePolyline(LatLng origin, LatLng destination) async {
    const apiKey = 'AIzaSyA98tXlKLb3JRZWUv8tFZMeNCQ55VBINaI';

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=${origin.latitude},${origin.longitude}'
      '&destination=${destination.latitude},${destination.longitude}'
      '&key=$apiKey',
    );

    try {
      final response = await http.get(url);
      final data = json.decode(response.body);

      if (data['status'] == 'OK') {
        final points = data['routes'][0]['overview_polyline']['points'];
        final List<LatLng> routeCoords = _decodePolyline(points);

        if (mounted) {
          setState(() {
            _routePolyline = Polyline(
              polylineId: const PolylineId('route'),
              color: AppColors.gold,
              width: 5,
              points: routeCoords,
            );
          });
        }
      } else {
        print('Directions API error: ${data['status']}');
      }
    } catch (e) {
      print('Failed to fetch directions: $e');
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
      return Container(
        decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppColors.gold),
              SizedBox(height: 16),
              Text(
                'Loading map...',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    final allMarkers = {
      ..._driverMarkers.values,
      if (_pickupMarker != null) _pickupMarker!,
      if (_dropoffMarker != null) _dropoffMarker!,
    };

    final allPolylines = {if (_routePolyline != null) _routePolyline!};

    return Stack(
      children: [
        // Map
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _currentUserLocation!,
            zoom: 14,
          ),
          markers: Set<Marker>.of(allMarkers),
          polylines: allPolylines,
          onMapCreated: (controller) => _mapController = controller,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
        ),

        // Top Info Panel (if showing pickup/dropoff)
        if (widget.pickupLocation != null && widget.dropoffLocation != null)
          Positioned(top: 20, left: 20, right: 20, child: _buildInfoPanel()),

        // Zoom Controls
        Positioned(
          right: 20,
          bottom: 100,
          child: Column(
            children: [
              _buildMapButton(Icons.add, () {
                _mapController?.animateCamera(CameraUpdate.zoomIn());
              }),
              const SizedBox(height: 8),
              _buildMapButton(Icons.remove, () {
                _mapController?.animateCamera(CameraUpdate.zoomOut());
              }),
              const SizedBox(height: 8),
              _buildMapButton(Icons.my_location, () async {
                if (_currentUserLocation != null) {
                  _mapController?.animateCamera(
                    CameraUpdate.newLatLng(_currentUserLocation!),
                  );
                }
              }),
            ],
          ),
        ),

        // Drivers Count
        Positioned(
          left: 20,
          bottom: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.3),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${_driverMarkers.length} drivers online',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoPanel() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.pickupLocation ?? 'Pickup',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 5),
                  child: Container(
                    width: 2,
                    height: 20,
                    color: AppColors.border,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.dropoffLocation ?? 'Drop-off',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapButton(IconData icon, VoidCallback onPressed) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.secondary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}
