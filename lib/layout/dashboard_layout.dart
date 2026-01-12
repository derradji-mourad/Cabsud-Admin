import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/live_requests/request_details_page.dart';
import 'sidebar_menu.dart';
import '../features/live_requests/live_requests_page.dart';
import '../features/request_history/request_history_page.dart';
import '../features/add_driver/add_driver_page.dart';
import '../features/fare_management/fare_management_page.dart';
import '../features/all_drivers/all_drivers_page.dart';
import '../main.dart'; // navigatorKey

class DashboardLayout extends StatefulWidget {
  const DashboardLayout({Key? key}) : super(key: key);

  @override
  State<DashboardLayout> createState() => _DashboardLayoutState();
}

class _DashboardLayoutState extends State<DashboardLayout> {
  int selectedIndex = 0;
  bool _dialogShown = false;
  RealtimeChannel? _channel;

  final List<Widget> pages = [
    ServicesPage(),
    RequestHistoryPage(),
    AddDriverPage(),
    FareManagementPage(),
    DriversPage(),
    LiveDriverMapPage(),
  ];

  @override
  void initState() {
    super.initState();
    _subscribeToDriverDeclines();
  }

  void _subscribeToDriverDeclines() {
    final supabase = Supabase.instance.client;

    _channel = supabase.channel('admin').onBroadcast(
      event: 'driver_declined',
      callback: (payload, [ref]) {
        if (!_dialogShown && payload != null && payload['payload'] != null) {
          _dialogShown = true;

          final data = payload['payload'];
          final String driverName = data['driver_name'] ?? 'Unknown';
          final String pickup = data['pickup'] ?? 'Unknown';
          final String dropoff = data['dropoff'] ?? 'Unknown';

          _showDeclinedDialog(
            driverName: driverName,
            tripInfo: 'From $pickup to $dropoff',
          );

          Future.delayed(const Duration(seconds: 10), () {
            _dialogShown = false;
          });
        }
      },
    ).subscribe();
  }

  void _showDeclinedDialog({
    required String driverName,
    required String tripInfo,
  }) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Driver Declined Trip'),
        content: Text('$driverName has declined the trip.\nTrip: $tripInfo'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          SidebarMenu(
            selectedIndex: selectedIndex,
            onItemSelected: (index) {
              setState(() {
                selectedIndex = index;
              });
            },
          ),
          Expanded(child: pages[selectedIndex]),
        ],
      ),
    );
  }
}
