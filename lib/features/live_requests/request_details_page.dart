import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;

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

  @override
  void initState() {
    super.initState();
    _getUserLocation();
    _loadInitialDrivers();
    _subscribeToDriverUpdates();

    if (widget.pickupLocation != null && widget.dropoffLocation != null) {
      _handlePickupAndDropoff(widget.pickupLocation!, widget.dropoffLocation!);
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

    setState(() {
      _currentUserLocation = LatLng(position.latitude, position.longitude);
    });
  }

  Future<void> _loadInitialDrivers() async {
    try {
      final response = await supabase
          .from('drivers_location')
          .select()
          .eq('is_available', true)
          .order('updated_at', ascending: false);

      if (response != null && response is List) {
        _updateDriverMarkers(response);
      }
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

    await _channel?.subscribe();
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

    setState(() {
      _driverMarkers
        ..clear()
        ..addAll(newMarkers);
    });
  }

  Future<void> _handlePickupAndDropoff(
      String pickupAddress, String dropoffAddress) async {
    try {
      List<Location> pickupLocations = await locationFromAddress(pickupAddress);
      List<Location> dropoffLocations =
      await locationFromAddress(dropoffAddress);

      if (pickupLocations.isNotEmpty && dropoffLocations.isNotEmpty) {
        LatLng pickupLatLng = LatLng(
            pickupLocations.first.latitude, pickupLocations.first.longitude);
        LatLng dropoffLatLng = LatLng(
            dropoffLocations.first.latitude, dropoffLocations.first.longitude);

        final pickupIcon = await BitmapDescriptor.fromAssetImage(
          const ImageConfiguration(size: Size(48, 48)),
          'assets/pickup_pin.png',
        );
        final dropoffIcon = await BitmapDescriptor.fromAssetImage(
          const ImageConfiguration(size: Size(48, 48)),
          'assets/dropoff_pin.png',
        );

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

        // Zoom to fit both markers
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
    const apiKey = 'AIzaSyA98tXlKLb3JRZWUv8tFZMeNCQ55VBINaI'; // Replace with your API key

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

        setState(() {
          _routePolyline = Polyline(
            polylineId: const PolylineId('route'),
            color: Colors.blue,
            width: 5,
            points: routeCoords,
          );
        });
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
    if (_currentUserLocation == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final allMarkers = {
      ..._driverMarkers.values,
      if (_pickupMarker != null) _pickupMarker!,
      if (_dropoffMarker != null) _dropoffMarker!,
    };

    final allPolylines = {
      if (_routePolyline != null) _routePolyline!,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Driver Map'),
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: _currentUserLocation!,
          zoom: 14,
        ),
        markers: Set<Marker>.of(allMarkers),
        polylines: allPolylines,
        onMapCreated: (controller) => _mapController = controller,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
      ),
    );
  }
}
